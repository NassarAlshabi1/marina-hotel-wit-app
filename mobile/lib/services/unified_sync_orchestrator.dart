import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'analytics_service.dart';
import 'appwrite_sync_manager.dart' show AppwriteSyncManager, SyncStatus;
import 'connectivity_service.dart';
import 'local_db.dart';
import 'sync/app_open_pull_gate.dart';
import 'sync_integrity_checker.dart';

class UnifiedSyncState {
  const UnifiedSyncState({
    required this.phase,
    required this.message,
    required this.timestamp,
    this.checksum,
    this.outboxCount = 0,
    this.lastError,
    this.lastPushAt,
    this.lastPullAt,
    this.lastSnapshotAt,
  });
  final String phase;
  final String message;
  final DateTime timestamp;
  final String? checksum;
  final int outboxCount;
  final String? lastError;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final DateTime? lastSnapshotAt;

  UnifiedSyncState copyWith({
    String? phase,
    String? message,
    DateTime? timestamp,
    String? checksum,
    int? outboxCount,
    String? lastError,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    DateTime? lastSnapshotAt,
  }) {
    return UnifiedSyncState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      checksum: checksum ?? this.checksum,
      outboxCount: outboxCount ?? this.outboxCount,
      lastError: lastError ?? this.lastError,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastPullAt: lastPullAt ?? this.lastPullAt,
      lastSnapshotAt: lastSnapshotAt ?? this.lastSnapshotAt,
    );
  }
}

/// ✅ (2026-09-17) Cloudflare-only: أُزيلت مسارات Google Drive وSmartSync
/// والـ Snapshot السحابي كاملة من المنسّق بطلب المستخدم («مزامنة appwrite
/// و sync google drive لا احتاجها نهائياً»). ما بقي: دورة Cloudflare D1
/// الموحدة (رفع/سحب دلتا) + فحص السلامة المحلي عند الطلب.
class UnifiedSyncOrchestrator {
  UnifiedSyncOrchestrator._();

  static final UnifiedSyncOrchestrator instance = UnifiedSyncOrchestrator._();

  AppwriteSyncManager? _appwrite;
  AppDatabase? _database;

  StreamSubscription<void>? _appwriteSub;
  Timer? _debounceTimer;

  bool _initialized = false;
  bool _syncing = false;

  final _stateController = StreamController<UnifiedSyncState>.broadcast();
  Stream<UnifiedSyncState> get stateStream => _stateController.stream;

  UnifiedSyncState _state = UnifiedSyncState(
    phase: 'idle',
    message: 'جاهز',
    timestamp: DateTime.now(),
  );

  Future<void> initialize({
    AppwriteSyncManager? appwrite,
    AppDatabase? database,
  }) async {
    // ✅ P1-1 fix: idempotent — لا نُعيد التهيئة إذا تمت مسبقاً
    if (appwrite != null && _appwrite == null) {
      _appwrite = appwrite;
      await _appwrite!.initialize();
    }
    // تهيئة Cloudflare جزء من بدء المنسق نفسه، لا تؤجل لأول ضغط زر أو
    // أول foreground. هذا يضمن أن التوكن موجود قبل أي مسار Delta.
    if (_appwrite == null) {
      _appwrite = AppwriteSyncManager(database: database);
      await _appwrite!.initialize(database: database);
    }
    if (database != null) {
      _database = database;
    }

    // ✅ P1-1 fix: عدم إعادة attachListeners إذا تمت مسبقاً
    if (!_initialized) {
      await _attachListeners();
      _initialized = true;
      _emit(_state);
    }
  }

