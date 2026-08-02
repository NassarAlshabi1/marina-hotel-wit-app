import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../adapters/adapter_registry.dart';
import '../appwrite_logger.dart';
import '../appwrite_sync_manager.dart';
import '../crashlytics_service.dart';
import '../local_db.dart';
import '../secondary_appwrite_config.dart';
import '../vector_clock_service.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db, [AdapterRegistry? a]) : adapters = a ?? AdapterRegistry.instance;

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
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
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

  /// ✅ P2-5 fix: عدد السجلات التي سيأخذها الرفع فعلياً (يطابق نطاق takeBatch).
  ///
  /// يطابق تماماً فلتر `takeBatch()` المستخدم في `pushLocalChanges()`:
  ///   - `processing_status = 'pending'` (فقط، لا يشمل 'failed' أو 'processing')
  ///   - `delivered_to_primary = 0` (لم تُسلَّم للرئيسي بعد)
  ///   - `source IN (sources)` عند تمريرها
  ///
  /// الفرق عن `count()`:
  ///   - `count()` يحسب `pending + failed` بغض النظر عن `delivered_to_primary`
  ///   - هذا يسبّب مبالغة في العدد المعروض لل مستخدم
  ///
  /// الاستخدام: شارة "تغييرات معلّقة" على زر الرفع في Dashboard.
  Future<int> countPendingPushable({List<String>? sources}) async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.equals('pending'))
      ..where(outbox.deliveredToPrimary.equals(false));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// ✅ عدد السجلات المحلية غير المُسلّمة للرئيسي بغضّ النظر عن حالتها الحالية
  /// (`pending` أو `processing` عالقة أو `failed`).
  ///
  /// الفرق الحرج عن `countPendingPushable`:
  ///   - `countPendingPushable` يحسب فقط `processing_status = 'pending'`.
  ///   - لكن عند الضغط على "رفع التغييرات" يحجز `takeBatch` السجلات فيحوّلها
  ///     إلى `processing`. إذا انقطع الرفع (إنترنت بطيء / إغلاق التطبيق قبل
  ///     الانتهاء) تبقى السجلات عالقة في `processing` → تختفي من عدّاد
  ///     `countPendingPushable` → يظهر 0 → يظنّ المستخدم أن الرفع نجح بينما
  ///     البيانات لم تصل الخادم فعلياً.
  ///
  /// هذا العدّاد يشمل كل ما لم يُسلَّم للرئيسي (`delivered_to_primary = 0`)
  /// وليس في حالة نهائية (`completed`/`dead`)، فتبقى التغييرات العالقة مرئية
  /// للمستخدم ويبقى زر الرفع مُفعّلاً لإعادة المحاولة.
  Future<int> countUndeliveredToPrimary({List<String>? sources}) async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'processing', 'failed']))
      ..where(outbox.deliveredToPrimary.equals(false));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// ✅ يُعيد السجلات العالقة في `processing` و/أو الفاشلة `failed` إلى
  /// `pending` قبل بدء رفع يدوي، بحيث يلتقطها `takeBatch` فعلياً.
  ///
  /// يُستدعى في بداية طور الرفع (`_pushAllEntities`). بما أن الرفع مُسلسَل
  /// عبر قفل المزامنة، لا توجد دفعة أخرى قيد المعالجة في نفس اللحظة، لذا
  /// إعادة كل السجلات `processing` الأقدم من [stuckAfter] آمنة تماماً وتضمن
  /// عدم ضياع أي تغيير عالق من جلسة رفع سابقة انقطعت.
  ///
  /// [maxFailedAttempts] — لا نُعيد محاولة السجلات الفاشلة التي تجاوزت هذا الحدّ
  /// حفاظاً على منطق التراجع الأسّي (backoff) للسجلات ذات الفشل المزمن؛ تلك
  /// تُترك للمؤقّت الدوري `retryFailedWithBackoff`.
  ///
  /// يُرجع عدد السجلات التي أُعيدت إلى `pending`.
  Future<int> reclaimForPush({Duration stuckAfter = const Duration(seconds: 30), int maxFailedAttempts = 5}) async {
    final cutoff = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - stuckAfter.inSeconds;

    // 1) استعادة السجلات العالقة في 'processing' الأقدم من العتبة —
    //    هذه هي جوهر الإصلاح: سجلات حُجزت لرفع انقطع ولم يكتمل.
    final reclaimedProcessing =
        await (update(outbox)..where(
              (t) => t.processingStatus.equals('processing') & t.processingStartedAt.isSmallerOrEqualValue(cutoff),
            ))
            .write(
              const OutboxCompanion(
                processingStatus: Value('pending'),
                processingStartedAt: Value(null),
                processingWorker: Value(null),
              ),
            );

    // 2) إعادة السجلات الفاشلة قليلة المحاولات إلى 'pending' (المستخدم يطلب
    //    إعادة المحاولة صراحةً بالضغط على الزر). لا نلمس 'dead' (فشل دائم)
    //    ولا السجلات كثيرة المحاولات (تُترك لمنطق backoff الدوري).
    final reclaimedFailed =
        await (update(outbox)
              ..where((t) => t.processingStatus.equals('failed') & t.attempts.isSmallerOrEqualValue(maxFailedAttempts)))
            .write(
              const OutboxCompanion(
                processingStatus: Value('pending'),
                processingStartedAt: Value(null),
                processingWorker: Value(null),
              ),
            );

    return reclaimedProcessing + reclaimedFailed;
  }

  Future<void> resetErrors() async {
    await (update(outbox)..where((t) => t.processingStatus.equals('failed'))).write(
      const OutboxCompanion(
        processingStatus: Value('pending'),
        attempts: Value(0),
        lastError: Value(null),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
  }

  /// إعادة تعيين العناصر القديمة بدلاً من حذفها — لا نفقد بيانات outbox أبداً
  /// العناصر التي فشلت عدة مرات تُعاد إلى حالة pending لمحاولة رفعها لاحقاً
  Future<int> clearStale({int attemptsThreshold = 3}) async {
    final rows =
        await (update(outbox)
              ..where((t) => t.attempts.isBiggerOrEqualValue(attemptsThreshold) & t.processingStatus.equals('failed')))
            .write(
              const OutboxCompanion(
                processingStatus: Value('pending'),
                attempts: Value(0),
                lastError: Value(null),
                processingStartedAt: Value(null),
                processingWorker: Value(null),
              ),
            );
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
  /// ✅ إصلاح إضافي: البحث عن السجلات الموجودة في حالة 'pending' أو 'processing'
  /// إذا كان السجل في حالة 'processing'، نحدثه بدلاً من إنشاء سجل جديد
  /// لأن السجل 'processing' سيعود لاحقاً كـ 'completed' أو 'failed'
  Future<int> merge({
    required String entity,
    required String op,
    required String localUuid,
    required Map<String, dynamic> payload,
    required int clientTs,
    int? serverId,
    String source = 'local',
  }) async {
    final payloadJson = jsonEncode(payload);
    final idempKey = '$entity:$op:$localUuid:$clientTs';

    // ✅ إصلاح P0-1 (2026-06-28): احسب delivered_to_secondary ديناميكياً
    // القيمة الافتراضية في schema هي true (لمنع الحجب عند تعطيل Secondary).
    // لكن عندما Secondary + Push مُفعّلان، يجب أن تكون false ليتمكن Secondary
    // من معالجة السجل قبل حذفه. بدون هذا، Primary يحذف السجل (كلاهما true)
    // قبل أن يراه Secondary → فقدان بيانات.
    bool deliveredToSecondary = true;
    try {
      deliveredToSecondary = !SecondaryAppwriteConfig.isEnabled || !SecondaryAppwriteConfig.isPushEnabled;
    } catch (_) {
      // إذا فشل الوصول للإعدادات (SharedPreferences غير مهيأ)، نستخدم true (آمن)
    }

    return transaction(() async {
      // ✅ P0-VC fix: زيادة Vector Clock عند كل كتابة محلية (لا عند الدفع فقط)
      // هذا يضمن كشف كل التعديلات المتزامنة حتى لو حدثت عدة تعديلات بين مزامنتين
      if (source == 'local' && op != 'delete') {
        await _bumpVectorClockForLocalWrite(entity, localUuid);
      }

      // ✅ البحث عن أي سجل موجود لنفس الكيان والـ UUID بغض النظر عن حالته
      // ('pending' أو 'processing') — هذا يمنع إنشاء سجل مكرر
      final existing =
          await (select(outbox)
                ..where(
                  (t) =>
                      t.entity.equals(entity) &
                      t.localUuid.equals(localUuid) &
                      t.processingStatus.isIn(const ['pending', 'processing']),
                )
                ..limit(1))
              .getSingleOrNull();

      if (existing != null) {
        await (update(outbox)..where((t) => t.id.equals(existing.id))).write(
          OutboxCompanion(
            // ✅ P0-3 fix: لا نستبدل 'delete' بـ 'update'
            // delete له أولوية أعلى — إذا كان السجل موجود كـ delete، نتركه
            op: existing.op == 'delete' ? const Value.absent() : Value(op),
            payload: Value(payloadJson),
            clientTs: Value(clientTs),
            idempotencyKey: Value(idempKey),
            serverId: Value(serverId),
            source: Value(source),
            // ✅ إصلاح P0-1: تحديث delivered_to_secondary للسجل الموجود أيضاً
            deliveredToSecondary: Value(deliveredToSecondary),
            // ✅ إذا كان السجل في حالة 'processing'، نعيده لـ 'pending'
            // لأن البيانات تغيرت والسجل القديم لم يُعالج بعد
            processingStatus: existing.processingStatus == 'processing' ? const Value('pending') : const Value.absent(),
            processingStartedAt: existing.processingStatus == 'processing' ? const Value(null) : const Value.absent(),
            processingWorker: existing.processingStatus == 'processing' ? const Value(null) : const Value.absent(),
          ),
        );
        return existing.id;
      }

      return into(outbox).insert(
        OutboxCompanion.insert(
          entity: entity,
          op: op,
          localUuid: localUuid,
          serverId: Value(serverId),
          payload: payloadJson,
          clientTs: clientTs,
          idempotencyKey: Value(idempKey),
          source: Value(source),
          // ✅ إصلاح P0-1: ضبط delivered_to_secondary ديناميكياً
          deliveredToSecondary: Value(deliveredToSecondary),
        ),
      );
    });
  }

  /// جلب دفعة من عناصر outbox للمعالجة
  /// [sources] — إذا حُدد، يقتصر الجلب على هذه المصادر فقط (مثلاً ['local'] فقط)
  /// [workerId] — معرف العامل الذي يعالج الدفعة
  ///
  /// ✅ إصلاح أمني (2026-06-28): استخدام parameterized query بدلاً من
  /// string concatenation لمنع SQL injection عبر معامل `sources`.
  /// حتى حالياً كل الاستدعاءات تمرر `const ['local']` (compile-time constant)،
  /// هذا النمط يشكّل ثغرة محتملة إذا أُضيفت ميزة مستقبلية تمرّر مدخلات ديناميكية.
  /// Parameterized queries تفصل بنية SQL عن البيانات، مما يجعل الحقن مستحيلاً.
  Future<List<OutboxData>> takeBatch(int limit, {String? workerId, List<String>? sources}) async {
    final worker = workerId ?? _uuid.v4();
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // ✅ Validation على المصادر (طبقة دفاع أولى)
    // حتى مع parameterized queries، نرفض القيم غير الصالحة مبكراً
    final hasSources = sources != null && sources.isNotEmpty;
    final safeSources = hasSources ? sources : const <String>[];
    if (hasSources) {
      for (final s in safeSources) {
        if (s.isEmpty || s.length > 50) {
          throw ArgumentError('Invalid source length: ${s.length}');
        }
        // السماح فقط بأحرف أبجدية رقمية + شرطة سفلية + شرطة طويلة
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s)) {
          throw ArgumentError('Invalid source characters: $s');
        }
      }
    }

    // ✅ بناء placeholders ديناميكياً (?, ?, ...) بدلاً من تمرير القيم مباشرة في SQL
    final sourcePlaceholders = hasSources ? safeSources.map((_) => '?').join(',') : '';
    final sourceCondition = hasSources ? ' AND source IN ($sourcePlaceholders)' : '';

    // ✅ Dual-delivery: نأخذ فقط السجلات غير المُسلّمة للرئيسي.
    // السجلات المُسلّمة للرئيسي فقط (وليس للثانوي) تُترك لـ SecondarySyncManager.
    // السجلات المُسلّمة لكلا الوجهتين تُحذف تلقائياً بواسطة markDelivered*.
    const primaryCondition = ' AND delivered_to_primary = 0';

    // ✅ تحديث ذري: حدّت الحالة مباشرة في استعلام واحد لمنع المعالجة المكررة
    // بدلاً من SELECT ثم UPDATE المنفصلين اللذين يسمحان بسباق البيانات
    const priorityCase =
        "CASE WHEN entity = 'rooms' THEN 1 "
        "WHEN entity = 'employees' THEN 2 "
        "WHEN entity = 'bookings' THEN 3 "
        "WHEN entity = 'payments' THEN 4 "
        "WHEN entity = 'expenses' THEN 5 "
        "WHEN entity = 'debts' THEN 6 "
        "WHEN entity = 'booking_notes' THEN 7 "
        "WHEN entity = 'shift_notes' THEN 8 "
        "WHEN entity = 'cash_transactions' THEN 9 "
        'ELSE 10 END';

    // ✅ بناء قائمة المتغيرات بالترتيب الصحيح: status→ts→worker→pending→[sources]→limit
    final variables = <Variable>[
      const Variable<String>('processing'),
      Variable<int>(nowEpoch),
      Variable<String>(worker),
      const Variable<String>('pending'),
      if (hasSources) ...safeSources.map(Variable<String>.new),
      Variable<int>(limit),
    ];

    final claimed =
        await customSelect(
              'UPDATE outbox SET processing_status = ?, processing_started_at = ?, processing_worker = ? '
              'WHERE id IN ('
              '  SELECT id FROM outbox WHERE processing_status = ?$primaryCondition$sourceCondition ORDER BY $priorityCase ASC, client_ts ASC LIMIT ? '
              ') RETURNING *',
              variables: variables,
              readsFrom: {outbox},
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
              ),
            )
            .get();

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
    // الحصول على معلومات السجل قبل التحديث
    try {
      final record = await (select(outbox)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (record != null) {
        // تسجيل الخطأ في AppwriteLogger
        AppwriteLogger().log('❌ فشل في Outbox', level: LogLevel.error, tag: 'OUTBOX_ERROR', error: message);

        // تفاصيل أكثر
        AppwriteLogger().log('   الجدول: ${record.entity}', level: LogLevel.error, tag: 'OUTBOX_ERROR');

        AppwriteLogger().log('   العملية: ${record.op}', level: LogLevel.error, tag: 'OUTBOX_ERROR');

        AppwriteLogger().log('   عدد المحاولات: $attempts', level: LogLevel.error, tag: 'OUTBOX_ERROR');
      }
    } catch (e) {
      // تجاهل أخطاء القراءة
    }

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

  /// ✅ P0-2 (Secondary Audit): يضع السجل في الحالة النهائية `dead`
  /// بعد تجاوز حد المحاولات. السجلات الـ dead لا تُلتقط للمعالجة لاحقاً
  /// (لا في Primary ولا في Secondary)، وتظهر في شاشة سجل المزامنة لمراجعة
  /// يدوية بدل إعادة محاولة صامتة لا نهائية.
  ///
  /// الفرق بين `dead` و `failed`:
  /// - `failed`: فشل مؤقت، سيُعاد التقاطها في الجلسة التالية.
  /// - `dead`: فشل دائم (خطأ 400/401/403 أو تجاوز maxAttempts)، لا تُعاد
  ///   محاولتها تلقائياً بل تنتظر تدخّلاً يدوياً.
  Future<void> setDead(int id, String message, int attempts) async {
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        lastError: Value(message),
        attempts: Value(attempts),
        processingStatus: const Value('dead'),
        processingStartedAt: const Value(null),
        processingWorker: const Value(null),
      ),
    );
    AppwriteLogger().log(
      '☠️ [Outbox] سجل #$id وُضع في الحالة النهائية dead بعد $attempts محاولة',
      level: LogLevel.error,
      tag: 'OUTBOX_DEAD',
      error: message,
    );
  }

  /// ✅ P0-2: عدد السجلات الـ dead (لعرضها في شاشة المراجعة اليدوية).
  Future<int> countDead() async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.equals('dead'));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// ✅ P0-2: قائمة السجلات الـ dead لمراجعة يدوية.
  Future<List<OutboxData>> listDead({int limit = 100}) async {
    return (select(outbox)
          ..where((t) => t.processingStatus.equals('dead'))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .get();
  }

  /// ✅ P0-2: إعادة تفعيل سجل dead (يضعه في حالة pending لإعادة المحاولة).
  /// يُستخدم من شاشة المراجعة اليدوية بعد إصلاح سبب الفشل.
  Future<void> reviveFromDead(int id) async {
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      const OutboxCompanion(
        processingStatus: Value('pending'),
        attempts: Value(0),
        lastError: Value(null),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
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

  // ════════════════════════════════════════════════════════════════════
  // ✅ تتبع التسليم لكل وجهة (Dual-Delivery Tracking)
  // ════════════════════════════════════════════════════════════════════
  //
  // بدلاً من حذف السجل بعد نجاح الرفع للرئيسي فقط، نستخدم علامتين
  // منفصلتين:
  //
  //   - delivered_to_primary: هل تم تسليم السجل لـ Appwrite الرئيسي؟
  //   - delivered_to_secondary: هل تم تسليم السجل لـ Appwrite الثانوي؟
  //
  // السجل يُحذف فقط بعد نجاح كلا الوجهتين. هذا يمنع فقدان البيانات
  // عند فشل إحدى الوجهتين، ويمنع تكرار العمليات بسبب سباق البيانات.

  /// يضع علامة "تم التسليم للرئيسي" على السجل.
  /// إذا كان السجل قد سُلّم للثانوي أيضاً، يتم حذفه تلقائياً.
  Future<void> markDeliveredToPrimary(int id) async {
    await _markDelivered(id, toPrimary: true);
  }

  /// يضع علامة "تم التسليم للثانوي" على السجل.
  /// إذا كان السجل قد سُلّم للرئيسي أيضاً، يتم حذفه تلقائياً.
  Future<void> markDeliveredToSecondary(int id) async {
    await _markDelivered(id, toPrimary: false);
  }

  /// المنطق الموحد لـ markDelivered:
  /// 1) نضع علامة التسليم المناسبة
  /// 2) نُعيد الحالة إلى pending (ليتمكن الـ sync الآخر من معالجتها)
  /// 3) إذا كانت كلتا العلامتين true، نحذف السجل
  Future<void> _markDelivered(int id, {required bool toPrimary}) async {
    await transaction(() async {
      // قراءة الحالة الحالية
      final record = await (select(outbox)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (record == null) return; // السجل محذوف بالفعل

      // تحديث العلامة المناسبة
      final companion = toPrimary
          ? const OutboxCompanion(
              deliveredToPrimary: Value(true),
              processingStatus: Value('pending'),
              processingStartedAt: Value(null),
              processingWorker: Value(null),
            )
          : const OutboxCompanion(
              deliveredToSecondary: Value(true),
              processingStatus: Value('pending'),
              processingStartedAt: Value(null),
              processingWorker: Value(null),
            );

      await (update(outbox)..where((t) => t.id.equals(id))).write(companion);

      // إعادة القراءة بعد التحديث للحصول على القيم الجديدة
      final updated = await (select(outbox)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (updated == null) return;

      // ✅ حذف السجل فقط إذا تم تسليمه لكلا الوجهتين
      if (updated.deliveredToPrimary && updated.deliveredToSecondary) {
        await (delete(outbox)..where((t) => t.id.equals(id))).go();
      }
    });
  }

  /// عدد السجلات غير المُسلّمة للرئيسي
  Future<int> countPendingForPrimary() async {
    final result = await customSelect(
      "SELECT COUNT(*) AS cnt FROM outbox WHERE delivered_to_primary = 0 AND source = 'local'",
      readsFrom: {outbox},
    ).getSingle();
    return result.read<int>('cnt');
  }

  /// عدد السجلات غير المُسلّمة للثانوي
  Future<int> countPendingForSecondary() async {
    final result = await customSelect(
      "SELECT COUNT(*) AS cnt FROM outbox WHERE delivered_to_secondary = 0 AND source = 'local'",
      readsFrom: {outbox},
    ).getSingle();
    return result.read<int>('cnt');
  }

  /// يضع علامة "غير مُسلّم للثانوي" على جميع السجلات المحلية القادمة.
  /// تُستدعى عند تفعيل Secondary لأول مرة — نريد إرسال كل السجلات القادمة.
  Future<int> markAllLocalAsUndeliveredToSecondary() async {
    final count = await (update(
      outbox,
    )..where((t) => t.source.equals('local'))).write(const OutboxCompanion(deliveredToSecondary: Value(false)));
    // ✅ إصلاح P1-2 (2026-06-28): تنظيف السجلات المُكتملة لكلا الوجهتين
    // بعد تحديث العلم، قد تكون هناك سجلات بـ delivered_to_primary=true
    // و delivered_to_secondary=true الآن — يجب حذفها لمنع التراكم.
    await _cleanupFullyDeliveredRecords();
    return count;
  }

  /// يضع علامة "مُسلّم للثانوي" على جميع السجلات المحلية.
  /// تُستدعى عند تعطيل Secondary — لا نريد إرسال أي شيء للثانوي.
  Future<int> markAllLocalAsDeliveredToSecondary() async {
    final count = await (update(
      outbox,
    )..where((t) => t.source.equals('local'))).write(const OutboxCompanion(deliveredToSecondary: Value(true)));
    // ✅ إصلاح P1-2 (2026-06-28): تنظيف السجلات المُكتملة لكلا الوجهتين
    await _cleanupFullyDeliveredRecords();
    return count;
  }

  /// ✅ حذف السجلات التي تم تسليمها لكلا الوجهتين (Primary + Secondary)
  /// تُستدعى بعد bulk flag operations لمنع تراكم السجلات المُكتملة.
  Future<int> _cleanupFullyDeliveredRecords() async {
    return (delete(outbox)..where((t) => t.deliveredToPrimary.equals(true) & t.deliveredToSecondary.equals(true))).go();
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
    await (update(outbox)..where((t) => t.processingStatus.equals('failed'))).write(
      const OutboxCompanion(
        processingStatus: Value('pending'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
  }

  /// إعادة محاولة العناصر الفاشلة مع تأخير أسي (Exponential Backoff)
  /// [maxAttempts] - الحد الأقصى للمحاولات قبل الانتظار
  /// [backoffMinutes] - عدد الدقائق للانتظار قبل إعادة محاولة العناصر عالية المحاولات
  Future<int> retryFailedWithBackoff({int maxAttempts = 5, int backoffMinutes = 30}) async {
    final cutoff = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - (backoffMinutes * 60);

    // عناصر قليلة المحاولات → retry فوراً
    final lowAttempts =
        await (update(
          outbox,
        )..where((t) => t.processingStatus.equals('failed') & t.attempts.isSmallerOrEqualValue(maxAttempts))).write(
          const OutboxCompanion(
            processingStatus: Value('pending'),
            processingStartedAt: Value(null),
            processingWorker: Value(null),
          ),
        );

    // عناصر كثيرة المحاولات → انتظر backoffMinutes قبل إعادة المحاولة
    final highAttempts =
        await (update(outbox)..where(
              (t) =>
                  t.processingStatus.equals('failed') &
                  t.attempts.isBiggerThanValue(maxAttempts) &
                  t.clientTs.isSmallerOrEqualValue(cutoff),
            ))
            .write(
              const OutboxCompanion(
                processingStatus: Value('pending'),
                processingStartedAt: Value(null),
                processingWorker: Value(null),
              ),
            );

    return lowAttempts + highAttempts;
  }

  Future<int> cleanupStuckEntries({Duration timeout = const Duration(minutes: 5)}) async {
    final cutoff = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timeout.inSeconds;
    final stuck =
        await (select(outbox)..where(
              (t) => t.processingStatus.equals('processing') & t.processingStartedAt.isSmallerOrEqualValue(cutoff),
            ))
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

  Future<int> cleanupCompleted({Duration olderThan = const Duration(days: 7)}) async {
    final cutoff = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - olderThan.inSeconds;
    final rows = await (delete(
      outbox,
    )..where((t) => t.processingStatus.equals('completed') & t.clientTs.isSmallerOrEqualValue(cutoff))).go();
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
        totalRemoved += await (delete(
          outbox,
        )..where((t) => t.localUuid.isIn(chunk) & t.entity.equals(entity) & t.source.isIn(effectiveSources))).go();
      } else {
        totalRemoved += await (delete(
          outbox,
        )..where((t) => t.localUuid.isIn(chunk) & t.source.isIn(effectiveSources))).go();
      }
    }
    return totalRemoved;
  }

  /// جلب التعارضات من Outbox (السجلات التي فشلت بسبب تعارض)
  ///
  /// ✅ P0-3 إصلاح (2026-06-28): دعم جلب البيانات البعيدة الحقيقية
  /// عبر [fetchRemote]. المُتصل يمرر دالة غير متزامنة تستلم
  /// (entity, localUuid) وتُعيد خريطة البيانات البعيدة أو null.
  /// إذا لم تُمرر الدالة أو فشل الجلب، يُستخدم payload المحلي
  /// كبديل (السلوك القديم مع تحذير).
  Future<List<ConflictRecord>> getConflicts({
    Future<Map<String, dynamic>?> Function(String entity, String localUuid)? fetchRemote,
  }) async {
    final failed =
        await (select(outbox)
              ..where((t) => t.processingStatus.equals('failed') & t.lastError.isNotNull())
              ..orderBy([(t) => OrderingTerm.desc(t.clientTs)]))
            .get();

    final results = <ConflictRecord>[];
    for (final entry in failed) {
      final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
      Map<String, dynamic>? remote = payload; // fallback = local data
      if (fetchRemote != null) {
        try {
          remote = await fetchRemote(entry.entity, entry.localUuid);
        } catch (_) {
          // فشل جلب البيانات البعيدة — نستخدم fallback
        }
      }
      remote ??= payload;
      results.add(
        ConflictRecord(
          id: entry.id,
          uuid: entry.localUuid,
          targetTable: entry.entity,
          localPayload: payload,
          remotePayload: remote,
          lastError: entry.lastError ?? 'Unknown conflict',
          timestamp: DateTime.fromMillisecondsSinceEpoch(entry.clientTs * 1000),
        ),
      );
    }
    return results;
  }

  /// حل تعارض محدد — يُعيد العنصر إلى pending لرفعه فعلياً لاحقاً
  Future<void> resolveConflict(int id, Map<String, dynamic> resolvedData, {required String resolution}) async {
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
  Future<int> cleanupOrphanedEntries({int maxAttempts = 10, Duration olderThan = const Duration(days: 3)}) async {
    final cutoff = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - olderThan.inSeconds;
    final rows =
        await (delete(outbox)..where(
              (t) =>
                  t.processingStatus.equals('failed') &
                  t.attempts.isBiggerOrEqualValue(maxAttempts) &
                  t.clientTs.isSmallerOrEqualValue(cutoff),
            ))
            .go();
    return rows;
  }

  /// ✅ إصلاح: حذف سجلات Outbox للكيانات المحذوفة (soft-delete)
  /// عندما يُحذف كيان محلياً (deletedAt != null) ويكون سجل outbox في حالة
  /// 'completed' أو 'pending'، فإنه يبقى إلى الأبد لأن cleanupCompleted
  /// يحذف فقط السجلات الأقدم من 7 أيام.
  /// هذه الدالة تُزيل سجلات outbox للكيانات المحذوفة فوراً بعد التأكد
  /// أن الحذف تم رفعه للسيرفر بنجاح (حالة completed).
  /// [entityDeletedAtMap] — خريطة من localUuid → deletedAt للكيانات المحذوفة
  Future<int> cleanupForSoftDeletedEntities(Map<String, int?> entityDeletedAtMap) async {
    if (entityDeletedAtMap.isEmpty) return 0;
    final uuids = entityDeletedAtMap.keys.toList();
    // حذف سجلات outbox المُكتملة للكيانات المحذوفة
    final rows = await (delete(
      outbox,
    )..where((t) => t.localUuid.isIn(uuids) & t.processingStatus.equals('completed'))).go();
    return rows;
  }

  /// ✅ إصلاح: حذف سجلات Outbox للكيانات غير الموجودة محلياً (hard-delete)
  /// عندما يُحذف كيان تماماً من قاعدة البيانات المحلية، سجلات outbox
  /// الخاصة به ستبقى للأبد إذا فشل رفعها سابقاً.
  /// [missingLocalUuids] — قائمة localUuid التي لا وجود لها محلياً
  Future<int> cleanupForMissingEntities(List<String> missingLocalUuids) async {
    if (missingLocalUuids.isEmpty) return 0;
    const batchSize = 500;
    int totalRemoved = 0;
    for (var i = 0; i < missingLocalUuids.length; i += batchSize) {
      final end = i + batchSize > missingLocalUuids.length ? missingLocalUuids.length : i + batchSize;
      final chunk = missingLocalUuids.sublist(i, end);
      totalRemoved += await (delete(
        outbox,
      )..where((t) => t.localUuid.isIn(chunk) & t.processingStatus.isIn(['pending', 'failed']))).go();
    }
    return totalRemoved;
  }

  /// ✅ P0: إدراج/تحديث دفعة من عناصر outbox في معاملة واحدة
  /// أسرع بكثير من استدعاء merge() لكل عنصر على حدة عند العمليات المجمّعة
  /// مثل: استيراد نسخة احتياطية، إضافة حجز مع دفعات وليالي
  Future<List<int>> mergeBatch(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return [];

    return transaction(() async {
      final ids = <int>[];
      for (final item in items) {
        final id = await _mergeSingle(
          entity: item['entity'] as String,
          op: item['op'] as String,
          localUuid: item['localUuid'] as String,
          serverId: item['serverId'] as int?,
          payload: item['payload'] as Map<String, dynamic>,
          clientTs: item['clientTs'] as int,
          source: item['source'] as String? ?? 'local',
        );
        if (id != null) ids.add(id);
      }
      return ids;
    });
  }

  /// ✅ P0: إدراج/تحديث عنصر outbox واحد (للاستخدام الداخلي في mergeBatch)
  Future<int?> _mergeSingle({
    required String entity,
    required String op,
    required String localUuid,
    required Map<String, dynamic> payload,
    required int clientTs,
    int? serverId,
    String source = 'local',
  }) async {
    final payloadJson = jsonEncode(payload);
    final idempKey = '$entity:$op:$localUuid:$clientTs';

    bool deliveredToSecondary = true;
    try {
      deliveredToSecondary = !SecondaryAppwriteConfig.isEnabled || !SecondaryAppwriteConfig.isPushEnabled;
    } catch (_) {}

    if (source == 'local' && op != 'delete') {
      await _bumpVectorClockForLocalWrite(entity, localUuid);
    }

    final existing =
        await (select(outbox)
              ..where(
                (t) =>
                    t.entity.equals(entity) &
                    t.localUuid.equals(localUuid) &
                    t.processingStatus.isIn(const ['pending', 'processing']),
              )
              ..limit(1))
            .getSingleOrNull();

    if (existing != null) {
      await (update(outbox)..where((t) => t.id.equals(existing.id))).write(
        OutboxCompanion(
          op: existing.op == 'delete' ? const Value.absent() : Value(op),
          payload: Value(payloadJson),
          clientTs: Value(clientTs),
          idempotencyKey: Value(idempKey),
          serverId: Value(serverId),
          source: Value(source),
          deliveredToSecondary: Value(deliveredToSecondary),
          processingStatus: existing.processingStatus == 'processing' ? const Value('pending') : const Value.absent(),
          processingStartedAt: existing.processingStatus == 'processing' ? const Value(null) : const Value.absent(),
          processingWorker: existing.processingStatus == 'processing' ? const Value(null) : const Value.absent(),
        ),
      );
      return existing.id;
    }

    return into(outbox).insert(
      OutboxCompanion.insert(
        entity: entity,
        op: op,
        localUuid: localUuid,
        serverId: Value(serverId),
        payload: payloadJson,
        clientTs: clientTs,
        idempotencyKey: Value(idempKey),
        source: Value(source),
        deliveredToSecondary: Value(deliveredToSecondary),
      ),
    );
  }

  /// يُستدعى من merge() عند source='local' لضمان كشف كل التعديلات المتزامنة.
  ///
  /// ✅ تحسين: استبدال silent catch بـ proper logging + Crashlytics reporting.
  /// سابقاً كان أي خطأ (SQL فشل، JSON تالف، etc.) يُتجاهل بصمت، مما يجعل
  /// debugging مستحيلاً ويُخفي مشاكل الـ vector clock في الإنتاج.
  /// الآن نُسجّل الخطأ محلياً + نُرسله إلى Crashlytics (low severity لأن
  /// الـ VC bump ليس حرجاً لدرجة تعطيل الكتابة، لكنه مهم لكشف التعارضات).
  Future<void> _bumpVectorClockForLocalWrite(String entity, String localUuid) async {
    final tableName = _entityTableMap[entity];
    if (tableName == null) return;

    final deviceId = AppwriteSyncManager.currentDeviceIdStatic;
    if (deviceId == null || deviceId.isEmpty) return;

    try {
      final rows = await attachedDatabase
          .customSelect(
            'SELECT vector_clock AS vc FROM $tableName WHERE local_uuid = ? LIMIT 1',
            variables: [Variable<String>(localUuid)],
          )
          .get();

      if (rows.isEmpty) return;

      final currentVcStr = (rows.first.data['vc'] as String?) ?? '{}';
      final vc = VectorClock.fromString(currentVcStr);

      // ✅ مراقبة: تسجيل السجلات ذات الـ VC الفارغ لإحصائيات الصحة
      if (vc.isEmpty) {
        developer.log(
          'VC bump: initializing empty vector clock for $entity/$localUuid '
          '(first local edit on device $deviceId)',
          name: 'VectorClock',
        );
      }

      vc.increment(deviceId);

      await attachedDatabase.customStatement('UPDATE $tableName SET vector_clock = ? WHERE local_uuid = ?', [
        vc.toString(),
        localUuid,
      ]);
    } catch (e, st) {
      // ✅ تحسين: تسجيل الخطأ بدلاً من التجاهل الصامت
      // الـ VC bump ليس حرجاً لدرجة تعطيل الكتابة، لكنه مهم لكشف التعارضات
      // نسجّل محلياً + نُرسل إلى Crashlytics بـ low severity
      developer.log('⚠️ VC bump failed for $entity/$localUuid: $e', name: 'VectorClock', error: e, stackTrace: st);
      debugPrint('⚠️ Vector clock bump failed for $entity (uuid=$localUuid): $e');

      // إرسال إلى Crashlytics بدون انتظار (fire-and-forget)
      unawaited(
        CrashlyticsService.instance.recordSyncError(
          operation: 'vc_bump_failed',
          error: e.toString(),
          stackTrace: st,
          severity: CrashlyticsSeverity.warning,
          context: {'entity': entity, 'local_uuid': localUuid, 'device_id': deviceId},
        ),
      );
    }
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

/// ✅ خريطة أسماء الكيانات إلى أسماء الجداول
const _entityTableMap = <String, String>{
  'rooms': 'rooms',
  'bookings': 'bookings',
  'payments': 'payments',
  'expenses': 'expenses',
  'debts': 'debts',
  'employees': 'employees',
  'booking_notes': 'booking_notes',
  'booking_nights': 'booking_nights',
  'cash_transactions': 'cash_transactions',
  'shift_notes': 'shift_notes',
  'salary_cycles': 'salary_cycles',
  'salary_payments': 'salary_payments',
  'salary_withdrawals': 'salary_withdrawals',
  'guest_infos': 'guest_infos',
  'blacklist': 'blacklist',
  'booking_price_adjustments': 'booking_price_adjustments',
  'price_adjustments': 'price_adjustments',
  'payment_voids': 'payment_voids',
  'salary_carry_over_logs': 'salary_carry_over_logs',
  // ✅ app_users — للمزامنة وحل التعارضات عبر vector clock
  'app_users': 'app_users',
};
