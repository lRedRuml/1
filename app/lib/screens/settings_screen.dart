import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/neon.dart';
import '../services/api_client.dart';
import '../services/local_prefs.dart';

/// Настройки — сведено по SCREEN 7 макета (.settings-row + .toggle).
///
/// [ИСПРАВЛЕНО] Раньше все три тумблера были обычным `bool` полем State —
/// значение "забывалось" при выходе с экрана и при перезапуске приложения
/// (подробный разбор причины — см. services/local_prefs.dart). Теперь
/// каждый тумблер читает стартовое значение из `LocalPrefs` при открытии
/// экрана и сразу пишет туда же при каждом переключении — значение
/// переживает и уход с экрана, и полный перезапуск приложения.
///
/// [ИСПРАВЛЕНО] Кнопка "Выйти из аккаунта" была `onPressed: () {}` —
/// не делала вообще ничего. Теперь реально чистит токен и возвращает на
/// экран входа (тот же путь, что и кнопка выхода в MenuScreen).
///
/// ДОПУЩЕНИЕ (честно): Kill Switch и "умное подключение на Wi-Fi" сами по
/// себе — предпочтения пользователя, реальная защита на уровне ОС
/// подключается на стороне tunnel_service.dart при старте туннеля (см.
/// NATIVE_SETUP.md) — сохранение выбора здесь уже полностью рабочее,
/// связка с самим VPN-сервисом отдельный следующий шаг.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onLoggedOut});
  final VoidCallback onLoggedOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _prefs = LocalPrefs.instance;

  bool _autoConnect = true;
  bool _smartWifi = true;
  bool _killSwitch = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _prefs.getBool(PrefKeys.autoConnect, fallback: true),
      _prefs.getBool(PrefKeys.smartWifi, fallback: true),
      _prefs.getBool(PrefKeys.killSwitch, fallback: true),
    ]);
    if (!mounted) return;
    setState(() {
      _autoConnect = results[0];
      _smartWifi = results[1];
      _killSwitch = results[2];
      _loaded = true;
    });
  }

  Future<void> _setAutoConnect(bool v) async {
    setState(() => _autoConnect = v);
    await _prefs.setBool(PrefKeys.autoConnect, v);
  }

  Future<void> _setSmartWifi(bool v) async {
    setState(() => _smartWifi = v);
    await _prefs.setBool(PrefKeys.smartWifi, v);
  }

  Future<void> _setKillSwitch(bool v) async {
    setState(() => _killSwitch = v);
    await _prefs.setBool(PrefKeys.killSwitch, v);
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Очистить кэш?'),
        content: const Text(
          'Локальные данные приложения (кэш серверов, избранное) будут удалены. '
          'Вход в аккаунт при этом сохранится.',
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Очистить')),
        ],
      ),
    );
    if (confirmed != true) return;
    // [НОВОЕ] Раньше пункт вообще ничего не делал (просто chevron без
    // onTap). Чистим только клиентский кэш-стейт (избранные сервера,
    // выбор split-tunnel) — токен входа НЕ трогаем, это не "выход",
    // а именно очистка локального кэша.
    await Future.wait([
      _prefs.setStringSet(PrefKeys.favoriteServers, {}),
      _prefs.setBool(PrefKeys.autoBalance, false),
      _prefs.setBoolMap(PrefKeys.splitTunnelBypass, {}),
    ]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Кэш очищен')),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Тебе нужно будет снова войти по email и паролю.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ApiClient.instance.logout();
      widget.onLoggedOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(trailing: Icons.arrow_back_rounded, onTrailingTap: () => Navigator.pop(context)),
              const Text('Настройки', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              if (!_loaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                _SettingsRow(
                  label: 'Автоподключение при запуске',
                  trailing: NeonToggle(value: _autoConnect, onChanged: _setAutoConnect),
                ),
                _SettingsRow(
                  label: 'Умное подключение на публичном Wi-Fi',
                  trailing: NeonToggle(value: _smartWifi, onChanged: _setSmartWifi),
                ),
                _SettingsRow(
                  label: 'Kill Switch',
                  trailing: NeonToggle(value: _killSwitch, onChanged: _setKillSwitch),
                ),
                _SettingsRow(
                  label: 'Язык',
                  trailing: const Text('Русский', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                ),
                _SettingsRow(
                  label: 'Очистить кэш',
                  onTap: _clearCache,
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Kill Switch и умное подключение зависят от нативного VPN-сервиса на устройстве — '
                  'переключатель сохраняет твой выбор, а фактическую защиту обеспечивает системный туннель '
                  '(см. NATIVE_SETUP.md).',
                  style: TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.4),
                ),
              ),
              const SizedBox(height: 22),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, size: 16, color: AppColors.danger),
                  label: const Text('Выйти из аккаунта', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.trailing, this.onTap});
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1A1230))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            trailing,
          ],
        ),
      ),
    );
  }
}
