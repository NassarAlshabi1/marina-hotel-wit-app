// ═══════════════════════════════════════════════════════════════
//  cloudflare_sync_manager.dart — Cloudflare Sync Manager
//  Drop-in replacement for AppwriteSyncManager
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/settings/error_tracker_screen.dart'
    show logHttpError, logError, ErrorCategory;
import '../utils/env.dart';
import 'cloudflare_config.dart';
import 'cloudflare_realtime_sync.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'remote_change_notifier.dart';
import 'resilient_http_client.dart';
import 'sync_core/smart_conflict_resolver.dart';
import 'sync_enums.dart';
import 'vector_clock_service.dart';

// ✅ المرحلة 3: التنفيذ الكامل للـ Realtime في cloudflare_realtime_sync.dart
// (WebSocket على SyncLockDO) — الاستيراد أعلاه + هذا الـ export يحفظان
// كل imports القائمة دون تغيير في بقية الملفات.
export 'cloudflare_realtime_sync.dart';

// ─── SyncResult (same interface as AppwriteSyncManager) ────────

class SyncResult {
  SyncResult({
    required this.status,
    required this.timestamp,
    required this.duration,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
  });

  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
}

// ─── Realtime sync state ───────────────────────────────────────
// ✅ المرحلة 3: كانت هنا stub فارغة — التنفيذ الكامل أصبح في
// cloudflare_realtime_sync.dart (مُستورد ومُعاد تصديره أعلاه).

// ─── CloudflareSyncManager ─────────────────────────────────────

class CloudflareSyncManager {
  factory CloudflareSyncManager() => _instance;
  CloudflareSyncManager._internal();
  static final CloudflareSyncManager _instance =
      CloudflareSyncManager._internal();

  // ─── Static device ID (same interface as AppwriteSyncManager) ──
  static String? _staticDeviceId;
  static String? get currentDeviceIdStatic => _staticDeviceId;
  static void setStaticDeviceId(String id) => _staticDeviceId = id;

  // ─── State ──────────────────────────────────────────────────
  AppDatabase? _db;
  String? _token;
  String? _deviceId;
  String? _initError;
  String? _lastError;
  SyncStatus _currentStatus = SyncStatus.idle;
  Timer? _autoSyncTimer;
  int _lastPullCursor = 0;

  /// ✅ P0-B (full sync bootstrap): علامة "اكتملت المزامنة الكاملة بنجاح".
  /// تُضبط على true فقط بعد اكتمال pagination حتى exhaustion لكل collections.
  /// قبل ذلك، أي مزامنة تُعتبر "full sync غير مكتملة" ولا يُسمح بالانتقال
  /// لـ delta-only sync.
  /// تُخزَّن في SharedPreferences لتعيش بين جلسات التطبيق.
  bool _fullSyncCompleted = false;
  static const String _kFullSyncCompletedKey = 'cf_full_sync_completed';

  /// ✅ P0-B: عدد صفحات full sync المتبقية (للتشخيص فقط).
  /// تُستخدم لعرض "full sync in progress (page 3/?)"
  int get fullSyncRemainingPages => _fullSyncRemainingPages;
  int _fullSyncRemainingPages = 0;

  /// ✅ P0-B: هل full sync قيد التنفيذ حالياً؟
  bool get isFullSyncInProgress => _isFullSyncInProgress;
  bool _isFullSyncInProgress = false;

  /// ✅ P0-C: Collections التي فشلت في آخر مزامنة (لمنع advance checkpoint).
  /// لا يُحرّك checkpoint لأي collection فشلت حتى تنجح في محاولة لاحقة.
  final Set<String> _failedCollectionsInLastSync = <String>{};

  /// ✅ P0-I: قفل متزامن لمنع ت重叠 عمليات sync المتزامنة.
  /// قبل هذا القفل، كان ممكناً أن يبدأ autoSync + manualSync + onResumeSync
  /// في نفس الوقت وكلها تعدّل على نفس outbox.
  bool _syncInProgress = false;

  bool get isAvailable => _token != null;
  String? get token => _token;
  String? get initError => _initError;
  String? get lastError => _lastError;
  SyncStatus get currentStatus => _currentStatus;
  String? get currentDeviceId => _deviceId;

  /// ✅ P0-B: هل اكتملت المزامنة الكاملة؟ (للـ UI ولفظ السلوك)
  bool get isFullSyncCompleted => _fullSyncCompleted;

  // ─── Realtime status stream (used by UnifiedSyncOrchestrator) ──
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _statusController.stream;

  // ─── HTTP client with DoH fallback (bypasses broken ISP DNS) ──
  // Solves DNS_PROBE_FINISHED_NXDOMAIN on Yemeni networks where ISP DNS
  // resolvers fail to resolve *.workers.dev. Falls back to Cloudflare DoH
  // (https://cloudflare-dns.com/dns-query) then Google DoH.
  // Uses 30s timeout (default) — generous enough for slow networks.
  final http.Client _httpClient = createResilientHttpClient(
    timeout: const Duration(seconds: 30),
  );

