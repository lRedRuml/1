import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/neon.dart';
import '../services/api_client.dart';
import '../services/local_prefs.dart';
import '../services/tunnel_service.dart';
import '../state/selected_server.dart';
import 'plans_screen.dart';
import 'servers_screen.dart';

/// Экран подключения.
///
/// [ИСПРАВЛЕНО v4.2] Кнопка "Подключить" реально запускает/останавливает
/// VLESS-туннель через [TunnelService] (обёртка над flutter_vless), RX/TX/
/// таймер — живые значения из [VlessStatus].
///
/// [ИСПРАВЛЕНО] Раньше экран ожидал поля `active_in_panel` и
/// `subscription_url`, которых у реального `GET /user/keys` нет (см.
/// api.py/database.py в бэкапе, тот же контракт что и в keys_screen.dart).
/// Реальные поля: `expiry_date` (ISO-строка — активность = дата в
/// будущем) и `connection_string` (готовая ссылка для туннеля, а не
/// `subscription_url`). Поля `devices_used` тоже не существует — сервер
/// отдаёт только `devices_limit`, поэтому показываем один лимит без
/// "занято/всего".
///
/// [ИСПРАВЛЕНО] `measureBackendLatencyMs()` был методом придуманного
/// бэкенда и в реальном ApiClient отсутствует. Задержку до backend теперь
/// меряем на этом экране напрямую — секундомером вокруг обычного TCP-
/// подключения к `connect_host`/`connect_port` выбранного сервера (это
/// TCP handshake, реальный сетевой сигнал; отдельного /ping эндпоинта на
/// сервере нет и придумывать его не стал).
///
/// ВАЖНО: платформенная часть (App Group + Network Extension на iOS/macOS
/// через Xcode, xray.exe на Windows) не может быть настроена только правкой
/// .dart-файлов — см. app/NATIVE_SETUP.md.
///
/// [ИСПРАВЛЕНО — критический баг] Кнопка "Подключить" (и вообще все
/// авторизованные запросы: ключи, серверы, тарифы) не работала не из-за
/// этого экрана — `ApiClient._headers` буквально отправлял строку
/// `'Authorization': '******'` вместо `'******'` (см.
/// services/api_client.dart). Backend отвечал 401 на любой запрос с
/// токеном, поэтому активный ключ никогда не находился, а нажатие
/// "Подключить" не имело эффекта. Также релизный AndroidManifest.xml не
/// объявлял `INTERNET` (есть только в debug/profile-манифестах, которые в
/// релизную сборку не попадают) — без этого разрешения ни один сетевой
/// запрос с телефона физически не может пройти ("серверы не пингуются").
/// Оба места исправлены — см. api_client.dart и
/// android/app/src/main/AndroidManifest.xml.
///
/// [ИСПРАВЛЕНО — заглушки в статистике/тесте соединения] Жалоба "после
/// подключения VPN приём 0 МБ, отдача 0 МБ, тест сервера не работает":
/// 1) `_formatBytes()` округлял любые значения меньше 1 МБ до "0.0 MB" —
///    визуально неотличимо от настоящего отсутствия трафика. Теперь малые
///    значения показываются в КБ.
/// 2) Кнопка "Тест скорости" при отключённом VPN не запускала проверку
///    вообще — только показывала "подключись сначала". Теперь она всегда
///    реально проверяет соединение (через уже существующий
///    `TunnelService.connectedDelayMs()` / TCP-пробу) и показывает
///    результат снэкбаром.
/// 3) Раньше неудачный замер задержки не отличался от "ещё измеряю" —
///    подпись рядом с сервером могла зависнуть на "проверка соединения…"
///    навсегда. Теперь добавлены явные состояния `_measuringLatency` /
///    `_latencyFailed`.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _api = ApiClient.instance;
  final _tunnel = TunnelService.instance;
  List<Map<String, dynamic>> _hosts = const [];
  bool _connecting = false;
  bool _loadingKey = true;
  Map<String, dynamic>? _activeKey;
  Map<String, dynamic>? _selectedHost;
  String? _keyError;
  int? _latencyMs;
  // [ИСПРАВЛЕНО] Раньше было только `_latencyMs` — при неудачном замере
  // (сервер/интернет через VPN не отвечает) оно оставалось `null`, и
  // `_latencyLabel` показывал "проверка соединения…" НАВСЕГДА, даже после
  // того как проверка реально завершилась с ошибкой. Пользователь не мог
  // отличить "ещё меряю" от "уже проверил — не отвечает". Теперь это два
  // разных явных состояния.
  bool _measuringLatency = false;
  bool _latencyFailed = false;

  @override
  void initState() {
    super.initState();
    _tunnel.status.addListener(_onTunnelStatus);
    SelectedServer.hostName.addListener(_onSelectedServerChanged);
    SelectedServer.displayName.addListener(_onSelectedServerChanged);
    _loadKeyState();
  }

  @override
  void dispose() {
    _tunnel.status.removeListener(_onTunnelStatus);
    SelectedServer.hostName.removeListener(_onSelectedServerChanged);
    SelectedServer.displayName.removeListener(_onSelectedServerChanged);
    super.dispose();
  }

  void _onTunnelStatus() {
    if (mounted) setState(() {});
  }

  void _onSelectedServerChanged() {
    final selectedName = SelectedServer.hostName.value;
    Map<String, dynamic>? selectedHost;
    if (selectedName != null) {
      for (final host in _hosts) {
        if (host['host_name'] == selectedName) {
          selectedHost = host;
          break;
        }
      }
    }
    _selectedHost = selectedHost ?? (_hosts.isNotEmpty ? _hosts.first : null);
    if (!mounted) return;
    setState(() {});
    _measureLatency();
  }

  bool _isActive(Map<String, dynamic> key) {
    final expiryStr = key['expiry_date'] as String?;
    final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  DateTime? _expiryOf(Map<String, dynamic> key) {
    final expiryStr = key['expiry_date'] as String?;
    return expiryStr != null ? DateTime.tryParse(expiryStr) : null;
  }

  /// [ИСПРАВЛЕНО] Если у пользователя несколько активных ключей (например,
  /// продлевал подписку несколько раз, или есть старый и новый тариф),
  /// раньше в качестве "активного" бралcя просто первый попавшийся ключ из
  /// ответа API — независимо от того, сколько дней аренды у него осталось.
  /// Это могло выбрать ключ с истекающей через день арендой вместо ключа с
  /// большим остатком, из-за чего подключение выглядело "сломанным"
  /// (работало на коротком ключе, который скоро гас, или путало пользователя).
  /// Теперь среди активных ключей выбирается тот, у кого `expiry_date`
  /// максимальный — то есть ключ с самым большим оставшимся сроком аренды.
  Map<String, dynamic>? _pickLongestActiveKey(Iterable<Map<String, dynamic>> activeKeys) {
    Map<String, dynamic>? best;
    DateTime? bestExpiry;
    for (final key in activeKeys) {
      final expiry = _expiryOf(key);
      if (expiry == null) continue;
      if (bestExpiry == null || expiry.isAfter(bestExpiry)) {
        best = key;
        bestExpiry = expiry;
      }
    }
    return best;
  }

  String _displayNameForHost(Map<String, dynamic> host) {
    return (host['display_name'] as String?) ??
        (host['name'] as String?) ??
        (host['host_name'] as String?) ??
        'Сервер не выбран';
  }

  Future<void> _loadKeyState() async {
    setState(() => _loadingKey = true);
    try {
      final results = await Future.wait([_api.getKeys(), _api.getHosts()]);
      final keys = results[0] as List<dynamic>;
      final hosts = (results[1] as List<dynamic>).cast<Map<String, dynamic>>();
      final active = keys.cast<Map<String, dynamic>>().where(_isActive);
      final longestActive = _pickLongestActiveKey(active);
      Map<String, dynamic>? selectedHost;
      if (hosts.isNotEmpty) {
        for (final host in hosts) {
          if (host['host_name'] == SelectedServer.hostName.value) {
            selectedHost = host;
            break;
          }
        }
        selectedHost ??= hosts.first;
        final hostName = selectedHost?['host_name'] as String?;
        final displayName = selectedHost != null ? _displayNameForHost(selectedHost) : null;
        if (hostName != null &&
            (SelectedServer.hostName.value != hostName || SelectedServer.displayName.value != displayName)) {
          SelectedServer.select(hostName, displayName ?? hostName);
        }
      }
      setState(() {
        _hosts = hosts;
        _activeKey = longestActive;
        _selectedHost = selectedHost;
        _keyError = null;
        _loadingKey = false;
      });
    } catch (e) {
      setState(() {
        _keyError = 'Не удалось проверить статус ключа: $e';
        _loadingKey = false;
      });
    }
    _measureLatency();
  }

  Future<void> _measureLatency() async {
    if (mounted) setState(() { _measuringLatency = true; _latencyFailed = false; });
    // Если туннель уже поднят — меряем задержку ЧЕРЕЗ него (реальный сигнал
    // для пользователя, что интернет РЕАЛЬНО проходит через VPN, а не
    // только поднят сетевой интерфейс). Иначе — грубая оценка "жив ли
    // сервер" секундомером вокруг TCP-подключения к его публичному адресу
    // (отдельного /ping эндпоинта на реальном сервере нет).
    if (_tunnel.isConnected) {
      final ms = await _tunnel.connectedDelayMs();
      if (!mounted) return;
      setState(() {
        _latencyMs = ms;
        _measuringLatency = false;
        _latencyFailed = ms == null;
      });
      return;
    }
    final host = _selectedHost;
    final connectHost = host?['connect_host'] as String?;
    if (connectHost == null || connectHost.isEmpty) {
      // Данные о сервере ещё не загружены — это "неизвестно", а не
      // "не отвечает", поэтому _latencyFailed здесь не взводим.
      if (mounted) setState(() { _latencyMs = null; _measuringLatency = false; });
      return;
    }
    final port = (host?['connect_port'] as num?)?.toInt() ?? 443;
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(connectHost, port, timeout: const Duration(seconds: 4));
      sw.stop();
      socket.destroy();
      if (!mounted) return;
      setState(() {
        _latencyMs = sw.elapsedMilliseconds;
        _measuringLatency = false;
        _latencyFailed = false;
      });
    } catch (_) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _latencyMs = null;
        _measuringLatency = false;
        _latencyFailed = true;
      });
    }
  }

  /// [ИСПРАВЛЕНО — заглушка] Раньше кнопка "Тест скорости" при отключённом
  /// VPN вообще не выполняла проверку — только показывала снэкбар
  /// "подключись сначала" и выходила. Теперь тест реально запускается в
  /// обоих состояниях (до и после подключения) и явно показывает результат
  /// — а не молча полагается на мелкую подпись рядом с сервером.
  Future<void> _runConnectionTest() async {
    if (_measuringLatency) return;
    await _measureLatency();
    if (!mounted) return;
    final connected = _tunnel.isConnected;
    if (_latencyMs != null) {
      _showInfo(connected
          ? 'Интернет через VPN работает: $_latencyMs мс.'
          : 'Сервер отвечает: $_latencyMs мс. Подключись, чтобы пустить через него трафик.');
    } else {
      _showError(connected
          ? 'VPN подключен, но интернет через него не проходит. Попробуй сменить сервер или переподключиться.'
          : 'Сервер не отвечает. Попробуй выбрать другую локацию.');
    }
  }

  Future<void> _toggleConnection() async {
    if (_activeKey == null || _connecting || _tunnel.isBusy) return;
    final connectionString = _activeKey!['connection_string'] as String?;

    if (_tunnel.isConnected) {
      setState(() => _connecting = true);
      await _tunnel.disconnect();
      setState(() => _connecting = false);
      _measureLatency();
      return;
    }

    if (connectionString == null || connectionString.isEmpty) {
      _showError('Для этого ключа пока нет ссылки на конфигурацию сервера — обратись в поддержку.');
      return;
    }

    setState(() => _connecting = true);
    try {
      // [НОВОЕ] Список приложений, отмеченных "в обход VPN" в
      // SplitTunnelScreen — реально передаётся в native-слой через
      // startVless(blockedApps: ...), а не только сохраняется в UI.
      final bypassed = await LocalPrefs.instance.getBoolMap(PrefKeys.splitTunnelBypass);
      final blockedApps = bypassed.entries.where((e) => e.value).map((e) => e.key).toList();
      await _tunnel.connect(connectionString, blockedApps: blockedApps);
      _measureLatency();
    } on TunnelException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Не удалось подключиться: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  String get _timerLabel {
    final seconds = _tunnel.status.value?.duration ?? 0;
    final d = Duration(seconds: seconds);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// [ИСПРАВЛЕНО] Раньше любое значение меньше 1 МБ (например, реальные
  /// первые 20-200 КБ сразу после подключения) округлялось до "0.0 MB" —
  /// визуально неотличимо от "трафик вообще не идёт", хотя туннель мог
  /// работать нормально. Теперь маленькие значения показываются в КБ, и
  /// "0 KB" означает буквально ноль байт, а не "меньше одного мегабайта".
  String _formatBytes(num? bytes) {
    final b = (bytes ?? 0).toDouble();
    if (b <= 0) return '0 KB';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (b < mb) return '${(b / kb).toStringAsFixed(b < kb * 10 ? 1 : 0)} KB';
    if (b < gb) return '${(b / mb).toStringAsFixed(1)} MB';
    return '${(b / gb).toStringAsFixed(2)} GB';
  }

  /// [ИСПРАВЛЕНО — заглушка] Раньше `_latencyMs == null` означало и "ещё не
  /// мерял", и "померял — сервер/интернет не отвечает" одновременно, из-за
  /// чего при реальном сбое подпись молча зависала на "проверка
  /// соединения…" навсегда. Теперь неудачный результат показывается явно.
  String get _latencyLabel {
    if (_measuringLatency) return 'проверка соединения…';
    if (_latencyMs != null) {
      if (_latencyMs! < 80) return '$_latencyMs мс · отличный сигнал';
      if (_latencyMs! < 200) return '$_latencyMs мс · стабильно';
      return '$_latencyMs мс · медленно';
    }
    if (_latencyFailed) {
      return _tunnel.isConnected ? 'нет интернета через VPN' : 'сервер не отвечает';
    }
    return 'проверка соединения…';
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = _activeKey != null;
    final connected = _tunnel.isConnected;
    final s = _tunnel.status.value;
    final devicesLimit = hasKey ? (_activeKey!['devices_limit'] as num?)?.toInt() : null;
    final serverName = SelectedServer.displayName.value ??
        (_selectedHost?['host_name'] as String?) ??
        'Сервер не выбран';
    final serverCode = (() {
      final parts = serverName.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty || parts.first.isEmpty) return '??';
      return parts.first.length >= 2 ? parts.first.substring(0, 2).toUpperCase() : parts.first.toUpperCase();
    })();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          const AppHeader(trailing: Icons.menu_rounded, screenLabel: 'Подключение'),
          const SizedBox(height: 18),
          _ConnectRing(
            connected: connected,
            hasKey: hasKey,
            loading: _loadingKey || _connecting,
            timerLabel: _timerLabel,
          ),
          const SizedBox(height: 28),
          if (_keyError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_keyError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          ServerPill(
            code: serverCode,
            name: serverName,
            pingLabel: _latencyLabel,
            pingColor: _latencyFailed
                ? AppColors.danger
                : (_latencyMs != null && _latencyMs! < 200) ? AppColors.success : AppColors.textDim,
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textDim, size: 18),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServersScreen())),
          ),
          Row(
            children: [
              StatMiniCard(label: 'Приём', value: _formatBytes(s?.download)),
              const SizedBox(width: 10),
              StatMiniCard(label: 'Отдача', value: _formatBytes(s?.upload)),
              const SizedBox(width: 10),
              StatMiniCard(
                label: 'Устройств',
                value: devicesLimit != null ? '$devicesLimit' : '—',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasKey && !_loadingKey)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
                child: const Text('Оформить подписку'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ServersScreen())),
                    child: const Text('Сменить сервер'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_loadingKey || _connecting || _tunnel.isBusy) ? null : _toggleConnection,
                    style: connected
                        ? ElevatedButton.styleFrom(backgroundColor: const Color(0xFF241028))
                        : null,
                    child: (_connecting || _tunnel.isBusy)
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(connected ? 'Отключить' : 'Подключить'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          PillButton(
            label: _measuringLatency ? 'Проверка…' : 'Тест скорости',
            icon: '⚡',
            onTap: _measuringLatency ? null : _runConnectionTest,
          ),
        ],
      ),
    );
  }
}

