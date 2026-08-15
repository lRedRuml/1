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

/// [ИСПРАВЛЕНО v4.3 — реальный баг "Подключено, но интернета нет"]
///
/// В прошлой версии этого файла было ДВЕ отдельные проблемы, обе давали
/// один и тот же симптом (UI: "ПОДКЛЮЧЕНО", 00:00:00, 0 MB, нет иконки
/// VPN в шторке Android):
///
/// БАГ №1 (уже был исправлен раньше) — connection_string с бэкенда это
/// URL подписки 3x-ui (https://.../sub/<uuid>), а не готовая vless://
/// ссылка. Раньше эта строка отдавалась в конфиг как есть. Сейчас
/// _resolveXrayConfig() правильно отличает share-ссылку от URL подписки,
/// скачивает её и парсит через FlutterVless.parseMany() — см. официальный
/// контракт пакета (doc/api.md репозитория XIIIFOX/flutter_vless):
/// parse()/parseMany() САМИ понимают base64-payload, ничего вручную
/// декодировать не нужно.
///
/// БАГ №2 (главная причина того, что проблема всё ещё оставалась) —
/// `status.value = TunnelStatus.connected` выставлялся СРАЗУ после того,
/// как `startVless()` просто завершался успехом. Но, согласно
/// официальному API-контракту плагина, startVless() только валидирует
/// JSON-конфиг и запускает нативный процесс — он НЕ гарантирует, что
/// туннель реально поднялся. Реальное состояние приходит асинхронно
/// через `onStatusChanged` в поле `VlessStatus.connectionState`
/// (enum `VlessConnectionState`: connected / connecting / disconnected /
/// disconnecting / unknown). Старый `_onNativeStatus()` читал только
/// download/upload и полностью игнорировал connectionState — поэтому
/// если нативная сторона падала с ошибкой (invalid config, permission,
/// сеть) уже ПОСЛЕ вызова startVless(), Dart-слой всё равно показывал
/// "подключено", а VPN-интерфейс в системе так и не поднимался (отсюда
/// и отсутствие иконки-ключа в шторке).
///
/// Исправление: `status` теперь ПОЛНОСТЬЮ управляется через
/// `_onNativeStatus()` на основе `connectionState`, а не оптимистично
/// внутри `connect()`. Плюс добавлен таймаут ожидания реального
/// подключения (20 секунд) — если нативная сторона зависла в
/// "connecting" и никогда не прислала connected/error, приложение сама
/// остановит попытку и покажет ошибку, а не будет вечно крутить спиннер.
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

  /// Меряет задержку через уже поднятый туннель — используем официальный
  /// метод плагина getConnectedServerDelay() (см. doc/api.md), а не
  /// ручной HEAD-запрос, который не гарантированно идёт через туннель на
  /// всех платформах.
  Future<int> connectedDelayMs() async {
    if (!isConnected) return -1;
    try {
      final ms = await _vless.getConnectedServerDelay().timeout(const Duration(seconds: 6));
      return ms;
    } catch (_) {
      return -1;
    }
  }

  // Завершается, когда пришёл первый connected/error после connect().
  Completer<void>? _connectCompleter;
  Timer? _connectTimeoutTimer;

  void _onNativeStatus(VlessStatus s) {
    downloadBytes.value = s.download;
    uploadBytes.value = s.upload;
    elapsed.value = Duration(seconds: s.duration.round());

    switch (s.connectionState) {
      case VlessConnectionState.connected:
        status.value = TunnelStatus.connected;
        _connectTimeoutTimer?.cancel();
        if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
          _connectCompleter!.complete();
        }
        break;

      case VlessConnectionState.connecting:
        status.value = TunnelStatus.connecting;
        break;

      case VlessConnectionState.disconnecting:
        status.value = TunnelStatus.disconnecting;
        break;

      case VlessConnectionState.disconnected:
        status.value = TunnelStatus.disconnected;
        downloadBytes.value = 0;
        uploadBytes.value = 0;
        elapsed.value = Duration.zero;
        _connectTimeoutTimer?.cancel();
        if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
          // Нативная сторона отвалилась ещё во время попытки подключения.
          _connectCompleter!.completeError(
            TunnelException('Соединение не установилось — сервер разорвал попытку подключения.'),
          );
        }
        break;

      case VlessConnectionState.unknown:
        // Промежуточное/неопознанное состояние платформы — не считаем
        // это ни успехом, ни ошибкой, просто ждём следующего события.
        break;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _vless.initializeVless(
      providerBundleIdentifier: 'su.vpnonline.vpnonlineApp.PacketTunnel',
      groupIdentifier: 'group.su.vpnonline.vpnonlineApp',
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
    );
    _initialized = true;
  }

  /// connectionString приходит из ключа пользователя (API-поле
  /// connection_string) и может быть:
  ///  - готовой share-ссылкой: vless://..., vmess://..., trojan://..., ss://...
  ///  - ссылкой-подпиской 3x-ui: https://.../sub/<uuid>
  Future<void> connect(String connectionString, {String remark = 'VPNonLine'}) async {
    final trimmed = connectionString.trim();
    if (trimmed.isEmpty) {
      throw TunnelException('У этого ключа нет ссылки для подключения.');
    }
    if (isBusy) return;

    status.value = TunnelStatus.connecting;
    _connectCompleter = Completer<void>();
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.completeError(
          TunnelException(
            'Не удалось подключиться за 20 секунд. Проверь, что сервер доступен, '
            'и попробуй сменить сервер.',
          ),
        );
      }
    });

    try {
      await _ensureInitialized();

      final config = await _resolveXrayConfig(trimmed);

      final granted = await _vless.requestPermission();
      if (!granted) {
        _connectTimeoutTimer?.cancel();
        status.value = TunnelStatus.disconnected;
        throw TunnelException(
          'Нет разрешения на создание VPN-соединения — подтверди системный '
          'диалог "Разрешить приложению настроить VPN-подключение".',
        );
      }

      // startVless() запускает нативный процесс, но НЕ гарантирует, что
      // туннель уже поднят — реальное подтверждение придёт в
      // _onNativeStatus() через connectionState.connected, на который мы
      // ждём ниже через _connectCompleter.
      await _vless.startVless(remark: remark, config: config);

      await _connectCompleter!.future;
      // Дошли сюда — _onNativeStatus() подтвердил connected, status уже
      // выставлен там же.
    } on TunnelException {
      _connectTimeoutTimer?.cancel();
      if (status.value != TunnelStatus.connected) {
        status.value = TunnelStatus.error;
      }
      // На всякий случай гасим нативную сторону, если она осталась
      // в подвешенном состоянии после неудачной попытки.
      unawaited(_vless.stopVless().catchError((_) {}));
      rethrow;
    } catch (e) {
      _connectTimeoutTimer?.cancel();
      status.value = TunnelStatus.error;
      unawaited(_vless.stopVless().catchError((_) {}));
      throw TunnelException('Не удалось подключиться: $e');
    }
  }

  /// Превращает то, что реально лежит в connection_string, в готовый
  /// JSON-конфиг Xray.
  Future<String> _resolveXrayConfig(String raw) async {
    final isShareLink = RegExp(
      r'^(vless|vmess|trojan|ss|socks):\/\/',
      caseSensitive: false,
    ).hasMatch(raw);

    if (isShareLink) {
      final parsed = FlutterVless.parse(raw);
      return parsed.getFullConfiguration();
    }

    final uri = Uri.tryParse(raw);
    final isHttpUrl = uri != null && (uri.isScheme('HTTP') || uri.isScheme('HTTPS'));
    if (!isHttpUrl) {
      throw TunnelException('Не удалось распознать ссылку ключа: $raw');
    }

    // Ссылка-подписка (как раз случай vpn.on2026linevp.ru/sub/...).
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

    // parseMany() сам понимает base64-payload и сам достаёт из него
    // список профилей (vless/vmess/trojan/ss) — см. doc/api.md пакета.
    final List<FlutterVlessURL> profiles;
    try {
      profiles = FlutterVless.parseMany(resp.body);
    } catch (e) {
      throw TunnelException('Не удалось разобрать подписку сервера: $e');
    }
    if (profiles.isEmpty) {
      throw TunnelException(
        'В подписке не нашлось ни одного рабочего профиля VLESS/VMess/Trojan.',
      );
    }

    // Берём первый профиль подписки. Если нужно подключаться к
    // конкретной локации — фильтруй profiles по .remark перед .first.
    try {
      return profiles.first.getFullConfiguration();
    } catch (e) {
      throw TunnelException('Конфигурация сервера повреждена: $e');
    }
  }

  Future<void> disconnect() async {
    if (status.value == TunnelStatus.disconnected) return;
    status.value = TunnelStatus.disconnecting;
    _connectTimeoutTimer?.cancel();
    try {
      await _vless.stopVless();
    } catch (_) {
      // если туннель уже не активен на нативной стороне — не страшно
    }
    // Финальное состояние выставит _onNativeStatus() при получении
    // connectionState.disconnected. На случай если плагин на какой-то
    // платформе не пришлёт это событие — подстрахуемся таймаутом.
    Timer(const Duration(seconds: 3), () {
      if (status.value == TunnelStatus.disconnecting) {
        status.value = TunnelStatus.disconnected;
        downloadBytes.value = 0;
        uploadBytes.value = 0;
        elapsed.value = Duration.zero;
      }
    });
  }

  void dispose() {
    _connectTimeoutTimer?.cancel();
    status.dispose();
    downloadBytes.dispose();
    uploadBytes.dispose();
    elapsed.dispose();
  }
}
