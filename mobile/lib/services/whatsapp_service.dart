// TODO(phase-2): remove this ignore and fix violations (avoid_dynamic_calls)
// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// أنواع واتساب API المدعومة
enum WhatsAppApiType { greenapi, custom }

class WhatsAppService {
  WhatsAppService({
    required this.apiType,
    this.baseUrl,
    this.instanceId,
    this.token,
    this.customUrlTemplate,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final WhatsAppApiType apiType;
  final String? baseUrl;
  final String? instanceId;
  final String? token;
  final String? customUrlTemplate;
  final http.Client _client;

  /// HTTP client للعمليات الخارجية (اختبار الاتصال)
  http.Client get client => _client;

  /// الحد الأقصى لطول الرسالة (حرف)
  static const int maxMessageLength = 1000;

  /// الحد الأدنى لعدد أرقام الهاتف المطلوب
  static const int minPhoneDigits = 12;

  /// إرسال رسالة واتساب
  Future<({bool success, String? quotaMessage})> sendMessage({
    required String phoneE164,
    required String message,
  }) async {
    // التحقق من عدد أرقام الهاتف — يجب أن يكون 12 رقم على الأقل
    final digitsOnly = phoneE164.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < minPhoneDigits) {
      return (success: false, quotaMessage: null);
    }

    final trimmedMessage = _trimMessage(message);

    switch (apiType) {
      case WhatsAppApiType.custom:
        return _sendViaCustom(phoneE164, trimmedMessage);
      case WhatsAppApiType.greenapi:
        return _sendViaGreenApi(phoneE164, trimmedMessage);
    }
  }

  /// إرسال عبر GreenAPI (POST مع JSON body)
  Future<({bool success, String? quotaMessage})> _sendViaGreenApi(
    String phoneE164,
    String message,
  ) async {
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
          final desc =
              json['invokeStatus']?['description'] as String? ??
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

  /// إرسال عبر Custom API (GET مع استبدال المتغيرات في الرابط)
  Future<({bool success, String? quotaMessage})> _sendViaCustom(
    String phoneE164,
    String message,
  ) async {
    if (customUrlTemplate == null || customUrlTemplate!.isEmpty) {
      return (success: false, quotaMessage: 'رابط API المخصص غير مضبوط');
    }

    final sanitizedPhone = phoneE164.startsWith('+')
        ? phoneE164.substring(1)
        : phoneE164;

    try {
      final urlStr = customUrlTemplate!
          .replaceAll('[number]', sanitizedPhone)
          .replaceAll('[text]', Uri.encodeComponent(message))
          .replaceAll('[message]', Uri.encodeComponent(message));

      final endpoint = Uri.parse(urlStr);
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return (success: true, quotaMessage: null);
      }

      debugPrint(
        'Custom WhatsApp API failed: ${response.statusCode} ${response.body}',
      );
      return (success: false, quotaMessage: null);
    } catch (error, stackTrace) {
      debugPrint('Custom WhatsApp send error: $error');
      debugPrint('$stackTrace');
      return (success: false, quotaMessage: null);
    }
  }

  /// اختبار الاتصال بـ API
  Future<({bool success, int statusCode, String body})> testConnection() async {
    switch (apiType) {
      case WhatsAppApiType.custom:
        return _testCustomConnection();
      case WhatsAppApiType.greenapi:
        return _testGreenApiConnection();
    }
  }

  /// اختبار GreenAPI عبر getSettings
  Future<({bool success, int statusCode, String body})>
  _testGreenApiConnection() async {
    final endpoint = Uri.parse('$baseUrl/$instanceId/getSettings/$token');
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

  /// اختبار Custom API
  Future<({bool success, int statusCode, String body})>
  _testCustomConnection() async {
    if (customUrlTemplate == null || customUrlTemplate!.isEmpty) {
      return (success: false, statusCode: 0, body: 'رابط API المخصص فارغ');
    }

    try {
      final testUrl = customUrlTemplate!
          .replaceAll('[number]', '000000000')
          .replaceAll('[text]', Uri.encodeComponent('test'))
          .replaceAll('[message]', Uri.encodeComponent('test'));

      final endpoint = Uri.parse(testUrl);
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 15));

      final isReachable = response.statusCode < 500;
      return (
        success: isReachable,
        statusCode: response.statusCode,
        body: response.body,
      );
    } catch (e) {
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  /// اقتصاص الرسالة لتتلاءم مع الحد الأقصى
  /// يستخدم characters لضمان عدم تقطيع أحرف UTF-8/Arabic
  String _trimMessage(String message) {
    if (message.characters.length <= maxMessageLength) {
      return message;
    }

    debugPrint(
      'WhatsApp message trimmed: ${message.characters.length} → $maxMessageLength chars',
    );

    final lines = message.split('\n');
    String footer = '';
    final footerLines = <String>[];
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.contains('فندق مارينا') ||
          line.contains('مارينا هوتل') ||
          line.contains('للاستفسار') ||
          line.contains('green-api') ||
          line.contains('967')) {
        footerLines.insert(0, lines[i]);
      } else if (footerLines.isNotEmpty) {
        break;
      }
    }
    if (footerLines.isNotEmpty) {
      footer = '\n${footerLines.join('\n')}';
    }

    final availableSpace = maxMessageLength - footer.length - 10;
    if (availableSpace < 100) {
      return '${message.characters.take(maxMessageLength - 3)}...';
    }

    final truncated = message.characters.take(availableSpace).toString();
    return '$truncated...\n$footer';
  }
}
