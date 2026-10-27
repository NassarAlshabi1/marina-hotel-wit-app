import 'package:appwrite/models.dart' as models;

import '../../utils/weak_device_optimizer.dart';
import 'sync_checkpoint_store.dart';
import 'sync_pull_service.dart';

/// ✅ Unified Pull (2026-08-31): خطة سحب لمجموعة واحدة.
class CollectionPullPlan {
  const CollectionPullPlan({
    required this.collectionName,
    required this.isFullSync,
    required this.queries,
    required this.sinceTs,
  });

  final String collectionName;

  /// true → أول تثبيت أو إعادة كاملة لهذه المجموعة (Full pull).
  /// false → Delta فقط (`$updatedAt > sinceTs - نافذة الأمان`).
  final bool isFullSync;

  /// استعلامات Appwrite الجاهزة لهذه المجموعة في هذه الدورة.
  final List<String> queries;

  /// المؤشر الحالي للمجموعة (0 في وضع Full).
  final int sinceTs;
}

/// ✅ مهمة سحب لمجموعة واحدة — يوفّرها AppwriteSyncManager (إغلاق على دواله الخاصة).
class CollectionPullTask {
  CollectionPullTask({
    required this.name,
    required this.fetch,
    required this.apply,
    this.fetchPage,
    this.streamFullSync = false,
    this.critical = true,
  });

  /// اسم المجموعة (مفتاح الـ checkpoint في sync_checkpoints).
  final String name;

  /// جلب المستندات من Appwrite وفق خطة المجموعة (Full أو Delta) — المسار
  /// الكلاسيكي أحادي الطلبات (كل الصفحات تُجلب دفعة واحدة في الذاكرة).
  final Future<List<models.Document>> Function(CollectionPullPlan plan) fetch;

  /// تطبيق المستندات محلياً — يعيد عدد السجلات المطبَّقة.
  final Future<int> Function(List<models.Document> docs) apply;

  /// ✅ Resumable Full Sync (2026-09-21): جلب **صفحة واحدة** بمعطى استعلاماتها
  /// الكاملة (orderAsc($id) + limit + cursorAfter مضمنة من
  /// [SyncPullService.buildFullSyncPageQueries]).
  ///
  /// عند توفّره مع [streamFullSync] يستبدل مسار Full الكلاسيكي بمسار تدفقي:
  /// صفحة → تطبيق → تقدّم مؤشر → صفحة. الذاكرة محدودة بحجم صفحة واحدة
  /// بغض النظر عن حجم المجموعة (عشرات آلاف الليالي)، والانقطاع (شبكة
  /// ضعيفة/قتل التطبيق) يُستأنف من آخر صفحة نجحت.
  final Future<List<models.Document>> Function(List<String> queries)? fetchPage;

  /// ✅ Resumable Full Sync: true → مسار Full لهذه المهمة يعمل تدفقياً
  /// (يتطلب [fetchPage]). false (الافتراضي) → السلوك الكلاسيكي كما هو —
  /// توافق خلفي كامل مع المجموعات الأخرى.
  final bool streamFullSync;

  /// false → فشلها لا يُسجَّل في failedCollections (مثل app_settings).
  final bool critical;
}

/// نتيجة دورة سحب موحّدة.
class PullRunResult {
  PullRunResult({required this.recordsPulled, required this.failedCollections});

  final int recordsPulled;
  final List<String> failedCollections;
}

/// مراقب اختياري لكل مهمة (للمقاييس والتسجيل).
typedef UnifiedPullTaskObserver =
    void Function(String name, int elapsedMs, bool success);

/// مراقب أخطاء اختياري لكل مهمة.
typedef UnifiedPullTaskErrorHandler =
    Future<void> Function(String name, Object error, StackTrace stackTrace);

