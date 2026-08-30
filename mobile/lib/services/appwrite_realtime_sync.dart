import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'crashlytics_service.dart';
import 'sync_constants.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// نوع المدخل الذي يُطلق السحب الفعلي.
@visibleForTesting
enum RealtimeMode { websocket, fallback, disabled }

/// callback السحب الفعلي المُحقن من main.dart.
///
/// العائد `true` = مرحلة السحب (pull) أُكملت فعلاً؛ `false` = السحب
/// تخطّى/فشل (مثل: outbox محلي لم يُفرَّغ بعد، أو sync قيد التنفيذ) —
/// في هذه الحالة تُجدول محاولة متابعة بدل اعتبار التغييرات مُطبّقة.
typedef RemoteChangePull = Future<bool> Function();

/// ✅ (2026-08-31) تفعيل Realtime الكامل.
///
/// التغييرات الجذرية عن النسخة السابقة:
///  1. WebSocket مفعّل افتراضياً (`appwrite_realtime_ws_enabled ?? true`
///     بدل false) — المفتاح لا تُكتبه أي شاشة أبداً، فالافتراضي الجديد يسري
///     على كل التركيبات القديمة والجديدة فوراً.
///  2. حدث Realtime من جهاز آخر **يُطلق سحباً فعلياً** عبر [setSyncTrigger]
///     (sync push+pull بأولوية realtime) — سابقاً كان يُحدّث شارة UI فقط
///     وينتظر auto-sync كل 15 دقيقة.
///  3. المفتاح المرئي `appwrite_realtime_sync_enabled` أصبح Master switch
///     يُحترم في start() وليس في شاشة الإعدادات فقط.
///  4. وضع الـ fallback (WS فاشل/معطّل) لم يعد مجرد علامة كل 30 ثانية؛
///     يُطلق سحباً خفيفاً كل [SyncConstants.realtimeFallbackPullInterval].
///  5. [ensureStarted] لإعادة الاشتراك عند عودة التطبيق بعد استسلام
///     إعادة الاتصال (max reconnect attempts).
///
/// ضبط المعدل (Self-pacing) — لماذا يجوز لمدخل Realtime تجاوز حارس
/// الدقيقتين (minPullGap)؟
///  - الحدث نفسه إثبات من الخادم بحدوث تغيير فعلي، وليس تخميناً دورياً.
///  - الطبقة هنا تُسرَّع ذاتها: ديبونس 500ms + تهيئة
///    [SyncConstants.realtimeEventPullCooldown] + طابور متابعة (trailing)
///    + حارس in-flight — الحد الأقصى النظري 4 دورات/دقيقة تحت عاصفة
///    مستمرة، وعادةً دورة واحدة لكل دفعة تغييرات.
///  - Metadata-first يجعل الدورة الرخيصة (سحب $id+$updatedAt فقط) عندما
///    لا يوجد شيء جديد فعلاً.
///  - حمايات المدير تبقى سارية: OutboxPullPolicy (لا سحب فوق تغييرات
///    محلية غير مرفوعة) و SyncLocks و فحص الاتصال.
class AppwriteRealtimeSync {
  factory AppwriteRealtimeSync() => _instance;
  AppwriteRealtimeSync._internal();
  static final AppwriteRealtimeSync _instance = AppwriteRealtimeSync._internal();

  Realtime? _realtime;
  RealtimeSubscription? _subscription;
  String? _currentDeviceId;
  bool _isListening = false;
  bool _intentionallyStopped = false;
  Timer? _debounceTimer;

  // ✅ تحسين: عداد التغييرات المعلقة من السيرفر (للـ Badge)
  final pendingRemoteChangesCount = ValueNotifier<int>(0);

  // ✅ تحسين: ValueNotifier لإشعار الـ UI بوجود تغييرات جديدة من السيرفر
  final hasRemoteChanges = ValueNotifier<bool>(false);

