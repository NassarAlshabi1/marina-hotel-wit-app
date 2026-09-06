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
import 'booking_derived_fields_service.dart';
import 'cloudflare_config.dart';
import 'cloudflare_d1_service.dart';
import 'cloudflare_dual_run_service.dart';
import 'cloudflare_realtime_sync.dart';
import 'daos/outbox_dao.dart';
import 'appwrite_models.dart' show AppwriteDevice;
import 'local_db.dart';
import 'remote_change_notifier.dart';
import 'resilient_http_client.dart';
import 'sync/payload_normalizer.dart';
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
  factory CloudflareSyncManager({
    // ✅ توافق Drop-in مع مواقع استدعاء AppwriteSyncManager القديمة
    // (perf providers/backup services تمرّرها) — تُتجاهل: خدمة Appwrite
    // ليست جزءاً من مسار Cloudflare، والقاعدة تُحَدَّد في initialize().
    dynamic appwriteService,
    dynamic database,
  }) => _instance;

  /// ✅ توافق: كود perf يستدعي `AppwriteSyncManager.instance`.
  static CloudflareSyncManager get instance => _instance;
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

  // ─── إحصائيات حقيقية لدورات المزامنة (2026-09-05) ──────────
  // ✅ كانت getSyncStatistics() تُرجع {} فارغة فتعرض شاشات الإحصائيات
  // أصفاراً دائمة (مضللة للإنتاج). الآن تُراكم المدير عدادات دورة
  // sync الفعلية وتُخزن في SharedPreferences لتبقى بين الجلسات.
  int _statTotalSyncs = 0;
  int _statSuccessfulSyncs = 0;
  int _statFailedSyncs = 0;
  int _statTotalPushed = 0;
  int _statTotalPulled = 0;
  DateTime? _statLastSyncTime;
  static const String _kSyncStatsKey = 'cf_sync_stats_v1';

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

    // ✅ (2026-09-05) استعادة عدادات الإحصائيات الحقيقية بين الجلسات.
    await _loadSyncStats();

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
            // ✅ (2026-09-05) هوية الصف المتزامن — تتقارب مسارات REST
            // وoutbox على صف واحد في D1 (نفس local_uuid).
            'localUuid': _deviceId,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      debugPrint('✅ Device registered: $_deviceId');
      // ✅ (2026-09-05) devices كيان متزامن في النطاق الافتراضي
      // (تعليمات المستخدم): كتابة محلية + outbox — السجل يُرفع عبر
      // push ويُسحب عبر delta لكل الأجهزة.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = _deviceSyncPayload(platform: 'android', now: now);
      await _writeLocalDeviceRow(payload);
      final deviceRowUuid = payload['local_uuid'] as String?;
      if (deviceRowUuid != null && deviceRowUuid.isNotEmpty) {
        try {
          await outboxDao.merge(
            entity: 'devices',
            op: 'create',
            localUuid: deviceRowUuid,
            payload: payload,
            clientTs: now,
            source: 'local',
          );
        } catch (e) {
          debugPrint('⚠️ devices outbox enqueue failed: $e');
        }
      }
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
      // ✅ (2026-09-05) devices كيان متزامن: كتابة محلية + outbox update.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = _deviceSyncPayload(
        fcmToken: token,
        platform: 'android',
        now: now,
      );
      await _writeLocalDeviceRow(payload);
      final deviceRowUuid = payload['local_uuid'] as String?;
      if (deviceRowUuid != null && deviceRowUuid.isNotEmpty) {
        try {
          await outboxDao.merge(
            entity: 'devices',
            op: 'update',
            localUuid: deviceRowUuid,
            payload: payload,
            clientTs: now,
            source: 'local',
          );
        } catch (e) {
          debugPrint('⚠️ devices outbox enqueue failed: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Set FCM token error: $e');
    }
  }

  // ─── Device sync row (local landing zone + outbox) ────────
  // ✅ (2026-09-05) حمولة مزامنة devices بصيغة snake_case مطابقة لأعمدة
  // جدول D1 (schema.sql + migrations/0004). الهوية: local_uuid =
  // deviceId (مستقر وفريد لكل تثبيت) — عمود device_id الموحّد هو
  // هوية الجهاز وعمود SyncFields.device_id (جهاز الكاتب) معاً.
  Map<String, dynamic> _deviceSyncPayload({
    String? fcmToken,
    String? platform,
    String? deviceName,
    required int now,
  }) {
    final deviceId = _deviceId ?? '';
    return <String, dynamic>{
      'local_uuid': deviceId,
      'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (platform != null) 'platform': platform,
      if (fcmToken != null) 'fcm_token': fcmToken,
      'status': 'active',
      'is_active': 1,
      'last_active': now,
      'updated_at': now,
      'last_modified': now,
      'last_modified_epoch': now,
      'version': 1,
      'origin': 'local',
      'vector_clock': jsonEncode(<String, int>{
        if (deviceId.isNotEmpty) deviceId: 1,
      }),
    };
  }

  /// كتابة/تحديث صف الجهاز محلياً (landing zone السحب ومصدر رفع D1).
  /// فشل الكتابة المحلية مساعد فقط — لا يُفشل التسجيل.
  Future<void> _writeLocalDeviceRow(Map<String, dynamic> syncPayload) async {
    try {
      final db = _db;
      if (db == null) return;
      final localUuid = syncPayload['local_uuid'] as String?;
      if (localUuid == null || localUuid.isEmpty) return;

      final existingRows = await db
          .customSelect(
            'SELECT id, version FROM devices WHERE local_uuid = ? LIMIT 1',
            variables: [Variable.withString(localUuid)],
          )
          .get();
      if (existingRows.isNotEmpty) {
        final existingVersion =
            (existingRows.first.data['version'] as int?) ?? 0;
        final fields = Map<String, dynamic>.from(syncPayload)
          ..remove('local_uuid')
          ..remove('created_at')
          ..['version'] = existingVersion + 1;
        final setClauses = fields.keys.map((c) => '$c = ?').join(', ');
        await db.customStatement(
          'UPDATE devices SET $setClauses WHERE local_uuid = ?',
          [...fields.values, localUuid],
        );
      } else {
        final row = <String, dynamic>{
          ...syncPayload,
          'device_name': syncPayload['device_name'] ?? '',
          'status': syncPayload['status'] ?? 'active',
          'is_active': syncPayload['is_active'] ?? 1,
          'created_at':
              (syncPayload['created_at'] ?? syncPayload['updated_at']) as int,
          'created_at_epoch': 0,
        }..remove('id');
        final columns = row.keys.join(', ');
        final placeholders = row.keys.map((_) => '?').join(', ');
        await db.customStatement(
          'INSERT OR REPLACE INTO devices ($columns) '
          'VALUES ($placeholders)',
          row.values.toList(),
        );
      }
    } catch (e) {
      debugPrint('⚠️ devices local row write failed: $e');
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
  Future<SyncResult> sync({
    bool push = true,
    bool pull = true,
    // ✅ توافق Drop-in (perf call-sites: dashboard_screen deltaOnly،
    // dashboard_sync_button/enhanced_sync_button forcePull):
    // deltaOnly = سحب دلتا فقط بلا رفع ولا full-sync bootstrap —
    // نفس عقد realtimeTriggeredPull؛ forcePull = طلب صريح من المستخدم
    // — المدير الحالي لا يملك حارس فاصل زمني على sync() (الأداء مُدار
    // بالـ auto-sync timer وP0-I)، فيُقبل ويُنفّذ السحب كالمعتاد.
    bool deltaOnly = false,
    bool forcePull = false,
  }) async {
    // ✅ المرحلة 6 (Dual-Run): مفتاح الإيقاف عن بُعد — disabled يعني
    // عودة آمنة للمحلي بلا مزامنة سحابية (خطة الرجوع: دقائق).
    if (!await CloudflareDualRunService().isCloudflareSyncEnabled()) {
      debugPrint('⏸️ Cloudflare sync disabled remotely (kill switch)');
      return SyncResult(
        status: SyncStatus.idle,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'Cloudflare sync disabled remotely (kill switch)',
      );
    }
    // ✅ (2026-09-05) مفتاح الإيقاف المحلي — «تفعيل مزامنة Appwrite»
    // في شاشة إعدادات المزامنة (appwrite_sync_enabled، افتراضه مفعّل).
    // سابقاً كان يوقف الحلقات الخلفية فقط بينما المزامنة اليدوية
    // تتجاهله — سلوك إنتاج غير متوقع. OFF يعني OFF لكل المسارات.
    try {
      final prefs = await SharedPreferences.getInstance();
      final locallyEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      if (!locallyEnabled) {
        debugPrint('⏸️ Sync disabled locally (appwrite_sync_enabled=false)');
        return SyncResult(
          status: SyncStatus.idle,
          timestamp: DateTime.now(),
          duration: Duration.zero,
          errorMessage: 'Sync disabled locally (appwrite_sync_enabled=false)',
        );
      }
    } catch (_) {
      // فشل قراءة التفضيل لا يجوز أن يمنع المزامنة (fail-open مثل المفتاح البعيد).
    }
    if (deltaOnly) {
      final bool ok = await realtimeTriggeredPull();
      return SyncResult(
        status: ok ? SyncStatus.success : SyncStatus.idle,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: ok
            ? null
            : 'Delta-only pull skipped (full sync not completed or sync in progress)',
      );
    }
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

    // ✅ (2026-09-05) تسجيل نتائج الدورة الفعلية في الإحصائيات —
    // نقطة اكتمال وحيدة بعد try/catch؛ الحروب المبكرة (kill switch،
    // deltaOnly، قفل re-entrancy) تعود قبلها فلا تُحتسب دورات.
    await _recordSyncOutcome(
      success: _currentStatus == SyncStatus.success,
      pushed: recordsPushed,
      pulled: recordsPulled,
      startedAt: startTime,
    );

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

    final outboxDao = OutboxDao(_db!);

    // ✅ (2026-09-06) استرجاع السجلات العالقة قبل التفريغ — reclaimForPush
    // وُجدت لهذا الغرض تحديداً (وثيقتها في outbox_dao.dart: «يُستدعى في
    // بداية طور الرفع») لكن الاستدعاء ضاع عند إعادة كتابة المدير السحابي.
    // بدونه: سجلات 'processing' عالقة (جلسة رفع انقطعت) تُحصى في عدّاد زر
    // الرفع (countUndeliveredToPrimary تشمل processing) بينما حلقة الرفع
    // أدناه تختار pending/failed فقط → زر «رفع التغييرات» يبقى مفعّلاً
    // للأبد ولا يفرّغ العداد. failed ≤ 5 محاولات تُعاد أيضاً إلى pending
    // — الضغط على الزر طلب صريح من المستخدم بإعادة المحاولة.
    try {
      await outboxDao.reclaimForPush();
    } catch (e) {
      // فشل الاسترجاع لا يجوز أن يمنع رفع السجلات السليمة
      debugPrint('⚠️ reclaimForPush failed (push continues): $e');
    }

    // ✅ حلقة الرفع: تكرر حتى يفرغ outbox من كل السجلات العالقة
    // هذا يضمن أن زر "رفع التغييرات" يرفع كل التغييرات دفعة واحدة
    // وليس فقط أول 25 سجل.
    while (true) {
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

    final operations = <Map<String, dynamic>>[];
    for (final item in pending) {
      // ✅ عقد الدفع (2026-09-05): snake_case + local_uuid + vector_clock —
      // البناء الكامل في buildPushOperation (sync/payload_normalizer.dart)
      // ليُحارس العقد باختبارات تشغّل المنتجين الحقيقيين للكيانات.
      operations.add(
        await buildPushOperation(
          item,
          resolveRowVectorClock: _rowVectorClock,
        ),
      );
      if (_deviceId != null) {
        operations.last['deviceId'] = _deviceId;
      }
    }

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

  /// يقرأ ساعة المتجه الحالية لصف الكيان المحلي — العقد المرجعي الذي
  /// يفهمه الـ worker في OCC (database.ts detectConflict). تُعاد null
  /// للكيانات بلا جدول محلي (blacklist) أو الصفوف المفقودة — عندها
  /// يهيّئ الـ worker ساعة جديدة {deviceId: 1} (سلوك create الأصلي).
  Future<String?> _rowVectorClock(String entity, String localUuid) async {
    final table = CloudflareConfig.tableNameFor(entity);
    if (table == null || _db == null) return null;
    try {
      final row = await _db!
          .customSelect(
            'SELECT vector_clock FROM $table WHERE local_uuid = ? LIMIT 1',
            variables: [Variable<String>(localUuid)],
          )
          .getSingleOrNull();
      final vc = row?.data['vector_clock'] as String?;
      if (vc == null || vc.isEmpty || vc == '{}') return null;
      return vc;
    } catch (_) {
      // جدول محلي غير موجود (blacklist) أو صف محذوف — {} يهيئها الـ worker
      return null;
    }
  }

  // ─── Pull changes from D1 ───────────────────────────────────
  Future<int> _pullChanges() async {
    if (_db == null) return 0;

    int totalPulled = 0;
    // كيانات مؤثرة على الحقول المشتقة للحجوزات — يُعاد بناء الليالي
    // والإجماليات المخزنة بعد اكتمال السحب (refreshAllActiveBookings
    // مع enqueueOutbox:false — البيانات المشتقة تُحسب محلياً ولا تُرفع،
    // وإلا حلقة سحب/رفع لا نهائية بين الأجهزة).
    final pulledDerivedEntities = <String>{};
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
        final touchedEntities = <String>{};
        for (final change in changes) {
          try {
            final record = Map<String, dynamic>.from(change as Map);
            final entity =
                record['_entity'] as String? ?? _detectEntity(record);
            record.remove('_entity'); // don't store this field in SQLite

            if (entity != null) {
              await _applyChange(entity, record);
              totalPulled++;
              touchedEntities.add(entity);
            }
          } catch (e) {
            debugPrint('⚠️ Failed to apply change: $e');
          }
        }
        pulledDerivedEntities.addAll(
          touchedEntities.intersection(_derivedRefreshEntities),
        );

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

      // ✅ بناء مشتق بعد السحب (2026-09-05): الليالي (booking_nights)
      // والإجماليات المخزنة صفوف مشتقة تُعاد الحسبة محلياً على كل جهاز
      // (bookings_adapter.dart:183-186) — سحب تغييرات bookings/payments/
      // adjustments دون إعادة بناء يترك الجهاز الآخر بأرقام قديمة.
      // enqueueOutbox:false — مشتق لا يُرفع، وإلا حلقة لا نهائية.
      if (pulledDerivedEntities.isNotEmpty && totalPulled > 0) {
        await _refreshDerivedAfterPull();
      }
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

    // ✅ عقد القائمة السوداء (2026-09-05): صفوف blacklist بلا جدول Drift
    // محلي — تخزينها في shift_notes الموسومة created_by='blacklist'
    // (blacklist_repository.dart:92). قبل هذا التحويل كان سحب صفوف
    // blacklist من D1 يفشل صمتاً (no such table: blacklist) ولا تصل
    // القائمة السوداء للأجهزة الأخرى أبداً.
    if (entity == 'blacklist') {
      final converted = CloudflareD1Service.blacklistShiftNoteRowFromD1(
        record,
      );
      if (converted == null) return;
      entity = 'shift_notes';
      record = converted;
    }

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

  /// الكيانات التي تؤثر صفوفها المسحوبة على الحقول المشتقة للحجوزات
  /// (الليالي + الإجماليات المخزنة) — تستدعي إعادة بناء بعد السحب.
  static const Set<String> _derivedRefreshEntities = {
    'bookings',
    'booking_nights',
    'payments',
    'price_adjustments',
    'booking_price_adjustments',
    'payment_voids',
  };

  bool _derivedRefreshRunning = false;

  /// إعادة بناء الحقول المشتقة للحجوزات النشطة بعد سحب تغييرات مؤثرة.
  /// enqueueOutbox:false إجبارياً — البيانات المشتقة تُحسب محلياً على كل
  /// جهاز ولا تُرفع للخادم، وإلا سجّرت الأجهزة في حلقة سحب/رفع لا نهائية.
  Future<void> _refreshDerivedAfterPull() async {
    if (_db == null || _derivedRefreshRunning) return;
    _derivedRefreshRunning = true;
    try {
      final service = BookingDerivedFieldsService(_db!);
      final refreshed = await service.refreshAllActiveBookings(
        enqueueOutbox: false,
      );
      debugPrint('🔄 Derived refresh after pull: $refreshed bookings rebuilt');
    } catch (e) {
      debugPrint('⚠️ Derived refresh after pull failed: $e');
    } finally {
      _derivedRefreshRunning = false;
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

    // app_users — حسابات مستخدمي التطبيق (كيان النطاق الافتراضي
    // 2026-09-05). الثنائي username + credentials_version فريد؛ لا
    // جدول آخر متزامن يملك عمود username.
    if (record.containsKey('username') &&
        record.containsKey('credentials_version')) {
      return 'app_users';
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

  /// ✅ (2026-09-06) هل مؤقّت المزامنة التلقائية نشط الآن؟
  /// يُستخدم في بطاقة «بيانات الاتصال التلقائي مع Cloudflare» لعرض
  /// حالة المحرك الفعلية (لا نية الإعداد المخزّنة فقط).
  bool get isAutoSyncRunning => _autoSyncTimer != null;

  // ─── Reset / Clear ──────────────────────────────────────────
  void reset() {
    _token = null;
    _currentStatus = SyncStatus.idle;
  }

  Future<void> resetSyncState() async {
    // ✅ (2026-09-05) كانت تكتفي بضبط الحالة الظاهرة بينما الرسالة
    // تعرض «تم إعادة تعيين مؤشر المزامنة المحلي فقط» — كذب. الآن
    // تُصفّر cursor السحب وعلامة full-sync فعلياً (نفس clearHistory +
    // مسح التخزين) فيبدأ السحب التالي من الصفر — «البدء من جديد».
    _currentStatus = SyncStatus.idle;
    _lastError = null;
    _statusController.add(SyncStatus.idle);
    clearHistory();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cf_last_pull_cursor');
      await prefs.remove(_kFullSyncCompletedKey);
      debugPrint('🔄 resetSyncState: cursor + fullSync flag cleared');
    } catch (e) {
      debugPrint('⚠️ resetSyncState prefs clear failed: $e');
    }
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

  // ─── Push all local data ────────────────────────────────────
  // ✅ توافق Drop-in (perf google_drive_backup_service يستدعيها
  // بـ skipDeleted ويتوقع Map<String,int> فيه 'errors'): الرفع
  // الفعلي للبيانات يجري عبر outbox/push العادي — هذه الدالة
  // للتوافق وتُرجع صفراً لكل جدول.
  Future<Map<String, int>> pushAllLocalDataToAppwrite({
    bool skipDeleted = false,
  }) async {
    debugPrint(
      '⚠️ pushAllLocalDataToAppwrite: cloudflare path uses outbox push — '
      'returning zeroed stats (skipDeleted: $skipDeleted)',
    );
    return const <String, int>{'errors': 0};
  }

  /// ✅ توافق Drop-in (perf google_drive_login_screen / appwrite_settings
  /// يستدعيها ويتوقع Future<bool>): سحب كامل — نفس sync(pull: true)
  /// بلا رفع؛ نجاحها = لا فشل جزئي.
  Future<bool> pullAllDataWithDisabledFK() async {
    final result = await sync(push: false, pull: true);
    return result.isSuccess;
  }

  /// ✅ توافق Drop-in (perf providers تسجّل ref.onDispose(manager.dispose)).
  /// singleton مشترك — لا يُغلق _statusController (broadcast stream
  /// مستهلك من شاشات أخرى)؛ تنظيف محدود فقط.
  void dispose() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// ✅ (2026-09-05) الأجهزة المسجلة — تُقرأ الآن من جدول devices المحلي
  /// (landing zone السحب — تُغذّى من D1 عبر pull) بدل القائمة الفارغة؛
  /// الشاشة مبنية على D1 عبر المزامنة كما تنص الخطة المعلقة سابقاً.
  Future<List<AppwriteDevice>> getRegisteredDevices() async {
    final db = _db;
    if (db == null) return const <AppwriteDevice>[];
    try {
      final rows = await db
          .customSelect(
            'SELECT * FROM devices WHERE deleted_at IS NULL '
            'ORDER BY COALESCE(last_active, updated_at) DESC',
          )
          .get();
      DateTime? epochToDateTime(dynamic v) {
        if (v is int && v > 0) {
          return DateTime.fromMillisecondsSinceEpoch(v * 1000);
        }
        return null;
      }

      DateTime? isoToDateTime(dynamic v) {
        if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
        return null;
      }

      return rows.map((r) {
        final d = r.data;
        return AppwriteDevice(
          id: (d['device_id'] as String?) ?? '',
          deviceName: (d['device_name'] as String?) ?? '',
          deviceModel: (d['device_model'] as String?) ?? '',
          osVersion: (d['os_version'] as String?) ?? '',
          lastSeen: isoToDateTime(d['last_seen']) ?? DateTime.now(),
          lastActive: epochToDateTime(d['last_active']),
          status: (d['status'] as String?) ?? 'active',
          createdAt: epochToDateTime(d['created_at']) ?? DateTime.now(),
          updatedAt: epochToDateTime(d['updated_at']) ?? DateTime.now(),
          version: (d['version'] as int?) ?? 1,
          origin: d['origin'] as String?,
          localUuid: d['local_uuid'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ getRegisteredDevices failed: $e');
      return const <AppwriteDevice>[];
    }
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

  /// ✅ (2026-09-06) عقد صادق لزر «رفع التغييرات» في dashboard.
  ///
  /// سابقاً: `sync(pull: false).then((r) => r.recordsPushed)` — كانت تُسقط
  /// `SyncResult.status` بالكامل، فأي فشل (شبكة :723-751، non-200 :753-779،
  /// kill switch :502-510، تعطيل محلي :515-526، غير مهيأ :541-548، دورة
  /// جارية :551-559) كان يُترجم عند المستدعي إلى نجاح مع 0 سجل، لأن
  /// `pushedCount >= 0` صادق دائماً (dashboard_sync_button.dart:536).
  /// النتيجة الإنتاجية: snackbar أخضر «✅ تم رفع التغييرات بنجاح!» بينما
  /// الـ outbox ما زال ممتلئاً — تضليل بنفس نمط pushAllLocalData المُصلح
  /// أعلاه (2026-09-05).
  ///
  /// الآن: ترمي [StateError] عند أي حالة غير `success`، وتُرجع العدد
  /// عند نجاح فعلي فقط. المستدعي dashboard_sync_button يلتقط الاستثناء
  /// في try/catch لكل هدف (:539-546) فيُظهر snackbar أحمر مع «إعادة».
  Future<int> pushLocalChanges() async {
    final r = await sync(pull: false);
    if (r.status != SyncStatus.success) {
      throw StateError(r.errorMessage ?? 'Push failed (${r.status.name})');
    }
    return r.recordsPushed;
  }

  /// ✅ (2026-09-05) كانت تُرجع 0 دائماً (stub) بينما زر «بدء الرفع»
  /// في الإعدادات يعرض «تم رفع البيانات بنجاح» دون رفع أي شيء —
  /// تضليل إنتاجي. الآن تنفّذ الرفع الفعلي عبر outbox push (نفس
  /// مسار pushLocalChanges) وتعيد عدد السجلات المرفوعة، وترمي
  /// استثناء عند فشل الدورة ليُظهره try/catch الشاشة بدل نجاح زائف.
  Future<int> pushAllLocalData() async {
    final r = await sync(pull: false);
    if (r.status == SyncStatus.failed) {
      throw StateError(r.errorMessage ?? 'Push failed');
    }
    return r.recordsPushed;
  }

  Future<void> pushAllEntities() async {}

  /// ✅ (2026-09-05) إحصائيات حقيقية بدل {} — عدادات دورات المدير
  /// (تعيش في SharedPreferences) + عدّ Outbox الفعلي (المعلّق
  /// غير المسلَّم + الفاشل). المفاتيح هي نفسها التي تقرأها
  /// شاشات الإحصائيات (appwrite_settings_screen، appwrite_sync_stats_screen).
  Future<Map<String, dynamic>> getSyncStatistics() async {
    final stats = <String, dynamic>{
      'totalSyncs': _statTotalSyncs,
      'successfulSyncs': _statSuccessfulSyncs,
      'failedSyncs': _statFailedSyncs,
      'totalRecordsPushed': _statTotalPushed,
      'totalRecordsPulled': _statTotalPulled,
      'totalConflicts': 0,
      'successRate': _statTotalSyncs == 0
          ? 0.0
          : _statSuccessfulSyncs / _statTotalSyncs,
      'lastSyncTime': _statLastSyncTime?.toIso8601String(),
      'outboxCount': 0,
      'fullSyncCompleted': _fullSyncCompleted,
      'lastError': _lastError,
    };
    final db = _db;
    if (db != null) {
      try {
        final pending = await OutboxDao(
          db,
        ).countUndeliveredToPrimary(sources: const ['local']);
        stats['outboxCount'] = pending;
      } catch (e) {
        debugPrint('⚠️ getSyncStatistics outbox count failed: $e');
      }
    }
    return stats;
  }

  /// تحميل عدادات الإحصائيات المحفوظة — يُستدعى من initialize().
  Future<void> _loadSyncStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSyncStatsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _statTotalSyncs = (map['totalSyncs'] as num?)?.toInt() ?? 0;
      _statSuccessfulSyncs = (map['successfulSyncs'] as num?)?.toInt() ?? 0;
      _statFailedSyncs = (map['failedSyncs'] as num?)?.toInt() ?? 0;
      _statTotalPushed = (map['totalPushed'] as num?)?.toInt() ?? 0;
      _statTotalPulled = (map['totalPulled'] as num?)?.toInt() ?? 0;
      final lastMs = (map['lastSyncMs'] as num?)?.toInt();
      _statLastSyncTime = lastMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastMs);
    } catch (e) {
      debugPrint('⚠️ _loadSyncStats failed: $e');
    }
  }

  /// تسجيل نتيجة دورة مزامنة مكتملة وحفظها.
  Future<void> _recordSyncOutcome({
    required bool success,
    required int pushed,
    required int pulled,
    required DateTime startedAt,
  }) async {
    _statTotalSyncs++;
    if (success) {
      _statSuccessfulSyncs++;
    } else {
      _statFailedSyncs++;
    }
    _statTotalPushed += pushed;
    _statTotalPulled += pulled;
    _statLastSyncTime = startedAt;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSyncStatsKey,
        jsonEncode(<String, dynamic>{
          'totalSyncs': _statTotalSyncs,
          'successfulSyncs': _statSuccessfulSyncs,
          'failedSyncs': _statFailedSyncs,
          'totalPushed': _statTotalPushed,
          'totalPulled': _statTotalPulled,
          'lastSyncMs': startedAt.millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      debugPrint('⚠️ _recordSyncOutcome persist failed: $e');
    }
  }

  Future<void> reinitializeAfterConfigChange() async {
    await initialize(forceRetry: true);
  }

  // ─── Pull remote changes (delta) — used by UnifiedSyncOrchestrator ──
  Future<bool> pullRemoteChanges() async {
    final result = await sync();
    return result.isSuccess;
  }

  // ─── Pull ALL remote data — used by appwrite_settings_screen ──
  // ✅ توافق Drop-in: perf screen يتوقع Future<bool>.
  Future<bool> pullAllRemoteData() async {
    final result = await sync(push: false);
    return result.isSuccess;
  }

  /// ✅ توافق Drop-in (perf auth_local_store يستخدم manager.outboxDao
  /// لدمج app_users من النسخ الاحتياطية): الوصول لـ OutboxDao على نفس
  /// قاعدة drift الخاصة بالمدير.
  OutboxDao get outboxDao => OutboxDao(_db!);

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
