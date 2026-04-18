import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WhatsAppService {
  WhatsAppService({
    required this.baseUrl,
    required this.instanceId,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl;
  final String instanceId;
  final String token;
  final http.Client _client;

  /// HTTP client للعمليات الخارجية (اختبار الاتصال)
  http.Client get client => _client;

  /// إرسال رسالة واتساب
  /// يُرجع true إذا تم الإرسال بنجاح، false إذا فشل
  /// يُرجع قيمة في quotaExceeded إذا كان رمز 466 (تجاوز الحصة)
  Future<({bool success, String? quotaMessage})> sendMessage({
    required String phoneE164,
    required String message,
  }) async {
    final sanitizedPhone = phoneE164.startsWith('+')
        ? phoneE164.substring(1)
        : phoneE164;
    final chatId = '$sanitizedPhone@c.us';
    final endpoint = Uri.parse('$baseUrl/$instanceId/sendMessage/$token');

    try {
      final response = await _client.post(
        endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chatId': chatId, 'message': message}),
      );
      if (response.statusCode == 200) {
        return (success: true, quotaMessage: null);
      }

      // 466 = تجاوز الحصة الشهرية
      if (response.statusCode == 466) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final desc = json['invokeStatus']?['description'] as String? ??
              json['correspondentsStatus']?['description'] as String? ??
              'تجاوز الحصة الشهرية';
          return (success: false, quotaMessage: desc);
        } catch (_) {
          return (success: false, quotaMessage: 'تجاوز الحصة الشهرية');
        }
      }

      debugPrint(
        'WhatsApp send failed: ${response.statusCode} ${response.body}',
      );
      return (success: false, quotaMessage: null);
    } catch (error, stackTrace) {
      debugPrint('WhatsApp send error: $error');
      debugPrint('$stackTrace');
      return (success: false, quotaMessage: null);
    }
  }

  /// اختبار الاتصال بـ API عبر getSettings (يعمل على الخطة المجانية)
  /// getState يعيد 403 على الخطة المجانية، لذلك نستخدم getSettings بدلاً منه
  Future<({bool success, int statusCode, String body})> testConnection() async {
    final endpoint =
        Uri.parse('$baseUrl/$instanceId/getSettings/$token');
    try {
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 15));
      return (
        success: response.statusCode == 200,
        statusCode: response.statusCode,
        body: response.body,
      );
    } catch (e) {
      return (success: false, statusCode: 0, body: e.toString());
    }
  }
}
