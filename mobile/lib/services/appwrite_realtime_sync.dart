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
///
/// ✅ (2026-09-01) إزالة fast-apply من مسار Realtime — المسار **الوحيد**
/// المقبول لـ Remote → Local:
///   Realtime event → AppwriteRealtimeSync → (طابور الأحداث المُجدول أدناه)
///   → AppwriteSyncManager/SyncPullService → Delta Pull → merge → Drift.
/// لا يوجد أي مسار مباشر من Realtime إلى Drift (typedef بلا وسائط: لا
/// "كيانات مطبّقة" ولا تطبيق من الحمولة).
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
/// ضبط المعدل (طابور الأحداث — دور RemoteChangeQueue): لماذا يجوز لمدخل
/// Realtime تجاوز حارس الدقيقتين (minPullGap)؟
///  - الحدث نفسه إثبات من الخادم بحدوث تغيير فعلي، وليس تخميناً دورياً.
///  - الطبقة هنا طابور مُصمت: ديبونس 500ms (دمج دفعة أحداث في حدث واحد)
///    + تهيئة [SyncConstants.realtimeEventPullCooldown] + حارس in-flight
///    + طابور متابعة (trailing) — 10 أحداث متتالية = دورة سحب **واحدة**:
///    الحد الأقصى النظري 4 دورات/دقيقة تحت عاصفة مستمرة، وعادةً دورة واحدة
///    لكل دفعة تغييرات. لا سحوبات متزامنة إطلاقاً (in-flight + trailing).
///  - Delta pull يجلب كل التغييرات منذ المؤشر أياً كان عددها، فالدمج آمن.
///  - Metadata-first يجعل الدورة الرخيصة عندما لا يوجد شيء جديد فعلاً.
///  - حمايات المدير تبقى سارية: OutboxPullPolicy (لا سحب فوق تغييرات
///    محلية غير مرفوعة) و SyncLocks و فحص الاتصال.
///  - ✅ (2026-09-01) السحب المُشغَّل من هنا **delta-only حصراً**
///    (deltaOnly: true في المدخل المحقون من main.dart) — يستحيل أن يبدأ
///    Full Sync من Realtime أو من الخلفية؛ الفحص الصريح فقط.
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
  // ✅ (2026-09-01) إزالة fast-apply نهائياً: الحدث لا يُطبَّق من الحمولة
  // أبداً — يمر عبر الطابور إلى Delta Pull (المسار الوحيد المقبول).
  RemoteChangePull? _syncTrigger;

  Timer? _cooldownTimer;
  bool _triggerInFlight = false;
  bool _pullQueued = false;
  DateTime? _lastFireAt;
  int _consecutiveSkips = 0;

  /// ✅ (2026-09-01) استرداد ما بعد إعادة الاتصال (إلزامي):
  /// تُضبط عند فقدان الاتصال/الاستسلام/عودة التطبيق — ويُستهلك في
  /// [onSubscriptionEstablished] بإطلاق Delta Pull يستدراك الأحداث المفقودة
  /// خلال الانقطاع. لا Full Sync أبداً — delta فقط عبر المدخل المحقون.
  bool _pendingRecoveryPull = false;

  /// ✅ (2026-09-01) جدول اشتراكات Realtime = الكيانات البعيدة التي يمكن
  /// تعديلها من جهاز آخر (جدول الكيانات الكامل في تقرير المسار المعماري):
  ///  - **18 كياناً بعيداً** لكل منها اشتراك + Delta pull.
  ///  - `audit_logs` مستبعد تماماً (SyncConstants.auditLogsSyncEnabled =
  ///    false — لا مزامنة أصلاً منذ e1975be) → لا Realtime ولا pull.
  ///  - `hotel_day_ledger` محلي فقط (appwrite_config.dart L59-60) →
  ///    No Realtime / No Appwrite Pull.
  ///  - `app_settings`/`blacklist`/`salary_carry_over_logs`/
  ///    `inventory_items`/`inventory_transactions` كانت تُسحب دلتا لكن
  ///    **بلا اشتراك Realtime** — تغييرها من جهاز آخر لم يكن يصل إلا بعد
  ///    auto-sync (15 دقيقة) أو حارس الركود (ساعة). أُضيفت هنا (2026-09-01):
  ///    كيانات Remote قابلة للتعديل من أجهزة أخرى.
  ///  - `devices`/`sync_logs`/`sync_state`/`app_users` بنية تحتية —
  ///    ليست بيانات عمل تُسحب؛ لا اشتراك.
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
    AppwriteConfig.salaryCarryOverLogsCollectionId,
    AppwriteConfig.shiftNotesCollectionId,
    AppwriteConfig.guestInfosCollectionId,
    // ❌ hotel_day_ledger - محلي فقط
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    AppwriteConfig.blacklistCollectionId,
    AppwriteConfig.inventoryItemsCollectionId,
    AppwriteConfig.inventoryTransactionsCollectionId,
    AppwriteConfig.appSettingsCollectionId,
    if (SyncConstants.auditLogsSyncEnabled) AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
  ];

  /// حقن دالة السحب الفعلي (يُستدعى من main.dart بعد جاهزية SyncManager).
  ///
  /// ```dart
  /// AppwriteRealtimeSync().setSyncTrigger(() async {
  ///   final r = await syncManager.sync(
  ///     // ✅ (2026-09-01) deltaOnly: true — السحب المُشغَّل من Realtime
  ///     // لا يبدأ Full Sync أبداً (Bootstrap الصريح فقط).
  ///     push: true, pull: true, realtimePriority: true, deltaOnly: true,
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
        .map((c) => 'databases.${AppwriteConfig.databaseId}.collections.$c.documents')
        .toList();

    try {
      _subscription = _realtime!.subscribe(channels);
      _isListening = true;
      onSubscriptionEstablished();

      dlog(
        () =>
            '[Realtime] connected — subscribed: ${channels.length} '
            'collections (delta pull enabled)',
      );

      _subscription!.stream.listen(
        _onEvent,
        onError: (Object e) {
          dlog(() => '[Realtime] disconnected — stream error: $e');
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
            dlog('[Realtime] disconnected — stream done');
            _reconnect();
          }
        },
      );
    } catch (e) {
      dlog('[Realtime] disconnected — WebSocket not available, falling back');
      dlog(() => '   Error: $e');
      // ✅ WebSocket غير متاح — نعتمد على fallback
      _startPollingFallback();
    }
  }

  /// ✅ (2026-09-01) نُفّذ نجاح الاشتراك — منفصل عن [start] ليكون قابلاً
  /// للاختبار بلا WebSocket حقيقي، ولتوحيد منطق "اشتراك جديد":
  ///
  ///  - الانتقال من fallback إلى WS ناجح → أوقف مؤقتات الـ fallback.
  ///  - استرداد ما بعد انقطاع (إلزامي): إذا كان الاتصال فقد سابقاً
  ///    (reconnect/resume/تحول من fallback) أطلق **Delta Pull** واحداً
  ///    يستدراك الأحداث المفقودة خلال الانقطاع — عبر نقطة الدخول الحالية
  ///    (المدخل المحقون) ولا Full Sync أبداً.
  ///  - الاشتراك الأول عند إقلاع التطبيق لا يُطلق استرداداً — فحص فتح
  ///    التطبيق والـ bootstrap الصريح هما مسؤولاه.
  @visibleForTesting
  void onSubscriptionEstablished() {
    final needsRecovery = _pendingRecoveryPull || _pollingTimer != null;
    _pendingRecoveryPull = false;
    _stopPollingFallback();
    if (needsRecovery) {
      dlog('[Realtime] reconnected — recovery pull scheduled');
      dlog('[DeltaSync] recovery pull started');
      _schedulePull();
    }
  }

  /// ✅ (2026-08-31) إعادة المحاولة الآمنة عند عودة التطبيق للواجهة:
  /// إذا استسلمت إعادة الاتصال (max attempts) أو فشل start() عند الإقلاع،
  /// استدعاء عند resume يعيد محاولة الاشتراك من جديد.
  ///
  /// ✅ (2026-09-01) عودة التطبيق بعد غياب = فجوة أحداث محتملة →
  /// يُعلَّم الاسترداد كي يُطلق Delta Pull بعد نجاح الاشتراك.
  Future<void> ensureStarted() async {
    if (_isListening || _intentionallyStopped) {
      return;
    }
    _pendingRecoveryPull = true;
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
      final interval = debugFallbackPullInterval ?? SyncConstants.realtimeFallbackPullInterval;
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

  /// تحليل قناة/حدث Appwrite: `databases.<db>.collections.<col>.documents.<doc>.<action>`
  /// يُرجع null-action للأحداث غير الخاصة بالبيانات.
  @visibleForTesting
  static ({String? collectionId, String? documentId, String? action}) parseDatabaseEvent(List<String> events) {
    for (final e in events) {
      final parts = e.split('.');
      final colIdx = parts.indexOf('collections');
      final docIdx = parts.indexOf('documents');
      if (colIdx == -1 || colIdx + 1 >= parts.length) continue;
      if (docIdx == -1 || docIdx + 1 >= parts.length) continue;
      // بنية حدث المستند الصارمة:
      // databases.<db>.collections.<col>.documents.<doc>.<action>
      // أي مقطع إضافي (مثل …documents.<doc>.permissions.update) يعني حدث
      // نظام/صلاحيات وليس تغيير بيانات → يُرفض.
      if (docIdx != colIdx + 2) continue;
      if (parts.length != docIdx + 3) continue;
      final action = parts.last;
      if (action == 'create' || action == 'update' || action == 'delete') {
        return (collectionId: parts[colIdx + 1], documentId: parts[docIdx + 1], action: action);
      }
    }
    return (collectionId: null, documentId: null, action: null);
  }

  void _onEvent(RealtimeMessage message) {
    handleRemoteDataChange(events: message.events, payload: message.payload);
  }

  /// نواة معالجة الحدث (مفصولة عن RealtimeMessage لتكون قابلة للاختبار
  /// المباشر بلا WebSocket ولا بناء نماذج SDK).
  @visibleForTesting
  void handleRemoteDataChange({required List<String> events, required Map<String, dynamic> payload}) {
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
    final isDataChange = events.any((e) => e.endsWith('.create') || e.endsWith('.update') || e.endsWith('.delete'));

    if (!isDataChange) {
      dlog(() => '📡 Realtime: ignoring non-data event: $events');
      return;
    }

    // ✅ (2026-09-01) إزالة fast-apply من مسار Realtime نهائياً — النقطة
    // الأهم في المواصفة: **لا يوجد مسار مباشر من Realtime إلى Drift**.
    // الحمولة لا تُطبَّق من هنا أبداً (create/update/delete كلها) — الحدث
    // يُدمَج في الطابور أدناه ويُسحب عبر Delta Pull (نقطة الدخول الحالية:
    // AppwriteSyncManager → SyncPullService) حيث يعمل Field-Level merge
    // ومنطق tombstones الحالي دون اختصار.

    // ✅ تحسين: تتبع آخر وقت تحديث (Delta Sync Safety)
    final updatedAt = payload[r'$updatedAt'] ?? payload[r'$createdAt'];
    if (updatedAt != null) {
      try {
        final serverTime = DateTime.parse(updatedAt as String);
        if (_lastServerUpdate == null || serverTime.isAfter(_lastServerUpdate!)) {
          _lastServerUpdate = serverTime;
        }
      } catch (e) {
        dlog('⚠️ Realtime: could not parse update timestamp');
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debugEventDebounce ?? const Duration(milliseconds: 500), () {
      // ✅ تحسين: حماية من الفيضان (Flood Protection)
      if (!_hasPendingChanges) {
        hasRemoteChanges.value = true;
        _hasPendingChanges = true;
        dlog('📡 Realtime: detected remote changes - UI activated');
      }

      pendingRemoteChangesCount.value++;

      // ✅✅ (2026-08-31) التفعيل الكامل: الحدث يُطلق **سحباً فعلياً**
      // وليس مجرد شارة UI — التغيير من جهاز آخر يصل خلال ثوانٍ.
      // ✅ (2026-09-01) تسجيل واضح للطابور: الحدث مُدمَج (debounce) وجاهز
      // لإطلاق Delta Pull — لا تطبيق مباشر من الحمولة.
      dlog(
        () =>
            '[Realtime] event: ${events.join(',')} — queued (merged by '
            'debounce), triggering delta pull',
      );
      _schedulePull();
    });
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
    final cooldown = debugPullCooldown ?? SyncConstants.realtimeEventPullCooldown;
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
    dlog('[Realtime] triggering delta pull');
    dlog('[DeltaSync] pull started');

    var pulled = false;
    try {
      // ✅ (2026-09-01) المسار الوحيد: Realtime → طابور → Delta Pull عبر
      // نقطة الدخول الحالية (sync(push, pull, realtimePriority, deltaOnly))
      // → Field-Level merge → Drift. بلا أي وسائط تخطٍّ/تطبيق مباشر.
      pulled = await trigger();
    } catch (e) {
      dlog(() => '⚠️ Realtime: triggered pull failed: $e');
    } finally {
      _triggerInFlight = false;
    }

    if (pulled) {
      // السحب أُكمل فعلاً — التغييرات من السيرفر طُبّقت، صفّر شارات الـ UI.
      _consecutiveSkips = 0;
      dlog('[DeltaSync] pull completed');
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
          () =>
              '📡 Realtime: pull skipped ×$_consecutiveSkips — '
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

    // ✅ (2026-09-01) استرداد إلزامي: فقدنا أحداثاً خلال الانقطاع حتماً —
    // الاشتراك القادم سيُطلق Delta Pull واحداً (لا Full Sync).
    _pendingRecoveryPull = true;

    _reconnectAttempts++;
    dlog(
      () =>
          '[Realtime] reconnecting '
          '(attempt $_reconnectAttempts/$_maxReconnectAttempts)',
    );

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
        error: 'Max reconnect attempts reached after $_maxReconnectAttempts tries',
        severity: CrashlyticsSeverity.warning,
        context: {'deviceId': _currentDeviceId ?? 'unknown'},
      );
      // ✅ (2026-08-31) الاستسلام لا يعني انقطاع التحديثات: fallback
      // polling (علامة + سحب خفيف كل 5 دقائق) يستمر حتى resume القادم.
      _startPollingFallback();
      return;
    }

    // ✅ P1-14 fix: backoff أسّي محدود (5s → 10s → 20s → 40s → 60s capped)
    final delaySeconds = (_reconnectAttempts == 1) ? 5 : (5 * (1 << (_reconnectAttempts - 1))).clamp(5, 60);

    CrashlyticsService.instance.recordSyncError(
      operation: 'realtime_reconnect',
      error:
          'Connection lost — reconnecting in ${delaySeconds}s '
          '(attempt $_reconnectAttempts/$_maxReconnectAttempts)',
      severity: CrashlyticsSeverity.info,
      context: {'deviceId': _currentDeviceId ?? 'unknown', 'attempt': _reconnectAttempts},
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
    _pullQueued = false; // ✅ (2026-09-01) إفراغ طابور الأحداث (Logout)
    _pendingRecoveryPull = false; // ✅ لا استرداد بعد توقف إرادي
    _stopPollingFallback(); // ✅ تنظيف polling fallback
    dlog(
      '[Realtime] disconnected — intentional stop (subscriptions closed, '
      'queue cleared)',
    );
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
    _pendingRecoveryPull = false;
    // ✅ (2026-08-31) تصفير حقول debug أيضاً — منع التسرب بين الاختبارات:
    // اختبار يترك debugPullCooldown صغيراً كان يغيّر سلوك اختبار آخر حسب
    // ترتيب تشغيلها (--test-randomize-ordering-seed random في CI).
    // كل اختبار يضبط حقول debug التي يحتاجها بعد resetForTesting صراحةً.
    debugEventDebounce = null;
    debugPullCooldown = null;
    debugFallbackPullInterval = null;
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

  @visibleForTesting
  bool get pendingRecoveryPullForTesting => _pendingRecoveryPull;

  /// ✅ (2026-09-01) خطاف اختبار: يحاكي حدث فقدان الاتصال (نفس أول خطوة
  /// [_reconnect] الحقيقية — تعليم الاسترداد) بلا WebSocket حقيقي.
  @visibleForTesting
  void markDisconnectedForTesting() {
    _pendingRecoveryPull = true;
  }
}