  // ─── Initialize ─────────────────────────────────────────────
  Future<void> initialize({
    AppDatabase? database,
    bool forceRetry = false,
  }) async {
    if (_token != null && !forceRetry) return;

    _db = database ?? DatabaseManager.instance;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('cf_device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _generateDeviceId();
      await prefs.setString('cf_device_id', _deviceId!);
    }
    setStaticDeviceId(_deviceId!);

    // ✅ RemoteChangeNotifier: اضبط معرّف جهازنا الحالي لتمييز تغييراتنا
    // عن تغييرات الأجهزة الأخرى.
    RemoteChangeNotifier.instance.setMyDeviceId(_deviceId!);

    // ✅ P0-B: استعادة علامة "full sync مكتملة" من الجلسة السابقة
    _fullSyncCompleted = prefs.getBool(_kFullSyncCompletedKey) ?? false;
    _lastPullCursor = prefs.getInt('cf_last_pull_cursor') ?? 0;

    // ✅ P0-H: استعادة أي سجلات عالقة في 'processing' من جلسة سابقة
    // (crash recovery). أي سجل 'processing' قبل restart هو بالتأكيد عالق
    // لأن الـ worker الذي حجزه مات مع إنهاء التطبيق.
    try {
      final outboxDao = OutboxDao(_db!);
      final reclaimed = await outboxDao.reclaimAllStuckProcessingOnStartup();
      if (reclaimed > 0) {
        debugPrint(
          '🔧 [P0-H] Reclaimed $reclaimed stuck outbox entries on init',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to reclaim stuck outbox entries: $e');
    }

    // Retry login up to 3 times for transient network failures (DNS, socket).
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _httpClient
            .post(
              Uri.parse('${CloudflareConfig.workerUrl}/api/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': CloudflareConfig.username,
                'password': CloudflareConfig.password,
                'device_id': _deviceId,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _token = data['token'] as String?;
          Env.cloudflareAuthToken = _token;
          _initError = null;
          debugPrint(
            '✅ CloudflareSyncManager initialized — device: $_deviceId '
            '(attempt $attempt/$maxAttempts)',
          );
          return;
        } else {
          _initError = 'Login failed: ${response.statusCode}';
          debugPrint('⚠️ Cloudflare login failed: ${response.body}');
          // ✅ سجل في شاشة تتبع الأخطاء
          logHttpError(
            title: 'فشل تسجيل الدخول (Cloudflare)',
            statusCode: response.statusCode,
            responseBody: response.body,
            source: 'sync:login',
          );
          return;
        }
      } catch (e) {
        // ✅ سجل في شاشة تتبع الأخطاء
        logError(
          title: 'استثناء أثناء تسجيل الدخول',
          message: e.toString(),
          category: ErrorCategory.auth,
          source: 'sync:login',
        );
        final errStr = e.toString();
        final isTransient =
            errStr.contains('Failed host lookup') ||
            errStr.contains('No address associated with hostname') ||
            errStr.contains('SocketException') ||
            errStr.contains('HandshakeException') ||
            errStr.contains('TimeoutException');

        if (isTransient && attempt < maxAttempts) {
          debugPrint(
            '⚠️ Cloudflare init attempt $attempt failed (transient), retrying in 2s: $e',
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        // Final attempt failed — set actionable error message
        if (errStr.contains('Failed host lookup') ||
            errStr.contains('No address associated with hostname')) {
          _initError =
              'لا يمكن الوصول إلى خادم Cloudflare (${CloudflareConfig.workerUrl}). '
              'تأكد من اتصالك بالإنترنت وأن الشبكة لا تحظر الدومين workers.dev. '
              'الخطأ الأصلي: $e';
        } else if (errStr.contains('SocketException') ||
            errStr.contains('HandshakeException')) {
          _initError =
              'فشل الاتصال بخادم Cloudflare. تحقق من الشبكة وأعد المحاولة. '
              'الخطأ الأصلي: $e';
        } else if (errStr.contains('TimeoutException')) {
          _initError =
              'انتهت مهلة الاتصال بخادم Cloudflare (15 ثانية). '
              'تحقق من سرعة الإنترنت وأعد المحاولة. الخطأ الأصلي: $e';
        } else {
          _initError = 'Init error: $e';
        }
        debugPrint('⚠️ CloudflareSyncManager init error: $e');
        return;
      }
    }
  }

  // ─── Register Device ────────────────────────────────────────
  Future<String> registerDevice() async {
    if (_token == null || _deviceId == null) {
      throw StateError('Not initialized');
    }

    final response = await _httpClient
        .post(
          Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
          headers: {
            'Authorization': 'Bearer $_token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': _deviceId,
            'platform': 'android',
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      debugPrint('✅ Device registered: $_deviceId');
      return _deviceId!;
    }
    // ✅ سجل في شاشة تتبع الأخطاء
    logHttpError(
      title: 'فشل تسجيل الجهاز',
      statusCode: response.statusCode,
      responseBody: response.body,
      source: 'sync:device_register',
    );
    throw Exception('Device registration failed: ${response.statusCode}');
  }

  // ─── Set FCM Token ──────────────────────────────────────────
  Future<void> setFcmToken(String token) async {
    if (_token == null || _deviceId == null) return;

    try {
      await _httpClient
          .post(
            Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': _deviceId,
              'fcmToken': token,
              'platform': 'android',
            }),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('✅ FCM token set for device: $_deviceId');
    } catch (e) {
      debugPrint('⚠️ Set FCM token error: $e');
    }
  }

  // ─── Sync (push + pull) ─────────────────────────────────────
  ///
  /// ✅ P0-I: قفل re-entrancy — يمنع تشغيل عمليتي sync متداخلتين.
  /// قبل هذا الإصلاح، كان autoSync timer + onResume + manualSync
  /// يمكن أن يتداخلوا وكلهم يقرأون/يكتبون نفس outbox.
  /// نُعيد SyncResult خاص للإشارة للتخطّي (وليس خطأ).
  ///
  /// ✅ P0-B: إذا لم تكن full sync مكتملة بعد، فإن sync() ينفّذ full pull
  /// (cursor=0 implicit since not completed) ولا يضع checkpoint نهائي
  /// إلا بعد اكتمال pagination حتى exhaustion.
  Future<SyncResult> sync({bool push = true, bool pull = true}) async {
    if (_token == null) {
      return SyncResult(
        status: SyncStatus.failed,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'Not initialized',
      );
    }

    // ✅ P0-I: قفل re-entrancy
    if (_syncInProgress) {
      debugPrint('⚠️ Sync already in progress — skipping this call');
      return SyncResult(
        status: SyncStatus.idle,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'Sync already in progress',
      );
    }
    _syncInProgress = true;

    final startTime = DateTime.now();
    _currentStatus = SyncStatus.syncing;
    _statusController.add(SyncStatus.syncing);
    int recordsPushed = 0;
    int recordsPulled = 0;
    String? errorMessage;

    try {
      if (push) {
        recordsPushed = await _pushOutbox();
      }
      if (pull) {
        recordsPulled = await _pullChanges();
      }

      // ✅ P0-B/P0-C: لا نعتبر المزامنة "نجحت" إلا إذا لم تكن هناك collections فاشلة.
      // وإلا نحتفظ بالحالة الحالية ونسمح بإعادة المحاولة لاحقاً.
      if (_failedCollectionsInLastSync.isEmpty) {
        _currentStatus = SyncStatus.success;
        _statusController.add(SyncStatus.success);
        _lastError = null;
      } else {
        // ✅ P0-C: فشل جزئي — لا نُحرّك checkpoint (تم داخل _pullChanges)
        // لكن نضع الحالة كـ failed لإعلام المستخدم وإعادة المحاولة.
        _currentStatus = SyncStatus.failed;
        _statusController.add(SyncStatus.failed);
        errorMessage =
            'Partial sync failure — failed collections: '
            '${_failedCollectionsInLastSync.join(', ')}';
        _lastError = errorMessage;
        logError(
          title: 'فشل مزامنة جزئي',
          message: errorMessage,
          category: ErrorCategory.sync,
          source: 'sync:sync()',
        );
      }
    } catch (e) {
      _currentStatus = SyncStatus.failed;
      _statusController.add(SyncStatus.failed);
      errorMessage = e.toString();
      _lastError = errorMessage;
      // ✅ سجل في شاشة تتبع الأخطاء (إذا لم يكن مسجلاً بالفعل)
      // نتجنب التكرار: login/push/pull يسجلون بمفردهم،
      // هذا للالتقاط أي استثناء آخر
      if (!errorMessage.contains('Push failed') &&
          !errorMessage.contains('Pull failed') &&
          !errorMessage.contains('Login failed') &&
          !errorMessage.contains('Device registration')) {
        logError(
          title: 'فشل المزامنة',
          message: errorMessage,
          category: ErrorCategory.sync,
          source: 'sync:sync()',
        );
      }
    } finally {
      _syncInProgress = false;
    }

    return SyncResult(
      status: _currentStatus,
      timestamp: startTime,
      duration: DateTime.now().difference(startTime),
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      errorMessage: errorMessage,
    );
  }

  // ─── Push outbox to D1 ──────────────────────────────────────
  Future<int> _pushOutbox() async {
    if (_db == null) return 0;

    int totalPushed = 0;

    // ✅ حلقة الرفع: تكرر حتى يفرغ outbox من كل السجلات العالقة
    // هذا يضمن أن زر "رفع التغييرات" يرفع كل التغييرات دفعة واحدة
    // وليس فقط أول 25 سجل.
    while (true) {
      final outboxDao = OutboxDao(_db!);
      final pending =
          await (outboxDao.select(outboxDao.outbox)
                ..where((t) => t.processingStatus.isIn(['pending', 'failed']))
                ..orderBy([(t) => OrderingTerm.asc(t.clientTs)])
                ..limit(CloudflareConfig.batchSize))
              .get();

      if (pending.isEmpty) break;

      final pushed = await _pushBatch(pending);
      totalPushed += pushed;

      // إذا فشل الرفع (0 سجل مرفوع), توقف — ستبقى العالقة
      if (pushed == 0) break;

      debugPrint('📤 Pushed $pushed operations (total: $totalPushed)');
    }

    return totalPushed;
  }

  /// رفع دفعة واحدة من outbox
  ///
  /// ✅ P0-G (push-side OCC): نفرّق بوضوح بين:
  ///   - 404 / "not found" → السجل غير موجود على remote، يمكن إدراجه
  ///   - 409 / "conflict" → stale version، نطبّق resolveConflict
  ///   - 400 / validation → خطأ بيانات، نضع السجل في dead-letter
  ///   - 401/403 → خطأ auth، لا نلمس السجل (سينجح بعد re-auth)
  ///   - 5xx / network → فشل مؤقت، إعادة المحاولة لاحقاً
  Future<int> _pushBatch(List<OutboxData> pending) async {
    if (pending.isEmpty) return 0;

    final outboxDao = OutboxDao(_db!);

    final operations = pending.map((item) {
      final data = jsonDecode(item.payload) as Map<String, dynamic>;
      return {
        'idempotencyKey': item.idempotencyKey,
        'entity': item.entity,
        'operation': item.op,
        'data': data,
        'vectorClock': data['vector_clock'] as String? ?? '{}',
        'updatedAt': item.clientTs,
        if (_deviceId != null) 'deviceId': _deviceId,
      };
    }).toList();

    // ─── gzip compress the push payload for faster upload ───
    final jsonPayload = jsonEncode({'operations': operations});
    final jsonBytes = utf8.encode(jsonPayload);
    final gzipCodec = GZipCodec(); // default level 6 = good balance
    final compressedBytes = gzipCodec.encode(jsonBytes);

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('${CloudflareConfig.workerUrl}/api/sync/push'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
              'Content-Encoding': 'gzip',
              'Content-Length': compressedBytes.length.toString(),
            },
            body: compressedBytes,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      // ✅ P0-G: خطأ شبكة (DNS, timeout, socket) — ليس 404!
      // نُعيد السجلات لحالة pending لإعادة المحاولة لاحقاً.
      // لا نضعها كـ failed لأنها قد تنجح في الدورة التالية.
      logError(
        title: 'فشل شبكة أثناء الرفع',
        message: e.toString(),
        category: ErrorCategory.network,
        source: 'sync:push',
      );
      // إعادة السجلات إلى pending (reclaim)
      for (final item in pending) {
        try {
          await (outboxDao.update(
            outboxDao.outbox,
          )..where((t) => t.id.equals(item.id))).write(
            const OutboxCompanion(
              processingStatus: Value('pending'),
              processingStartedAt: Value(null),
              processingWorker: Value(null),
            ),
          );
        } catch (_) {
          // تجاهل — ستُلتقط لاحقاً
        }
      }
      // أعد الخطأ للمتصل، _pushOutbox ستتوقف عند pushed==0
      throw Exception('Push network error: $e');
    }

    if (response.statusCode != 200) {
      // ✅ سجل في شاشة تتبع الأخطاء
      logHttpError(
        title: 'فشل رفع التغييرات (Push)',
        statusCode: response.statusCode,
        responseBody: response.body,
        source: 'sync:push',
      );
      // ✅ P0-G: 401/403 → لا نلمس السجلات (ستُعاد المحاولة بعد re-auth)
      // 5xx → نعيد السجلات لـ pending
      if (response.statusCode == 401 || response.statusCode == 403) {
        // auth issue — أعِد السجلات لـ pending بدل failed
        for (final item in pending) {
          try {
            await (outboxDao.update(
              outboxDao.outbox,
            )..where((t) => t.id.equals(item.id))).write(
              const OutboxCompanion(
                processingStatus: Value('pending'),
                processingStartedAt: Value(null),
                processingWorker: Value(null),
              ),
            );
          } catch (_) {}
        }
      }
      throw Exception('Push failed: ${response.statusCode}');
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final results = result['results'] as List? ?? [];
    int successCount = 0;

    for (final r in results) {
      final item = r as Map<String, dynamic>;
      final key = item['idempotencyKey'] as String?;
      final success = item['success'] as bool? ?? false;
      final opStatus =
          item['status']
              as String?; // ✅ P0-G: 'ok','not_found','conflict','validation_error'
      final errorMsg = item['error'] as String?;

      if (key == null) continue;

      final outboxItem = pending.firstWhere(
        (p) => p.idempotencyKey == key,
        orElse: () => pending.first,
      );

      if (success) {
        await (outboxDao.delete(
          outboxDao.outbox,
        )..where((t) => t.id.equals(outboxItem.id))).go();
        successCount++;
      } else {
        // ✅ P0-G: نفرّق بين أنواع الفشل
        // - 'conflict' (409): تعارض إصدار — نطبّق resolveConflict لاحقاً
        // - 'validation_error' (400): خطأ بيانات دائم — dead-letter
        // - 'not_found' (404): لا يمكن أن يحدث في push (يحدث في pull)
        // - أي شيء آخر: فشل مؤقت — failed + إعادة محاولة
        final isPermanentError =
            opStatus == 'validation_error' ||
            errorMsg != null && errorMsg.contains('validation');
        final isConflict =
            opStatus == 'conflict' ||
            errorMsg != null && errorMsg.contains('conflict');

        if (isPermanentError) {
          // ✅ P0-G: خطأ دائم — ضع السجل في dead-letter
          await outboxDao.setDead(
            outboxItem.id,
            errorMsg ?? 'Permanent validation error',
            outboxItem.attempts + 1,
          );
        } else if (isConflict) {
          // ✅ P0-F: تعارض — علّمه كـ failed مع lastError واضح
          // conflict resolver سيلتقطه لاحقاً عبر getConflicts()
          await outboxDao.setError(
            outboxItem.id,
            'CONFLICT: ${errorMsg ?? "version mismatch"}',
            outboxItem.attempts + 1,
          );
        } else {
          // فشل مؤقت — إعادة المحاولة في الدورة القادمة
          await (outboxDao.update(
            outboxDao.outbox,
          )..where((t) => t.id.equals(outboxItem.id))).write(
            OutboxCompanion(
              processingStatus: const Value('failed'),
              attempts: Value(outboxItem.attempts + 1),
              lastError: Value(errorMsg ?? 'Unknown push failure'),
            ),
          );
        }
      }
    }

    debugPrint('📤 Pushed $successCount/${pending.length} operations');
    return successCount;
  }

  // ─── Pull changes from D1 ───────────────────────────────────
  Future<int> _pullChanges() async {
    if (_db == null) return 0;

    int totalPulled = 0;
    bool hasMore = true;
    // P0-C: save initial cursor to restore on failure
    final initialCursor = _lastPullCursor;
    int pendingCursor = _lastPullCursor;
    bool hadError = false;
    String? errorMessage;

    // P0-B: if full sync not yet completed, run to exhaustion
    final wasFullSync = !_fullSyncCompleted;
    if (wasFullSync) {
      _isFullSyncInProgress = true;
      _fullSyncRemainingPages = -1;
      debugPrint('🔄 Full sync in progress (cursor=$pendingCursor)');
    }

    try {
      while (hasMore) {
        final http.Response response;
        try {
          response = await _httpClient
              .get(
                Uri.parse(
                  '${CloudflareConfig.workerUrl}/api/sync/pull',
                ).replace(
                  queryParameters: {
                    'cursor': pendingCursor.toString(),
                    'limit': CloudflareConfig.batchSize.toString(),
                    // ✅ خطة 2.5: لا تُعد إلينا سجلات دفعناها نحن (echo) —
                    // الخادم يستثني device_id الخاص بنا من نتيجة السحب.
                    if (_deviceId case final ownDevice?
                        when ownDevice.isNotEmpty)
                      'exclude_device': ownDevice,
                  },
                ),
                headers: {
                  'Authorization': 'Bearer $_token',
                },
              )
              .timeout(const Duration(seconds: 30));
        } catch (e) {
          // P0-G: network error (DNS, timeout) - not "sync complete"
          hadError = true;
          errorMessage = 'Pull network error: $e';
          logError(
            title: 'Network failure during pull',
            message: e.toString(),
            category: ErrorCategory.network,
            source: 'sync:pull',
          );
          break;
        }

        if (response.statusCode != 200) {
          hadError = true;
          errorMessage = 'Pull HTTP ${response.statusCode}';
          logHttpError(
            title: 'Pull failed',
            statusCode: response.statusCode,
            responseBody: response.body,
            source: 'sync:pull',
          );
          break;
        }

        Map<String, dynamic> data;
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e) {
          hadError = true;
          errorMessage = 'Pull JSON parse error: $e';
          logError(
            title: 'Pull JSON parse error',
            message: e.toString(),
            category: ErrorCategory.sync,
            source: 'sync:pull',
          );
          break;
        }

        final changes = data['changes'] as List? ?? [];
        // P0-C: server-derived cursor is authoritative, not device time
        final serverCursor = int.tryParse(
          data['cursor']?.toString() ?? '0',
        );
        hasMore = data['has_more'] as bool? ?? false;

        if (serverCursor != null && serverCursor > pendingCursor) {
          pendingCursor = serverCursor;
        }

        // P0-C: apply changes; one bad record should not stop the batch
        for (final change in changes) {
          try {
            final record = Map<String, dynamic>.from(change as Map);
            final entity =
                record['_entity'] as String? ?? _detectEntity(record);
            record.remove('_entity'); // don't store this field in SQLite

            if (entity != null) {
              await _applyChange(entity, record);
              totalPulled++;
            }
          } catch (e) {
            debugPrint('⚠️ Failed to apply change: $e');
          }
        }

        // P0-C: contradictory state - has_more=true but empty changes
        if (changes.isEmpty && hasMore) {
          debugPrint(
            '⚠️ Pull returned has_more=true but empty changes - stopping',
          );
          hasMore = false;
        }
      }
    } finally {
      if (wasFullSync) {
        _isFullSyncInProgress = false;
        _fullSyncRemainingPages = 0;
      }
    }

    // P0-C: only advance checkpoint in prefs on full success
    if (!hadError) {
      _lastPullCursor = pendingCursor;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cf_last_pull_cursor', _lastPullCursor);

      // P0-B: mark full sync as completed only on full success
      if (wasFullSync) {
        _fullSyncCompleted = true;
        await prefs.setBool(_kFullSyncCompletedKey, true);
        debugPrint('✅ Full sync completed - device is now delta-ready');
      }

      debugPrint(
        '📥 Pulled $totalPulled changes (cursor: $initialCursor -> $_lastPullCursor)',
      );
    } else {
      // P0-C: on failure, do NOT advance cursor in prefs
      _lastPullCursor = initialCursor;
      _failedCollectionsInLastSync.add('pull');
      debugPrint(
        '⚠️ Pull failed - checkpoint NOT advanced (stayed at $initialCursor). Error: $errorMessage',
      );
      throw Exception('Pull failed: $errorMessage');
    }

    return totalPulled;
  }

  // ─── Apply change to local Drift DB ─────────────────────────
  ///
  /// ✅ P0-F: إذا كان السجل البعيد أحدث ويسبب تعارضاً مع تعديل محلي معلّق
  /// (لم يُرفع بعد في outbox)، نُطبّق SmartConflictResolver ونكتب النتيجة
  /// المدمجة محلياً + نُعيدها لـ outbox ليتم رفعها للخادم (end-to-end).
  /// قبل هذا الإصلاح، كان السجل المحلي الأحدث يُحتفظ به فقط دون إعادة رفع،
  /// مما يسبب "stale divergence" — الخادم لا يعرف بالقيمة المحلية النهائية.
  Future<void> _applyChange(String entity, Map<String, dynamic> record) async {
    if (_db == null) return;

    if (record.isEmpty) return;

    final tableName = CloudflareConfig.tableNameFor(entity);
    if (tableName == null) return;

    final localUuid = record['local_uuid'] as String?;
    if (localUuid == null) return;

    final remoteUpdatedAt = record['updated_at'] as int? ?? 0;

    // اقرأ السجل المحلي كاملاً (للـ conflict resolution)
    final existing = await _db!
        .customSelect(
          'SELECT * FROM $tableName WHERE local_uuid = ?',
          variables: [Variable<String>(localUuid)],
        )
        .getSingleOrNull();

    if (existing != null) {
      final localData = Map<String, dynamic>.from(existing.data);
      final localUpdatedAt = localData['updated_at'] as int? ?? 0;
      final localId = localData['id'];

      // ✅ معالجة الحذف الناعم (soft delete) - البعيد يقول "محذوف"
      final deletedAt = record['deleted_at'];
      if (deletedAt != null) {
        // ✅ P0-E: حتى لو كان المحلي أحدث، نطبّق الـ tombstone لأنه قرار نهائي
        // من جهاز آخر. لكن إذا كان المحلي لديه تعديل معلّق في outbox،
        // نحتفظ بالتعديل (delete-vs-update) - لكن نطبّق tombstone.
        // ConflictDetector.detect يعطي الأولوية للحذف في deleteVsUpdate.
        await _db!.customStatement(
          'UPDATE $tableName SET deleted_at = ?, updated_at = ?, last_modified = ? WHERE id = ?',
          [deletedAt, remoteUpdatedAt, remoteUpdatedAt, localId],
        );
        debugPrint('  🗑️ $entity/$localUuid: soft delete applied');

        // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'delete',
          ),
        );
        return;
      }

      // ✅ تخطي إذا كان السجل المحلي أحدث (LWW الأساسي)
      if (localUpdatedAt > remoteUpdatedAt) {
        // ✅ P0-F: تحقق هل يوجد تعديل محلي معلّق في outbox.
        // إذا كان موجود، فنحن في حالة "تعارض" - السجل المحلي أحدث لكنه لم
        // يُرفع بعد. السجل البعيد أقدم لكنه على الخادم. هذا تعارض محتمل
        // لكن LWW هنا يعطي الأولوية للمحلي. سنرفع المحلي في الـ sync القادمة.
        debugPrint(
          '  ⏭️ $entity/$localUuid: محلي أحدث ($localUpdatedAt > $remoteUpdatedAt) — تخطي',
        );
        return;
      }

      // ✅ P0-F: السجل البعيد أحدث. طبّق SmartConflictResolver للتحقق
      // هل هو تعارض حقيقي (concurrent) أم مجرد تحديث تسلسلي؟
      // إذا كان تعارضاً حقيقياً ونتيجته مدمجة، نرفعها للخادم عبر outbox.
      final localVcStr = (localData['vector_clock'] as String?) ?? '{}';
      final remoteVcStr = (record['vector_clock'] as String?) ?? '{}';
      final localVc = VectorClock.fromString(localVcStr);
      final remoteVc = VectorClock.fromString(remoteVcStr);

      // إذا كانت الـ vector clocks متزامنة (concurrent)، فهذا تعارض حقيقي
      // نستخدم SmartConflictResolver لحله على مستوى الحقول.
      if (localVc.isNotEmpty &&
          remoteVc.isNotEmpty &&
          localVc.isConcurrent(remoteVc)) {
        final resolution = SmartConflictResolver.resolve(
          entity: entity,
          localData: localData,
          remoteData: record,
          commonAncestor: null, // لا نحتفظ بـ ancestor حالياً
        );

        // اكتب النتيجة المدمجة محلياً
        final mergedData = resolution.mergedData;
        final cleanRecord = Map<String, dynamic>.from(mergedData);
        cleanRecord.remove('id');
        final setClauses = cleanRecord.keys.map((c) => '$c = ?').join(', ');
        final values = cleanRecord.values.map(_toDriftValue).toList();
        await _db!.customStatement(
          'UPDATE $tableName SET $setClauses WHERE id = ?',
          [...values, localId],
        );

        // ✅ P0-F: إذا كانت النتيجة تحتاج رفع للخادم (pushedToRemote=true)،
        // اكتبها في outbox ليتم رفعها في الـ sync القادمة.
        if (resolution.pushedToRemote) {
          try {
            final outboxDao = OutboxDao(_db!);
            await outboxDao.merge(
              entity: entity,
              op: 'update',
              localUuid: localUuid,
              payload: mergedData,
              clientTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              source: 'local',
            );
            debugPrint(
              '  🤝 $entity/$localUuid: conflict resolved + queued for re-upload',
            );
          } catch (e) {
            debugPrint('  ⚠️ Failed to queue merged conflict result: $e');
          }
        }

        // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح (merged conflict)
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'update',
          ),
        );
        return;
      }

