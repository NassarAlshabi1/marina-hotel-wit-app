import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'telegram_config.dart';

/// عميل API للتواصل مع CallMeBot WhatsApp API
/// بديل Telegram Bot API — يُرسل رسائل WhatsApp مجاناً
class TelegramApiClient {
  static TelegramApiClient? _instance;
  static TelegramApiClient get instance => _instance ??= TelegramApiClient._();

  TelegramApiClient._();

  final http.Client _client = http.Client();

  String _cachedApiKey = '';
  String _cachedPhone = '';

  /// تحديث الإعدادات من SharedPreferences
  Future<void> _updateConfig() async {
    _cachedApiKey = await TelegramConfig.getBotToken(); // API Key من CallMeBot
    _cachedPhone = await TelegramConfig.getChatId();    // رقم الهاتف
  }

  /// إرسال رسالة نصية عبر CallMeBot WhatsApp
  Future<bool> sendMessage({
    required String chatId,
    required String text,
    String parseMode = 'plain', // CallMeBot لا يدعم HTML
    bool disableWebPagePreview = true,
  }) async {
    try {
      await _updateConfig();

      // إزالة تنسيق HTML إذا وجد (WhatsApp لا يدعمه)
      String cleanText = _stripHtml(text);

      // CallMeBot يتطلب الرقم بدون +
      final phone = chatId.replaceAll('+', '');

      final url = Uri.parse(
        '${TelegramConfig.callMeBotUrl}'
        '?phone=${Uri.encodeComponent(phone)}'
        '&text=${Uri.encodeComponent(cleanText)}'
        '&apikey=${Uri.encodeComponent(_cachedApiKey)}',
      );

      final response = await _client.get(url);

      final body = response.body;

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(body) as Map<String, dynamic>;
          if (json['success'] == true || json['sent'] == true) {
            debugPrint('✅ WhatsApp: تم إرسال الرسالة بنجاح');
            return true;
          }
        } catch (_) {
          // رد نصي
          if (body.toLowerCase().contains('sent') ||
              body.toLowerCase().contains('ok') ||
              body.toLowerCase().contains('success')) {
            debugPrint('✅ WhatsApp: تم إرسال الرسالة بنجاح');
            return true;
          }
        }
        debugPrint('⚠️ WhatsApp: فشل الإرسال: $body');
        return false;
      } else {
        debugPrint('⚠️ WhatsApp: فشل الإرسال HTTP ${response.statusCode}: $body');
        return false;
      }
    } catch (e) {
      debugPrint('❌ WhatsApp خطأ: $e');
      return false;
    }
  }

  /// إرسال رسالة إلى الرقم المحفوظ في الإعدادات
  Future<bool> sendToDefaultChat({
    required String text,
    String parseMode = 'plain',
  }) async {
    final chatId = await TelegramConfig.getChatId();
    if (chatId.isEmpty) {
      debugPrint('⚠️ WhatsApp: رقم الهاتف غير مضبوط');
      return false;
    }

    return sendMessage(
      chatId: chatId,
      text: text,
      parseMode: parseMode,
    );
  }

  /// إرسال رسالة منسقة (بدون HTML — WhatsApp لا يدعمه)
  Future<bool> sendFormattedMessage({
    required String chatId,
    required String title,
    required String body,
    String? footer,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(title);
    buffer.writeln('');
    buffer.write(body);
    if (footer != null) {
      buffer.writeln('');
      buffer.writeln('');
      buffer.writeln(footer);
    }

    return sendMessage(
      chatId: chatId,
      text: buffer.toString().trimRight(),
    );
  }

  /// اختبار الاتصال بـ CallMeBot
  Future<bool> testConnection() async {
    try {
      await _updateConfig();

      final phone = _cachedPhone.replaceAll('+', '');
      final url = Uri.parse(
        '${TelegramConfig.callMeBotUrl}'
        '?phone=${Uri.encodeComponent(phone)}'
        '&text=${Uri.encodeComponent("اختبار اتصال - Marina Hotel App")}'
        '&apikey=${Uri.encodeComponent(_cachedApiKey)}',
      );

      final response = await _client.get(url);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ WhatsApp: فشل اختبار الاتصال: $e');
      return false;
    }
  }

  /// اختبار إرسال رسالة
  Future<bool> testSendMessage() async {
    final chatId = await TelegramConfig.getChatId();
    if (chatId.isEmpty) return false;

    return sendFormattedMessage(
      chatId: chatId,
      title: 'اختبار اتصال Marina Hotel App',
      body: 'الاتصال بنجاح!\n\nالبوت يعمل بشكل صحيح وستصلك الإشعارات هنا.',
      footer: 'Marina Hotel App',
    );
  }

  /// إزالة تنسيق HTML من النص (WhatsApp لا يدعم HTML)
  String _stripHtml(String text) {
    return text
        .replaceAll('<b>', '')
        .replaceAll('</b>', '')
        .replaceAll('<i>', '')
        .replaceAll('</i>', '')
        .replaceAll('<code>', '')
        .replaceAll('</code>', '')
        .replaceAll('<pre>', '')
        .replaceAll('</pre>', '')
        .replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trimRight();
  }
}
