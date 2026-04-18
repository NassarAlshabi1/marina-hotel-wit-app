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

  /// الحد الأقصى لطول الرسالة (حرف)
  static const int maxMessageLength = 1000;

  /// إرسال رسالة واتساب
  /// يُرجع true إذا تم الإرسال بنجاح، false إذا فشل
  /// يُرجع قيمة في quotaExceeded إذا كان رمز 466 (تجاوز الحصة)
  Future<({bool success, String? quotaMessage})> sendMessage({
    required String phoneE164,
    required String message,
  }) async {
    // اقتصاص الرسالة إذا تجاوزت الحد الأقصى
    final trimmedMessage = _trimMessage(message);
    final sanitizedPhone = phoneE164.startsWith('+')
        ? phoneE164.substring(1)
        : phoneE164;
    final chatId = '$sanitizedPhone@c.us';
    final endpoint = Uri.parse('$baseUrl/$instanceId/sendMessage/$token');

    try {
      final response = await _client.post(
        endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chatId': chatId, 'message': trimmedMessage}),
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

  /// اقتصاص الرسالة لتتلاءم مع الحد الأقصى
  /// يحافظ على التذييل (فندق مارينا + رقم الهاتف) ويقتطع من المنتصف
  String _trimMessage(String message) {
    if (message.length <= maxMessageLength) return message;

    debugPrint(
      'WhatsApp message trimmed: ${message.length} → $maxMessageLength chars',
    );

    // نبحث عن التذييل (آخر 3 أسطر عادة: فندق مارينا + هاتف)
    final lines = message.split('\n');
    String footer = '';
    final footerLines = <String>[];
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.contains('فندق مارينا') ||
          line.contains('للاستفسار') ||
          line.contains('green-api') ||
          line.contains('967')) {
        footerLines.insert(0, lines[i]);
      } else if (footerLines.isNotEmpty) {
        // وصلنا لنهاية التذييل
        break;
      }
    }
    if (footerLines.isNotEmpty) {
      footer = '\n${footerLines.join('\n')}';
    }

    // المساحة المتاحة للمحتوى (مع مراعاة التذييل و ...)
    final availableSpace = maxMessageLength - footer.length - 10; // 10 = '\n...' + buffer
    if (availableSpace < 100) return message.substring(0, maxMessageLength - 3) + '...';

    // اقتطاع المحتوى مع إضافة ... والتذييل
    final truncated = message.substring(0, availableSpace);
    return '$truncated...\n$footer';
  }
}
