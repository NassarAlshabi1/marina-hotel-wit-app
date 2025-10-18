import 'dart:convert';
import 'package:http/http.dart' as http;

class WhatsAppService {
  static const String _baseUrl = 'https://7103.api.greenapi.com';
  static const String _instanceId = 'waInstance7103894450';
  static const String _token = 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1';

  Future<bool> sendMessage({
    required String phoneE164,
    required String message,
  }) async {
    try {
      final chatId = '${phoneE164}@c.us';
      final url = Uri.parse('$_baseUrl/$_instanceId/sendMessage/$_token');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatId': chatId,
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('WhatsApp message failed: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to send WhatsApp message: ${response.statusCode}');
      }
    } catch (e) {
      print('WhatsApp service error: $e');
      throw Exception('WhatsApp service error: $e');
    }
  }
}