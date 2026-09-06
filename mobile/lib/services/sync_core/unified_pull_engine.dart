import 'package:appwrite/models.dart' as models;

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
    this.critical = true,
  });

  /// اسم المجموعة (مفتاح الـ checkpoint في sync_checkpoints).
  final String name;

  /// جلب المستندات من Appwrite وفق خطة المجموعة (Full أو Delta).
  final Future<List<models.Document>> Function(CollectionPullPlan plan) fetch;

  /// تطبيق المستندات محلياً — يعيد عدد السجلات المطبَّقة.
  final Future<int> Function(List<models.Document> docs) apply;

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
class UnifiedPullEngine {
  UnifiedPullEngine({required this.checkpoints, required this.pullService});

  final SyncCheckpointStore checkpoints;
  final SyncPullService pullService;

  /// يبني خطة السحب لمجموعة واحدة:
  ///   - checkpoint غير مكتمل أو صفر → Full pull.
  ///     ✅ إصلاح (2026-09-07): الآباء المرجعية (employees) تُسحب في وضع
  ///     Full **شاملة tombstones** — فلتر `[deletedAt isNull OR =0]` كان
  ///     يستبعد الموظفين المحذوفين فتبقى سحوبات/دورات رواتبهم يتيمة على
  ///     الأجهزة الجديدة (سحابة الإنتاج: الموظفان serverId=11/12 مرتبط
  ///     بهما 128 سحوبة راتب). الآلية `entityNeedsTombstoneParents` كانت
  ///     معرّفة ومختبرة وغير مربوطة بمسار السحب أبداً (كود ميت) — هذا
  ///     الاستدعاء يوصّلها فعلياً. راجع SyncPullService.entityNeedsTombstoneParents.
  ///   - غير ذلك → Delta فقط منذ مؤشر المجموعة الخاص
  ///     (استعلامات Delta لا تفلتر tombstones أصلاً — الحذف اللاحق يصل طبيعياً).
  Future<CollectionPullPlan> plan(String collectionName) async {
    final fullDone = await checkpoints.isFullSyncComplete(collectionName);
    final sinceTs = await checkpoints.getLastPullTs(collectionName);
    if (!fullDone || sinceTs <= 0) {
      return CollectionPullPlan(
        collectionName: collectionName,
        isFullSync: true,
        queries: SyncPullService.entityNeedsTombstoneParents(collectionName)
            ? SyncPullService.buildFullSyncQueries(includeTombstones: true)
            : SyncPullService.buildFullSyncQueries(),
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
        final docs = await task.fetch(pullPlan);
        recordsPulled += await task.apply(docs);
        await commit(
          task.name,
          maxUpdatedAtSec: maxUpdatedAtOf(docs),
          sinceTs: pullPlan.sinceTs,
        );
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
