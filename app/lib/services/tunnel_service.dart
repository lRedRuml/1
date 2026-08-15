import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:http/http.dart' as http;

/// Статус VPN-туннеля, отображается на экране "Подключение".
enum TunnelStatus { disconnected, connecting, connected, disconnecting, error }

class TunnelException implements Exception {
  TunnelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// [ИСПРАВЛЕНО] Корень бага "Подключено, но интернета нет":
///
/// Бэкенд в поле connection_string отдаёт ссылку вида
/// https://vpn.on2026linevp.ru/sub/<uuid> — это URL ПОДПИСКИ 3x-ui,
/// а не готовый vless://-конфиг. Xray/flutter_vless не умеет сам
/// понимать такую ссылку как конфигурацию — если отдать её напрямую в
/// startVless(), нативный VPN-интерфейс на Android поднимется (отсюда и
/// статус "Подключено"), но внутри будет мусор вместо конфига, и весь
/// трафик будет молча дропаться.
///
/// Правильная цепочка:
///   1) понять, что это НЕ share-ссылка (vless://…), а http(s)-ссылка;
///   2) СКАЧАТЬ её содержимое обычным GET-запросом (это обычно
///      base64-строка со списком vless://-ссылок, стандартный формат
///      подписки 3x-ui);
///   3) отдать скачанный текст в FlutterVless.parseMany() — он сам
///      понимает base64 и сам достаёт из него профили;
///   4) взять первый профиль и получить из него готовый JSON-конфиг
///      Xray через getFullConfiguration();
///   5) только этот JSON передавать в startVless().
class TunnelService {
  TunnelService._internal() {
    _vless = FlutterVless(onStatusChanged: _onNativeStatus);
  }
  static final TunnelService instance = TunnelService._internal();
  factory TunnelService() => instance;

  late final FlutterVless _vless;
  bool _initialized = false;

  final ValueNotifier<TunnelStatus> status = ValueNotifier(TunnelStatus.disconnected);
  final ValueNotifier<int> downloadBytes = ValueNotifier(0);
  final ValueNotifier<int> uploadBytes = ValueNotifier(0);
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  bool get isConnected => status.value == TunnelStatus.connected;
  bool get isBusy =>
      status.value == TunnelStatus.connecting || status.value == TunnelStatus.disconnecting;

  /// Меряет задержку через уже поднятый туннель: засекает время ответа
  /// лёгкого HTTPS-запроса. -1, если туннель не поднят или запрос не удался.
  Future<int> connectedDelayMs() async {
    if (!isConnected) return -1;
    final sw = Stopwatch()..start();
    try {
      await http
          .head(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      sw.stop();
      return -1;
    }
  }

  Timer? _ticker;
  DateTime? _connectedAt;
  String? _lastRemark;

  void _onNativeStatus(dynamic s) {
    // download/upload — суммарные байты сессии, отдаёт сам плагин
    // (см. doc/getting-started.md: status.download / status.upload).
    try {
      downloadBytes.value = (s.download ?? 0) as int;
      uploadBytes.value = (s.upload ?? 0) as int;
    } catch (_) {
      // на части платформ поля могут отсутствовать до первого пакета — не критично
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _vless.initializeVless(
      providerBundleIdentifier: 'su.vpnonline.vpnonlineApp.PacketTunnel',
      groupIdentifier: 'group.su.vpnonline.vpnonlineApp',
    );
    _initialized = true;
  }

  /// [ИСПРАВЛЕНО] connectionString приходит из ключа пользователя
  /// (API-поле connection_string) и может быть:
  ///  - готовой share-ссылкой: vless://..., vmess://..., trojan://..., ss://...
  ///  - ссылкой-подпиской 3x-ui: https://.../sub/<uuid>
  /// Раньше вторая форма передавалась в конфиг как есть — отсюда и баг.
  Future<void> connect(String connectionString, {String remark = 'VPNonLine'}) async {
    final trimmed = connectionString.trim();
    if (trimmed.isEmpty) {
      throw TunnelException('У этого ключа нет ссылки для подключения.');
    }

    status.value = TunnelStatus.connecting;
    try {
      await _ensureInitialized();

      final config = await _resolveXrayConfig(trimmed);

      final granted = await _vless.requestPermission();
      if (!granted) {
        status.value = TunnelStatus.disconnected;
        throw TunnelException('Нет разрешения на создание VPN-соединения.');
      }

      _lastRemark = remark;
      await _vless.startVless(remark: remark, config: config);

      _connectedAt = DateTime.now();
      _startTicker();
      status.value = TunnelStatus.connected;
    } on TunnelException {
      status.value = TunnelStatus.error;
      rethrow;
    } catch (e) {
      status.value = TunnelStatus.error;
      throw TunnelException('Не удалось подключиться: $e');
    }
  }

  /// Главная точка исправления — превращает то, что реально лежит в
  /// connection_string, в готовый JSON-конфиг Xray.
  Future<String> _resolveXrayConfig(String raw) async {
    final isShareLink = RegExp(
      r'^(vless|vmess|trojan|ss|socks):\/\/',
      caseSensitive: false,
    ).hasMatch(raw);

    if (isShareLink) {
      // Уже готовая share-ссылка — можно парсить напрямую.
      final parsed = FlutterVless.parse(raw);
      return parsed.getFullConfiguration();
    }

    final uri = Uri.tryParse(raw);
    final isHttpUrl = uri != null && (uri.isScheme('HTTP') || uri.isScheme('HTTPS'));
    if (!isHttpUrl) {
      throw TunnelException('Не удалось распознать ссылку ключа: $raw');
    }

    // Это ссылка-подписка (как раз случай vpn.on2026linevp.ru/sub/...).
    // Её нужно СКАЧАТЬ, а не передавать в конфиг как строку.
    late final http.Response resp;
    try {
      resp = await http
          .get(uri, headers: const {'User-Agent': 'VPNonLine/1.0 (Xray)'})
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw TunnelException('Не удалось загрузить подписку сервера: $e');
    }

    if (resp.statusCode != 200 || resp.body.trim().isEmpty) {
      throw TunnelException(
        'Сервер подписки ответил ошибкой (HTTP ${resp.statusCode}). '
        'Проверь, что ссылка ключа ещё активна.',
      );
    }

    // parseMany сам понимает, что тело base64-закодировано, и сам
    // достаёт из него список профилей (vless/vmess/trojan/ss).
    final profiles = FlutterVless.parseMany(resp.body);
    if (profiles.isEmpty) {
      throw TunnelException(
        'В подписке не нашлось ни одного рабочего профиля VLESS/VMess/Trojan.',
      );
    }

    // Берём первый профиль подписки. Если бэкенд отдаёт несколько
    // локаций в одной подписке и нужно подключаться к конкретной —
    // здесь можно фильтровать profiles по .remark перед .first.
    return profiles.first.getFullConfiguration();
  }

  Future<void> disconnect() async {
    status.value = TunnelStatus.disconnecting;
    try {
      await _vless.stopVless();
    } catch (_) {
      // если туннель уже не активен на нативной стороне — не страшно
    } finally {
      _stopTicker();
      downloadBytes.value = 0;
      uploadBytes.value = 0;
      elapsed.value = Duration.zero;
      status.value = TunnelStatus.disconnected;
    }
  }

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        elapsed.value = DateTime.now().difference(_connectedAt!);
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _connectedAt = null;
  }

  void dispose() {
    _stopTicker();
    status.dispose();
    downloadBytes.dispose();
    uploadBytes.dispose();
    elapsed.dispose();
  }
}