/// ✅ Unified Pull Engine (2026-08-31) — مسار السحب الوحيد في التطبيق.
///
/// **المبدأ**: أول تثبيت = Full pull لكل مجموعة، وبعدها Delta فقط —
/// على مستوى كل مجموعة مستقلة (checkpoint خاص في جدول `sync_checkpoints`).
///
/// **ما يوحّده**: `AppwriteSyncManager.sync()` و`pullRemoteChanges()`
/// كلاهما ينفّذ نفس قائمة المهام عبر [run] — لا مسارين منفصلين بعد اليوم.
///
/// **إصلاحات مدمجة**:
///   - `failedCollections` تُعبَّأ فعلياً عند أي فشل (كانت تُعلن ولا تُملأ
///     في pullRemoteChanges → المؤشر العام كان يتقدّم رغم الفشل).
///   - مؤشر كل مجموعة مشتق من `max($updatedAt)` للمستندات المسحوبة
///     (سلطة الخادم) — لا `Time.nowEpoch()` (زمن الجهاز الساحب).
///     هذا يُصلح خلل booking_nights التاريخي.
///   - فشل مجموعة لا يمنع تقدّم مؤشرات المجموعات الناجحة.
///   - pullRemoteChanges كان يفقد 3 مجموعات موجودة في sync()
///     (inventory_items, inventory_transactions, salary_carry_over_logs) —
///     القائمة الموحدة تُغلق هذه الفجوة.
///
/// ✅ Resumable Full Sync (2026-09-21) — إصلاح P0 فقدان البيانات:
///
/// المشكلة القديمة: مهمة Full لـ booking_nights كانت تُسحب بسقف جزئي
/// (1000 سجل) ثم يُثبَّت checkpoint من `max($updatedAt)` لأقدم 1000 سجل
/// وتُعلن المجموعة مكتملة → السجلات الباقية (الأحدث ترتيباً بـ $id أو
/// غير المعدّلة منذ المؤشر) لا تظهر في أي Delta لاحق → **فقدان صامت**.
/// فندق 20 غرفة × سنة ≈ 7000 ليلة: 85% من الليالي مفقودة على أي تثبيت
/// جديد — والحجوزات المكتملة تعتمد عمداً على ليالي السحابة (لا إعادة
/// بناء محلي) فتظهر التقارير المالية ناقصة.
///
/// الحل ([_runStreamingFullPull]):
///   - **بلا سقف**: الحلقة تستمر حتى نفاد المستندات فعلياً — أول مزامنة
///     كاملة بلا حد كما هو مطلوب.
///   - **ذاكرة محدودة**: صفحة (100 مستند) تُطبَّق ثم تُنسى — لا تجميع
///     آلاف المستندات في الذاكرة (حماية أجهزة 1GB).
///   - **crash-safe**: مؤشر الصفحة (`full_sync_cursor`) يُثبَّت بعد نجاح
///     التطبيق فقط؛ الانقطاع (إنترنت ضعيف، قتل التطبيق، نفاد مهلة الدورة)
///     يُستأنف من آخر صفحة في الدورة التالية (المزامنة التلقائية 15 دقيقة
///     أو فتح التطبيق).
///   - **checkpoint عند النفاد فقط**: `completeFullSync` يُثبّت مؤشر Delta
///     من أقصى `$updatedAt` مُشاهد عبر كل الصفحات — لا فقدان أبداً.
///   - **تنفّس للأجهزة الضعيفة**: مهلة قصيرة بين الصفحات (250ms على
///     الأجهزة الضعيفة / yield للأجهزة القوية) تمنع تجويع حلقة الأحداث
///     واضطراب الواجهة أثناء سحب طويل.
class UnifiedPullEngine {
  UnifiedPullEngine({required this.checkpoints, required this.pullService});

  final SyncCheckpointStore checkpoints;
  final SyncPullService pullService;

  /// حجم صفحة السحب الكامل التدفقي — مطابق لـ AppwriteConfig.maxPageSize
  /// (100). صفحة واحدة في الذاكرة في كل لحظة.
  static const int fullSyncPageSize = 100;

  /// صمام أمان ضد حلقة لا نهائية (مؤشر لا يتقدم بخادم مخرب): 5000 صفحة
  /// × 100 مستند = 500 ألف مستند لكل مجموعة — أبعد من أي فندق واقعي.
  static const int _maxFullSyncPages = 5000;

