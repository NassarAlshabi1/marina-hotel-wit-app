import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'telegram_config.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// عميل API للتواصل مع Telegram Bot API
class TelegramApiClient {
  TelegramApiClient._();
  static TelegramApiClient? _instance;
  // ignore: prefer_constructors_over_static_methods
  static TelegramApiClient get instance => _instance ??= TelegramApiClient._();

  final http.Client _client = http.Client();

  /// تحرير موارد HTTP client
  void dispose() {
    _client.close();
  }

  /// تحرير الموارد الثابتة للـ singleton
  static void disposeInstance() {
    _instance?._client.close();
    _instance = null;
  }

  /// بناء رابط API
  String _apiUrl(String method) {
    return '${TelegramConfig.telegramApiBase}/bot$_cachedToken/$method';
  }

  String _cachedToken = '';

  /// تحديث الرمز
  Future<void> _updateToken() async {
    _cachedToken = await TelegramConfig.getBotToken();
  }

  /// إرسال رسالة نصية
  Future<bool> sendMessage({
    required String chatId,
    required String text,
    String parseMode = 'HTML',
    bool disableWebPagePreview = true,
  }) async {
    try {
      await _updateToken();

      final response = await _client.post(
        Uri.parse(_apiUrl('sendMessage')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': parseMode,
          'disable_web_page_preview': disableWebPagePreview,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['ok'] == true) {
        dlog('✅ Telegram: تم إرسال الرسالة بنجاح');
        return true;
      } else {
        dlog(() => '⚠️ Telegram: فشل الإرسال: ${data['description']}');
        return false;
      }
    } catch (e) {
      dlog(() => '❌ Telegram خطأ: $e');
      return false;
    }
  }

  /// إرسال رسالة إلى Chat ID المحفوظ في الإعدادات
  Future<bool> sendToDefaultChat({
    required String text,
    String parseMode = 'HTML',
  }) async {
    final chatId = await TelegramConfig.getChatId();
    if (chatId.isEmpty) {
      dlog('⚠️ Telegram: Chat ID غير مضبوط');
      return false;
    }

    return sendMessage(chatId: chatId, text: text, parseMode: parseMode);
  }

  /// إرسال رسالة منسقة (Bold + ضربات)
  Future<bool> sendFormattedMessage({
    required String chatId,
    required String title,
    required String body,
    String? footer,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<b>$title</b>');
    buffer.writeln();
    buffer.write(body);
    if (footer != null) {
      buffer.writeln();
      buffer.writeln();
      buffer.writeln('<i>$footer</i>');
    }

    return sendMessage(chatId: chatId, text: buffer.toString().trimRight());
  }

  /// اختبار الاتصال بالبوت
  Future<bool> testConnection() async {
    try {
      await _updateToken();

      final response = await _client.get(Uri.parse(_apiUrl('getMe')));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (e) {
      dlog(() => '❌ Telegram: فشل اختبار الاتصال: $e');
      return false;
    }
  }

  /// اختبار إرسال رسالة
  Future<bool> testSendMessage() async {
    final chatId = await TelegramConfig.getChatId();
    if (chatId.isEmpty) {
      return false;
    }

    return sendFormattedMessage(
      chatId: chatId,
      title: '🔔 اختبار اتصال Marina Hotel App',
      body: '✅ الاتصال بنجاح!\n\n🏨 البوت يعمل بشكل صحيح وستصلك الإشعارات هنا.',
      footer: 'Marina Hotel App',
    );
  }
}
