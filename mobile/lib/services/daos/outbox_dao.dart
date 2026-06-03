import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../adapters/adapter_registry.dart';
import '../local_db.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db) : adapters = AdapterRegistry(db);

  final AdapterRegistry adapters;

  /// مشاهدة عدد عناصر outbox المعلقة/الفاشلة
  /// [sources] — إذا حُدد، يقتصر العد على هذه المصادر فقط
  Stream<int> watchCount({List<String>? sources}) {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    return query
        .map((row) => row.read(countExp) ?? 0)
        .watchSingle();
  }

  /// عدد عناصر outbox المعلقة/الفاشلة
  /// [sources] — إذا حُدد، يقتصر العد على هذه المصادر فقط
  Future<int> count({List<String>? sources}) async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<void> resetErrors() async {
    await (update(outbox)
          ..where(
              (t) => t.processingStatus.equals('failed'),))
        .write(const OutboxCompanion(
      processingStatus: Value('pending'),
      attempts: Value(0),
      lastError: Value(null),
      processingStartedAt: Value(null),
      processingWorker: Value(null),
    ),);
  }

  /// إعادة تعيين العناصر القديمة بدلاً من حذفها — لا نفقد بيانات outbox أبداً
  /// العناصر التي فشلت عدة مرات تُعاد إلى حالة pending لمحاولة رفعها لاحقاً
  Future<int> clearStale({int attemptsThreshold = 3}) async {
    final rows = await (update(outbox)
          ..where((t) =>
              t.attempts.isBiggerOrEqualValue(attemptsThreshold) &
              t.processingStatus.equals('failed'),))
        .write(const OutboxCompanion(
      processingStatus: Value('pending'),
      attempts: Value(0),
      lastError: Value(null),
      processingStartedAt: Value(null),
      processingWorker: Value(null),
    ),);
    // تحديث إحصائيات الاستعلام بعد إعادة تعيين جماعي
    if (rows > 20) {
      await customSelect('ANALYZE outbox').get();
    }
    return rows;
  }

  /// إدراج أو تحديث عنصر outbox
  /// [source] — مصدر العنصر: 'local' = تغيير محلي (افتراضي)، 'restore' = استعادة من نسخة احتياطية
  /// هذا يفصل بين التغييرات المحلية والعمليات البعيدة
  /// ✅ إصلاح حرج: تغليف العملية بالكامل في transaction لمنع إدراج سجلين مكررين
  /// عند استدعاء merge() بالتوازي (مثلاً: debounce timer + manual sync)
  Future<int> merge({
    required String entity,
    required String op,
    required String localUuid,
    int? serverId,
    required Map<String, dynamic> payload,
    required int clientTs,
    String source = 'local',
  }) async {
    final payloadJson = jsonEncode(payload);
    final idempKey = '$entity:$op:$localUuid:$clientTs';

    return transaction(() async {
      final existing = await (select(outbox)
            ..where((t) =>
                t.entity.equals(entity) &
                t.localUuid.equals(localUuid) &
                t.processingStatus.equals('pending'),)
            ..limit(1))
          .getSingleOrNull();

      if (existing != null) {
        await (update(outbox)..where((t) => t.id.equals(existing.id))).write(
          OutboxCompanion(
            op: Value(op),
            payload: Value(payloadJson),
            clientTs: Value(clientTs),
            idempotencyKey: Value(idempKey),
            serverId: Value(serverId),
            source: Value(source),
          ),
        );
        return existing.id;
      }

      return into(outbox).insert(OutboxCompanion.insert(
        entity: entity,
        op: op,
        localUuid: localUuid,
        serverId: Value(serverId),
        payload: payloadJson,
        clientTs: clientTs,
        idempotencyKey: Value(idempKey),
        source: Value(source),
      ),);
    });
  }

  /// جلب دفعة من عناصر outbox للمعالجة
  /// [sources] — إذا حُدد، يقتصر الجلب على هذه المصادر فقط (مثلاً ['local'] فقط)
  /// [workerId] — معرف العامل الذي يعالج الدفعة
  Future<List<OutboxData>> takeBatch(int limit, {String? workerId, List<String>? sources}) async {
    final worker = workerId ?? _uuid.v4();
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // بناء شرط source إذا حُدد
    final sourceCondition = (sources != null && sources.isNotEmpty)
        ? ' AND source IN (${sources.map((s) => "'$s'").join(',')})'
        : '';

    // ✅ تحديث ذري: حدّت الحالة مباشرة في استعلام واحد لمنع المعالجة المكررة
    // بدلاً من SELECT ثم UPDATE المنفصلين اللذين يسمحان بسباق البيانات
    final claimed = await customSelect(
      'UPDATE outbox SET processing_status = ?, processing_started_at = ?, processing_worker = ? '
      'WHERE id IN ('
      '  SELECT id FROM outbox WHERE processing_status = ?$sourceCondition ORDER BY client_ts ASC LIMIT ? '
      ') RETURNING *',
      variables: [
        const Variable<String>('processing'),
        Variable<int>(nowEpoch),
        Variable<String>(worker),
        const Variable<String>('pending'),
        Variable<int>(limit),
      ],
      readsFrom: {outbox},
    ).map((row) => OutboxData(
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
    ),).get();

    return claimed;
  }

  Future<void> removeById(int id) async {
    await (delete(outbox)..where((t) => t.id.equals(id))).go();
  }

  Future<void> removeByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await (delete(outbox)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> setError(int id, String message, int attempts) async {
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        lastError: Value(message),
        attempts: Value(attempts),
        processingStatus: const Value('failed'),
        processingStartedAt: const Value(null),
        processingWorker: const Value(null),
      ),
    );
  }

  Future<void> markCompleted(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      const OutboxCompanion(
        processingStatus: Value('completed'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
  }

  Future<void> markFailed(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      const OutboxCompanion(
        processingStatus: Value('failed'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
  }

  Future<void> retryFailed() async {
    await (update(outbox)
          ..where((t) => t.processingStatus.equals('failed')))
        .write(const OutboxCompanion(
      processingStatus: Value('pending'),
      processingStartedAt: Value(null),
      processingWorker: Value(null),
    ),);
  }

  Future<int> cleanupStuckEntries({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final cutoff =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timeout.inSeconds;
    final stuck = await (select(outbox)
          ..where((t) =>
              t.processingStatus.equals('processing') &
              t.processingStartedAt.isSmallerOrEqualValue(cutoff),))
        .get();

    if (stuck.isEmpty) {
      return 0;
    }

    final ids = stuck.map((e) => e.id).toList();
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      const OutboxCompanion(
        processingStatus: Value('pending'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
    return ids.length;
  }

  Future<int> cleanupCompleted({
    Duration olderThan = const Duration(days: 7),
  }) async {
    final cutoff =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - olderThan.inSeconds;
    final rows = await (delete(outbox)
          ..where((t) =>
              t.processingStatus.equals('completed') &
              t.clientTs.isSmallerOrEqualValue(cutoff),))
        .go();
    // تحديث إحصائيات الاستعلام بعد الحذف الجماعي
    if (rows > 50) {
      await customSelect('ANALYZE outbox').get();
    }
    return rows;
  }

  /// حذف عناصر outbox المطابقة لبيانات تم سحبها من السحابة.
  /// يُستدعى بعد pull ناجح: إذا كان السحابة تحتوي على نفس entity + localUuid
  /// فلا حاجة لإرسال هذا العنصر مرة أخرى.
  ///
  /// [sources] — إذا حُدد، يحذف فقط العناصر ذات المصدر المحدد.
  /// افتراضياً يحذف فقط عناصر 'local' (تغييرات محلية) لأن عناصر 'restore'
  /// لا علاقة لها بعملية السحب من السحابة.
  ///
  /// ✅ إصلاح: دمج شروط entity و localUuid في استعلام واحد بدلاً من إنشاء
  /// استعلام جديد يفقد شرط localUuid (الخطأ السابق كان يُنشئ delete(outbox)
  /// جديد عند وجود entity، مما يُلغي شرط localUuid.isIn(chunk)).
  Future<int> removePulledEntities(List<String> uuids, {String? entity, List<String>? sources}) async {
    if (uuids.isEmpty) {
      return 0;
    }
    // افتراضياً نحذف فقط عناصر source='local' — هذا هو السلوك الصحيح
    // لأن السحب من السحابة يعني أن البيانات موجودة بالفعل على السيرفر
    // وعناصر 'restore' تم إنشاؤها بغرض الرفع ولا يجب حذفها بهذا المنطق
    final effectiveSources = sources ?? const ['local'];
    const batchSize = 500;
    int totalRemoved = 0;
    for (var i = 0; i < uuids.length; i += batchSize) {
      final end = i + batchSize > uuids.length ? uuids.length : i + batchSize;
      final chunk = uuids.sublist(i, end);
      if (entity != null) {
        totalRemoved += await (delete(outbox)
              ..where((t) => t.localUuid.isIn(chunk) & t.entity.equals(entity) & t.source.isIn(effectiveSources)))
            .go();
      } else {
        totalRemoved += await (delete(outbox)
              ..where((t) => t.localUuid.isIn(chunk) & t.source.isIn(effectiveSources)))
            .go();
      }
    }
    return totalRemoved;
  }

  /// جلب التعارضات من Outbox (السجلات التي فشلت بسبب تعارض)
  Future<List<ConflictRecord>> getConflicts() async {
    final failed = await (select(outbox)
          ..where((t) =>
              t.processingStatus.equals('failed') &
              t.lastError.isNotNull(),)
          ..orderBy([(t) => OrderingTerm.desc(t.clientTs)]))
        .get();

    return failed.map((entry) {
      final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
      return ConflictRecord(
        id: entry.id,
        uuid: entry.localUuid,
        targetTable: entry.entity,
        localPayload: payload,
        remotePayload: payload, // TODO: Fetch actual remote data
        lastError: entry.lastError ?? 'Unknown conflict',
        timestamp: DateTime.fromMillisecondsSinceEpoch(entry.clientTs * 1000),
      );
    }).toList();
  }

  /// حل تعارض محدد — يُعيد العنصر إلى pending لرفعه فعلياً لاحقاً
  Future<void> resolveConflict(
    int id,
    Map<String, dynamic> resolvedData, {
    required String resolution,
  }) async {
    // تحديث السجل ليعكس الحل وإعادته إلى pending ليُرفع فعلياً
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        processingStatus: const Value('pending'),
        lastError: const Value(null),
        attempts: const Value(0),
        payload: Value(jsonEncode(resolvedData)),
        processingStartedAt: const Value(null),
        processingWorker: const Value(null),
      ),
    );
  }

  /// ✅ إصلاح: حذف سجلات Outbox التي فشلت مرات عديدة مع خطأ "unknown entity"
  /// عند إزالة أو إعادة تسمية نوع كيان في الكود، سجلات Outbox الخاصة به
  /// لن تُعالج أبداً وستبطئ المزامنة في كل دورة.
  /// [maxAttempts] — الحد الأقصى لمحاولات الفشل قبل الحذف
  /// [olderThan] — لا يحذف سجلات أحدث من هذه المدة (حماية من حذف سجلات جديدة)
  Future<int> cleanupOrphanedEntries({
    int maxAttempts = 10,
    Duration olderThan = const Duration(days: 3),
  }) async {
    final cutoff =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - olderThan.inSeconds;
    final rows = await (delete(outbox)
          ..where((t) =>
              t.processingStatus.equals('failed') &
              t.attempts.isBiggerOrEqualValue(maxAttempts) &
              t.clientTs.isSmallerOrEqualValue(cutoff),))
        .go();
    return rows;
  }
}

/// سجل يمثل تعارض في البيانات
class ConflictRecord {

  ConflictRecord({
    required this.id,
    required this.uuid,
    required this.targetTable,
    required this.localPayload,
    required this.remotePayload,
    required this.lastError,
    required this.timestamp,
  });
  final int id;
  final String uuid;
  final String targetTable;
  final Map<String, dynamic> localPayload;
  final Map<String, dynamic> remotePayload;
  final String lastError;
  final DateTime timestamp;
}