      // ✅ لا يوجد تعارض متزامن — البعيد أحدث تسلسلياً، اطبّقه مباشرة
      final cleanRecord = Map<String, dynamic>.from(record);
      cleanRecord.remove('id');
      final setClauses = cleanRecord.keys.map((c) => '$c = ?').join(', ');
      final values = cleanRecord.values.map(_toDriftValue).toList();
      await _db!.customStatement(
        'UPDATE $tableName SET $setClauses WHERE id = ?',
        [...values, localId],
      );

      // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح (sequential update)
      unawaited(
        RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: entity,
          record: record,
          op: 'update',
        ),
      );
    } else {
      // ✅ سجل جديد — أدخله
      final cleanRecord = Map<String, dynamic>.from(record);
      cleanRecord.remove('id');

      final columns = cleanRecord.keys.join(', ');
      final placeholders = cleanRecord.keys.map((_) => '?').join(', ');
      final values = cleanRecord.values.map(_toDriftValue).toList();
      await _db!.customStatement(
        'INSERT OR IGNORE INTO $tableName ($columns) VALUES ($placeholders)',
        values,
      );

      // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح
      // (نتحقق من التأثير الفعلي عبر SELECT — INSERT OR IGNORE قد تجاهله)
      final inserted = await _db!
          .customSelect(
            'SELECT 1 FROM $tableName WHERE local_uuid = ? AND updated_at = ?',
            variables: [
              Variable<String>(localUuid),
              Variable<int>(remoteUpdatedAt),
            ],
          )
          .getSingleOrNull();
      if (inserted != null) {
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'create',
          ),
        );
      }
    }
  }

  // ─── Detect entity from record fields ───────────────────────
  // يحاول تحديد نوع الجدول من حقول السجل المستلم من D1
  String? _detectEntity(Map<String, dynamic> record) {
    // Core entities
    if (record.containsKey('room_number') && record.containsKey('price')) {
      return 'rooms';
    }
    if (record.containsKey('guest_name') &&
        record.containsKey('checkin_date')) {
      return 'bookings';
    }
    if (record.containsKey('amount') && record.containsKey('payment_method')) {
      return 'payments';
    }
    if (record.containsKey('expense_type') &&
        record.containsKey('description')) {
      return 'expenses';
    }
    if (record.containsKey('basic_salary') && record.containsKey('position')) {
      return 'employees';
    }
    if (record.containsKey('debt_reason') &&
        record.containsKey('remaining_amount')) {
      return 'debts';
    }

    // Booking-related
    if (record.containsKey('final_rate') &&
        record.containsKey('hotel_day_key')) {
      return 'booking_nights';
    }
    if (record.containsKey('adjustment_type') &&
        record.containsKey('effective_hotel_day')) {
      return 'booking_price_adjustments';
    }
    if (record.containsKey('note_text') && record.containsKey('alert_type')) {
      return 'booking_notes';
    }
    if (record.containsKey('guest_name') && record.containsKey('id_number')) {
      return 'guest_infos';
    }

    // Shift & cash
    if (record.containsKey('shift_date') && record.containsKey('is_read')) {
      return 'shift_notes';
    }
    if (record.containsKey('transaction_type') &&
        record.containsKey('transaction_time')) {
      return 'cash_transactions';
    }

    // Salary
    if (record.containsKey('cycle_key') &&
        record.containsKey('expected_amount')) {
      return 'salary_cycles';
    }
    if (record.containsKey('payment_date_iso') &&
        record.containsKey('cycle_id')) {
      return 'salary_payments';
    }
    if (record.containsKey('withdrawal_type') && record.containsKey('amount')) {
      return 'salary_withdrawals';
    }
    if (record.containsKey('previous_cycle_start') &&
        record.containsKey('new_cycle_start')) {
      return 'salary_carry_over_logs';
    }

    // Adjustments & audit
    if (record.containsKey('target_type') &&
        record.containsKey('target_uuid')) {
      return 'price_adjustments';
    }
    if (record.containsKey('operation_type') &&
        record.containsKey('entity_type')) {
      return 'audit_logs';
    }
    if (record.containsKey('void_reason') && record.containsKey('voided_by')) {
      return 'payment_voids';
    }

    // hotel_day_ledger is local-only — should not be pulled
    // (but if it arrives, we skip it)

    return null;
  }

  // ─── Convert value for Drift ────────────────────────────────
  dynamic _toDriftValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is List || value is Map) {
      return jsonEncode(value);
    }
    return value;
  }

  // ─── Auto Sync ──────────────────────────────────────────────
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      // Fire-and-forget: sync errors are handled by catchError, not awaited
      // because Timer.periodic callback is synchronous.
      unawaited(
        sync().catchError((Object e) {
          debugPrint('⚠️ Auto-sync error: $e');
          return SyncResult(
            status: SyncStatus.failed,
            timestamp: DateTime.now(),
            duration: Duration.zero,
            errorMessage: e.toString(),
          );
        }),
      );
    });
    debugPrint('⏰ Auto-sync started: every ${interval.inMinutes} minutes');
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ─── Reset / Clear ──────────────────────────────────────────
  void reset() {
    _token = null;
    _currentStatus = SyncStatus.idle;
  }

  Future<void> resetSyncState() async {
    _currentStatus = SyncStatus.idle;
    _lastError = null;
    _statusController.add(SyncStatus.idle);
  }

  /// إعادة تعيين cursor — يُجبر الـ pull التالي على جلب كل البيانات (full sync).
  /// يستخدم عند: تبديل الجهاز، استعادة backup، إصلاح تعارضات.
  ///
  /// ✅ P0-B: يُعيد أيضاً تعيين علامة "full sync مكتملة" لتجبر الجهاز على
  /// إعادة full sync كامل قبل العودة لـ delta mode.
  void clearHistory() {
    _lastPullCursor = 0;
    _fullSyncCompleted = false;
    _failedCollectionsInLastSync.clear();
    debugPrint('🔄 Sync cursor reset — next pull will be full sync');
  }

  /// مزامنة كاملة (full sync) — يعيد تعيين cursor ثم ينفذ sync.
  /// يستخدم عند: تبديل الجهاز، استعادة backup، مشاكل في البيانات.
  ///
  /// ✅ P0-B: بعد اكتمال full sync بنجاح، تُضبط علامة _fullSyncCompleted=true
  /// تلقائياً داخل _pullChanges() عند الوصول لـ exhaustion بدون أخطاء.
  /// إذا فشلت full sync جزئياً، تبقى العلامة false ويُعاد المحاولة في
  /// الـ sync التالي تلقائياً (لأن _pullChanges سيرى wasFullSync=true).
  Future<SyncResult> fullSync() async {
    clearHistory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cf_last_pull_cursor');
    await prefs.remove(_kFullSyncCompletedKey);
    debugPrint('🔄 Full sync: cursor reset + fullSyncCompleted flag cleared');
    return sync(push: true, pull: true);
  }

  // ─── Push all local data (stub) ─────────────────────────────
  Future<int> pushAllLocalDataToAppwrite() async {
    return 0;
  }

  // ─── Device ID generation ───────────────────────────────────
  String _generateDeviceId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'cf_dev_${now.toRadixString(36)}';
  }

  // ─── Audit log (stub — same interface as AppwriteSyncManager) ─
  final List<Map<String, dynamic>> _auditLog = [];
  List<Map<String, dynamic>> get auditLog => List.unmodifiable(_auditLog);

  void logToAudit({
    required String userMessage,
    required String aiResponse,
    required String executionResult,
    required bool wasConfirmed,
    String? commandType,
    String? commandDescription,
  }) {
    _auditLog.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'userMessage': userMessage,
      'aiResponse': aiResponse,
      'executionResult': executionResult,
      'wasConfirmed': wasConfirmed,
      'commandType': commandType,
      'commandDescription': commandDescription,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_auditLog.length > 100) _auditLog.removeAt(0);
  }

  void clearAuditLog() => _auditLog.clear();

  // ─── Stubs for methods called by existing screens ──────────

  Future<int> pushLocalChanges() async =>
      sync(pull: false).then((r) => r.recordsPushed);
  Future<int> pushAllLocalData() async => 0;
  Future<void> pullAllDataWithDisabledFK() async {}
  Future<void> pushAllEntities() async {}
  Future<Map<String, dynamic>> getSyncStatistics() async => {};
  Future<void> reinitializeAfterConfigChange() async {
    await initialize(forceRetry: true);
  }

  // ─── Pull remote changes (delta) — used by UnifiedSyncOrchestrator ──
  Future<bool> pullRemoteChanges() async {
    final result = await sync();
    return result.isSuccess;
  }

  // ─── Pull ALL remote data — used by appwrite_settings_screen ──
  Future<void> pullAllRemoteData() async {
    await sync(push: false);
  }

  // AppwriteService compatibility (some files pass this)
  dynamic get appwriteService => null;

  /// ✅ المرحلة 3: مدخل السحب المُشغَّل من Realtime (عقد RemoteChangePull).
  ///
  /// - delta-only حصراً: لا يبدأ Full Sync أبداً من حدث realtime —
  ///   لا يُسحب قبل اكتمال full sync الأولى (P0-B)؛ الـ full sync
  ///   يجري عبر المسار الصريح فقط.
  /// - حارس re-entrancy (P0-I): sync() نفسه محمي، لكن نتجنب هنا
  ///   إهدار دورة على "already in progress".
  /// - push أولاً ثم pull داخل sync() — الترتيب يضمن أن التغييرات
  ///   المحلية المعلّقة تُرفع قبل الاستماع للبعيدة (نفس عقد Outbox).
  Future<bool> realtimeTriggeredPull() async {
    if (!_fullSyncCompleted) {
      debugPrint('⏭️ Realtime pull skipped — full sync not completed yet');
      return false;
    }
    if (_syncInProgress) {
      debugPrint('⏭️ Realtime pull skipped — sync already in progress');
      return false;
    }
    // sync() الافتراضي: push ثم pull — الترتيب الداخلي يرفع outbox أولاً
    final result = await sync();
    return result.isSuccess;
  }
}

// ═══ Backward compatibility aliases ═══════════════════════════
// All files that imported AppwriteSyncManager will get these aliases
// No need to change any imports or references in existing code.

typedef AppwriteSyncManager = CloudflareSyncManager;
typedef AppwriteRealtimeSync = CloudflareRealtimeSync;