  // ✅ تححسين: تتبع آخر وقت تحديث من السيرفر (للـ Delta Sync Safety)
  DateTime? _lastServerUpdate;

  // ✅ تحسين: حماية من الفيضان (Flood Protection)
  bool _hasPendingChanges = false;

  // ── ✅ (2026-08-31) محرّك السحب الفعلي عند الأحداث ──
  RemoteChangePull? _syncTrigger;
  Timer? _cooldownTimer;
  bool _triggerInFlight = false;
  bool _pullQueued = false;
  DateTime? _lastFireAt;
  int _consecutiveSkips = 0;

  /// ✅ (2026-08-30) audit_logs مستبعد من اشتراكات Realtime
  /// (SyncConstants.auditLogsSyncEnabled = false) — لا أحداث ولا سحب له.
  static final List<String> _collections = [
    AppwriteConfig.roomsCollectionId,
    AppwriteConfig.bookingsCollectionId,
    AppwriteConfig.bookingNotesCollectionId,
    AppwriteConfig.bookingNightsCollectionId,
    AppwriteConfig.paymentsCollectionId,
    AppwriteConfig.expensesCollectionId,
    AppwriteConfig.cashTransactionsCollectionId,
    AppwriteConfig.debtsCollectionId,
    AppwriteConfig.employeesCollectionId,
    AppwriteConfig.salaryCyclesCollectionId,
    AppwriteConfig.salaryPaymentsCollectionId,
    AppwriteConfig.salaryWithdrawalsCollectionId,
    AppwriteConfig.shiftNotesCollectionId,
    AppwriteConfig.guestInfosCollectionId,
    // ❌ hotel_day_ledger - محلي فقط
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    if (SyncConstants.auditLogsSyncEnabled) AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
  ];

  /// حقن دالة السحب الفعلي (يُستدعى من main.dart بعد جاهزية SyncManager).
  ///
  /// ```dart
  /// AppwriteRealtimeSync().setSyncTrigger(() async {
  ///   final r = await syncManager.sync(
  ///     push: true, pull: true, realtimePriority: true,
  ///   );
  ///   return r.isSuccess && !r.pullSkipped;
  /// });
  /// ```
  void setSyncTrigger(RemoteChangePull trigger) {
    _syncTrigger = trigger;
  }

  Future<void> initialize({required String deviceId}) async {
    _currentDeviceId = deviceId;
    // AppwriteService.initialize() idempotent — يضمن client جاهزاً حتى لو
    // استُدعي start() من شاشة الإعدادات قبل مسار main.dart.
    await AppwriteService().initialize();
    _realtime ??= Realtime(AppwriteService().client);
    dlog('📡 AppwriteRealtimeSync initialized');
  }

  /// قرار بدء الاستماع (منطق نقي — قابل للاختبار بلا شبكة).
  ///
  /// سلسلة القرار (2026-08-31):
  ///  1. `appwrite_sync_enabled` (افتراضي true) — master sync.
  ///  2. `appwrite_realtime_sync_enabled` (افتراضي true) — مفتاح Realtime
  ///     المرئي في شاشة الإعدادات؛ أصبح يُحترم هنا أيضاً وليس هناك فقط.
  ///  3. `appwrite_realtime_ws_enabled` (**افتراضي true الآن** — كان false) —
  ///     false يعني fallback (سحب دوري خفيف) بلا WebSocket.
  @visibleForTesting
  static RealtimeMode resolveRealtimeMode({
    required bool? appwriteSyncEnabled,
    required bool? realtimeSyncEnabled,
    required bool? wsEnabled,
  }) {
    if (!(appwriteSyncEnabled ?? true)) return RealtimeMode.disabled;
    if (!(realtimeSyncEnabled ?? true)) return RealtimeMode.disabled;
    if (!(wsEnabled ?? true)) return RealtimeMode.fallback;
    return RealtimeMode.websocket;
  }