  /// يبني خطة السحب لمجموعة واحدة:
  ///   - checkpoint غير مكتمل أو صفر → Full pull (استبعاد tombstones).
  ///   - غير ذلك → Delta فقط منذ مؤشر المجموعة الخاص.
  ///
  /// ✅ إصلاح توصيل (2026-09-13): كيانات "الآباء المرجعية" (employees —
  /// موثقة في [SyncPullService.entityNeedsTombstoneParents]) تُسحب
  /// tombstones الخاصة بها حتى في Full pull. الدالة كانت معرّفة منذ
  /// 2026-09-02 بتوثيق كامل (128 سحوبة راتب يتيمة في بيانات الإنتاج،
  /// 654,500 وحدة) لكن لم يكن لها أي استدعاء في كود الإنتاج — والمحرك
  /// الموحد كان يستدعي buildFullSyncQueries() دائماً بلا tombstones،
  /// فلا يُنزَّل الموظفون المحذوفون ناعماً ويُتخطى أبناؤهم الماليون
  /// (salary_withdrawals/salary_cycles) كأيتام في كل دورة سحب.
  Future<CollectionPullPlan> plan(String collectionName) async {
    final fullDone = await checkpoints.isFullSyncComplete(collectionName);
    final sinceTs = await checkpoints.getLastPullTs(collectionName);
    if (!fullDone || sinceTs <= 0) {
      return CollectionPullPlan(
        collectionName: collectionName,
        isFullSync: true,
        queries: SyncPullService.buildFullSyncQueries(
          includeTombstones: SyncPullService.entityNeedsTombstoneParents(
            collectionName,
          ),
        ),
        sinceTs: 0,
      );
    }
    return CollectionPullPlan(
      collectionName: collectionName,
      isFullSync: false,
      queries: pullService.buildDeltaQueriesForCollection(sinceTs),
      sinceTs: sinceTs,
    );
  }

  /// يثبّت مؤشر المجموعة بعد نجاح سحبها — من سلطة الخادم max($updatedAt).
  ///
  /// ملاحظة: إذا لم تُرجع المجموعة مستندات (maxTs = null) والمؤشر الحالي 0،
  /// لا نُثبّت شيئاً — المجموعة الفارغة تبقى في وضع Full (استعلام رخيص)
  /// حتى تظهر أول مستندات حقيقية، تفادياً لانحراف ساعات الأجهزة.
  Future<void> commit(
    String collectionName, {
    required int? maxUpdatedAtSec,
    required int sinceTs,
  }) async {
    if (maxUpdatedAtSec != null) {
      await checkpoints.setLastPullTs(collectionName, maxUpdatedAtSec);
      return;
    }
    if (sinceTs > 0) {
      // دورة Delta بلا تغييرات — نؤكد الاكتمال (idempotent) ونحافظ على المؤشر.
      await checkpoints.markFullSyncComplete(collectionName);
    }
  }

  /// ينفّذ قائمة المهام بالترتيب (ترتيب FK-آمن يحدده المستدعي).
  ///
  /// فشل مهمة لا يوقف الباقي — يُسجَّل في failedCollections فقط إذا كانت
  /// [CollectionPullTask.critical].
  Future<PullRunResult> run(
    List<CollectionPullTask> tasks, {
    UnifiedPullTaskObserver? onTaskDone,
    UnifiedPullTaskErrorHandler? onTaskError,
  }) async {
    int recordsPulled = 0;
    final failed = <String>[];

    for (final task in tasks) {
      final stopwatch = Stopwatch()..start();
      var success = false;
      try {
        // ملاحظة: اسم المتغير المحلي يجب ألا يحجب اسم الدالة [plan] —
        // الظلّ هنا (final plan = await plan(...)) يجعل الاستدعاء يشير
        // إلى المتغير نفسه قبل تهيئته (referenced_before_declaration).
        final pullPlan = await plan(task.name);
        if (pullPlan.isFullSync &&
            task.streamFullSync &&
            task.fetchPage != null) {
          // ✅ مسار تدفقي قابل للاستئناف (بلا سقف، ذاكرة صفحة واحدة).
          recordsPulled += await _runStreamingFullPull(task, pullPlan);
        } else {
          // المسار الكلاسيكي — Full أحادي الطلب أو Delta.
          final docs = await task.fetch(pullPlan);
          recordsPulled += await task.apply(docs);
          await commit(
            task.name,
            maxUpdatedAtSec: maxUpdatedAtOf(docs),
            sinceTs: pullPlan.sinceTs,
          );
        }
        success = true;
      } catch (error, stackTrace) {
        if (task.critical) failed.add(task.name);
        if (onTaskError != null) {
          try {
            await onTaskError(task.name, error, stackTrace);
          } catch (_) {
            // مراقب الأخطاء لا يُفشل المهمة.
          }
        }
      } finally {
        stopwatch.stop();
        onTaskDone?.call(task.name, stopwatch.elapsedMilliseconds, success);
      }
    }

    return PullRunResult(
      recordsPulled: recordsPulled,
      failedCollections: failed,
    );
  }

