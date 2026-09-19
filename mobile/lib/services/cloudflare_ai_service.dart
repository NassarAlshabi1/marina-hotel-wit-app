import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_config.dart';

class CloudflareAiResult {
  const CloudflareAiResult({
    required this.answer,
    this.plan,
    this.rows = const [],
    this.requiresConfirmation = false,
  });
  final String answer;
  final Map<String, dynamic>? plan;
  final List<Map<String, dynamic>> rows;
  final bool requiresConfirmation;
}

class CloudflareAiService {
  CloudflareAiService._();
  static final instance = CloudflareAiService._();
  static const _storage = FlutterSecureStorage();

  Future<CloudflareAiResult> ask(String prompt) async {
    return _send({'prompt': prompt});
  }

  Future<CloudflareAiResult> confirm(Map<String, dynamic> plan) async {
    return _send({'plan': plan, 'confirm': true});
  }

  Future<CloudflareAiResult> _send(Map<String, dynamic> body) async {
    final token = await _storage.read(key: 'auth_token');
    final response = await http
        .post(
          Uri.parse('${CloudflareConfig.workerUrl}/api/ai/query'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('استجابة غير صالحة من Cloudflare');
    }
    if (response.statusCode >= 400) {
      throw Exception(decoded['error']?.toString() ?? 'فشل الطلب');
    }
    return CloudflareAiResult(
      answer: decoded['answer']?.toString() ?? 'تم استلام الطلب.',
      plan: decoded['plan'] is Map
          ? Map<String, dynamic>.from(decoded['plan'] as Map)
          : null,
      requiresConfirmation: decoded['requires_confirmation'] == true,
      rows: decoded['rows'] is List
          ? (decoded['rows'] as List).whereType<Map<String, dynamic>>().toList()
          : const [],
    );
  }
}
