import 'package:flutter/material.dart';
import 'services/api_client.dart';
import 'screens/connect_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  const String apiKey = String.fromEnvironment(
    'SHOPBOT_API_KEY',
    defaultValue: 'default_fallback_secure_key_2026',
  );
  
  const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://vpnonline.shop',
  );

  await ApiClient.init(baseUrl: baseUrl, apiKey: apiKey);

  runApp(const VpnOnLineApp());
}

class VpnOnLineApp extends StatelessWidget {
  const VpnOnLineApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VPN onLine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB026FF),
          secondary: Color(0xFFE042E0),
          background: Color(0xFF000000),
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}
