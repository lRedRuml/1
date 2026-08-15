import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:http/http.dart' as http;

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
      providerBundleIdentifier: 'su.vpnonline.vpnonlineApp',
      groupIdentifier: 'group.su.vpnonline.vpnonlineApp',
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
    );
    _initialized = true;
  }

  Future<List<FlutterVlessURL>> _fetchOrderedProfiles(String connectionString, {String? preferredRemark}) async {
    final direct = connectionString.trim();

    List<FlutterVlessURL> profiles;
    if (direct.startsWith('vless://') || direct.startsWith('vmess://')) {
      try {
        profiles = FlutterVless.parseMany(direct);
      } catch (_) {
        throw TunnelException('Не удалось разобрать конфигурацию сервера.');
      }
      if (profiles.isEmpty) {
        throw TunnelException('Конфигурация сервера пуста или повреждена.');
      }
      return _orderProfiles(profiles, preferredRemark);
    }

    late final http.Response res;
    try {
      res = await http.get(Uri.parse(direct)).timeout(const Duration(seconds: 12));
    } catch (_) {
      throw TunnelException('Не удалось получить конфигурацию сервера. Проверь интернет-соединение.');
    }
    if (res.statusCode >= 400) {
      throw TunnelException('Сервер конфигурации недоступен (${res.statusCode}). Попробуй позже.');
    }

    profiles = [];
    try {
      profiles = FlutterVless.parseMany(res.body);
    } catch (_) {
      profiles = [];
    }

    if (profiles.isEmpty) {
      final decoded = _tryDecodeBase64Subscription(res.body);
      if (decoded != null) {
        try {
          profiles = FlutterVless.parseMany(decoded);
        } catch (_) {
          profiles = [];
        }
      }
    }

    if (profiles.isEmpty) {
      throw TunnelException('Конфигурация сервера пуста или повреждена.');
    }
    return _orderProfiles(profiles, preferredRemark);
  }

  List<FlutterVlessURL> _orderProfiles(List<FlutterVlessURL> profiles, String? preferredRemark) {
    if (preferredRemark == null || preferredRemark.trim().isEmpty) return profiles;
    final needle = preferredRemark.trim().toLowerCase();
    final match = profiles.where((p) => p.remark.toLowerCase().contains(needle)).toList();
    if (match.isEmpty) return profiles;
    final rest = profiles.where((p) => !match.contains(p)).toList();
    return [...match, ...rest];
  }

  String? _tryDecodeBase64Subscription(String body) {
    var cleaned = body.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;

    cleaned = cleaned.replaceAll('-', '+').replaceAll('_', '/');

    final remainder = cleaned.length % 4;
    if (remainder != 0) {
      cleaned = cleaned + ('=' * (4 - remainder));
    }

    try {
      final bytes = base64.decode(cleaned);
      final text = utf8.decode(bytes);
      if (text.contains('vless://') || text.contains('vmess://')) {
        return text;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> connect(String connectionString, {String? preferredServerName}) async {
    lastError.value = null;
    await _ensureInitialized();

    final profiles = await _fetchOrderedProfiles(connectionString, preferredRemark: preferredServerName);

    final allowed = await _vless!.requestPermission();
    if (!allowed) {
      throw TunnelException('Нужно разрешение на создание VPN-подключения — без него туннель не запустится.');
    }

    Object? lastFailure;
    for (final profile in profiles) {
      try {
        await _vless!.startVless(
          remark: profile.remark.isNotEmpty ? profile.remark : 'VPN onLine',
          config: profile.getFullConfiguration(),
          notificationDisconnectButtonName: 'Отключить',
        );
        return;
      } catch (e) {
        lastFailure = e;
        try {
          await _vless!.stopVless();
        } catch (_) {}
      }
    }

    final triedCount = profiles.length;
    final suffix = triedCount > 1 ? ' (испробовано серверов: $triedCount)' : '';
    throw TunnelException('Не удалось запустить туннель: $lastFailure$suffix');
  }

  Future<void> disconnect() async {
    if (!_initialized) return;
    try {
      await _vless!.stopVless();
    } catch (e) {
      lastError.value = 'Не удалось корректно отключиться: $e';
    }
  }

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