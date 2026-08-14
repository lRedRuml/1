import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:http/http.dart' as http;

/// Реальный запуск/остановка VLESS-туннеля — v4.2.
///
/// Раньше (см. старый docstring в connect_screen.dart) точка вызова была
/// явно помечена как НЕ реализованная — кнопка "Подключить" только меняла
/// UI-состояние, трафик никуда не шифровался. Здесь — рабочая обвязка над
/// пакетом `flutter_vless` (см. комментарий в pubspec.yaml, почему выбран
/// именно он, а не ручной JNI/Go-биндинг).
///
/// Модель данных: реальный `GET /user/keys` отдаёт на каждый ключ
/// `connection_string` (см. api.py -> xui_api.get_key_details_from_host_sync
/// в бэкенде бота). Модуль `xui_api`, который формирует эту строку, не
/// входил в присланные файлы (только api.py/database.py) — поэтому нельзя
/// быть на 100% уверенным в её формате без чтения xui_api.py. Есть два
/// реалистичных варианта: (1) готовая ссылка `vless://...`, которую можно
/// скормить `FlutterVless.parse()` сразу, или (2) URL подписки 3x-ui,
/// который сначала нужно GET-нуть и результат отдать `parseMany()`.
/// [_fetchProfile] ниже пробует оба варианта по префиксу строки — если
/// в твоём `xui_api.py` формат другой, поправь именно эту функцию.
class TunnelService {
  TunnelService._();
  static final TunnelService instance = TunnelService._();

  FlutterVless? _vless;
  bool _initialized = false;

  final ValueNotifier<VlessStatus?> status = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  bool get isConnected => status.value?.connectionState == VlessConnectionState.connected;
  bool get isBusy =>
      status.value?.connectionState == VlessConnectionState.connecting ||
      status.value?.connectionState == VlessConnectionState.disconnecting;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _vless = FlutterVless(onStatusChanged: (s) => status.value = s);
    await _vless!.initializeVless(
      // iOS/macOS: базовый bundle id приложения (БЕЗ суффикса расширения —
      // пакет сам добавляет суффикс Packet Tunnel extension). Совпадает с
      // applicationId, который сгенерирует `flutter create --org su.vpnonline`
      // (см. .github/workflows/scaffold-platforms.yml) — su.vpnonline + имя
      // пакета vpnonline_app = su.vpnonline.vpnonline_app. Если переименуешь
      // проект или сменишь org — поменяй и здесь, иначе iOS/macOS сборка
      // не найдёт Network Extension по этому bundle id.
      providerBundleIdentifier: 'su.vpnonline.vpnonline_app',
      groupIdentifier: 'group.su.vpnonline.vpnonline_app',
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
    );
    _initialized = true;
  }

  /// Скачивает содержимое подписки и возвращает первый рабочий VLESS-профиль.
  /// Кидает `TunnelException` с понятным для UI текстом вместо технической
  /// ошибки http/парсинга — экран подключения не должен показывать
  /// пользователю "FormatException" или "SocketException".
  Future<FlutterVlessURL> _fetchProfile(String connectionString) async {
    final direct = connectionString.trim();

    // Вариант 1: уже готовая vless://-ссылка — парсим напрямую, без
    // лишнего сетевого запроса. `parseMany` принимает и одиночную ссылку
    // (она рассчитана на текст с одной или несколькими ссылками), поэтому
    // отдельный `parse()` не нужен — не изобретаю метод, которого может не
    // быть в конкретной версии пакета `flutter_vless`.
    if (direct.startsWith('vless://') || direct.startsWith('vmess://')) {
      try {
        final profiles = FlutterVless.parseMany(direct);
        if (profiles.isEmpty) {
          throw TunnelException('Конфигурация сервера пуста или повреждена.');
        }
        return profiles.first;
      } on TunnelException {
        rethrow;
      } catch (_) {
        throw TunnelException('Не удалось разобрать конфигурацию сервера.');
      }
    }

    // Вариант 2: это URL подписки 3x-ui — сначала GET, потом парсим тело
    // (обычно список ссылок, часто в base64; parseMany сам это умеет).
    late final http.Response res;
    try {
      res = await http.get(Uri.parse(direct)).timeout(const Duration(seconds: 12));
    } catch (_) {
      throw TunnelException('Не удалось получить конфигурацию сервера. Проверь интернет-соединение.');
    }
    if (res.statusCode >= 400) {
      throw TunnelException('Сервер конфигурации недоступен (${res.statusCode}). Попробуй позже.');
    }
    try {
      final profiles = FlutterVless.parseMany(res.body);
      if (profiles.isEmpty) {
        throw TunnelException('Конфигурация сервера пуста или повреждена.');
      }
      return profiles.first;
    } on TunnelException {
      rethrow;
    } catch (_) {
      throw TunnelException('Не удалось разобрать конфигурацию сервера.');
    }
  }

  /// Подключение. [connectionString] — берётся из поля `connection_string`
  /// активного ключа (см. ApiClient.getKeys()). [blockedApps] — пакеты,
  /// помеченные в SplitTunnelScreen как "идут в обход VPN" (см.
  /// screens/split_tunnel_screen.dart); поддерживается `flutter_vless` через
  /// параметр `blockedApps` у `startVless` (Android-only — на других
  /// платформах пакет молча игнорирует список).
  Future<void> connect(String connectionString, {List<String>? blockedApps}) async {
    lastError.value = null;
    await _ensureInitialized();

    final profile = await _fetchProfile(connectionString);

    final allowed = await _vless!.requestPermission();
    if (!allowed) {
      throw TunnelException('Нужно разрешение на создание VPN-подключения — без него туннель не запустится.');
    }

    try {
      await _vless!.startVless(
        remark: profile.remark.isNotEmpty ? profile.remark : 'VPNonLine',
        config: profile.getFullConfiguration(),
        blockedApps: (blockedApps != null && blockedApps.isNotEmpty) ? blockedApps : null,
        notificationDisconnectButtonName: 'Отключить',
      );
    } catch (e) {
      throw TunnelException('Не удалось запустить туннель: $e');
    }
  }

  Future<void> disconnect() async {
    if (!_initialized) return;
    try {
      await _vless!.stopVless();
    } catch (e) {
      lastError.value = 'Не удалось корректно отключиться: $e';
    }
  }

  /// Пинг через УЖЕ активный туннель — использовать вместо измерения
  /// задержки до бэкенда, когда пользователь подключён: показывает
  /// реальную задержку до интернета через VPN, а не до нашего API.
  Future<int?> connectedDelayMs() async {
    if (!_initialized || !isConnected) return null;
    try {
      return await _vless!.getConnectedServerDelay();
    } catch (_) {
      return null;
    }
  }
}

class TunnelException implements Exception {
  TunnelException(this.message);
  final String message;
  @override
  String toString() => message;
}
