import 'dart:async';
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

  /// Время текущей сессии — берётся из VlessStatus.duration (секунды от
  /// нативного рантайма), не считается вручную таймером на стороне Dart.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  /// Суммарный входящий/исходящий трафик за сессию — берётся из
  /// VlessStatus.download / VlessStatus.upload (реальные поля пакета
  /// flutter_vless_platform_interface, см. vless_status.dart).
  final ValueNotifier<num> downloadBytes = ValueNotifier(0);
  final ValueNotifier<num> uploadBytes = ValueNotifier(0);

  bool get isConnected => status.value?.connectionState == VlessConnectionState.connected;
  bool get isBusy =>
      status.value?.connectionState == VlessConnectionState.connecting ||
      status.value?.connectionState == VlessConnectionState.disconnecting;