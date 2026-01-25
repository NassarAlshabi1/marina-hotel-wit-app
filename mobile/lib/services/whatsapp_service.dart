import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WhatsAppService {
  final String baseUrl;
  final String instanceId;
  final String token;
  final http.Client _client;

  WhatsAppService({
    required this.baseUrl,
    required this.instanceId,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<bool> sendMessage({
    required String phoneE164,
    required String message,
  }) async {
    final sanitizedPhone =
        phoneE164.startsWith('+') ? phoneE164.substring(1) : phoneE164;
    final chatId = '$sanitizedPhone@c.us';
    final endpoint = Uri.parse('$baseUrl/$instanceId/sendMessage/$token');

    try {
      final response = await _client.post(
        endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chatId': chatId, 'message': message}),
      );
      if (response.statusCode == 200) {
        return true;
      }
      debugPrint(
        'WhatsApp send failed: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint('WhatsApp send error: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }
}