  /// ✅ Resumable Full Sync (2026-09-21): سحب كامل تدفقي بلا سقف.
  ///
  /// الحلقة: صفحة (100) → apply → bump max($updatedAt) → cursor = آخر $id
  /// → الصفحة التالية. عند نفاد المستندات أو صفحة ناقصة:
  /// [SyncCheckpointStore.completeFullSync] يثبّت مؤشر Delta النهائي.
  ///
  /// **الانقطاع**: أي استثناء (شبكة/قتل/مهلة) يخرج من الحلقة والمؤشر
  /// محفوظ عند آخر صفحة **ناجحة** — الدورة التالية تستأنف من
  /// `cursorAfter(cursor)` فلا صفحة مفقودة ولا إعادة عمل كبيرة.
  ///
  /// **المجموعة الفارغة** (أول صفحة فارغة ولم يُسحب شيء): نمسح حالة التقدم
  /// فقط ونُبقي المجموعة في وضع Full — نفس دلالات [commit] الكلاسيكية
  /// (استعلام فارغ رخيص في كل دورة حتى تظهر أول مستندات).
  Future<int> _runStreamingFullPull(
    CollectionPullTask task,
    CollectionPullPlan plan,
  ) async {
    var cursor = await checkpoints.getFullSyncCursor(task.name);
    var totalApplied = 0;
    var pages = 0;
    final weakDevice = WeakDeviceOptimizer.instance.isWeakDevice;

    while (true) {
      pages++;
      if (pages > _maxFullSyncPages) {
        throw StateError(
          'full sync page limit exceeded for ${task.name} '
          '($_maxFullSyncPages pages) — cursor not advancing?',
        );
      }

      final pageQueries = SyncPullService.buildFullSyncPageQueries(
        baseQueries: plan.queries,
        cursor: cursor,
        pageSize: fullSyncPageSize,
      );
      final docs = await task.fetchPage!(pageQueries);

      // نفاد المستندات.
      if (docs.isEmpty) {
        final maxUpdated = await checkpoints.getFullSyncMaxUpdated(task.name);
        if (maxUpdated > 0) {
          // سحبنا صفحات سابقة (صفحة كاملة أخيرة بالضبط) → اكتمل فعلياً.
          await checkpoints.completeFullSync(
            task.name,
            maxUpdatedSec: maxUpdated,
          );
        } else {
          // مجموعة فارغة من البداية → وضع Full رخيص (كما في commit).
          await checkpoints.clearFullSyncProgress(task.name);
        }
        break;
      }

      final applied = await task.apply(docs);
      totalApplied += applied;

      // تتبّع أقصى $updatedAt (سلطة الخادم للمؤشر النهائي) قبل تقدّم المؤشر.
      final pageMax = maxUpdatedAtOf(docs);
      if (pageMax != null) {
        await checkpoints.bumpFullSyncMaxUpdated(task.name, pageMax);
      }

      // تقدّم المؤشر بعد نجاح التطبيق فقط (crash-safe).
      cursor = docs.last.$id;
      await checkpoints.setFullSyncCursor(task.name, cursor);

      // صفحة ناقصة = الأخيرة → اكتمال.
      if (docs.length < fullSyncPageSize) {
        final maxUpdated = await checkpoints.getFullSyncMaxUpdated(task.name);
        await checkpoints.completeFullSync(
          task.name,
          maxUpdatedSec: maxUpdated,
        );
        break;
      }

      // ✅ تنفّس للأجهزة الضعيفة: مهلة قصيرة بين الصفحات تسمح لحلقة
      // الأحداث بمعالجة أحداث الواجهة (فريمات/لمسات) أثناء سحب طويل،
      // وتقلل ضغط الذاكرة/الشبكة المتتالي على الجهاز.
      await Future<void>.delayed(
        weakDevice
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 0),
      );
    }

    return totalApplied;
  }

  /// أقصى $updatedAt (ثوانٍ epoch) بين مستندات مجموعة — سلطة الخادم.
  static int? maxUpdatedAtOf(List<models.Document> docs) {
    int? maxSec;
    for (final doc in docs) {
      final sec = updatedAtSecOf(doc);
      if (sec != null && (maxSec == null || sec > maxSec)) maxSec = sec;
    }
    return maxSec;
  }

  /// استخراج $updatedAt من مستند Appwrite كثوانٍ epoch.
  static int? updatedAtSecOf(models.Document doc) {
    try {
      final iso = doc.$updatedAt;
      if (iso.isEmpty) return null;
      final dt = DateTime.parse(iso);
      return (dt.millisecondsSinceEpoch / 1000).round();
    } catch (_) {
      return null;
    }
  }
}
