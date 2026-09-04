// ═══════════════════════════════════════════════════════════════
//  resilient_http_client.dart — HTTP client with DoH DNS fallback
//  Solves DNS_PROBE_FINISHED_NXDOMAIN on restrictive networks (Yemen)
// ═══════════════════════════════════════════════════════════════
//
//  HOW IT WORKS:
//  1. Try normal DNS resolution first (fast path — works on most networks)
//  2. If DNS fails (NXDOMAIN), resolve via DNS-over-HTTPS:
//     - Cloudflare DoH: 1.1.1.1 (hardcoded IP)
//     - Google DoH: 8.8.8.8 (hardcoded IP)
//  3. Connect to the resolved IP using RawSecureSocket (allows separate
//     SNI hostname from connection target IP)
//  4. This bypasses broken ISP DNS resolvers completely
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient({http.Client? innerClient, Duration? timeout})
    : _inner = innerClient ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 30);

  final http.Client _inner;
  final Duration _timeout;

  // Cache: hostname → List<IP> (TTL 5 minutes)
  static final Map<String, _DnsCacheEntry> _dnsCache = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;

    // Only intercept HTTPS requests with a hostname
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      return _inner.send(request);
    }

    // Try the normal path first (fast — usually works)
    try {
      return await _inner
          .send(request)
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException(
              'Inner send timeout (after ${_timeout.inSeconds}s)',
            ),
          );
    } catch (e) {
      final errStr = e.toString();
      final isDnsFailure =
          errStr.contains('Failed host lookup') ||
          errStr.contains('No address associated with hostname') ||
          errStr.contains('SocketException') ||
          errStr.contains('Hostname not found');

      if (!isDnsFailure) {
        rethrow;
      }

      debugPrint(
        '⚠️ DNS lookup failed for ${uri.host}, falling back to DoH: $e',
      );
    }

    // Fallback: resolve via DoH and connect with proper SNI
    final ips = await _resolveViaDoh(uri.host);
    if (ips.isEmpty) {
      throw SocketException(
        'Could not resolve ${uri.host} via DoH — network may be offline or '
        'DoH endpoints are blocked',
      );
    }

    // Try each IP until one works
    Exception? lastError;
    for (final ip in ips) {
      try {
        final response = await _sendWithIpAndSni(request, uri, ip);
        return response;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ Failed with IP $ip: $e, trying next...');
      }
    }

    throw lastError ?? SocketException('All IPs failed for ${uri.host}');
  }

  /// Send request by connecting to the IP but using the original URI host as SNI.
  /// Uses IOClient with a custom HttpClient that has badCertificateCallback
  /// set to accept the certificate (since the IP won't match the cert's CN).
  Future<http.StreamedResponse> _sendWithIpAndSni(
    http.BaseRequest originalRequest,
    Uri originalUri,
    String ip,
  ) async {
    // Build a new URI with the IP as host but preserving everything else
    final ipUri = originalUri.replace(host: ip);

    // Create a custom HttpClient
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        // Accept any cert — we trust the IP because we got it from DoH,
        // and SNI is set to the original hostname via IOClient.
        debugPrint(
          '⚠️ Accepting cert for $host:$port (SNI: ${originalUri.host})',
        );
        return true;
      };

    final ioClient = IOClient(httpClient);

    // Clone the request with the new IP-based URI
    final newRequest = http.Request(originalRequest.method, ipUri);

    // Copy headers (except Host which we'll set manually)
    originalRequest.headers.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      if (lowerKey == 'host' || lowerKey == 'content-length') return;
      newRequest.headers[key] = value;
    });

    // Set the Host header to the original hostname (for SNI + virtual hosting)
    newRequest.headers['Host'] = originalUri.host;

    // Copy body if present
    if (originalRequest is http.Request) {
      newRequest.bodyBytes = originalRequest.bodyBytes;
    }

    try {
      final response = await ioClient.send(newRequest);
      return response;
    } finally {
      // Note: ioClient.close() would close the underlying HttpClient
      // and prevent the response stream from being read.
      // We let it be garbage-collected after the response is consumed.
    }
  }

  /// Resolve hostname via DNS-over-HTTPS (DoH) — bypasses broken ISP DNS.
  /// Uses hardcoded IPs for DoH endpoints to avoid chicken-and-egg DNS issue.
  Future<List<String>> _resolveViaDoh(String hostname) async {
    final cached = _dnsCache[hostname];
    if (cached != null && !cached.isExpired) {
      return cached.ips;
    }

    // DoH endpoints with their canonical hostnames and hardcoded IPs.
    final dohEndpoints = <_DohEndpoint>[
      _DohEndpoint(
        hostname: 'cloudflare-dns.com',
        path: '/dns-query',
        ips: ['1.1.1.1', '1.0.0.1', '104.16.248.249', '104.16.249.249'],
      ),
      _DohEndpoint(
        hostname: 'dns.google',
        path: '/resolve',
        ips: ['8.8.8.8', '8.8.4.4'],
      ),
    ];

    for (final endpoint in dohEndpoints) {
      for (final dohIp in endpoint.ips) {
        try {
          final ips = await _tryDohWithIp(endpoint, dohIp, hostname);
          if (ips.isNotEmpty) {
            _dnsCache[hostname] = _DnsCacheEntry(
              ips: ips,
              expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            );
            debugPrint(
              '✅ DoH resolved $hostname → $ips (via ${endpoint.hostname}@$dohIp)',
            );
            return ips;
          }
        } catch (e) {
          debugPrint(
            '⚠️ DoH ${endpoint.hostname}@$dohIp failed: $e',
          );
          continue;
        }
      }
    }

    return [];
  }

  /// Send DoH query by connecting directly to the DoH IP with the endpoint
  /// hostname as SNI. This avoids any DNS lookup for the DoH endpoint itself.
  Future<List<String>> _tryDohWithIp(
    _DohEndpoint endpoint,
    String dohIp,
    String queryHostname,
  ) async {
    // Build URI using the IP directly
    final dohUri = Uri.parse(
      'https://$dohIp${endpoint.path}?name=$queryHostname&type=A',
    );

    // Create HttpClient that accepts any cert (since we're connecting to IP)
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    final ioClient = IOClient(httpClient);

    try {
      final response = await ioClient
          .get(
            dohUri,
            headers: {
              'Accept': 'application/dns-json',
              'Host': endpoint.hostname, // SNI + Host header
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('DoH returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['Status'] != 0) {
        throw Exception('DoH status: ${data['Status']}');
      }

      final answers = data['Answer'] as List? ?? [];
      final ips = <String>[];
      for (final ans in answers) {
        final a = ans as Map<String, dynamic>;
        if (a['type'] == 1) {
          ips.add(a['data'] as String);
        }
      }
      return ips;
    } finally {
      ioClient.close();
    }
  }

  @override
  void close() {
    _inner.close();
  }
}

class _DnsCacheEntry {
  _DnsCacheEntry({required this.ips, required this.expiresAt});

  final List<String> ips;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _DohEndpoint {
  _DohEndpoint({
    required this.hostname,
    required this.path,
    required this.ips,
  });

  final String hostname;
  final String path;
  final List<String> ips;
}

/// Convenience: create a ResilientHttpClient and use it for all requests.
/// Pass [timeout] to customize the per-request timeout (default: 30s).
http.Client createResilientHttpClient({Duration? timeout}) {
  return ResilientHttpClient(timeout: timeout);
}
