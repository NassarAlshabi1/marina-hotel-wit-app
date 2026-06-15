import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'telegram_config.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// عميل API للتواصل مع Telegram Bot API
class TelegramApiClient {

  factory TelegramApiClient.instance() => _instance ??= TelegramApiClient._();
  TelegramApiClient._();
  static TelegramApiClient? _instance;

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
        AppLogger.info('✅ Telegram: تم إرسال الرسالة بنجاح', tag: 'APP');
        return true;
      } else {
        AppLogger.warning(
  '⚠️ Telegram: فشل الإرسال: ${data['description']}',
  tag: 'APP',
);
        return false;
      }
    } catch (e) {
      AppLogger.warning('❌ Telegram خطأ: $e', tag: 'APP');
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
      AppLogger.warning('⚠️ Telegram: Chat ID غير مضبوط', tag: 'APP');
      return false;
    }

    return sendMessage(
      chatId: chatId,
      text: text,
      parseMode: parseMode,
    );
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

    return sendMessage(
      chatId: chatId,
      text: buffer.toString().trimRight(),
    );
  }

  /// اختبار الاتصال بالبوت
  Future<bool> testConnection() async {
    try {
      await _updateToken();

      final response = await _client.get(
        Uri.parse(_apiUrl('getMe')),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (e) {
      AppLogger.warning('❌ Telegram: فشل اختبار الاتصال: $e', tag: 'APP');
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
