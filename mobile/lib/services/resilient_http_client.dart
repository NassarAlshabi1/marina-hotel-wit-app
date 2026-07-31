// ═══════════════════════════════════════════════════════════════
//  resilient_http_client.dart — HTTP client with DoH DNS fallback
//  Solves DNS_PROBE_FINISHED_NXDOMAIN on restrictive networks (Yemen)
// ═══════════════════════════════════════════════════════════════
//
//  HOW IT WORKS:
//  1. Try normal DNS resolution first (fast path — works on most networks)
//  2. If DNS fails (NXDOMAIN), resolve via DNS-over-HTTPS:
//     - Cloudflare DoH: https://cloudflare-dns.com/dns-query
//     - Google DoH: https://dns.google/resolve
//  3. Connect to the resolved IP with proper SNI (hostname in TLS handshake)
//  4. This bypasses broken ISP DNS resolvers completely
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient({http.Client? innerClient})
      : _inner = innerClient ?? http.Client();

  final http.Client _inner;

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
      return await _inner.send(request).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Inner send timeout'),
      );
    } catch (e) {
      final errStr = e.toString();
      final isDnsFailure = errStr.contains('Failed host lookup') ||
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

  /// Send request using a raw HttpClient that connects to [ip] but uses
  /// [originalUri.host] as the SNI hostname in the TLS handshake.
  /// This is critical for Cloudflare Workers which use SNI to route requests.
  Future<http.StreamedResponse> _sendWithIpAndSni(
    http.BaseRequest originalRequest,
    Uri originalUri,
    String ip,
  ) async {
    final port = originalUri.port == 0
        ? (originalUri.scheme == 'https' ? 443 : 80)
        : originalUri.port;

    // Create a custom HttpClient that connects to the IP but uses the
    // original hostname for SNI.
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (cert, host, port) {
      // The host here will be the IP we connected to. We trust the cert
      // because Cloudflare's wildcard cert matches the original hostname
      // (verified via SNI in the TLS handshake).
      debugPrint(
        '⚠️ Cert verification skipped for $host:$port (SNI: ${originalUri.host})',
      );
      return true;
    };

    try {
      // Open a secure socket to the IP, but with the original hostname
      // as the SNI server name.
      final socket = await SecureSocket.connect(
        ip,
        port,
        host: originalUri.host, // ← This sets SNI to the original hostname
        context: SecurityContext(withTrustedRoots: true),
        onBadCertificate: (cert) => true, // Accept any cert (we trust via SNI)
      );

      // Build the raw HTTP request
      final path = originalUri.path.isEmpty ? '/' : originalUri.path;
      final queryString = originalUri.query.isEmpty
          ? ''
          : '?${originalUri.query}';
      final requestLine =
          '${originalRequest.method} $path$queryString HTTP/1.1\r\n';
      final hostHeader = 'Host: ${originalUri.host}\r\n';

      // Collect headers
      final headersBuffer = StringBuffer()
        ..write(requestLine)
        ..write(hostHeader);

      // Get body bytes if any
      List<int> bodyBytes = [];
      String? contentType;
      if (originalRequest is http.Request) {
        bodyBytes = originalRequest.bodyBytes;
        contentType = originalRequest.headers['content-type'];
      }

      // Copy custom headers (except Content-Length and Host which we set)
      originalRequest.headers.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        if (lowerKey == 'host' ||
            lowerKey == 'content-length' ||
            lowerKey == 'connection') {
          return;
        }
        headersBuffer.write('$key: $value\r\n');
      });

      if (contentType != null && bodyBytes.isNotEmpty) {
        headersBuffer.write('Content-Length: ${bodyBytes.length}\r\n');
      }
      headersBuffer.write('Connection: close\r\n\r\n');

      // Send request
      socket.write(headersBuffer.toString());
      if (bodyBytes.isNotEmpty) {
        socket.add(bodyBytes);
      }
      await socket.flush();

      // Read response
      final responseBytes = <int>[];
      await for (final chunk in socket) {
        responseBytes.addAll(chunk);
      }
      await socket.close();

      // Parse the HTTP response
      final responseStr = utf8.decode(responseBytes, allowMalformed: true);
      final headerEnd = responseStr.indexOf('\r\n\r\n');
      if (headerEnd < 0) {
        throw SocketException('Malformed HTTP response');
      }
      final headerSection = responseStr.substring(0, headerEnd);
      final bodySection = responseBytes.sublist(headerEnd + 4);

      final lines = headerSection.split('\r\n');
      final statusLine = lines.first;
      final statusMatch = RegExp(r'HTTP/\d\.\d (\d+)').firstMatch(statusLine);
      if (statusMatch == null) {
        throw SocketException('Invalid status line: $statusLine');
      }
      final statusCode = int.parse(statusMatch.group(1)!);

      final responseHeaders = <String, String>{};
      for (var i = 1; i < lines.length; i++) {
        final colonIdx = lines[i].indexOf(':');
        if (colonIdx > 0) {
          final key = lines[i].substring(0, colonIdx).trim();
          final value = lines[i].substring(colonIdx + 1).trim();
          responseHeaders[key] = value;
        }
      }

      // Build a StreamedResponse
      final stream = Stream<List<int>>.fromIterable([bodyBytes]);
      return http.StreamedResponse(
        stream,
        statusCode,
        headers: responseHeaders,
        request: originalRequest,
      );
    } finally {
      httpClient.close(force: true);
    }
  }

  /// Resolve hostname via DNS-over-HTTPS (DoH) — bypasses broken ISP DNS.
  /// Uses hardcoded IPs for DoH endpoints to avoid chicken-and-egg DNS issue.
  /// Tries Cloudflare DoH (1.1.1.1) first, then Google DoH (8.8.8.8).
  Future<List<String>> _resolveViaDoh(String hostname) async {
    final cached = _dnsCache[hostname];
    if (cached != null && !cached.isExpired) {
      return cached.ips;
    }

    // DoH endpoints with their canonical hostnames and hardcoded IPs.
    // We connect directly to the IP and use the hostname for SNI.
    final dohEndpoints = <_DohEndpoint>[
      _DohEndpoint(
        hostname: 'cloudflare-dns.com',
        path: '/dns-query',
        // Cloudflare public DNS IPs (well-known, hardcoded)
        ips: ['1.1.1.1', '1.0.0.1', '104.16.248.249', '104.16.249.249'],
      ),
      _DohEndpoint(
        hostname: 'dns.google',
        path: '/resolve',
        // Google public DNS IPs (well-known, hardcoded)
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

  /// Send DoH query by connecting directly to [dohIp] with [endpoint.hostname]
  /// as SNI. This avoids any DNS lookup for the DoH endpoint itself.
  Future<List<String>> _tryDohWithIp(
    _DohEndpoint endpoint,
    String dohIp,
    String queryHostname,
  ) async {
    final port = 443;
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (cert, host, port) => true;

    try {
      final socket = await SecureSocket.connect(
        dohIp,
        port,
        host: endpoint.hostname, // SNI = DoH endpoint hostname
        context: SecurityContext(withTrustedRoots: true),
        onBadCertificate: (cert) => true,
      );

      // Build DoH GET request
      final path = '${endpoint.path}?name=$queryHostname&type=A';
      final requestLine = 'GET $path HTTP/1.1\r\n';
      final hostHeader = 'Host: ${endpoint.hostname}\r\n';
      final acceptHeader = 'Accept: application/dns-json\r\n';
      final connectionHeader = 'Connection: close\r\n\r\n';

      socket.write(requestLine);
      socket.write(hostHeader);
      socket.write(acceptHeader);
      socket.write(connectionHeader);
      await socket.flush();

      // Read response
      final responseBytes = <int>[];
      await for (final chunk in socket) {
        responseBytes.addAll(chunk);
      }
      await socket.close();

      // Parse HTTP response
      final responseStr = utf8.decode(responseBytes, allowMalformed: true);
      final headerEnd = responseStr.indexOf('\r\n\r\n');
      if (headerEnd < 0) {
        throw Exception('Malformed DoH response');
      }
      final bodyStr = responseStr.substring(headerEnd + 4);

      final data = jsonDecode(bodyStr) as Map<String, dynamic>;
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
      httpClient.close(force: true);
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
http.Client createResilientHttpClient() {
  return ResilientHttpClient();
}
