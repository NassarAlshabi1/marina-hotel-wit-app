import 'dart:async';
import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'appwrite_network_helper.dart';
import 'appwrite_sync_utils.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'secondary_appwrite_config.dart';
import 'secondary_appwrite_service.dart';
import 'secondary_sync_tracker.dart';
import 'sync/payload_mapper.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// Secondary Sync Manager — مزامنة الوجهة الثانوية بنفس outbox الرئيسي.
///
/// ## الفلسفة التصميمية
///
/// الـ outbox المحلي هو **مصدر واحد للحقائق** لجميع التغييرات المحلية.
/// عندما يحدث تغيير محلي (إنشاء/تعديل/حذف)، يُضاف إلى outbox مرة واحدة.
/// ثم يعمل **مزامنان متوازيان** على نفس الـ outbox:
///
///   1. AppwriteSyncManager (Primary) — يرفع للوجهة الرئيسية
///   2. SecondarySyncManager (Secondary) — يرفع للوجهة الثانوية
///
/// لمنع سباق البيانات (race condition) بين المزامنتين، نستخدم:
///
///   - `delivered_to_primary` (bool): هل تم تسليم السجل للرئيسي؟
///   - `delivered_to_secondary` (bool): هل تم تسليم السجل للثانوي؟
///
/// **السجل يُحذف فقط بعد نجاح كلا الوجهتين** (أو تعطيل Secondary).
///
/// ⚠️ **Sync Simplification (2026-08-10) — DEPRECATED / DISABLED**.
/// Secondary sync معطّل بالكامل عبر [`kSecondarySyncDisabled`] = true.
/// Appwrite primary هو authority الوحيد. جميع الطرق العامة تُرجع no-op
/// فوراً دون تنفيذ أي عمل. الكود محفوظ للتوافق الرجعي مع شاشة الإعدادات
/// (`SecondaryAppwriteSettingsScreen`) ومزوّد Riverpod
/// (`secondarySyncManagerProvider`). إزالة الملف كلياً تتطلب refactor
/// شامل للشاشة + المزوّد — يمكن تأجيله بأمان دون التأثير على السلامة.
///
/// عندما تُستدعى `startAutoSync()` أو `sync()` بعد التعطيل:
/// - تُسجّل رسالة تشخيصية واحدة فقط (لمنع تكرار السجل)
/// - تُرجع فوراً دون جدولة Timer أو تنفيذ loop
/// - لا تغيّر أي حالة داخلية
///
/// ## إصلاحات Secondary Audit (2026-07-03)
///
/// - **P0-1**: حلقة لا نهائية — تتبّع المُعالَج + استبعاد الفاشل + backoff
/// - **P0-2**: فلترة `attempts < maxAttempts` + حالة `dead`
/// - **P1-1**: استبدال `_rebuildPayloadFromLocalDb` بـ `PayloadMapper`
/// - **P1-2**: `deleteDocument` idempotent (تم في الخدمة)
/// - **P1-4**: `await` في `upsertDocument` (تم في الخدمة)
/// - **P1-5**: فحص اتصال مسبق + backoff أسّي + circuit breaker
/// - **P1-6**: timeout + استرداد لـ `_isSyncing`
class SecondarySyncManager {
  factory SecondarySyncManager() => _instance ??= SecondarySyncManager._();

  SecondarySyncManager._();
  static SecondarySyncManager? _instance;

  // ignore: prefer_constructors_over_static_methods
  static SecondarySyncManager get instance => SecondarySyncManager();

  /// ⚠️ **Sync Simplification (2026-08-10)** — معطّل بالكامل.
  /// عند true، جميع الطرق العامة تُرجع no-op فوراً. Appwrite primary هو
  /// authority الوحيد. الكود محفوظ للتوافق الرجعي مع شاشة الإعدادات.
  static const bool kSecondarySyncDisabled = true;

  /// ✅ لتتبّع ما إذا تم تسجيل رسالة "disabled" لتجنب تكرارها في السجل
  /// على كل استدعاء (قد تكون مزعجة عند استدعاء startAutoSync كل بضع دقائق).
  bool _disabledNoticeLogged = false;

