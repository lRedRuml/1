import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';

class TopupScreen extends StatefulWidget {
  const TopupScreen({Key? key}) : super(key: key);

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  final ApiClient _api = ApiClient.instance;
  final TextEditingController _amountController = TextEditingController();
  String _method = 'yookassa';
  bool _isLoading = false;

  Future<void> _executeTopup() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      _showError('Введите сумму пополнения');
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showError('Введите корректную сумму');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final payUrl = await _api.billingTopup(amount: amount, method: _method);
      if (payUrl.isNotEmpty) {
        final uri = Uri.parse(payUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showError('Не удалось открыть платежную ссылку');
        }
      } else {
        _showError('Ошибка генерации ссылки на оплату');
      }
    } catch (e) {
      _showError(e.toString().replaceAll('ApiException: ', ''));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text('Пополнение баланса'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        children: [
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Сумма пополнения (₽)',
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFB026FF))),
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _method,
            dropdownColor: const Color(0xFF1E1E1E),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Способ оплаты'),
            items: const [
              DropdownMenuItem(value: 'yookassa', child: Text('ЮKassa (Карты/СБП)')),
              DropdownMenuItem(value: 'cryptobot', child: Text('CryptoBot (Telegram)')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _method = val);
            },
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB026FF),
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _executeTopup,
              child: _isLoading
                  ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white))
                  : const Text('Перейти к оплате', style: TextStyle(fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }
}
