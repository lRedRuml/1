import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// Класс-заглушка ошибок для совместимости с кодом экранов (plans_screen и topup_screen)
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  static ApiClient get instance => _instance;

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
      throw ApiException('Отсутствует интернет-соединение.');
    }
  }

  Future<List<Map<String, dynamic>>> getKeys() async {
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

  // --- Новые методы для интеграции с планами и биллингом ---

  Future<Map<String, dynamic>> getPlans() async {
    final uri = Uri.parse('$baseUrl/plans');
    try {
      final response = await http.get(uri, headers: _getHeaders()).timeout(const Duration(seconds: 10));
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Ошибка сети при загрузке тарифных планов.');
    }
  }

  Future<Map<String, dynamic>> createKey(String planId) async {
    final uri = Uri.parse('$baseUrl/keys/create');
    try {
      final response = await http.post(
        uri, 
        headers: _getHeaders(),
        body: json.encode({'plan_id': planId}),
      ).timeout(const Duration(seconds: 10));
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Ошибка сети при выпуске ключа.');
    }
  }

  Future<Map<String, dynamic>> extendKey({required String keyId, required String planId}) async {
    final uri = Uri.parse('$baseUrl/keys/extend');
    try {
      final response = await http.post(
        uri, 
        headers: _getHeaders(),
        body: json.encode({'key_id': keyId, 'plan_id': planId}),
      ).timeout(const Duration(seconds: 10));
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Ошибка сети при продлении подписки.');
    }
  }

  Future<String> billingTopup({required double amount, required String method}) async {
    final uri = Uri.parse('$baseUrl/billing/topup');
    try {
      final response = await http.post(
        uri, 
        headers: _getHeaders(),
        body: json.encode({'amount': amount, 'method': method}),
      ).timeout(const Duration(seconds: 10));
      
      final processed = _processResponse(response);
      if (processed['status'] == 'success' && processed['data'] != null) {
        return processed['data']['payment_url'] ?? '';
      }
      throw ApiException('Не удалось получить ссылку на оплату.');
    } on SocketException {
      throw ApiException('Ошибка сети при формировании счета.');
    }
  }

  Map<String, dynamic> _processResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw ApiException('Ошибка авторизации: Неверный API ключ.');
    }
    if (response.statusCode >= 500) {
      throw ApiException('Внутренняя ошибка сервера бэкенда.');
    }
    
    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      if (decoded['status'] == 'error' || decoded['error'] != null) {
        throw ApiException(decoded['error'] ?? decoded['message'] ?? 'Неизвестная ошибка сервера.');
      }
      return decoded;
    }
    throw ApiException('Неверный формат ответа сервера.');
  }
}
