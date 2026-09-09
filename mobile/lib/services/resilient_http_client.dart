// ═══════════════════════════════════════════════════════════════
//  resilient_http_client.dart — HTTP client with DoH + tunnel fallback
//  Solves DNS blackhole/NXDOMAIN and connect-hang on restrictive
//  networks (Yemen) for *.workers.dev endpoints.
// ═══════════════════════════════════════════════════════════════
//
//  HOW IT WORKS (2026-09-09 redesign):
//  1. FAST PATH: normal request via the inner client, bounded by a SHORT
//     fast-path timeout (6s). Covers the healthy-network case with zero
//     overhead.
//  2. ANY fast-path failure — DNS lookup failure, DNS blackhole (timeout),
//     dropped SYN packets (timeout), dead keep-alive socket, TLS reset —
//     triggers the fallback. The previous design only fell back on DNS
//     errors, so a hanging DNS/connect surfaced as TimeoutException and
//     the fallback never ran (root cause of «المصادقة TimeoutException»).
//  3. COOLDOWN: after one fast-path failure the host is pinned to the
//     fallback path for 10 minutes, so subsequent requests skip the hang
//     entirely.
//  4. RESOLUTION: DNS-over-HTTPS via 6 providers — Cloudflare (1.1.1.1),
//     Google (8.8.8.8), Quad9:5053, dns.sb, AdGuard, ControlD — ALL
//     endpoints raced in PARALLEL, first answer wins (sequential probing
//     could waste 8s per blocked IP). ✅ (2026-09-10) تنويع المزوّدين:
//     اليمن يحجب 1.1.1.1/8.8.8.8 غالباً — مزوّدون أقل شهرةً ينجون من
//     قوائم الحجب نفسها. Results cached 5 min; the last known-good set is
//     kept indefinitely as a stale last-resort. The last IP that actually
//     served a response is retried first on subsequent fallbacks.
//     4b. إذا فشل كل مزوّدي DoH → جسر أخير عبر محلّل النظام نفسه
//     (ينجح للنطاق المخصّص لأن الحجب يستهدف *.workers.dev تحديداً).
//  5. CONNECTION: connect directly to the resolved IP while still doing
//     TLS with the REAL hostname. Dart sends SNI from the URL host, and a
//     URL like https://<ip>/… makes Cloudflare's edge abort the handshake
//     (verified: SSLV3_ALERT_HANDSHAKE_FAILURE) — so the old
//     IP-URL + manual Host header approach could never work. Instead we
//     run a tiny local CONNECT tunnel on 127.0.0.1: HttpClient is pointed
//     at it via findProxy, it forwards bytes to the pinned IP, and Dart
//     performs the TLS handshake INSIDE the tunnel with SNI = real
//     hostname (verified working: 200 OK in ~140ms).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'worker_endpoints.dart';

/// ✅ (2026-09-09) مخطط نقاط النهاية — يعيد قائمة مرشحين مرتّبة لطلب
/// نحو [requestUrl]. قائمة بعنصر واحد = لا تدوير (السلوك السابق).
/// الإنتاج: [WorkerEndpoints.candidatesFor] — النطاق المخصّص ثم
/// workers.dev، مع عزل الطلبات خارج عائلة نقاط الـ worker.
typedef EndpointPlanner = List<Uri> Function(Uri requestUrl);