class _ConnectRing extends StatelessWidget {
  const _ConnectRing({
    required this.connected,
    required this.hasKey,
    required this.loading,
    required this.timerLabel,
  });

  final bool connected;
  final bool hasKey;
  final bool loading;
  final String timerLabel;

  @override
  Widget build(BuildContext context) {
    final ringColor = !hasKey ? AppColors.danger : (connected ? AppColors.violet2 : AppColors.border);
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Внешнее свечение — .globe-bg аналог за кольцом.
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.violet2.withOpacity(connected ? 0.14 : 0.05), Colors.transparent],
              ),
            ),
          ),
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _RingPainter(
                progress: connected ? 0.86 : (hasKey ? 0.18 : 0.04),
                color: ringColor,
                glow: connected,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.violetGlow),
                )
              else ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !hasKey ? AppColors.danger : (connected ? AppColors.success : AppColors.textDim),
                    boxShadow: connected
                        ? AppColors.glow(AppColors.success, blur: 8, alpha: 0.8)
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  !hasKey ? 'НЕТ КЛЮЧА' : (connected ? 'ПОДКЛЮЧЕНО' : 'ОТКЛЮЧЕНО'),
                  style: orbitron(fontSize: 15, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                const Text('VLESS · Reality', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
                if (connected) ...[
                  const SizedBox(height: 10),
                  Text(timerLabel,
                      style: orbitron(fontSize: 11, color: AppColors.violetGlow, fontWeight: FontWeight.w500)),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Кольцо с градиентной обводкой и свечением — воспроизводит SVG
/// .ring-fg с linearGradient(#a855f7 → #8b5cf6) и drop-shadow из макета.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.glow});
  final double progress; // 0..1 доля дуги
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final bgPaint = Paint()
      ..color = const Color(0xFF1C1330)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: -1.5708,
      endAngle: -1.5708 + 6.28319,
      colors: const [AppColors.violet2, AppColors.violet, AppColors.violet2],
      stops: const [0.0, 0.5, 1.0],
    );
    final fgPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    if (glow) {
      fgPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    }
    final sweep = 6.28319 * progress;
    canvas.drawArc(rect, -1.5708, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.glow != glow;
}
