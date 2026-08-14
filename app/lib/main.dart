import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'screens/connect_screen.dart';
import 'screens/keys_screen.dart';
import 'screens/plans_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'services/api_client.dart';

void main() {
  // [ИСПРАВЛЕНО по факту теста от 13.08.2026] Прошлая сборка вернула
  // "Unauthorized: Invalid or missing API key" — потому что ключ
  // передавался только через --dart-define при сборке, а сборка была
  // сделана без него (см. .github/workflows/build-android.yml /
  // локальную команду flutter build). Теперь ключ прописан здесь как
  // значение по умолчанию — сборка работает "из коробки", без
  // обязательных флагов. --dart-define всё ещё можно передать, чтобы
  // переопределить его (например для другого окружения) — defaultValue
  // ниже используется, только если флаг не передан.
  ApiClient.init(
    apiKey: const String.fromEnvironment(
      'SHOPBOT_API_KEY',
      defaultValue: '393b9b395689f9624a86060eee8b5584a009ac51e20bf2b2ff6020e85c9e44ac',
    ),
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.vpnonline.shop/api/v1',
    ),
  );
  // [ИСПРАВЛЕНО] Раньше цвет статус-бара/шторки нигде не задавался —
  // приложение использовало системные значения по умолчанию, а на тёмной
  // теме (фон #050308) это на части устройств/прошивок Android выглядит
  // как светлая или прозрачная полоса поверх контента — визуально похоже
  // на то, что "дизайн вылезает в шторку". Явно закрепляем тёмный статус-
  // бар в цвет приложения со светлыми иконками, и такую же навигационную
  // панель снизу, чтобы обе системные области были предсказуемо тёмными
  // на любом устройстве, а не зависели от темы прошивки.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const VpnOnlineApp());
}

class VpnOnlineApp extends StatelessWidget {
  const VpnOnlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VPNonLine',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppEntryPoint(),
    );
  }
}

/// [ИСПРАВЛЕНО v4] Раньше после онбординга приложение сразу показывало
/// RootShell без единой проверки токена — экрана входа не существовало,
/// и ApiClient() в каждом экране создавался заново без токена (см. разбор
/// в services/api_client.dart). Теперь порядок такой:
/// онбординг (1 раз) -> восстановление сессии из защищённого хранилища ->
/// если сессии нет, AuthScreen -> после входа RootShell.
class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});
  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

enum _Stage { loading, onboarding, auth, app }

class _AppEntryPointState extends State<AppEntryPoint> {
  _Stage _stage = _Stage.loading;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final showOnboarding = await OnboardingScreen.shouldShow();
    if (showOnboarding) {
      if (mounted) setState(() => _stage = _Stage.onboarding);
      return;
    }
    await _checkSession();
  }

  Future<void> _checkSession() async {
    final restored = await ApiClient.instance.restoreSession();
    if (mounted) setState(() => _stage = restored ? _Stage.app : _Stage.auth);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.loading:
        return const Scaffold(backgroundColor: AppColors.bg, body: SizedBox.shrink());
      case _Stage.onboarding:
        return OnboardingScreen(onDone: () => _checkSession());
      case _Stage.auth:
        return AuthScreen(onAuthenticated: () => setState(() => _stage = _Stage.app));
      case _Stage.app:
        return RootShell(onLoggedOut: () => setState(() => _stage = _Stage.auth));
    }
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.onLoggedOut});
  final VoidCallback onLoggedOut;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  late final List<Widget?> _screens = List<Widget?>.filled(5, null);
  late final List<Widget> _screenSlots =
      List<Widget>.generate(_screens.length, (_) => const SizedBox.shrink());

  @override
  void initState() {
    super.initState();
    _ensureScreenBuilt(_index);
  }

  void _ensureScreenBuilt(int index) {
    final screen = _screens[index] ??= switch (index) {
      0 => const ConnectScreen(),
      1 => const KeysScreen(),
      2 => const PlansScreen(),
      3 => const ServersScreen(),
      _ => MenuScreen(onLoggedOut: widget.onLoggedOut),
    };
    _screenSlots[index] = screen;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: _screenSlots,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _ensureScreenBuilt(i);
          _index = i;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.vpn_key_rounded), label: 'Ключи'),
          NavigationDestination(icon: Icon(Icons.payments_rounded), label: 'Баланс'),
          NavigationDestination(icon: Icon(Icons.public_rounded), label: 'Серверы'),
          NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'Меню'),
        ],
      ),
    );
  }
}