class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient({
    http.Client? innerClient,
    Duration? timeout,
    Duration? fastTimeout,
    Future<List<String>> Function(String host)? dohResolver,
    Future<List<String>> Function(String host)? systemResolver,
    Future<Socket> Function(String ip, int port)? tunnelConnector,
    SecurityContext? fallbackSecurityContext,
    EndpointPlanner? endpointPlanner,
    void Function(Uri base)? onEndpointSuccess,
    void Function(Uri base)? onEndpointFailure,
  }) : _inner = innerClient ?? _createDefaultInnerClient(),
       _timeout = timeout ?? const Duration(seconds: 30),
       _fastTimeout = fastTimeout ?? const Duration(seconds: 6),
       _dohResolver = dohResolver ?? _defaultDohResolver,
       _systemResolver = systemResolver ?? _defaultSystemResolver,
       _tunnelConnector =
           tunnelConnector ??
           ((String ip, int port) =>
               Socket.connect(ip, port).timeout(const Duration(seconds: 8))),
       _fallbackSecurityContext = fallbackSecurityContext,
       _endpointPlanner = endpointPlanner,
       _onEndpointSuccess = onEndpointSuccess,
       _onEndpointFailure = onEndpointFailure;

  final http.Client _inner;
  final Duration _timeout;
  final Duration _fastTimeout;
  final Future<List<String>> Function(String host) _dohResolver;
  final Future<List<String>> Function(String host) _systemResolver;
  final Future<Socket> Function(String ip, int port) _tunnelConnector;

  /// null = system roots (production: proper cert validation against the
  /// real hostname via SNI). Tests inject a context trusting the test CA.
  final SecurityContext? _fallbackSecurityContext;

  /// ✅ (2026-09-09) تدوير نقاط النهاية (جزء A): فشل كامل على نقطة
  /// (مسار سريع + نفق) → إعادة كتابة الطلب على المرشح التالي.
  /// null = السلوك السابق بلا تدوير (الاختبارات).
  final EndpointPlanner? _endpointPlanner;
  final void Function(Uri base)? _onEndpointSuccess;
  final void Function(Uri base)? _onEndpointFailure;

  // ── Shared learning across instances (single isolate) ──
  /// Fresh DoH results (hostname → IPs), TTL 5 minutes.
  static final Map<String, _DnsCacheEntry> _dnsCache = {};

  /// Last known-good DoH results — never expires; used only when fresh
  /// resolution fails completely.
  static final Map<String, List<String>> _staleDns = {};

  /// The IP that last served a successful response per hostname — tried
  /// first on subsequent fallbacks.
  static final Map<String, String> _lastGoodIp = {};

  /// Fast-path breaker: hostname → blocked-until timestamp (10 min).
  static final Map<String, DateTime> _fastPathBlockedUntil = {};

  // ── Fallback infrastructure (lazy, per instance) ──
  ServerSocket? _tunnelServer;
  http.Client? _activeFallbackClient;
  String? _activeFallbackPin; // 'host|ip' of the active fallback client
  final Map<String, String> _pinnedTargets = {}; // CONNECT host → pinned IP

  static http.Client _createDefaultInnerClient() {
    final hc = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    return IOClient(hc);
  }

  // ═══════════════════════════════════════════════════════════
  //  send()
  // ═══════════════════════════════════════════════════════════
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;

    // Only intercept HTTPS requests with a hostname
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      return _inner.send(request);
    }

    // ✅ (2026-09-09) تدوير نقاط النهاية (جزء A): مخطط يعيد أكثر من
    // مرشح → نجرّب كل نقطة كاملة (مسار سريع + نفق DoH) بالترتيب،
    // وأول نجاح يثبّت نقطته. يغطي حالة اليمن: workers.dev محجوب
    // بـSNI فلا ينجو حتى النفق (SNI حقيقي محجوب) → التدوير للنطاق
    // المخصّص ينجح فوراً.
    final planner = _endpointPlanner;
    if (planner != null) {
      final candidates = planner(uri);
      if (candidates.length > 1) {
        return _sendWithEndpointRotation(request, candidates);
      }
    }

    return _sendWithFastPathAndTunnel(request, uri);
  }

  /// حلقة التدوير بين مرشحي نقاط النهاية.
  /// ملاحظة عقد الأمان: الطلب الأصلي لا يُرسَل مطلقاً هنا — كل مرشح
  /// يعمل على نسخة جديدة (http.Request يُرسَل مرة واحدة؛ النسخة الأولى
  /// تطابق URL الأصلي تماماً).
  Future<http.StreamedResponse> _sendWithEndpointRotation(
    http.BaseRequest request,
    List<Uri> candidates,
  ) async {
    Object? lastError;
    for (final base in candidates) {
      final targetUrl = _mergeUrl(base, request.url);
      final http.BaseRequest attempt;
      try {
        attempt = _cloneRequestTo(request, targetUrl);
      } on ArgumentError {
        rethrow; // نوع طلب غير مدعوم للنسخ — خطأ برمجي لا تدوير شبكي.
      }
      try {
        final response = await _sendWithFastPathAndTunnel(attempt, targetUrl);
        _onEndpointSuccess?.call(base);
        debugPrint('✅ [ResilientHTTP] endpoint ${base.host} succeeded');
        return response;
      } catch (e) {
        _onEndpointFailure?.call(base);
        lastError = e;
        debugPrint(
          '🔁 [ResilientHTTP] endpoint ${base.host} failed '
          '(${e.runtimeType}) → next candidate',
        );
      }
    }
    throw lastError is Exception
        ? lastError
        : SocketException('All ${candidates.length} worker endpoints failed');
  }

  /// المسار الكامل لنقطة واحدة — breaker + مسار سريع + نفق DoH.
  /// ✅ (جزء B) أي استثناء فشل اتصالي يخرج من هنا بلا ابتلاع:
  /// SocketException (reset/refused)، TimeoutException (أسود/بطيء)،
  /// HandshakeException (TLS/SNI مرفوض)، ClientException — كلها
  /// تصل حلقة التدوير فوق مباشرة.
  Future<http.StreamedResponse> _sendWithFastPathAndTunnel(
    http.BaseRequest request,
    Uri uri,
  ) async {
    final host = uri.host;

    // Fast-path breaker open → go straight to the tunnel fallback.
    if (_isFastPathBlocked(host)) {
      debugPrint(
        '↪️ [ResilientHTTP] fast path is cooling down for $host — '
        'going straight to tunnel fallback',
      );
      return _sendViaTunnelFallback(request, host);
    }

    // Fast path (short budget). ANY failure → fallback.
    try {
      return await _inner
          .send(request)
          .timeout(
            _fastTimeout,
            onTimeout: () => throw TimeoutException(
              'Fast path timeout after ${_fastTimeout.inSeconds}s',
            ),
          );
    } catch (e) {
      // DNS failure, DNS blackhole (timeout), dropped SYN (timeout), dead
      // keep-alive socket, TLS reset — all are connectivity failures that
      // the tunnel fallback may bypass.
      _fastPathBlockedUntil[host] = DateTime.now().add(
        const Duration(minutes: 10),
      );
      debugPrint(
        '⚠️ [ResilientHTTP] fast path failed for $host '
        '(${e.runtimeType}) → tunnel fallback: $e',
      );
      return _sendViaTunnelFallback(request, host);
    }
  }

  /// دمج مسار/استعلام الطلب الأصلي على قاعدة مرشح.
  /// القواعد بلا مسار (https://host[:port]) — replace يورّث المنفذ
  /// الضمني من القاعدة ويستبدل المسار والاستعلام فقط.
  Uri _mergeUrl(Uri base, Uri original) => base.replace(
    path: original.path,
    query: original.query.isEmpty ? null : original.query,
  );

  static bool _isFastPathBlocked(String host) {
    final until = _fastPathBlockedUntil[host];
    return until != null && DateTime.now().isBefore(until);
  }

  // ═══════════════════════════════════════════════════════════
  //  Tunnel fallback: DoH IPs + local CONNECT tunnel (SNI-correct)
  // ═══════════════════════════════════════════════════════════
  Future<http.StreamedResponse> _sendViaTunnelFallback(
    http.BaseRequest request,
    String host,
  ) async {
    final ips = await _candidateIps(host);
    if (ips.isEmpty) {
      // ✅ (2026-09-10) رسالة قابلة للتنفيذ: workers.dev محجوب شبكياً في
      // اليمن — إن فشل الحلّ هنا فالمخرج الوحيد نطاق مخصّص، فنوجّه
      // المستخدم له مباشرة بدل تشخيص إنجليزي عامّ.
      final isWorkersDev = host.endsWith('.workers.dev');
      throw SocketException(
        isWorkersDev
            ? 'Could not resolve $host via DoH — الحجب كامل على هذه '
                  'الشبكة: فشل كل مزوّدي DoH وDNS النظام. الحل المضمون: '
                  'أضف نطاقاً مخصّصاً للـ Worker من الإعدادات («نطاق Worker '
                  'مخصص») — حجب workers.dev في اليمن على مستوى الشبكة لا '
                  'يُتجاوَز تطبيقياً'
            : 'Could not resolve $host via DoH — network may be offline or '
                  'DoH endpoints are blocked',
      );
    }

    Exception? lastError;
    for (final ip in ips) {
      try {
        final response = await _sendViaTunnel(request, host, ip).timeout(
          _timeout,
          onTimeout: () => throw TimeoutException(
            'Fallback attempt timeout after ${_timeout.inSeconds}s',
          ),
        );
        _lastGoodIp[host] = ip;
        debugPrint('✅ [ResilientHTTP] tunnel fallback succeeded via $ip');
        return response;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ [ResilientHTTP] fallback via $ip failed: $e');
        // If the local tunnel itself died (bind/port closed), force a
        // re-bind on the next attempt.
        final t = _tunnelServer;
        if (t != null && e is SocketException) {
          unawaited(() async {
            try {
              await t.close();
            } catch (_) {}
          }());
          _tunnelServer = null;
        }
      }
    }
    throw lastError ?? SocketException('All fallback IPs failed for $host');
  }

  /// Candidate IPs, best-first: last-good IP → fresh DoH → stale DoH.
  Future<List<String>> _candidateIps(String host) async {
    final candidates = <String>[];
    final lastGood = _lastGoodIp[host];
    if (lastGood != null) candidates.add(lastGood);

    var fresh = const <String>[];
    try {
      fresh = await _dohResolver(host);
    } catch (e) {
      debugPrint('⚠️ [ResilientHTTP] DoH resolver threw for $host: $e');
    }
    for (final ip in fresh) {
      if (!candidates.contains(ip)) candidates.add(ip);
    }
    for (final ip in _staleDns[host] ?? const <String>[]) {
      if (!candidates.contains(ip)) candidates.add(ip);
    }
    if (candidates.isEmpty) {
      // ✅ (2026-09-10) الجسر الأخير: محلّل النظام نفسه. سيناريوهين:
      // (1) DoH محجوب بالكامل لكن DNS النظام يمرّ عبر الشبكة؛
      // (2) النطاق المخصّص — الحجب يستهدف *.workers.dev تحديداً،
      // فمحلّل الشبكة قد يجيب عليه صحيحاً. الأفضلية للأخير دائماً.
      try {
        final system = await _systemResolver(host);
        for (final ip in system) {
          if (!candidates.contains(ip)) candidates.add(ip);
        }
        if (candidates.isNotEmpty) {
          debugPrint(
            '✅ [ResilientHTTP] system-DNS bridge resolved '
            '$host → $candidates',
          );
        }
      } catch (e) {
        debugPrint('⚠️ [ResilientHTTP] system-DNS bridge failed for $host: $e');
      }
    }
    return candidates.take(6).toList();
  }

  /// جسر DNS النظام — آخر طبقة بعد استنفاد كل مزوّدي DoH.
  /// IPv4 فقط (النفق يربط A-records)، مهلة قصيرة حتى لا يطيل الفشل.
  static Future<List<String>> _defaultSystemResolver(String host) async {
    final results = await InternetAddress.lookup(
      host,
      type: InternetAddressType.IPv4,
    ).timeout(const Duration(seconds: 4));
    return [
      for (final a in results)
        if (!a.isLoopback && !a.isLinkLocal) a.address,
    ].take(4).toList();
  }

  Future<http.StreamedResponse> _sendViaTunnel(
    http.BaseRequest original,
    String host,
    String ip,
  ) async {
    final pin = '$host|$ip';
    if (_activeFallbackClient == null || _activeFallbackPin != pin) {
      final server = await _ensureTunnel();
      _pinnedTargets[host] = ip;
      // A request can only be sent once and pooled sockets belong to the
      // previous pin — rebuild the routing client for this pin. The
      // previous client's responses are already fully consumed by the
      // post()/get() callers used across this app.
      await _closeActiveFallbackClient();
      final hc = HttpClient(context: _fallbackSecurityContext)
        ..connectionTimeout = const Duration(seconds: 8)
        ..findProxy = (Uri uri) => 'PROXY 127.0.0.1:${server.port}';
      _activeFallbackClient = IOClient(hc);
      _activeFallbackPin = pin;
    }
    return _activeFallbackClient!.send(_cloneRequest(original));
  }

  Future<ServerSocket> _ensureTunnel() async {
    final existing = _tunnelServer;
    if (existing != null) return existing;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handleTunnelConnection, onError: (Object _) {});
    _tunnelServer = server;
    return server;
  }

  /// Clones a request so it can be re-sent across fallback attempts.
  /// Only in-memory [http.Request]s are supported (all callers in this
  /// app use post()/get() which build exactly that).
  http.BaseRequest _cloneRequest(http.BaseRequest original) =>
      _cloneRequestTo(original, original.url);

  /// ✅ (2026-09-09) نسخة تدعم إعادة كتابة الـURL — أساس تدوير نقاط
  /// النهاية: نفس الجسم والترويسات على نطاق المرشح التالي.
  http.BaseRequest _cloneRequestTo(http.BaseRequest original, Uri url) {
    if (original is http.Request) {
      final clone = http.Request(original.method, url)
        ..followRedirects = original.followRedirects
        ..persistentConnection = original.persistentConnection
        ..maxRedirects = original.maxRedirects
        ..bodyBytes = original.bodyBytes;
      clone.headers.addAll(original.headers);
      return clone;
    }
    throw ArgumentError(
      'ResilientHttpClient fallback supports http.Request only '
      '(got ${original.runtimeType})',
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Local CONNECT tunnel
  // ═══════════════════════════════════════════════════════════
  void _handleTunnelConnection(Socket client) {
    final buf = BytesBuilder(copy: false);
    final staged = BytesBuilder(copy: false); // post-CONNECT bytes
    var headersDone = false;
    Socket? upstream;
    var upstreamReady = false;

    void tearDown() {
      try {
        upstream?.destroy();
      } catch (_) {}
      try {
        client.destroy();
      } catch (_) {}
    }

    client.listen(
      (Uint8List data) {
        if (!headersDone) {
          buf.add(data);
          final raw = buf.toBytes();
          final end = _findHeaderEnd(raw);
          if (end < 0) return;
          headersDone = true;

          final head = utf8.decode(raw.sublist(0, end), allowMalformed: true);
          final requestLine = head.substring(0, head.indexOf('\r\n'));
          final match = RegExp(
            r'^CONNECT\s+([^\s:]+):(\d+)',
          ).firstMatch(requestLine);
          if (match == null) {
            tearDown();
            return;
          }
          final targetHost = match.group(1)!;
          final targetPort = int.parse(match.group(2)!);

          // Bytes after the CONNECT header block belong to the TLS ClientHello
          // — stage them (binary! never route through utf8 round-trips).
          final leftover = raw.sublist(end + 4);
          if (leftover.isNotEmpty) staged.add(leftover);

          client.add(
            utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
          );

          // Route to the pinned IP when known, else plain passthrough.
          final connectTarget = _pinnedTargets[targetHost] ?? targetHost;
          unawaited(
            _tunnelConnector(connectTarget, targetPort)
                .then((up) {
                  upstream = up;
                  up.listen(
                    client.add,
                    onDone: tearDown,
                    onError: (Object _) => tearDown(),
                  );
                  upstreamReady = true;
                  final bytes = staged.takeBytes();
                  if (bytes.isNotEmpty) {
                    up.add(bytes);
                  }
                })
                .catchError((Object e) {
                  debugPrint('⚠️ [ResilientHTTP] tunnel upstream failed: $e');
                  tearDown();
                }),
          );
          return;
        }
        if (upstreamReady) {
          upstream!.add(data);
        } else {
          staged.add(data);
        }
      },
      onDone: tearDown,
      onError: (Object _) => tearDown(),
    );
  }

  static int _findHeaderEnd(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  // ═══════════════════════════════════════════════════════════
  //  DNS-over-HTTPS — all endpoints raced in parallel
  // ═══════════════════════════════════════════════════════════
  static Future<List<String>> _defaultDohResolver(String hostname) async {
    final cached = _dnsCache[hostname];
    if (cached != null && !cached.isExpired) {
      return cached.ips;
    }

    // DoH endpoints with hardcoded IPs (no chicken-and-egg DNS).
    // ✅ (2026-09-10) 6 مزوّدين بدل 2 — اليمن يحجب Cloudflare/Google
    // تحديداً؛ الصغار ينجون من نفس قوائم الحجب. الكل JSON-API مؤكد
    // (application/dns-json) — من لا يدعمه يرمي داخل السباق بلا ضرر.
    const endpoints = <_DohEndpoint>[
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
      _DohEndpoint(
        hostname: 'dns.quad9.net',
        port: 5053, // JSON API حصرياً هنا؛ 443 = wireformat فقط
        path: '/dns-query',
        ips: ['9.9.9.9', '149.112.112.112'],
      ),
      _DohEndpoint(
        hostname: 'dns.sb',
        path: '/dns-query',
        ips: ['185.222.222.222', '45.11.45.11'],
      ),
      _DohEndpoint(
        hostname: 'dns.adguard-dns.com',
        path: '/dns-query',
        ips: ['94.140.14.14', '94.140.15.15'],
      ),
      _DohEndpoint(
        hostname: 'freedns.controld.com',
        path: '/dns-query',
        ips: ['76.76.2.0', '76.76.10.0'],
      ),
    ];

    // Race ALL endpoint IPs in parallel — first non-empty answer wins.
    // (Sequential probing burned up to 8s per blocked IP: 1.1.1.1 is
    // commonly throttled, so a winning answer could sit 24s+ deep in the
    // queue — far beyond every caller timeout.)
    final first = Completer<List<String>>();
    var remaining = 0;
    for (final endpoint in endpoints) {
      for (final dohIp in endpoint.ips) {
        remaining++;
        unawaited(
          _tryDohWithIp(endpoint, dohIp, hostname)
              .then((ips) {
                if (ips.isNotEmpty && !first.isCompleted) {
                  first.complete(ips);
                  debugPrint(
                    '✅ DoH resolved $hostname → $ips '
                    '(via ${endpoint.hostname}@$dohIp)',
                  );
                }
              })
              .catchError((Object e) {
                debugPrint('⚠️ DoH ${endpoint.hostname}@$dohIp failed: $e');
              })
              .whenComplete(() {
                remaining--;
                if (remaining == 0 && !first.isCompleted) {
                  first.complete(const <String>[]);
                }
              }),
        );
      }
    }

    final result = await first.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => const <String>[],
    );

    if (result.isNotEmpty) {
      _dnsCache[hostname] = _DnsCacheEntry(
        ips: result,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      _staleDns[hostname] = result;
      return result;
    }
    // Fresh resolution failed entirely — stale last-resort.
    return _staleDns[hostname] ?? const <String>[];
  }

  static Future<List<String>> _tryDohWithIp(
    _DohEndpoint endpoint,
    String dohIp,
    String queryHostname,
  ) async {
    // Build URI using the IP directly (+ port when non-default).
    final portPart = endpoint.port == 443 ? '' : ':${endpoint.port}';
    final dohUri = Uri.parse(
      'https://$dohIp$portPart${endpoint.path}?name=$queryHostname&type=A',
    );

    // Accept any cert (we connect to the IP; SNI is an IP literal so the
    // cert name cannot match) — the DoH answer itself is used only to pick
    // an IP for a TLS session that IS properly validated via the tunnel.
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (cert, host, port) => true;
    httpClient.connectionTimeout = const Duration(seconds: 6);

    final ioClient = IOClient(httpClient);

    try {
      final response = await ioClient
          .get(
            dohUri,
            headers: {
              'Accept': 'application/dns-json',
              'Host': endpoint.hostname, // Host routing
            },
          )
          .timeout(const Duration(seconds: 6));

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

  // ═══════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════
  Future<void> _closeActiveFallbackClient() async {
    final c = _activeFallbackClient;
    _activeFallbackClient = null;
    _activeFallbackPin = null;
    try {
      c?.close();
    } catch (_) {}
  }

  @override
  void close() {
    _inner.close();
    unawaited(_closeActiveFallbackClient());
    final t = _tunnelServer;
    _tunnelServer = null;
    if (t != null) {
      unawaited(() async {
        try {
          await t.close();
        } catch (_) {}
      }());
    }
  }

  /// Test-only: fast-path cooldown state per hostname.
  @visibleForTesting
  static bool isFastPathBlockedFor(String host) {
    final until = _fastPathBlockedUntil[host];
    return until != null && DateTime.now().isBefore(until);
  }

  /// Test-only: clear all shared learning (cooldown, caches, last-good).
  @visibleForTesting
  static void resetSharedState() {
    _fastPathBlockedUntil.clear();
    _dnsCache.clear();
    _staleDns.clear();
    _lastGoodIp.clear();
  }
}

class _DnsCacheEntry {
  _DnsCacheEntry({required this.ips, required this.expiresAt});

  final List<String> ips;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _DohEndpoint {
  const _DohEndpoint({
    required this.hostname,
    required this.path,
    required this.ips,
    this.port = 443,
  });

  final String hostname;
  final String path;
  final List<String> ips;
  final int port;
}

/// Convenience: create a ResilientHttpClient and use it for all requests.
/// Pass [timeout] to customize the per-attempt fallback timeout (default:
/// 30s). The fast path always uses a short 6s budget before switching to
/// the tunnel fallback.
///
/// ✅ (2026-09-09) يوصل تدوير نقاط الـ worker تلقائياً (جزء A):
/// المرشحون من [WorkerEndpoints] — النطاق المخصّص (إن ضبطه المستخدم)
/// ثم workers.dev؛ النجاح يثبّت النقطة (sticky) والفشل يمرّر للتالي.
http.Client createResilientHttpClient({Duration? timeout}) {
  return ResilientHttpClient(
    timeout: timeout,
    endpointPlanner: WorkerEndpoints.candidatesFor,
    onEndpointSuccess: WorkerEndpoints.reportSuccess,
    onEndpointFailure: WorkerEndpoints.reportFailure,
  );
}
