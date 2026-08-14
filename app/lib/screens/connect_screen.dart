import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/neon.dart';
import '../services/api_client.dart';
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
/// меряем на этом экране напрямую — секундомером вокруг лёгкого
/// авторизованного запроса `getHosts()` (это всё равно нужные данные,
/// отдельного /ping эндпоинта на сервере нет и придумывать его не стал).
///
/// ВАЖНО: платформенная часть (App Group + Network Extension на iOS/macOS
/// через Xcode, xray.exe на Windows) не может быть настроена только правкой
/// .dart-файлов — см. app/NATIVE_SETUP.md.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _api = ApiClient.instance;
  final _tunnel = TunnelService.instance;
  bool _connecting = false;
  bool _loadingKey = true;
  Map<String, dynamic>? _activeKey;
  String? _keyError;
  int? _latencyMs;

  @override
  void initState() {
    super.initState();
    _tunnel.status.addListener(_onTunnelStatus);
    SelectedServer.displayName.addListener(_onServerSelected);
    _loadKeyState();
  }

  @override
  void dispose() {
    _tunnel.status.removeListener(_onTunnelStatus);
    SelectedServer.displayName.removeListener(_onServerSelected);
    super.dispose();
  }

  void _onTunnelStatus() {
    if (mounted) setState(() {});
  }

  void _onServerSelected() {
    if (mounted) setState(() {});
  }

  bool _isActive(Map<String, dynamic> key) {
    final expiryStr = key['expiry_date'] as String?;
    final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  Future<void> _loadKeyState() async {
    setState(() => _loadingKey = true);
    try {
      final keys = await _api.getKeys();
      final active = keys.cast<Map<String, dynamic>>().where(_isActive);
      setState(() {
        _activeKey = active.isNotEmpty ? active.first : null;
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
    // Если туннель уже поднят — меряем задержку ЧЕРЕЗ него (реальный сигнал
    // для пользователя). Иначе — грубая оценка "жив ли backend" секундомером
    // вокруг обычного авторизованного запроса (отдельного /ping эндпоинта
    // на реальном сервере нет).
    if (_tunnel.isConnected) {
      final ms = await _tunnel.connectedDelayMs();
      if (mounted) setState(() => _latencyMs = ms);
      return;
    }
    final sw = Stopwatch()..start();
    try {
      await _api.getHosts();
      sw.stop();
      if (mounted) setState(() => _latencyMs = sw.elapsedMilliseconds);
    } catch (_) {
      sw.stop();
      if (mounted) setState(() => _latencyMs = null);
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
      await _tunnel.connect(connectionString);
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

  String get _timerLabel {
    final seconds = _tunnel.status.value?.duration ?? 0;
    final d = Duration(seconds: seconds);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatBytes(num? bytes) {
    if (bytes == null || bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  String get _latencyLabel {
    if (_latencyMs == null) return 'проверка соединения…';
    if (_latencyMs! < 80) return '$_latencyMs мс · отличный сигнал';
    if (_latencyMs! < 200) return '$_latencyMs мс · стабильно';
    return '$_latencyMs мс · медленно';
  }

  String _getCountryCode(String? name) {
    if (name == null || name.isEmpty) return '??';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '??';
    final firstWord = trimmed.split(RegExp(r'\s+')).first;
    return firstWord.length >= 2 ? firstWord.substring(0, 2).toUpperCase() : firstWord.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = _activeKey != null;
    final connected = _tunnel.isConnected;
    final s = _tunnel.status.value;
    final devicesLimit = hasKey ? (_activeKey!['devices_limit'] as num?)?.toInt() : null;
    final selectedServerName = SelectedServer.displayName.value ?? 'Сервер';
    final serverCountryCode = _getCountryCode(selectedServerName);

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
           code: serverCountryCode,
           name: selectedServerName,
            pingLabel: _latencyLabel,
            pingColor: (_latencyMs != null && _latencyMs! < 200) ? AppColors.success : AppColors.textDim,
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
            label: 'Тест скорости',
            icon: '⚡',
            onTap: () {
              if (!connected) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Тест скорости доступен после подключения к серверу')),
                );
                return;
              }
              _measureLatency();
            },
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