  void _logDisabledNotice(String methodName) {
    if (!_disabledNoticeLogged) {
      dlog(
        '🔵 [SecondarySync] DISABLED — $methodName is no-op. '
        'Appwrite primary is the sole authority. (notice logged once)',
      );
      _disabledNoticeLogged = true;
    }
  }

  Timer? _syncTimer;
  bool _isSyncing = false;
  DateTime? _lastSync;
  DateTime? _syncStartedAt;

  /// ✅ P1-6: لتتبّع مدة الجلسة الحالية وإعادة ضبط العلم إن علِق.
  DateTime? get syncStartedAt => _syncStartedAt;

  /// ✅ P1-5: Circuit Breaker — بعد N فشل متتالٍ، نقطع الدائرة لمدة M دقيقة.
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenUntil;
  static const int _circuitBreakerThreshold = 5;
  static const Duration _circuitBreakerCooldown = Duration(minutes: 5);

  /// ✅ P0-2: الحد الأقصى لمحاولات إعادة المحاولة قبل الانتقال لـ `dead`.
  static const int maxAttempts = 10;

  /// ✅ P1-6: المهلة القصوى لجلسة المزامنة الواحدة (10 دقائق). إن تجاوزتها
  /// يُعتبر الثانوي عالقاً ويُعاد ضبط `_isSyncing` في الجلسة التالية.
  static const Duration _syncTimeout = Duration(minutes: 10);

  /// ✅ P1-1: إعادة استخدام PayloadMapper من Primary بدل إعادة بناء يدوي.
  final PayloadMapper _payloadMapper = const PayloadMapper();

  DateTime? get lastSync => _lastSync;
  bool get isSyncing => _isSyncing;
  /// ⚠️ عند التعطيل، دائماً false — حتى لا تعرض شاشة الإعدادات أن auto-sync
  /// يعمل بينما هو في الواقع no-op.
  bool get isAutoSyncEnabled =>
      !kSecondarySyncDisabled && _syncTimer != null;

  /// ✅ P1-5: هل الـ circuit breaker مفتوح حالياً؟
  bool get isCircuitOpen =>
      _circuitOpenUntil != null && DateTime.now().isBefore(_circuitOpenUntil!);

  /// ✅ P1-5: متى يُغلق الـ breaker؟ (للعرض في الواجهة)
  DateTime? get circuitOpenUntil => _circuitOpenUntil;

  /// بدء المزامنة التلقائية
  ///
  /// تعمل فقط إذا كان Secondary مُفعّلاً والرفع (Push) مُفعّلاً.
  /// إذا كان Push معطّلاً، لا فائدة من الجدولة لأن sync() سيرفض العملية.
  ///
  /// ⚠️ **معطّل بالكامل (2026-08-10)** — no-op. انظر [kSecondarySyncDisabled].
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    if (kSecondarySyncDisabled) {
      _logDisabledNotice('startAutoSync');
      return;
    }
    if (!SecondaryAppwriteConfig.isEnabled) {
      dlog('🔵 [SecondarySync] Disabled - enable first');
      return;
    }
    if (!SecondaryAppwriteConfig.isPushEnabled) {
      dlog('🔵 [SecondarySync] Push disabled - no auto-sync');
      return;
    }

