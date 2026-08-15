import 'package:flutter/material.dart';
import '../services/api_client.dart';

class PlansScreen extends StatefulWidget {
  final String? extendKeyId;
  const PlansScreen({Key? key, this.extendKeyId}) : super(key: key);

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final ApiClient _api = ApiClient.instance;
  bool _isLoading = false;
  List<dynamic> _plans = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await _api.getPlans();
      if (response['status'] == 'success' && response['data'] is List) {
        setState(() {
          _plans = response['data'];
        });
      } else {
        setState(() {
          _errorMessage = 'Не удалось загрузить тарифные планы';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('ApiException: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePurchase(String planId) async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (widget.extendKeyId != null) {
        await _api.extendKey(keyId: widget.extendKeyId!, planId: planId);
        _showSnackBar('Подписка успешно продлена!');
      } else {
        await _api.createKey(planId);
        _showSnackBar('Новый VPN ключ успешно создан!');
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('ApiException: ', ''));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text(widget.extendKeyId != null ? 'Продление подписки' : 'Тарифные планы'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFFB026FF))))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : ListView.builder(
                  itemCount: _plans.length,
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    return Card(
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: Text(plan['name'] ?? 'Тариф', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${plan['duration_days'] ?? 0} дней • Лимит устройств: ${plan['devices_limit'] ?? 1}'),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB026FF),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _handlePurchase(plan['id'].toString()),
                          child: Text('${plan['price'] ?? 0} ₽'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