  Future<void> _attachListeners() async {
    await _appwriteSub?.cancel();

    if (_appwrite != null) {
      _appwriteSub = _appwrite!.syncStatusStream.listen((status) async {
        switch (status) {
          case SyncStatus.syncing:
            _emit(
              _state.copyWith(
                phase: 'pushing',
                message: 'مزامنة الدلتا مع Cloudflare',
                timestamp: DateTime.now(),
              ),
            );
          case SyncStatus.success:
            _emit(
              _state.copyWith(
                phase: 'pulling',
                message: 'سحب التغييرات وإنهاء الدمج',
                timestamp: DateTime.now(),
                lastPushAt: DateTime.now(),
              ),
            );
          case SyncStatus.failed:
            _emit(
              _state.copyWith(
                phase: 'error',
                message: 'فشل مزامنة Cloudflare',
                timestamp: DateTime.now(),
                lastError: 'Cloudflare sync failed',
              ),
            );
          case SyncStatus.idle:
          case SyncStatus.partial:
            _emit(
              _state.copyWith(
                phase: 'idle',
                message: 'جاهز',
                timestamp: DateTime.now(),
              ),
            );
        }
      });
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _appwriteSub?.cancel();
    unawaited(_stateController.close());
    _initialized = false;
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static void disposeInstance() {
    unawaited(instance.dispose());
  }

  Future<void> notifyLocalChange({String? table, String? operation}) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 10), () async {
      // ✅ إصلاح جذري: Timer callback async بدون try-catch يُسبب
      // unhandled async error → Crashlytics Fatal عند أي استثناء شبكي.
      try {
        await _autoSyncToAppwrite(
          reason:
              'local_change:${table ?? 'unknown'}:${operation ?? 'unknown'}',
        );
      } catch (e, stackTrace) {
        dwarn(() => '❌ UnifiedSyncOrchestrator: خطأ في debounce auto sync: $e');
        dwarn(() => 'Stack trace: $stackTrace');
        // لا rethrow — نمنع fatal crash
      }
    });
  }

  /// رفع تلقائي إلى Cloudflare فقط
  /// ✅ P1-2 fix: تمييز "مشغول" (true) عن "فشل" (false)
  Future<bool> _autoSyncToAppwrite({String reason = 'auto'}) async {
    if (_syncing) {
      dlog(() => '⏸️ _autoSyncToAppwrite: مشغول — تخطي (ليس فشل)');
      return true; // مشغول ≠ فشل — لا نُعيد جدولة إعادة محاولة
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cloudflareEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;

      if (!cloudflareEnabled) {
        dlog(() => 'ℹ️ مزامنة Cloudflare معطلة - تخطي الرفع التلقائي');
        return true;
      }

      _syncing = true;
      dlog(() => '🔄 رفع تلقائي إلى Cloudflare: $reason');

      final success = await _syncAppwrite(push: true, pull: false);

      if (success) {
        dlog(() => '✅ تم الرفع التلقائي إلى Cloudflare');
      } else {
        dwarn(() => '❌ فشل الرفع التلقائي إلى Cloudflare');
      }

      return success;
    } catch (e) {
      dwarn(() => '❌ خطأ في الرفع التلقائي: $e');
      return false;
    } finally {
      _syncing = false;
    }
  }

  Future<bool> syncNow({
    bool push = true,
    bool pull = true,
    String reason = 'manual',
    bool verifyIntegrity = false,
  }) async {
    if (_syncing) {
      dlog(() => '⏸️ syncNow: مشغول — تخطي (ليس فشل)');
      return true; // ✅ P1-2: مشغول ≠ فشل
    }

    _syncing = true;
    // ✅ Analytics: تتبّع بدء المزامنة مع سببها (manual/foreground/periodic)
    final syncStartTime = DateTime.now();
    unawaited(AnalyticsService().logSyncStart(trigger: reason));

    _emit(
      _state.copyWith(
        phase: push ? 'pushing' : 'pulling',
        message: 'تشغيل المزامنة الموحدة',
        timestamp: DateTime.now(),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final cloudflareEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;

      var success = true;

      if (cloudflareEnabled) {
        success = await _syncAppwrite(push: push, pull: pull) && success;
      }

      // فحص التكامل يقرأ جداول التطبيق كاملة، لذلك لا يكون جزءاً من كل
      // دورة Delta/foreground. يُطلب صراحةً للدورات التشخيصية حتى تظهر
      // السجلات فور اكتمال السحب.
      if (success && verifyIntegrity) {
        await _verifySyncIntegrity();
      }

      _emit(
        _state.copyWith(
          phase: success ? 'completing' : 'error',
          message: success ? 'اكتملت الدورة' : 'فشل في المزامنة',
          timestamp: DateTime.now(),
        ),
      );

      // ✅ Analytics: تسجيل اكتمال المزامنة مع المدة وعدد العناصر
      final syncDuration = DateTime.now().difference(syncStartTime);
      unawaited(
        AnalyticsService().logSyncComplete(
          itemsProcessed: 0, // ملاحظة: عدد العناصر الفعلي غير متاح هنا
          duration: syncDuration,
        ),
      );

      return success;
    } catch (e) {
      _emit(
        _state.copyWith(
          phase: 'error',
          message: 'فشل تشغيل المزامنة',
          timestamp: DateTime.now(),
          lastError: e.toString(),
        ),
      );
      // ✅ Analytics: تسجيل فشل المزامنة
      final syncDuration = DateTime.now().difference(syncStartTime);
      unawaited(
        AnalyticsService().logSyncFailure(
          error: e.toString(),
          operation: 'syncNow',
          attempt: 1,
        ),
      );
      dlog(
        () =>
            '📊 Analytics: sync failed after ${syncDuration.inMilliseconds}ms',
      );
      return false;
    } finally {
      _syncing = false;
    }
  }

  /// ✅ P0-2 (تدقيق معماري 2026-09-07): المشغّل الوحيد للعودة من الخلفية —
  /// دورة واحدة متسلسلة (رفع ثم سحب) تحت موتكس المدير مرة واحدة.
  /// كانت main.dart تستدعي _syncOnResume() (push) هنا بالتوازي مع
  /// هذا النداء (pull) — فيتنافسان على sync() نفسه ويُتخطى أحدهما
  /// عشوائياً بـ «Sync already in progress». الدمج هنا يلغي السباق
  /// ويحفظ كلا السلوكين (رفع outbox المعلق + سحب دلتا).
  ///
  /// ✅ (تحديث 2026-09-22): الرفع (push) يبقى غير مشروط في كل استدعاء،
  /// أما السحب (pull) فأصبح مشروطاً ببوابة زمنية (مرة كل ساعة عبر
  /// `SyncConstants.lastAppOpenPullKey`) وبفحص اتصال مسبق — راجع التعليق
  /// داخل الجسم لتفاصيل الشرط ولمنطق ختم المؤشر بعد نجاح سحب فعلي فقط.
  Future<void> onAppForeground() async {
    // ✅ (2026-09-22 طلب المستخدم) نفس شرطي فتح التطبيق البارد
    // (main.dart _startRealtimeSync) يُطبَّقان الآن هنا أيضاً — كان
    // هذا المسار يزامن (رفع+سحب) في كل عودة من الخلفية بلا أي throttle
    // زمني ولا فحص اتصال مسبق، بعكس مسار الإقلاع الأول.
    //
    // • فحص الاتصال أولاً: لا فائدة من محاولة أي طلب HTTP محكوم عليه
    //   بالفشل إن لم يوجد اتصال أصلاً.
    // • الرفع (push) يبقى بلا throttle — تعديلات محلية معلّقة يجب أن
    //   تصل بأسرع وقت ممكن، بنفس فلسفة AutoOutboxSyncWatcher.
    // • السحب (pull) فقط يخضع لشرط الساعة (نفس مفتاح
    //   SyncConstants.lastAppOpenPullKey — مصدر واحد للحقيقة مع مسار
    //   الإقلاع البارد، فلا يُعاد ضبط المؤشر مرتين بمعايير مختلفة).
    final isOnline = await ConnectivityService.instance.checkConnectivity();
    if (!isOnline) {
      dlog(() => '📴 onAppForeground: تخطي — لا يوجد اتصال بالإنترنت');
      return;
    }

    // ✅ (توحيد 2026-09-23) القرار عبر AppOpenPullGate — مصدر وحيد
    // للحقيقة مشترك مع main.dart::_startRealtimeSync (راجع تعليق الصنف).
    var shouldPull = true;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final gate = AppOpenPullGate.check(prefs);
      shouldPull = gate.shouldPull;
      if (!shouldPull) {
        dlog(
          () =>
              '⏭️ onAppForeground: تخطي السحب — مرت '
              '${gate.elapsedSinceLastPull.inMinutes} دقيقة فقط '
              '(متبقي ${gate.remainingUntilNextPull.inMinutes} دقيقة) — '
              'الرفع يتابع كالمعتاد',
        );
      }
    } catch (e) {
      dlog(() => '⚠️ onAppForeground: فشل فحص مؤشر آخر سحب: $e');
    }

    // ✅ (إصلاح) syncNow() يُعيد true أيضاً في حالتين لا يحدث فيهما أي
    // سحب فعلي: (1) "مشغول" — مزامنة أخرى قيد التنفيذ (`_syncing`)
    // فيتخطّى syncNow التنفيذ بالكامل ويُعيد true فوراً بلا استدعاء
    // _syncAppwrite (نمط "مشغول ≠ فشل" أعلاه في نفس الملف)، و(2) مزامنة
    // Cloudflare معطّلة (`appwrite_sync_enabled`) فتبقى success=true
    // الافتراضية دون أي نداء شبكي. القيمتان تُلتقطان هنا **قبل** نداء
    // syncNow مباشرة وبلا أي await بينهما — لا فرصة لتبدُّل `_syncing` في
    // هذه الفجوة لأن Dart تعاوني/أحادي الخيط، فتُطابق تماماً ما سيراه
    // فحص syncNow الداخلي عند التنفيذ.
    // الختم غير المشروط بهاتين الحالتين كان يُسجّل «سحب ناجح» وهمياً
    // فيقمع أي سحب حقيقي حتى ساعة كاملة — نفس فئة الخلل الذي أُصلح سابقاً
    // في main.dart:_startRealtimeSync عبر bootResult.isSuccess (تعليق
    // 2026-09-14 أعلى تلك الدالة).
    final wasBusy = _syncing;
    final cloudflareEnabled = prefs?.getBool('appwrite_sync_enabled') ?? true;

    // push دائماً true؛ pull محكوم بشرط الساعة أعلاه — دورة واحدة
    // متسلسلة كما كانت (رفع ثم سحب عند اجتماع الشرطين).
    final success = await syncNow(pull: shouldPull, reason: 'app_foreground');
    final pullActuallyRan = !wasBusy && cloudflareEnabled;

    if (success && shouldPull && pullActuallyRan && prefs != null) {
      try {
        await AppOpenPullGate.markPulled(prefs);
      } catch (e) {
        dlog(() => '⚠️ onAppForeground: فشل تحديث مؤشر آخر سحب: $e');
      }
    } else if (success && shouldPull && !pullActuallyRan) {
      dlog(
        () =>
            '⏭️ onAppForeground: لم يُحدَّث مؤشر آخر سحب — لم يحدث سحب '
            'فعلي (${wasBusy ? "مزامنة أخرى قيد التنفيذ" : "Cloudflare معطّلة"})',
      );
    }
  }

  Future<bool> _syncAppwrite({required bool push, required bool pull}) async {
    final manager = await _ensureAppwriteManager();
    if (manager == null) {
      return false;
    }

    if (push && pull) {
      // Pull first so a slow local outbox cannot delay visibility of remote
      // changes when the app returns to the foreground. Bootstrap is explicit
      // via fullSync(); foreground cycles are always delta-only.
      final pullResult = await manager.sync(
        push: false,
        deltaOnly: true,
      );
      final pushResult = await manager.sync(pull: false);
      return pullResult.isSuccess && pushResult.isSuccess;
    }

    var success = true;
    if (push) {
      // ✅ (2026-09-06) سابقاً: `manager.pushLocalChanges()` مع
      // `pushed >= 0` — شرط صادق دائماً (recordsPushed ليس سالباً أبداً)
      // فأي دورة فاشلة كانت تُحسب نجاحاً. الآن sync() مباشرة مع فحص
      // الحالة — نفس نمط فرع push&&pull أعلاه.
      final result = await manager.sync(pull: false);
      success = result.isSuccess && success;
    }
    if (pull) {
      // ✅ V-2 (تدقيق معماري — perf 014cc156): تفويض السحب للحلقة الرئيسية
      // الموحدة — pullRemoteChanges مسار قديم بلا metadata-first: checkpoint
      // عالمي فقط، لا يكتب sync_remote_meta ولا مؤشرات الكيانات، فيعيد
      // تنزيل كامل في كل استدعاء. deltaOnly يمنع بدء Full Sync من الخلفية
      // على جهاز في مرحلة bootstrap (نمط حارس الركود — ASM:760).
      // كل مستدعي pull-only هم مهام خلفية/تلقائية؛ اليدوي يمر عبر فرع
      // push&&pull أعلاه حيث يبقى السحب الكامل قراراً مرئياً.
      final result = await manager.sync(push: false, deltaOnly: true);
      success = result.isSuccess && success;
    }

    return success;
  }

  Future<AppwriteSyncManager?> _ensureAppwriteManager() async {
    if (_appwrite != null) {
      return _appwrite;
    }
    final db = _database ?? DatabaseManager.instance;
    _database ??= db;
    // ✅ (2026-09-05) Cloudflare-only: بلا خدمة Appwrite
    final manager = AppwriteSyncManager(database: db);
    await manager.initialize();
    _appwrite = manager;
    return manager;
  }

  Future<void> _verifySyncIntegrity() async {
    if (_database == null) {
      return;
    }

    try {
      _emit(
        _state.copyWith(
          phase: 'verifying',
          message: 'التحقق من سلامة البيانات',
          timestamp: DateTime.now(),
        ),
      );

      final report = await SyncIntegrityChecker.instance.verify(_database!);

      if (report.hasCriticalIssues) {
        _emit(
          _state.copyWith(
            phase: 'completing',
            message: 'تم اكتشاف ${report.criticalIssueCount} مشاكل حرجة',
            timestamp: DateTime.now(),
            lastError:
                'Found ${report.criticalIssueCount} critical integrity issues',
          ),
        );
      } else if (report.hasIssues) {
        _emit(
          _state.copyWith(
            phase: 'completing',
            message: 'تم اكتشاف ${report.issueCount} مشاكل غير حرجة',
            timestamp: DateTime.now(),
          ),
        );
      } else {
        _emit(
          _state.copyWith(
            phase: 'completing',
            message: 'سلامة البيانات جيدة',
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      _emit(
        _state.copyWith(
          phase: 'error',
          message: 'فشل التحقق من سلامة البيانات',
          timestamp: DateTime.now(),
          lastError: e.toString(),
        ),
      );
    }
  }

  void _emit(UnifiedSyncState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }
}
