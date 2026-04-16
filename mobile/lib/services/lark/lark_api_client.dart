import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'lark_config.dart';

/// عميل API للتواصل مع خوادم Lark Suite
/// يدعم المصادقة عبر Tenant Access Token والطلبات المباشرة عبر Webhook
class LarkApiClient {
  static LarkApiClient? _instance;
  static LarkApiClient get instance => _instance ??= LarkApiClient._();

  LarkApiClient._();

  final http.Client _client = http.Client();

  String? _cachedToken;
  int? _tokenExpiry;

  /// الحصول على Base URL
  Future<String> get _baseUrl async {
    return await LarkConfig.getBaseUrl();
  }

  /// الحصول على Tenant Access Token صالح
  /// يتم تجديده تلقائياً عند انتهاء الصلاحية
  Future<String> getTenantAccessToken() async {
    // التحقق من وجود رمز صالح في الذاكرة
    if (_cachedToken != null && _tokenExpiry != null) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now < (_tokenExpiry! - LarkConfig.tokenExpiryBufferSeconds)) {
        return _cachedToken!;
      }
    }

    // التحقق من وجود رمز صالح في التخزين المحلي
    if (await LarkConfig.hasValidToken()) {
      final cached = await LarkConfig.getTokenCache();
      final expiry = await LarkConfig.getTokenExpiry();
      _cachedToken = cached;
      _tokenExpiry = expiry;
      return cached!;
    }

    // طلب رمز جديد
    return await _fetchNewToken();
  }

  /// طلب Tenant Access Token جديد من Lark API
  Future<String> _fetchNewToken() async {
    final appId = await LarkConfig.getAppId();
    final appSecret = await LarkConfig.getAppSecret();

    if (appId.isEmpty || appSecret.isEmpty) {
      throw Exception('App ID أو App Secret غير مضبوطين');
    }

    final baseUrl = await _baseUrl;
    final uri = Uri.parse('$baseUrl/open-apis/auth/v3/tenant_access_token/internal');

    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'app_id': appId,
          'app_secret': appSecret,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['code'] == 0 && data['tenant_access_token'] != null) {
        final token = data['tenant_access_token'] as String;
        final expire = data['expire'] as int;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        _cachedToken = token;
        _tokenExpiry = now + expire;

        // تخزين في SharedPreferences
        await LarkConfig.setTokenCache(token, _tokenExpiry!);

        debugPrint('✅ Lark: تم الحصول على Tenant Access Token (ينتهي بعد $expire ثانية)');
        return token;
      } else {
        throw Exception('فشل الحصول على الرمز: ${data['msg']}');
      }
    } catch (e) {
      debugPrint('❌ Lark: خطأ في طلب Tenant Access Token: $e');
      rethrow;
    }
  }

  /// إرسال طلب عام مع إضافة الرمز في الترويسة
  Future<Map<String, dynamic>> authenticatedPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await getTenantAccessToken();
    final baseUrl = await _baseUrl;
    final uri = Uri.parse('$baseUrl$path');

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body != null ? jsonEncode(body) : null,
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      debugPrint('❌ Lark API POST خطأ ($path): $e');
      rethrow;
    }
  }

  /// إرسال طلب GET مع إضافة الرمز في الترويسة
  Future<Map<String, dynamic>> authenticatedGet(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final token = await getTenantAccessToken();
    final baseUrl = await _baseUrl;

    Uri uri;
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
    } else {
      uri = Uri.parse('$baseUrl$path');
    }

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      debugPrint('❌ Lark API GET خطأ ($path): $e');
      rethrow;
    }
  }

  /// إرسال رسالة عبر Incoming Webhook (بدون مصادقة)
  /// هذه أبسط طريقة للبدء — تحتاج فقط Webhook URL
  Future<bool> sendWebhookMessage({
    required String webhookUrl,
    required Map<String, dynamic> message,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 || data['StatusCode'] == 0) {
          debugPrint('✅ Lark Webhook: تم إرسال الرسالة بنجاح');
          return true;
        } else {
          debugPrint('⚠️ Lark Webhook: استجابة غير متوقعة: ${response.body}');
          return false;
        }
      } else {
        debugPrint('❌ Lark Webhook: خطأ HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Lark Webhook خطأ: $e');
      return false;
    }
  }

  /// إرسال رسالة بسيطة (نص عادي) عبر Webhook
  Future<bool> sendSimpleWebhookText({
    required String webhookUrl,
    required String text,
  }) async {
    return sendWebhookMessage(
      webhookUrl: webhookUrl,
      message: {
        'msg_type': 'text',
        'content': {'text': text},
      },
    );
  }

  /// إرسال بطاقة تفاعلية عبر Webhook
  Future<bool> sendWebhookCard({
    required String webhookUrl,
    required String title,
    required String content,
    String? subtitle,
    String themeColor = 'blue',
  }) async {
    final elements = <Map<String, dynamic>>[];

    if (subtitle != null) {
      elements.add({
        'tag': 'div',
        'text': {
          'tag': 'lark_md',
          'content': subtitle,
        },
      });
    }

    elements.add({
      'tag': 'div',
      'text': {
        'tag': 'lark_md',
        'content': content,
      },
    });

    elements.add({'tag': 'hr'});

    elements.add({
      'tag': 'note',
      'elements': [
        {
          'tag': 'plain_text',
          'content': 'Marina Hotel App 🏨',
        },
      ],
    });

    return sendWebhookMessage(
      webhookUrl: webhookUrl,
      message: {
        'msg_type': 'interactive',
        'card': {
          'header': {
            'title': {'tag': 'plain_text', 'content': title},
            'template': themeColor,
          },
          'elements': elements,
        },
      },
    );
  }

  /// إرسال رسالة عبر Bot API (تحتاج مصادقة + chat_id)
  Future<bool> sendBotMessage({
    required String chatId,
    required String msgType,
    required Map<String, dynamic> content,
  }) async {
    try {
      final data = await authenticatedPost(
        '/open-apis/im/v1/messages',
        body: {
          'receive_id': chatId,
          'msg_type': msgType,
          'content': jsonEncode(content),
        },
      );

      if (data['code'] == 0) {
        debugPrint('✅ Lark Bot: تم إرسال الرسالة إلى $chatId');
        return true;
      } else {
        debugPrint('⚠️ Lark Bot: فشل الإرسال: ${data['msg']}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Lark Bot خطأ: $e');
      return false;
    }
  }

  /// مسح الرمز المخزن (عند تغيير الإعدادات)
  Future<void> invalidateToken() async {
    _cachedToken = null;
    _tokenExpiry = null;
    await LarkConfig.clearTokenCache();
    debugPrint('🔓 Lark: تم مسح الرمز المخزن');
  }

  /// اختبار الاتصال بالخادم
  Future<bool> testConnection() async {
    try {
      final appId = await LarkConfig.getAppId();
      final appSecret = await LarkConfig.getAppSecret();
      final webhookUrl = await LarkConfig.getWebhookUrl();

      // اختبار Webhook أولاً (أسهل)
      if (webhookUrl.isNotEmpty) {
        return await sendSimpleWebhookText(
          webhookUrl: webhookUrl,
          text: '🔔 اختبار اتصال Marina Hotel App\n✅ الاتصال بنجاح!',
        );
      }

      // اختبار عبر API مع المصادقة
      if (appId.isNotEmpty && appSecret.isNotEmpty) {
        await getTenantAccessToken();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Lark: فشل اختبار الاتصال: $e');
      return false;
    }
  }
}