  Future<void> start() async {
    if (_isListening) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final mode = resolveRealtimeMode(
      appwriteSyncEnabled: prefs.getBool('appwrite_sync_enabled'),
      realtimeSyncEnabled: prefs.getBool('appwrite_realtime_sync_enabled'),
      wsEnabled: prefs.getBool('appwrite_realtime_ws_enabled'),
    );

    if (mode == RealtimeMode.disabled) {
      dlog('📡 Realtime: disabled in settings — not starting');
      return;
    }

    // ✅ إعادة تعيين علامة التوقف الإرادي — start() تعني أن المستخدم يريد الاستماع
    _intentionallyStopped = false;

    if (mode == RealtimeMode.fallback) {
      dlog(
        '📡 Realtime: WebSocket disabled — fallback mode '
        '(light pull every ${SyncConstants.realtimeFallbackPullInterval.inMinutes}m)',
      );
      _startPollingFallback();
      return;
    }

    // ✅ (2026-08-31) تهيئة كسولة: start() يعمل حتى لو لم يُستدعَ initialize()
    // صراحة (مثلاً من شاشة الإعدادات قبل اكتمال مسار main.dart).
    if (_realtime == null) {
      try {
        await initialize(deviceId: _currentDeviceId ?? 'unknown');
      } catch (e) {
        dlog(() => '❌ Realtime: lazy initialize failed — fallback mode: $e');
        _startPollingFallback();
        return;
      }
    }

    final channels = _collections
        .map(
          (c) =>
              'databases.${AppwriteConfig.databaseId}.collections.$c.documents',
        )
        .toList();

    try {
      _subscription = _realtime!.subscribe(channels);
      _isListening = true;
      // ✅ الانتقال من fallback إلى WS ناجح — أوقف مؤقتات الـ fallback
      _stopPollingFallback();

      dlog(
        () =>
            '📡 Realtime: WebSocket ON — listening on ${channels.length} '
            'collections (full realtime pull enabled)',
      );

      _subscription!.stream.listen(
        _onEvent,
        onError: (Object e) {
          dlog(() => '❌ Realtime WebSocket error: $e');
          CrashlyticsService.instance.recordSyncError(
            operation: 'realtime_listen',
            error: e.toString(),
            severity: CrashlyticsSeverity.warning,
            context: {'deviceId': _currentDeviceId ?? 'unknown'},
          );
          _isListening = false;
          // ✅ إذا فشل WebSocket، ننتقل لـ polling fallback
          _startPollingFallback();
        },
        onDone: () {
          _isListening = false;
          if (!_intentionallyStopped) {
            _reconnect();
          }
        },
      );
    } catch (e) {
      dlog('❌ Realtime: WebSocket not available — falling back to polling');
      dlog(() => '   Error: $e');
      // ✅ WebSocket غير متاح — نعتمد على fallback
      _startPollingFallback();
    }
  }

  /// ✅ (2026-08-31) إعادة المحاولة الآمنة عند عودة التطبيق للواجهة:
  /// إذا استسلمت إعادة الاتصال (max attempts) أو فشل start() عند الإقلاع،
  /// استدعاء عند resume يعيد محاولة الاشتراك من جديد.
  Future<void> ensureStarted() async {
    if (_isListening || _intentionallyStopped) {
      return;
    }
    await start();
  }

  // ── وضع الـ fallback: علامة UI كل 30 ثانية + سحب فعلي خفيف دوري ──
  Timer? _pollingTimer;
  static const Duration _pollingInterval = Duration(seconds: 30);