    stopAutoSync();
    // ✅ إصلاح جذري: Timer callback يستدعي sync() (async) بدون try-catch.
    // سابقاً: (_) => sync() — أي استثناء يصبح unhandled async error → Fatal.
    _syncTimer = Timer.periodic(interval, (_) async {
      try {
        await sync();
      } catch (e) {
        dlog(() => '❌ [SecondarySync] Auto-sync Timer error: $e');
        // لا rethrow — نمنع fatal crash
      }
    });
    dlog(
      () =>
          '🔵 [SecondarySync] Auto-sync started (every ${interval.inMinutes} min)',
    );
  }

  /// إيقاف المزامنة التلقائية
  ///
  /// ⚠️ **معطّل بالكامل (2026-08-10)** — يُلغي أي Timer معلّق فقط (للأمان).
  void stopAutoSync() {
    // ✅ نُلغي أي Timer معلّق حتى لو كان kSecondarySyncDisabled=true
    // (لحالة الترقية من نسخة قديمة كان فيها Timer فعّال)
    _syncTimer?.cancel();
    _syncTimer = null;
    if (kSecondarySyncDisabled) {
      // لا نسجّل رسالة لتفادي التكرار — stopAutoSync يُستدعى كثيراً
      return;
    }
    dlog('🔵 [SecondarySync] Auto-sync stopped');
  }

  /// ✅ P1-6: استرداد العلم إن علِق لأكثر من _syncTimeout.
  /// يُستدعى في بداية sync() لاكتشاف الجمود.
  bool _isStuck() {
    if (!_isSyncing || _syncStartedAt == null) return false;
    final elapsed = DateTime.now().difference(_syncStartedAt!);
    if (elapsed > _syncTimeout) {
      dlog(
        () =>
            '⚠️ [SecondarySync] stuck for ${elapsed.inMinutes} min — forcing reset',
      );
      _isSyncing = false;
      _syncStartedAt = null;
      return true;
    }
    return false;
  }

  /// مزامنة كاملة (Push only)
  ///
  /// ✅ P0-1: الحلقة آمنة الآن — السجلات الفاشلة تُستبعد من إعادة الالتقاط
  /// في نفس الجلسة عبر تتبّع معرّفاتها. الفاشل يُرجَع لحالة `failed` (لإعادة
  /// المحاولة في جلسة لاحقة) أو `dead` (إذا تجاوز maxAttempts أو خطأ دائم).
  ///
  /// ✅ P0-2: لا يُلتقط سجل `attempts >= maxAttempts`.
  ///
  /// ✅ P1-5: فحص اتصال مسبق + circuit breaker + backoff بين الدورات.
  ///
  /// ✅ P1-6: timeout + استرداد لـ _isSyncing.
  Future<SecondarySyncResult> sync() async {
    // ✅ Sync Simplification (2026-08-10): no-op كامل.
    if (kSecondarySyncDisabled) {
      _logDisabledNotice('sync');
      return SecondarySyncResult(
        success: false,
        message: 'المزامنة الثانوية معطّلة — Appwrite primary هو authority الوحيد',
      );
    }

    // ✅ P1-6: استرداد الجمود قبل فحص _isSyncing
    _isStuck();

    if (_isSyncing) {
      return SecondarySyncResult(
        success: false,
        message: 'مزامنة ثانوية جارية',
      );
    }

    if (!SecondaryAppwriteConfig.isEnabled) {
      return SecondarySyncResult(
        success: false,
        message: 'المزامنة الثانوية معطّلة',
      );
    }

    if (!SecondaryAppwriteConfig.isPushEnabled) {
      return SecondarySyncResult(
        success: false,
        message: 'الرفع للثانوي معطّل',
      );
    }

    // ✅ P1-5: Circuit Breaker — إن كان مفتوحاً، نرفض فوراً
    if (isCircuitOpen) {
      final remaining = _circuitOpenUntil!.difference(DateTime.now());
      return SecondarySyncResult(
        success: false,
        message: 'Circuit breaker مفتوح — حاول بعد ${remaining.inSeconds}s',
      );
    }

    // ✅ P1-5: فحص اتصال مسبق — لا نقصف السيرفر إن كانت الشبكة مقطوعة
    final service = SecondaryAppwriteService.instance;
    final connectionOk = await _checkConnection(service);
    if (!connectionOk) {
      _recordFailure();
      return SecondarySyncResult(
        success: false,
        message: 'لا اتصال بالثانوي — سيُعاد المحاولة لاحقاً',
      );
    }

    _isSyncing = true;
    _syncStartedAt = DateTime.now();

    try {
      final db = DatabaseManager.instance;
      final outboxDao = OutboxDao(db);

      int pushed = 0;
      int failed = 0;
      int dead = 0;
      final tracker = SecondarySyncTracker.instance;
      tracker.startSession();

      // ✅ P0-1: تتبّع السجلات المُعالَجة في هذه الجلسة لمنع إعادة التقاطها
      final processedIds = <int>{};

      // ✅ P0-1 + P1-5: حلقة آمنة مع backoff بين الدورات
      int emptyLoopsInRow = 0;
      while (true) {
        // ✅ إصلاح (2026-07-11): توقف فوري إذا كان network circuit breaker
        // مفعّلاً — لا نلتقط سجلات جديدة وندعها تتراكم للمزامنة القادمة.
        // هذا يمنع الحلقة المفرغة: 429 → circuit breaker → محاولة جديدة → 429.
        if (AppwriteNetworkHelper().isCircuitBreakerActive) {
          final remaining = AppwriteNetworkHelper().circuitBreakerRemaining;
          dlog(
            () =>
                '🔌 [SecondarySync] Network circuit breaker active '
                '(remaining ${remaining?.inSeconds ?? 0}s) — '
                'stopping sync to avoid rate limit loop. '
                '$pushed pushed, $failed failed so far.',
          );
          break;
        }

        // ✅ P0-1: نستبعد السجلات المُعالَجة في هذه الجلسة من الالتقاط
        final entries = await _takeUndeliveredBatch(
          db,
          batchSize: 50,
          excludeIds: processedIds,
        );
        if (entries.isEmpty) {
          emptyLoopsInRow++;
          if (emptyLoopsInRow >= 1) break; // لا مزيد من السجلات
          break;
        }
        emptyLoopsInRow = 0;

        for (final entry in entries) {
          // ✅ P0-1: ضمان مضاعف — لن يُعاد التقاطه لأنه في processedIds
          processedIds.add(entry.id);

          try {
            final success = await _processEntry(service, entry);
            if (success) {
              // ✅ ضع علامة "مُسلّم للثانوي" — لا نحذف!
              await outboxDao.markDeliveredToSecondary(entry.id);
              pushed++;
            } else {
              // _processEntry أرجع false → السجل دخل في setError/setDead
              // بالفعل، لا نضيف شيء هنا
              failed++;
              tracker.trackError(
                entity: entry.entity,
                localUuid: entry.localUuid,
                reason: '_processEntry فشل',
                attempts: entry.attempts + 1,
              );
            }
          } catch (e) {
            dlog(() => '❌ [SecondarySync] Failed entry ${entry.id}: $e');
            // ✅ P0-2: تصنيف الخطأ — دائم أم عابر
            final newAttempts = entry.attempts + 1;
            final isPermanent = _isPermanentError(e);
            if (isPermanent || newAttempts >= maxAttempts) {
              await outboxDao.setDead(
                entry.id,
                '${isPermanent ? "Permanent" : "MaxAttempts"}: $e',
                newAttempts,
              );
              dead++;
            } else {
              await outboxDao.setError(entry.id, e.toString(), newAttempts);
            }
            failed++;
            tracker.trackError(
              entity: entry.entity,
              localUuid: entry.localUuid,
              reason: e.toString(),
              isPermanent: isPermanent,
              attempts: newAttempts,
            );
          }
        }

        // ✅ P1-5: backoff بسيط بين الدورات (10ms فقط إذا كانت هناك سجلات
        // ناجحة لتجنّب إغراق السيرفر، أطول إذا كانت هناك فشل)
        if (failed > 0 && entries.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      _lastSync = DateTime.now();
      await SecondaryAppwriteConfig.updateLastSync();

      // ✅ P1-5: إعادة ضبط الـ circuit breaker عند النجاح
      if (failed == 0) {
        _recordSuccess();
        await SecondaryAppwriteConfig.updateSyncStatus('success');
      } else if (pushed > 0) {
        await SecondaryAppwriteConfig.updateSyncStatus('partial');
      } else {
        _recordFailure();
        await SecondaryAppwriteConfig.updateSyncStatus('partial');
      }

      final sessionSummary = tracker.endSession(
        pushed: pushed,
        failed: failed,
        dead: dead,
        isSuccess: failed == 0,
        message: dead > 0
            ? 'رفع: $pushed، فشل: $failed، ميت: $dead'
            : 'رفع للثانوي: $pushed، فشل: $failed',
      );

      return SecondarySyncResult(
        success: failed == 0,
        message: sessionSummary.message,
        pushed: pushed,
        failed: failed,
        dead: dead,
        failures: tracker.currentErrors
            .map(
              (e) => SecondarySyncFailure(
                entity: e.entity,
                localUuid: e.localUuid,
                reason: e.reason,
                timestamp: e.timestamp,
              ),
            )
            .toList(),
      );
    } catch (e) {
      dlog(() => '❌ [SecondarySync] sync() error: $e');
      _recordFailure();
      await SecondaryAppwriteConfig.updateSyncStatus('error');
      return SecondarySyncResult(success: false, message: 'خطأ: $e');
    } finally {
      _isSyncing = false;
      _syncStartedAt = null;
    }
  }

  /// ✅ P0-2: تصنيف الخطأ — هل هو دائم (400/401/403) أم عابر؟
  bool _isPermanentError(Object e) {
    if (e is! AppwriteException) return false;
    return e.code == 400 || e.code == 401 || e.code == 403;
  }

  /// ✅ P1-5: فحص اتصال مسبق قبل بدء المزامنة.
  Future<bool> _checkConnection(SecondaryAppwriteService service) async {
    try {
      final result = await service.testConnection();
      return result.success;
    } catch (e) {
      dlog(() => '⚠️ [SecondarySync] connection check failed: $e');
      return false;
    }
  }

  /// ✅ P1-5: تسجيل نجاح — يُغلق الـ circuit breaker إن كان مفتوحاً.
  void _recordSuccess() {
    _consecutiveFailures = 0;
    if (_circuitOpenUntil != null) {
      dlog('🟢 [SecondarySync] circuit breaker closed');
    }
    _circuitOpenUntil = null;
  }

  /// ✅ P1-5: تسجيل فشل — بعد N فشل متتالٍ، نفتح الـ circuit breaker.
  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _circuitBreakerThreshold && !isCircuitOpen) {
      _circuitOpenUntil = DateTime.now().add(_circuitBreakerCooldown);
      dlog(
        () =>
            '🔴 [SecondarySync] circuit breaker OPENED for '
            '${_circuitBreakerCooldown.inMinutes} min '
            '($_consecutiveFailures consecutive failures)',
      );
    }
  }

  /// رفع التغييرات المحلية فقط (مثل sync لكن مع returns bool)
  ///
  /// ✅ P2 fix: ترجع `true` إذا نجحت (حتى لو 0 معلّق)، `false` فقط عند الفشل.
  Future<bool> pushLocalChanges() async {
    // ✅ Sync Simplification (2026-08-10): no-op — لا تغييرات تُرفع للثانوي.
    if (kSecondarySyncDisabled) {
      _logDisabledNotice('pushLocalChanges');
      return false;
    }
    final result = await sync();
    // قبل الإصلاح: `result.pushed > 0` — يعطي false إذا كان 0 معلّق
    // (حتى لو كانت sync ناجحة بلا أخطاء)، مما يُظهر اللوحة كـ"فشل".
    // بعد الإصلاح: نعتبر النجاح = لا فشل + لا dead.
    return result.failed == 0 && result.dead == 0;
  }

  /// سحب التغييرات من الثانوي — غير مُدعوم في هذه النسخة
  ///
  /// السحب من Secondary يحتاج منطقاً معقداً للتعارض مع Primary (أيهما أحدث؟).
  /// يُنصح باستخدام Secondary للقراءة فقط عند فشل Primary (Failover).
  ///
  /// ⚠️ **معطّل بالكامل (2026-08-10)** — no-op. انظر [kSecondarySyncDisabled].
  Future<bool> pullRemoteChanges() async {
    if (kSecondarySyncDisabled) {
      _logDisabledNotice('pullRemoteChanges');
      return false;
    }
    if (!SecondaryAppwriteConfig.isPullEnabled) {
      dlog('🔵 [SecondarySync] Pull disabled');
      return false;
    }
    dlog('🔵 [SecondarySync] Pull not implemented in this version');
    return false;
  }

  /// يأخذ batch من سجلات outbox التي لم تُسلّم للثانوي بعد.
  ///
  /// ✅ P0-1: [excludeIds] يستبعد السجلات المُعالَجة في نفس الجلسة.
  /// ✅ P0-2: فلترة `attempts < maxAttempts` + استبعاد حالة `dead`.
  ///
  /// نستخدم atomic UPDATE...RETURNING لمنع سباق البيانات. السجلات تُؤخذ
  /// بشكل مستقل عن Primary (الذي يأخذ سجلاته الخاصة بناءً على
  /// delivered_to_primary).
  Future<List<OutboxData>> _takeUndeliveredBatch(
    AppDatabase db, {
    required int batchSize,
    Set<int>? excludeIds,
  }) async {
    final worker = DateTime.now().millisecondsSinceEpoch.toString();
    // ✅ P2 fix: نوحّد الوحدة إلى ميلي ثانية (ms) لا ثوانٍ — مطابق لـ Primary
    // الذي يقارن بالملّي. هذا يمنع الاسترداد المبكّر/المتأخر للسجلات العالقة.
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;

    // بناء شرط source: نأخذ فقط سجلات 'local' (تغييرات المستخدم)
    // ولا نأخذ 'restore' (استعادة من نسخة احتياطية لا تحتاج secondary)
    const sourceCondition = " AND source = 'local'";

    // ✅ P0-2: نستبعد السجلات الـ dead نهائياً، ونفحص 'pending' و 'failed'
    // ✅ P0-2: نستبعد السجلات التي وصلت لـ maxAttempts
    const statusCondition =
        " AND processing_status IN ('pending', 'failed')"
        ' AND attempts < $maxAttempts';

    // ✅ P0-1: استبعاد السجلات المُعالَجة في هذه الجلسة
    String excludeCondition = '';
    final variables = <drift.Variable>[
      const drift.Variable<String>('processing'),
      drift.Variable<int>(nowEpochMs),
      drift.Variable<String>('secondary_$worker'),
    ];
    if (excludeIds != null && excludeIds.isNotEmpty) {
      // بناء placeholders ديناميكياً: NOT IN (?, ?, ...)
      final placeholders = List.filled(excludeIds.length, '?').join(', ');
      excludeCondition = ' AND id NOT IN ($placeholders)';
      for (final id in excludeIds) {
        variables.add(drift.Variable<int>(id));
      }
    }
    variables.add(drift.Variable<int>(batchSize));

    // ✅ Atomic claim: ضع علامة processing على السجلات غير المُسلّمة للثانوي
    final claimed = await db
        .customSelect(
          'UPDATE outbox SET processing_status = ?, processing_started_at = ?, processing_worker = ? '
          'WHERE id IN ('
          '  SELECT id FROM outbox WHERE delivered_to_secondary = 0$statusCondition$sourceCondition$excludeCondition '
          '  ORDER BY client_ts ASC LIMIT ? '
          ') RETURNING *',
          variables: variables,
          readsFrom: {db.outbox},
        )
        .map(
          (row) => OutboxData(
            id: row.read<int>('id'),
            entity: row.read<String>('entity'),
            op: row.read<String>('op'),
            localUuid: row.read<String>('local_uuid'),
            serverId: row.read<int?>('server_id'),
            payload: row.read<String>('payload'),
            clientTs: row.read<int>('client_ts'),
            processingStatus: row.read<String>('processing_status'),
            processingStartedAt: row.read<int?>('processing_started_at'),
            processingWorker: row.read<String?>('processing_worker'),
            lastError: row.read<String?>('last_error'),
            attempts: row.read<int>('attempts'),
            idempotencyKey: row.read<String?>('idempotency_key'),
            source: row.read<String>('source'),
            deliveredToPrimary: row.read<bool>('delivered_to_primary'),
            deliveredToSecondary: row.read<bool>('delivered_to_secondary'),
            // ✅ Migration 55: قراءة حقول الفصل الجديدة (مع fallback)
            primaryProcessingStatus:
                row.read<String?>('primary_processing_status') ??
                'pending',
            primaryAttempts: row.read<int?>('primary_attempts') ?? 0,
            primaryLastError: row.read<String?>('primary_last_error'),
            secondaryProcessingStatus:
                row.read<String?>('secondary_processing_status') ??
                'pending',
            secondaryAttempts: row.read<int?>('secondary_attempts') ?? 0,
            secondaryLastError: row.read<String?>('secondary_last_error'),
          ),
        )
        .get();

    return claimed;
  }

  /// معالجة سجل واحد من outbox وإرساله للثانوي
  Future<bool> _processEntry(
    SecondaryAppwriteService service,
    OutboxData entry,
  ) async {
    final collectionId = AppwriteConfig.collectionIdFor(entry.entity);
    if (collectionId == null) {
      dlog(() => '⚠️ [SecondarySync] Unknown entity: ${entry.entity}');
      // ✅ P0-2: كيان غير معروف = خطأ دائم → dead مباشرة
      final db = DatabaseManager.instance;
      final outboxDao = OutboxDao(db);
      await outboxDao.setDead(
        entry.id,
        'Unknown entity: ${entry.entity}',
        entry.attempts + 1,
      );
      return false;
    }

    // ✅ P1-1: إعادة بناء الحمولة باستخدام PayloadMapper (يدعم كل الكيانات)
    // بدل إعادة بناء يدوي جزئي كان يدعم rooms و debts فقط.
    Map<String, dynamic> payload;
    try {
      payload = await _rebuildPayloadWithMapper(entry.entity, entry.localUuid);
      payload['localUuid'] = entry.localUuid;
      if (entry.idempotencyKey != null && entry.idempotencyKey!.isNotEmpty) {
        payload['idempotencyKey'] = entry.idempotencyKey;
      }
    } catch (e) {
      // في حالة الفشل، نستخدم الحمولة المخزنة كاحتياط
      dlog(
        () =>
            '⚠️ [SecondarySync] PayloadMapper failed for ${entry.entity}: $e — using stored payload',
      );
      payload = _parsePayload(entry.payload);
      payload['localUuid'] = entry.localUuid;
      if (entry.idempotencyKey != null && entry.idempotencyKey!.isNotEmpty) {
        payload['idempotencyKey'] = entry.idempotencyKey;
      }
    }

    // ✅ تصفية payload قبل الإرسال (إزالة الحقول غير الموجودة في المخطط)
    final filteredPayload = AppwriteSyncUtils.filterPayloadForCollection(
      collectionId,
      payload,
    );

    try {
      if (entry.op == 'delete') {
        await service.deleteDocument(
          collectionId: collectionId,
          documentId: entry.localUuid,
        );
        return true;
      }

      // create أو update — نستخدم upsert (نفس منطق Primary)
      await service.upsertDocument(
        collectionId: collectionId,
        documentId: entry.localUuid,
        data: filteredPayload,
      );
      return true;
    } on AppwriteException catch (e) {
      // ✅ P0-2: معالجة صحيحة للأخطاء الدائمة → setDead مباشرة
      if (_isPermanentError(e)) {
        dlog(
          () =>
              '❌ [SecondarySync] Permanent error for ${entry.entity}/${entry.localUuid}: ${e.code} ${e.message}',
        );
        final db = DatabaseManager.instance;
        final outboxDao = OutboxDao(db);
        await outboxDao.setDead(
          entry.id,
          'Permanent (${e.code}): ${e.message}',
          entry.attempts + 1,
        );
        return false;
      }
      rethrow; // خطأ عابر → يُلتقط في sync() ويعامل كـ failed مؤقت
    }
  }

  /// ✅ P1-1: إعادة بناء الحمولة باستخدام PayloadMapper من Primary.
  ///
  /// يدعم كل الكيانات الـ 18+ بدل الكيانين فقط (rooms، debts) في الإصدار
  /// القديم. إن لم يكن الكيان مدعوماً في PayloadMapper، يرمي UnsupportedError
  /// الذي يُلتقط في `_processEntry` ويعود للحمولة المخزنة في outbox.
  Future<Map<String, dynamic>> _rebuildPayloadWithMapper(
    String entity,
    String localUuid,
  ) async {
    final db = DatabaseManager.instance;

    switch (entity) {
      case 'rooms':
        final row = await (db.select(
          db.rooms,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.roomToRemote(row);

      case 'bookings':
        final row = await (db.select(
          db.bookings,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.bookingToRemote(row);

      case 'expenses':
        final row = await (db.select(
          db.expenses,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.expenseToRemote(row);

      case 'payments':
        final row = await (db.select(
          db.payments,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.paymentToRemote(row);

      case 'debts':
        final row = await (db.select(
          db.debts,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.debtToRemote(row);

      case 'employees':
        final row = await (db.select(
          db.employees,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.employeeToRemote(row);

      case 'booking_notes':
        final row = await (db.select(
          db.bookingNotes,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.bookingNoteToRemote(row);

      case 'booking_nights':
        final row = await (db.select(
          db.bookingNights,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.bookingNightToRemote(row);

      case 'cash_transactions':
        final row = await (db.select(
          db.cashTransactions,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.cashTransactionToRemote(row);

      case 'salary_cycles':
        final row = await (db.select(
          db.salaryCycles,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.salaryCycleToRemote(row);

      case 'salary_payments':
        final row = await (db.select(
          db.salaryPayments,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.salaryPaymentToRemote(row);

      case 'shift_notes':
        final row = await (db.select(
          db.shiftNotes,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.shiftNoteToRemote(row);

      case 'price_adjustments':
        final row = await (db.select(
          db.priceAdjustments,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.priceAdjustmentToRemote(row);

      case 'blacklist':
        // ⚠️ blacklist table غير موجود محلياً — يستخدم shiftNotes كـ workaround
        // يجب إضافة جدول blacklist في local_db.dart أو استخدام جدول بديل
        final row = await (db.select(
          db.shiftNotes,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.blacklistToRemote(row);

      case 'guest_infos':
        final row = await (db.select(
          db.guestInfos,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.guestInfoToRemote(row);

      case 'salary_withdrawals':
        final row = await (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.salaryWithdrawalToRemote(row);

      case 'booking_price_adjustments':
        final row = await (db.select(
          db.bookingPriceAdjustments,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.bookingPriceAdjustmentToRemote(row);

      case 'salary_carry_over_logs':
        final row = await (db.select(
          db.salaryCarryOverLogs,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.salaryCarryOverLogToRemote(row);

      case 'payment_voids':
        final row = await (db.select(
          db.paymentVoids,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row == null) return {};
        return _payloadMapper.paymentVoidToRemote(row);

      default:
        throw UnsupportedError(
          'PayloadMapper does not support entity: $entity',
        );
    }
  }

  /// تحويل payload من JSON string إلى Map
  Map<String, dynamic> _parsePayload(String payload) {
    try {
      if (payload.isEmpty || payload == '{}') return {};
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    } catch (e) {
      dlog(() => '⚠️ [SecondarySync] Failed to parse payload: $e');
      return {};
    }
  }
}

/// نتيجة المزامنة الثانوية
class SecondarySyncResult {
  SecondarySyncResult({
    required this.success,
    required this.message,
    this.pushed = 0,
    this.failed = 0,
    this.dead = 0,
    this.failures = const [],
  });

  final bool success;
  final String message;
  final int pushed;
  final int failed;

  /// ✅ P0-2: عدد السجلات التي انتقلت للحالة النهائية `dead` في هذه الجلسة.
  final int dead;

  /// تفاصيل الإخفاقات في هذه الجلسة
  final List<SecondarySyncFailure> failures;

  /// نص ملخص جاهز للنسخ إلى الحافظة
  String get textSummary {
    final buf = StringBuffer();
    buf.writeln('🔄 تقرير المزامنة الثانوية');
    buf.writeln('════════════════════════════');
    buf.writeln();
    final statusIcon = success ? '✅' : '❌';
    buf.writeln('$statusIcon الحالة: $message');
    buf.writeln('📤 تم الرفع: $pushed');
    buf.writeln('❌ فشل: $failed');
    buf.writeln('☠️ Dead: $dead');
    buf.writeln();

    if (failures.isNotEmpty) {
      buf.writeln('── تفاصيل الإخفاقات ──');
      for (final f in failures) {
        buf.writeln('  · [${f.entity}] ${f.localUuid}: ${f.reason}');
      }
      buf.writeln();
    }

    buf.writeln('🕐 ${DateTime.now().toLocal().toIso8601String()}');
    buf.writeln('Marina Hotel — Secondary Sync Report');
    return buf.toString();
  }
}

/// خطأ في مزامنة سجل واحد للثانوي
class SecondarySyncFailure {
  SecondarySyncFailure({
    required this.entity,
    required this.localUuid,
    required this.reason,
    this.timestamp,
  });

  final String entity;
  final String localUuid;
  final String reason;
  final DateTime? timestamp;

  @override
  String toString() {
    return '❌ [$entity] $localUuid: $reason';
  }

  Map<String, dynamic> toJson() {
    return {
      'entity': entity,
      'localUuid': localUuid,
      'reason': reason,
      'timestamp': timestamp?.toLocal().toIso8601String(),
    };
  }
}
