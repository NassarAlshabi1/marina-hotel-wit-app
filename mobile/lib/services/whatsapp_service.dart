import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// أنواع واتساب API المدعومة
enum WhatsAppApiType {
  greenapi,
  custom,
  sendzen,
}

class WhatsAppService {
  WhatsAppService({
    required this.apiType,
    this.baseUrl,
    this.instanceId,
    this.token,
    this.customUrlTemplate,
    this.sendzenApiKey,
    this.sendzenFromNumber,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final WhatsAppApiType apiType;
  final String? baseUrl;
  final String? instanceId;
  final String? token;
  final String? customUrlTemplate;
  final String? sendzenApiKey;
  final String? sendzenFromNumber;
  final http.Client _client;

  /// HTTP client للعمليات الخارجية (اختبار الاتصال)
  http.Client get client => _client;

  /// الحد الأقصى لطول الرسالة (حرف)
  static const int maxMessageLength = 1000;

  /// إرسال رسالة واتساب
  Future<({bool success, String? quotaMessage})> sendMessage({
    required String phoneE164,
    required String message,
  }) async {
    final trimmedMessage = _trimMessage(message);

    switch (apiType) {
      case WhatsAppApiType.custom:
        return _sendViaCustom(phoneE164, trimmedMessage);
      case WhatsAppApiType.sendzen:
        return _sendViaSendZen(phoneE164, trimmedMessage);
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
          .replaceAll('[message]', Uri.encodeComponent(message));

      final endpoint = Uri.parse(urlStr);
      final response = await _client.get(endpoint).timeout(
        const Duration(seconds: 15),
      );

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

  /// إرسال عبر SendZen API (POST مع Bearer token)
  /// Endpoint: POST https://api.sendzen.io/v1/messages
  /// Body: {"from": "sender", "to": "recipient", "type": "text", "text": {"body": "msg"}}
  Future<({bool success, String? quotaMessage})> _sendViaSendZen(
    String phoneE164,
    String message,
  ) async {
    if (sendzenApiKey == null ||
        sendzenApiKey!.isEmpty ||
        sendzenFromNumber == null ||
        sendzenFromNumber!.isEmpty) {
      return (success: false, quotaMessage: 'إعدادات SendZen غير مكتملة');
    }

    final sanitizedPhone = phoneE164.startsWith('+')
        ? phoneE164.substring(1)
        : phoneE164;

    final endpoint = Uri.parse('https://api.sendzen.io/v1/messages');

    try {
      final response = await _client.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $sendzenApiKey',
        },
        body: jsonEncode({
          'from': sendzenFromNumber,
          'to': sanitizedPhone,
          'type': 'text',
          'text': {
            'body': message,
            'preview_url': false,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      // SendZen يُرجع 202 Accepted عند النجاح (ليس 200 أو 201)
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 202) {
        return (success: true, quotaMessage: null);
      }

      // 401 = API key غير صالح
      if (response.statusCode == 401) {
        return (success: false, quotaMessage: 'مفتاح API غير صالح أو منتهي');
      }

      // 402 أو 429 = تجاوز الحصة
      if (response.statusCode == 402 || response.statusCode == 429) {
        return (
          success: false,
          quotaMessage: 'تجاوز الحصة الشهرية (600 رسالة مجانية)',
        );
      }

      // 400/422 = خطأ في البيانات — استخراج رسالة الخطأ من JSON
      if (response.statusCode == 400 || response.statusCode == 422) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final msg = json['message'] as String? ?? '';
          final data = json['data'];
          String detail = msg;
          if (data is List && data.isNotEmpty) {
            detail += ' (${data.join(', ')})';
          }
          return (success: false, quotaMessage: detail.isNotEmpty ? detail : null);
        } catch (_) {
          return (success: false, quotaMessage: null);
        }
      }

      debugPrint(
        'SendZen send failed: ${response.statusCode} ${response.body}',
      );
      return (success: false, quotaMessage: null);
    } catch (error, stackTrace) {
      debugPrint('SendZen send error: $error');
      debugPrint('$stackTrace');
      return (success: false, quotaMessage: null);
    }
  }

  /// اختبار الاتصال بـ API
  Future<({bool success, int statusCode, String body})> testConnection() async {
    switch (apiType) {
      case WhatsAppApiType.custom:
        return _testCustomConnection();
      case WhatsAppApiType.sendzen:
        return _testSendZenConnection();
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
      return (
        success: false,
        statusCode: 0,
        body: 'رابط API المخصص فارغ',
      );
    }

    try {
      final testUrl = customUrlTemplate!
          .replaceAll('[number]', '000000000')
          .replaceAll('[message]', Uri.encodeComponent('test'));

      final endpoint = Uri.parse(testUrl);
      final response = await _client.get(endpoint).timeout(
        const Duration(seconds: 15),
      );

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

  /// اختبار SendZen عبر طلب POST لمحاكاة إرسال رسالة
  /// يستخدم endpoint الرسائل لأنه يعمل مع مفاتيح Sandbox والإنتاج
  /// لا يتم إرسال رسالة حقيقية — فقط التحقق من صحة المفتاح
  Future<({bool success, int statusCode, String body})>
      _testSendZenConnection() async {
    if (sendzenApiKey == null || sendzenApiKey!.isEmpty) {
      return (
        success: false,
        statusCode: 0,
        body: 'مفتاح API غير موجود',
      );
    }

    try {
      final endpoint = Uri.parse('https://api.sendzen.io/v1/messages');
      final response = await _client.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $sendzenApiKey',
        },
        body: jsonEncode({
          // بيانات اختبار — لن يتم إرسالها فعلياً لأن الرقم غير صالح
          'from': sendzenFromNumber ?? '0000000000',
          'to': '0000000000',
          'type': 'text',
          'text': {'body': 'test', 'preview_url': false},
        }),
      ).timeout(const Duration(seconds: 15));

      // 200/201/202 = نجاح — SendZen يُرجع 202 Accepted عند القبول
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 202) {
        return (
          success: true,
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      // 400/422 = المفتاح صالح لكن البيانات غير صحيحة (متوقع مع بيانات اختبار)
      // هذا يعني أن المفتاح معترف به من الخادم ✅
      if (response.statusCode == 400 || response.statusCode == 422) {
        return (
          success: true,
          statusCode: response.statusCode,
          body: 'تم التحقق من المفتاح بنجاح — الخادم يعترف بالمفتاح',
        );
      }

      // 401/403 = مفتاح غير صالح أو غير مصرح ❌
      if (response.statusCode == 401 || response.statusCode == 403) {
        return (
          success: false,
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      // أي شيء آخر (5xx الخ) = الخادم يواجه مشكلة
      return (
        success: false,
        statusCode: response.statusCode,
        body: response.body,
      );
    } catch (e) {
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  /// اقتصاص الرسالة لتتلاءم مع الحد الأقصى
  String _trimMessage(String message) {
    if (message.length <= maxMessageLength) return message;

    debugPrint(
      'WhatsApp message trimmed: ${message.length} → $maxMessageLength chars',
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
      return message.substring(0, maxMessageLength - 3) + '...';
    }

    final truncated = message.substring(0, availableSpace);
    return '$truncated...\n$footer';
  }
}