  void _startPollingFallback() {
    if (_pollingTimer != null) return;

    dlog(
      () =>
          '📡 Realtime: started fallback polling (UI flag every '
          '${_pollingInterval.inSeconds}s, real pull every '
          '${SyncConstants.realtimeFallbackPullInterval.inMinutes}m)',
    );

    var elapsed = Duration.zero;
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (_intentionallyStopped) return;

      elapsed += _pollingInterval;

      // علامة الـ UI بوجود تغييرات محتملة (المزامنة الفعلية عبر السحب أدناه)
      if (!_hasPendingChanges) {
        hasRemoteChanges.value = true;
        _hasPendingChanges = true;
        dlog('📡 Realtime: fallback tick — UI flag set');
      }

      // ✅ (2026-08-31) سحب فعلي خفيف دوري — الأجهزة التي يفشل عندها WS
      // لا تبقى بلا تحديثات حتى auto-sync التالي.
      final interval =
          debugFallbackPullInterval ?? SyncConstants.realtimeFallbackPullInterval;
      if (elapsed >= interval) {
        elapsed = Duration.zero;
        dlog('📡 Realtime: fallback periodic pull triggered');
        _schedulePull();
      }
    });
  }

  void _stopPollingFallback() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _onEvent(RealtimeMessage message) {
    handleRemoteDataChange(
      events: message.events,
      payload: message.payload,
    );
  }

  /// نواة معالجة الحدث (مفصولة عن RealtimeMessage لتكون قابلة للاختبار
  /// المباشر بلا WebSocket ولا بناء نماذج SDK).
  @visibleForTesting
  void handleRemoteDataChange({
    required List<String> events,
    required Map<String, dynamic> payload,
  }) {
    // ✅ stop() يعني التوقف الكامل: لا سحب من أحداث متأخرة بعد الإغلاق
    // (الاشتراك مغلق فعلياً، وهذا حارس إضافي ضد أي أحداث متبقية).
    if (_intentionallyStopped) {
      dlog('📡 Realtime: ignored event after intentional stop');
      return;
    }

    final sourceDevice = payload['device_id'] ?? payload['lastModifiedBy'];

    // ✅ إصلاح P2-13: تصفير عداد إعادة الاتصال عند استلام حدث صحي — يعني
    // الاتصال سليم، لذا أي انقطاع مستقبلي يبدأ من backoff قصير.
    _reconnectAttempts = 0;

    // تجاهل التغييرات من نفس الجهاز (لأنها محلية بالفعل)
    if (sourceDevice == _currentDeviceId) {
      dlog('📡 Realtime: ignored own-device change');
      return;
    }

    // ✅ تحسين: تصفية أنواع الأحداث (create/update/delete فقط)
    // لا نهتم بـ permissions.update أو أحداث النظام
    final isDataChange = events.any(
      (e) =>
          e.endsWith('.create') ||
          e.endsWith('.update') ||
          e.endsWith('.delete'),
    );

    if (!isDataChange) {
      dlog(() => '📡 Realtime: ignoring non-data event: $events');
      return;
    }

    // ✅ تحسين: تتبع آخر وقت تحديث (Delta Sync Safety)
    final updatedAt = payload[r'$updatedAt'] ?? payload[r'$createdAt'];
    if (updatedAt != null) {
      try {
        final serverTime = DateTime.parse(updatedAt as String);
        if (_lastServerUpdate == null ||
            serverTime.isAfter(_lastServerUpdate!)) {
          _lastServerUpdate = serverTime;
        }
      } catch (e) {
        dlog('⚠️ Realtime: could not parse update timestamp');
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      debugEventDebounce ?? const Duration(milliseconds: 500),
      () {
        // ✅ تحسين: حماية من الفيضان (Flood Protection)
        if (!_hasPendingChanges) {
          hasRemoteChanges.value = true;
          _hasPendingChanges = true;
          dlog('📡 Realtime: detected remote changes - UI activated');
        }

        pendingRemoteChangesCount.value++;

        // ✅✅ (2026-08-31) التفعيل الكامل: الحدث يُطلق **سحباً فعلياً**
        // وليس مجرد شارة UI — التغيير من جهاز آخر يصل خلال ثوانٍ.
        _schedulePull();
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // مجدول السحب الفعلي (cooldown + trailing queue + in-flight guard)
  // ───────────────────────────────────────────────────────────────────────

  /// جدولة سحب فعلي. آمن للاستدعاء المتكرر:
  ///  - أثناء دورة جارية → يُعلَّم طلب متابعة (يُنفَّذ بعد انتهائها مباشرة).
  ///  - داخل فترة التهيئة → يُترك المؤقت المجدول (سيغطي كل المتراكم لأن
  ///    السحب delta يجلب كل التغييرات منذ المؤشر، أياً كان عددها).
  ///  - خارج التهيئة → يُطلق فوراً.
  void _schedulePull() {
    if (_syncTrigger == null) {
      dlog('📡 Realtime: no sync trigger injected — pull skipped');
      return;
    }
    if (_triggerInFlight) {
      _pullQueued = true;
      return;
    }
    if (_cooldownTimer != null) return;

    final now = DateTime.now();
    final last = _lastFireAt;
    final cooldown =
        debugPullCooldown ?? SyncConstants.realtimeEventPullCooldown;
    if (last == null || now.difference(last) >= cooldown) {
      unawaited(_firePull());
      return;
    }
    _cooldownTimer = Timer(cooldown - now.difference(last), () {
      _cooldownTimer = null;
      unawaited(_firePull());
    });
  }

  Future<void> _firePull() async {
    final trigger = _syncTrigger;
    if (trigger == null) return;

    _lastFireAt = DateTime.now();
    _triggerInFlight = true;
    dlog('⚡ Realtime: firing real pull (remote change)');

    var pulled = false;
    try {
      pulled = await trigger();
    } catch (e) {
      dlog(() => '⚠️ Realtime: triggered pull failed: $e');
    } finally {
      _triggerInFlight = false;
    }

    if (pulled) {
      // السحب أُكمل فعلاً — التغييرات من السيرفر طُبّقت، صفّر شارات الـ UI.
      _consecutiveSkips = 0;
      resetRemoteChangesFlag();
    } else {
      // السحب تخطّى (مثلاً: outbox محلي لم يُفرَّغ بعد، أو دورة أخرى كانت
      // جارية). **متابعة واحدة فقط** بعد أول تخطٍّ — إن فشلت التالية أيضاً
      // نتوقف حتى حدث جديد (لا حلقة إعادة غير محدودة).
      _consecutiveSkips++;
      if (_consecutiveSkips == 1) {
        dlog('📡 Realtime: pull was skipped — scheduling ONE follow-up');
        _schedulePull();
      } else {
        dlog(
          () => '📡 Realtime: pull skipped ×$_consecutiveSkips — '
              'waiting for next event',
        );
      }
    }

    if (_pullQueued && !_intentionallyStopped) {
      _pullQueued = false;
      _schedulePull();
    }
  }

  /// ✅ تحسين: الحصول على آخر وقت تحديث معروف من السيرفر
  DateTime? get lastKnownServerUpdate => _lastServerUpdate;

  /// ✅ تحسين: تعيين آخر وقت تحديث يدوياً (مفيد للـ Delta Sync)
  void updateLastServerTimestamp(DateTime timestamp) {
    if (_lastServerUpdate == null || timestamp.isAfter(_lastServerUpdate!)) {
      _lastServerUpdate = timestamp;
      dlog(() => '📡 Realtime: updated last server timestamp to $timestamp');
    }
  }

  /// إعادة تعيين حالة "توجد تغييرات من السيرفر"
  /// يُستدعى بعد انتهاء عملية السحب اليدوي بنجاح
  void resetRemoteChangesFlag() {
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
    dlog('📡 Realtime: remote changes flag reset - count cleared');
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 6;

  void _reconnect() {
    // ✅ إصلاح P2-13: عدم إعادة الاتصال بعد stop() الإرادي
    if (_intentionallyStopped) {
      return;
    }

    _reconnectAttempts++;

    // ✅ إصلاح P2-13: حد أقصى لمحاولات إعادة الاتصال لتجنب إهدار البطارية
    // بعد 6 محاولات (5s → 10s → 20s → 40s → 60s → 60s = ~3.5 min total)
    if (_reconnectAttempts > _maxReconnectAttempts) {
      dlog(
        () =>
            '📡 Realtime: max reconnect attempts ($_maxReconnectAttempts) '
            'reached — fallback polling continues; try ensureStarted() on resume',
      );
      CrashlyticsService.instance.recordSyncError(
        operation: 'realtime_reconnect_giveup',
        error:
            'Max reconnect attempts reached after $_maxReconnectAttempts tries',
        severity: CrashlyticsSeverity.warning,
        context: {'deviceId': _currentDeviceId ?? 'unknown'},
      );
      // ✅ (2026-08-31) الاستسلام لا يعني انقطاع التحديثات: fallback
      // polling (علامة + سحب خفيف كل 5 دقائق) يستمر حتى resume القادم.
      _startPollingFallback();
      return;
    }

    // ✅ P1-14 fix: backoff أسّي محدود (5s → 10s → 20s → 40s → 60s capped)
    final delaySeconds = (_reconnectAttempts == 1)
        ? 5
        : (5 * (1 << (_reconnectAttempts - 1))).clamp(5, 60);

    CrashlyticsService.instance.recordSyncError(
      operation: 'realtime_reconnect',
      error:
          'Connection lost — reconnecting in ${delaySeconds}s '
          '(attempt $_reconnectAttempts/$_maxReconnectAttempts)',
      severity: CrashlyticsSeverity.info,
      context: {
        'deviceId': _currentDeviceId ?? 'unknown',
        'attempt': _reconnectAttempts,
      },
    );

    // ✅ P1-14 fix: إغلاق الاشتراك القديم قبل إعادة الاشتراك
    _subscription?.close().catchError((_) {});
    _subscription = null;
    _isListening = false;

    Future<void>.delayed(Duration(seconds: delaySeconds), () {
      // ✅ تحقق مزدوج: عدم إعادة الاتصال إذا تم استدعاء stop() أثناء الانتظار
      if (!_isListening && !_intentionallyStopped) {
        start();
      }
    });
  }

  Future<void> stop() async {
    // ✅ إصلاح P2-13: تعليم التوقف كإرادي لمنع _reconnect من إعادة الاتصال
    _intentionallyStopped = true;
    unawaited(_subscription?.close());
    _subscription = null;
    _isListening = false;
    _debounceTimer?.cancel();
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _pullQueued = false;
    _stopPollingFallback(); // ✅ تنظيف polling fallback
    // عند التوقف، نعيد تعيين الحالة
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
  }

  void dispose() => stop();

  bool get isListening => _isListening;

  // ── خطافات اختبار (لا تُستخدم من كود الإنتاج) ──

  /// إعادة تهيئة الحالة الداخلية بالكامل بين الاختبارات (singleton).
  @visibleForTesting
  void resetForTesting() {
    _subscription = null;
    _isListening = false;
    _intentionallyStopped = false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _triggerInFlight = false;
    _pullQueued = false;
    _lastFireAt = null;
    _consecutiveSkips = 0;
    _lastServerUpdate = null;
    _hasPendingChanges = false;
    _reconnectAttempts = 0;
    hasRemoteChanges.value = false;
    pendingRemoteChangesCount.value = 0;
    _syncTrigger = null;
  }

  @visibleForTesting
  set currentDeviceIdForTesting(String? id) => _currentDeviceId = id;

  @visibleForTesting
  Duration? debugEventDebounce;

  @visibleForTesting
  Duration? debugPullCooldown;

  @visibleForTesting
  Duration? debugFallbackPullInterval;

  @visibleForTesting
  bool get triggerInFlightForTesting => _triggerInFlight;

  @visibleForTesting
  bool get fallbackPollingActiveForTesting => _pollingTimer != null;
}
