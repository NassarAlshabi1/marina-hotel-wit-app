import 'dart:async';
import 'dart:io';

import '../utils/debug_log.dart';

/// DNS resolver with fallback mechanism for restricted networks.
///
/// في شبكات محدودة (اليمن، إلخ)، قد تكون resolution للنطاقات محجوبة.
/// هذا الفئة توفر عدة استراتيجيات:
/// 1. معيار DNS (port 53)
/// 2. DNS over HTTPS (DoH) — عبر Google/Cloudflare
/// 3. IP مسجل مسبقاً (hardcoded IPs)
class DNSResolver {
  DNSResolver._();

  /// خريطة IPs المسجلة مسبقاً كنسخة احتياطية أخيرة.
  static const Map<String, String> hardcodedIPs = {
    'marina-hotel-api.adenmarina2.workers.dev': '104.16.132.229',
    'api.adenmarina.com': '104.16.132.230',
    'localhost': '127.0.0.1',
  };

  /// محاولة resolve hostname مع عدة استراتيجيات.
  ///
  /// ترتيب المحاولات:
  /// 1. DNS معياري (الأسرع في الشبكات الطبيعية)
  /// 2. DoH via Google (يعمل في معظم الشبكات المحدودة)
  /// 3. DoH via Cloudflare
  /// 4. IP المسجل مسبقاً (آخر ملاذ)
  ///
  /// يعيد IP address أول محاولة ناجحة، أو يرمي Exception.
  static Future<String> resolve(String hostname) async {
    dlog(() => '🔍 DNS: Resolving $hostname');

    // 1. معيار DNS (port 53)
    try {
      final result = await InternetAddress.lookup(hostname).timeout(
        const Duration(seconds: 5),
      );
      if (result.isNotEmpty) {
        final ip = result[0].address;
        dlog(() => '✅ DNS: Resolved $hostname → $ip (standard DNS)');
        return ip;
      }
    } catch (e) {
      dwarn(() => '⚠️ DNS: Standard lookup failed for $hostname: $e');
    }

    // 2. DoH via Google
    try {
      final ip = await _resolveViaDoH(
        hostname,
        'https://dns.google/dns-query',
      );
      dlog(() => '✅ DNS: Resolved $hostname → $ip (Google DoH)');
      return ip;
    } catch (e) {
      dwarn(() => '⚠️ DNS: Google DoH failed for $hostname: $e');
    }

    // 3. DoH via Cloudflare
    try {
      final ip = await _resolveViaDoH(
        hostname,
        'https://cloudflare-dns.com/dns-query',
      );
      dlog(() => '✅ DNS: Resolved $hostname → $ip (Cloudflare DoH)');
      return ip;
    } catch (e) {
      dwarn(() => '⚠️ DNS: Cloudflare DoH failed for $hostname: $e');
    }

    // 4. IP المسجل مسبقاً (آخر خيار)
    if (hardcodedIPs.containsKey(hostname)) {
      final ip = hardcodedIPs[hostname]!;
      dwarn(() =>
          '⚠️ DNS: Using hardcoded IP for $hostname: $ip (fallback)');
      return ip;
    }

    // فشل تام
    throw Exception(
      'Could not resolve $hostname via any method (standard DNS, DoH, hardcoded)',
    );
  }

  /// DNS over HTTPS (DoH) lookup via Google or Cloudflare.
  ///
  /// بروتوكول DNS over HTTPS أقل عرضة للحجب من DNS معياري.
  /// يُرسل استعلام DNS كـ HTTP GET مع Content-Type: application/dns-message
  static Future<String> _resolveViaDoH(
    String hostname,
    String dohEndpoint,
  ) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(dohEndpoint).replace(
        queryParameters: {
          'name': hostname,
          'type': 'A',  // IPv4 address
        },
      );

      final request = await client.getUrl(uri).timeout(
        const Duration(seconds: 5),
      );
      request.headers.set('Accept', 'application/dns-json');

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode != 200) {
        throw Exception('DoH returned ${response.statusCode}');
      }

      final body = await response.transform(_utf8()).join();
      // بسيط جداً: نتوقع JSON بـ structure: {"Answer":[{"data":"1.2.3.4"},...]}
      // في الممارسة العملية، استخدم json decode للموثوقية
      if (body.contains('"data"')) {
        // استخراج أول IP من الـ response
        final match = RegExp(r'"data":"(\d+\.\d+\.\d+\.\d+)"').firstMatch(body);
        if (match != null) {
          return match.group(1)!;
        }
      }

      throw Exception('Invalid DoH response format');
    } catch (e) {
      rethrow;
    }
  }

  /// تحويل stream من bytes إلى UTF-8 strings.
  static StreamTransformer<List<int>, String> _utf8() {
    return StreamTransformer<List<int>, String>.fromHandlers(
      handleData: (data, sink) {
        try {
          sink.add(String.fromCharCodes(data));
        } catch (e) {
          sink.addError(e);
        }
      },
    );
  }
}
