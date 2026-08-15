import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  late final String baseUrl;
  late final String apiKey;
  String? _authToken;

  static bool _isInitialized = false;

  static Future<void> init({required String baseUrl, required String apiKey}) async {
    if (_isInitialized) return;
    _instance.baseUrl = baseUrl;
    _instance.apiKey = apiKey;
    _isInitialized = true;
  }

  Map<String, String> _getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> getProfile(String email) async {
    final uri = Uri.parse('$baseUrl/user/profile').replace(queryParameters: {'email': email});
    try {
      final response = await http.get(uri, headers: _getHeaders()).timeout(const Duration(seconds: 10));
      return _processResponse(response);
    } on SocketException {
      throw const HttpException('Отсутствует интернет-соединение.');
    }
  }

  Future<List<Map<String, dynamic>>> getKeys() async {
    // В реальном сценарии идентификатор сессии или ID пользователя извлекается из авторизационного токена
    final uri = Uri.parse('$baseUrl/user/keys').replace(queryParameters: {'user_id': 'current_session_user'});
    try {
      final response = await http.get(uri, headers: _getHeaders()).timeout(const Duration(seconds: 10));
      final processed = _processResponse(response);
      if (processed['status'] == 'success' && processed['data'] is List) {
        return List<Map<String, dynamic>>.from(processed['data']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getHosts() async {
    final uri = Uri.parse('$baseUrl/hosts');
    try {
      final response = await http.get(uri, headers: _getHeaders()).timeout(const Duration(seconds: 10));
      final processed = _processResponse(response);
      if (processed['status'] == 'success' && processed['data'] is List) {
        return List<Map<String, dynamic>>.from(processed['data']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Map<String, dynamic> _processResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw const HttpException('Ошибка авторизации: Неверный API ключ.');
    }
    if (response.statusCode >= 500) {
      throw const HttpException('Внутренняя ошибка сервера бэкенда.');
    }
    
    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Неверный формат ответа сервера.');
  }
}
