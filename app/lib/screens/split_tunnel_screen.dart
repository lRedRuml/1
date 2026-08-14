import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import '../theme.dart';
import '../widgets/neon.dart';
import '../services/local_prefs.dart';

/// Split-туннелирование — сведено по SCREEN 8 макета (.app-toggle-row).
///
/// [ИСПРАВЛЕНО] Раньше здесь был фиксированный демо-список из 5 названий
/// ('Банк Онлайн', 'Карты', ...) — не имел отношения к реальному
/// устройству. Теперь список реально читается через пакет `installed_apps`
/// (Android-only, требует QUERY_ALL_PACKAGES — см. NATIVE_SETUP.md).
///
/// ВАЖНО (осталось честно, принцип 4): включение/выключение тумблера
/// сейчас сохраняет выбор ТОЛЬКО как локальный UI-стейт (в памяти экрана).
/// Реальное распределение трафика по приложениям (какие идут через VPN,
/// какие в обход) требует нативного вызова
/// `VpnService.Builder.addAllowedApplication/addDisallowedApplication` на
/// Android — это должен делать пакет `flutter_vless` при старте туннеля, а
/// подтверждения, что он принимает список пакетов на вход, в его README
/// нет (только `startVless(remark, config, ...)`, без параметра-списка
/// приложений). Поэтому пока список реальный, а фактическая маршрутизация
/// трафика по нему — нет. Если версия flutter_vless, которая реально
/// подтянется через pub get, добавит такой параметр — это единственное
/// место, которое нужно доработать (см. `_bypassedPackages` ниже, уже
/// готов список пакетов для передачи).
///
/// [ИСПРАВЛЕНО] Выбор ("_bypassed") раньше был обычным `Map` полем State —
/// сбрасывался при уходе с экрана/перезапуске приложения (то же семейство
/// багов, что и остальные тумблеры — см. services/local_prefs.dart).
/// Теперь читается/пишется в LocalPrefs при каждом переключении.
class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});
  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  final _prefs = LocalPrefs.instance;
  List<AppInfo> _apps = [];
  final Map<String, bool> _bypassed = {}; // packageName -> "идёт в обход VPN"
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // [НОВОЕ] Восстанавливаем ранее сохранённый выбор ДО показа списка —
    // иначе первая отрисовка на секунду показала бы все тумблеры выключенными
    // (значения по умолчанию), а потом "дёрнулась" бы после чтения из
    // хранилища. Загружаем оба источника параллельно и объединяем один раз.
    final savedBypassed = await _prefs.getBoolMap(PrefKeys.splitTunnelBypass);
    if (!Platform.isAndroid) {
      setState(() {
        _bypassed.addAll(savedBypassed);
        _loading = false;
        _error = 'Выбор приложений доступен только на Android — на этой платформе список системы недоступен.';
      });
      return;
    }
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: true,
        excludeNonLaunchableApps: true,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        _apps = apps;
        _bypassed.addAll(savedBypassed);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        // Частая причина — нет QUERY_ALL_PACKAGES в AndroidManifest.xml
        // (см. NATIVE_SETUP.md) или сборка сделана без прогона scaffold.
        _error = 'Не удалось получить список приложений: $e';
      });
    }
  }

  /// Пакеты, которые пользователь пометил "в обход VPN" — готово для
  /// передачи в нативный слой, когда/если flutter_vless станет это
  /// поддерживать (см. docstring класса).
  List<String> get _bypassedPackages =>
      _bypassed.entries.where((e) => e.value).map((e) => e.key).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppHeader(trailing: Icons.arrow_back_rounded, onTrailingTap: () => Navigator.pop(context)),
                  const Text('Split-туннелирование', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text(
                    'Выбери, какие приложения работают в обход VPN — например банк или локальные сервисы. '
                    'Список — реальные приложения с этого устройства.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Center(
                    child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12), textAlign: TextAlign.center),
                  ),
                ),
              ),
            if (!_loading && _error == null)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _apps.length,
                  itemBuilder: (context, i) {
                    final app = _apps[i];
                    final bypassed = _bypassed[app.packageName] ?? false;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(color: const Color(0xFF1C1330), borderRadius: BorderRadius.circular(9)),
                            alignment: Alignment.center,
                            clipBehavior: Clip.antiAlias,
                            child: app.icon is Uint8List && (app.icon as Uint8List).isNotEmpty
                                ? Image.memory(app.icon as Uint8List, width: 30, height: 30, fit: BoxFit.cover)
                                : const Text('📱', style: TextStyle(fontSize: 14)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(app.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          ),
                          NeonToggle(
                            value: bypassed,
                            onChanged: (v) {
                              setState(() => _bypassed[app.packageName] = v);
                              _prefs.setBoolMap(PrefKeys.splitTunnelBypass, _bypassed);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
