// lib/services/sync_core/deferred_relation_relinker.dart
//
// ✅ (G-3 / البنود 1، 5، 6، 8، 12 — تدقيق الهوية المالية 2026-10-06):
// طبقة المجال التي **تُعيد ربط** السجلات «ناقصة الربط» بعد وصول آبائها.
//
// المبادئ المنفَّذة هنا حرفياً:
//   • البند 5 (Idempotency): كل حمولة تحمل `localUuid` ثابتاً، وإعادة
//     التطبيق تمر بنفس مسار المزامنة الرسمي (`AdapterRegistry` →
//     `BaseRepository.upsertFromJson` → UNIQUE(local_uuid)) فلا يتكوّن
//     سجل مكرر أبداً، ولو أُعيد الربط مرات عديدة.
//   • البند 6 (الابن قبل الأب): لا ربط عبر `id`؛ الربط بـ UUID فقط. وإن
//     لم يصل الأب يبقى السجل معلّقاً (لا حذف، لا تخمين).
//   • البند 12 (لا إصلاح بالحدس): ما لا يمكن إثباته يذهب إلى «مراجعة»
//     ويظهر في التقرير، ولا يُربط بالاسم/المبلغ/التاريخ/التشابه.
//   • البند 8 (الطبقات): هذا الملف طبقة مجال؛ لا يعرف شيئاً عن Appwrite/
//     Drive — يتعامل مع `Source` المجرّد وحمولات JSON محايدة المزوّد.
//
// ⚠️ تنبيه سلامة مهم: لا نكتب فوق سجل محلي **أحدث** من الحمولة المعلّقة.
//    قبل التطبيق نقارن `last_modified`؛ إن كان المحلي أحدث ⇒ نعتبر العلاقة
//    محلولة فعلاً (السجل وصل من مسار آخر) ولا نكتب شيئاً.
import 'package:drift/drift.dart';

import '../../utils/app_logger.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/entity_adapter.dart';
import '../adapters/source.dart';
import '../local_db.dart';
import '../repositories/base_repository.dart';
import 'deferred_relation_store.dart';

/// نتيجة دورة إعادة الربط (تُستخدم في السجلات والتقرير).
class DeferredRelinkResult {
  const DeferredRelinkResult({
    this.attempted = 0,
    this.resolved = 0,
    this.stillPending = 0,
    this.movedToReview = 0,
    this.deferredTotal = 0,
  });

  final int attempted;
  final int resolved;
  final int stillPending;
  final int movedToReview;

  /// إجمالي الصفوف في المخزن بعد الدورة (كل الحالات).
  final int deferredTotal;

  bool get hasWork => attempted > 0 || deferredTotal > 0;

  @override
  String toString() =>
      'DeferredRelink(attempted=$attempted, resolved=$resolved, '
      'pending=$stillPending, review=$movedToReview, '
      'total=$deferredTotal)';
}

/// يعرف كيف يعيد تطبيق الحمولات المعلّقة، ويعرف أي علاقة أب ننتظرها.
class DeferredRelationRelinker {
  DeferredRelationRelinker({
    required this.db,
    required this.registry,
    required this.store,
  });

  final AppDatabase db;
  final AdapterRegistry registry;
  final DeferredRelationStore store;

  /// ربط كل مجموعة بالعلاقة الأب المتوقّعة (للتشخيص وإعادة التفعيل).
  static const Map<String, String> parentByCollection = {
    'salary_withdrawals': 'employee',
    'salary_cycles': 'employee',
    'salary_carry_over_logs': 'employee',
    'salary_payments': 'salary_cycle',
    'booking_nights': 'booking',
    'inventory_transactions': 'inventory_item',
  };

  /// مفاتيح هوية الأب داخل الحمولة (بنفس أولوية المحوّلات).
  static const Map<String, List<String>> parentUuidKeysByCollection = {
    'salary_withdrawals': [
      'employeeUuid',
      'employee_uuid',
      'employeeLocalUuid',
    ],
    'salary_cycles': ['employeeUuid', 'employee_uuid', 'employeeLocalUuid'],
    'salary_carry_over_logs': [
      'employeeUuid',
      'employee_uuid',
      'employeeLocalUuid',
    ],
    'salary_payments': ['cycleUuid', 'cycle_uuid', 'cycleLocalUuid'],
    'booking_nights': ['bookingUuidCache', 'bookingUuid', 'booking_uuid'],
    'inventory_transactions': ['itemLocalUuid', 'item_local_uuid'],
  };

  bool _installed = false;

  /// يُثبّت نقطة الالتقاط على المستودعات المعنية. تُستدعى مرة واحدة عند
  /// بناء مدير المزامنة. آمنة للاستدعاء المتكرر.
  void install() {
    if (_installed) return;
    final repos = <String, BaseRepository<dynamic, dynamic>?>{
      'salary_withdrawals': registry.salaryWithdrawals,
      'salary_cycles': registry.salaryCycles,
      'salary_carry_over_logs': registry.salaryCarryOverLogs,
      'salary_payments': registry.salaryPayments,
      'booking_nights': registry.nights,
      'inventory_transactions': registry.inventoryTransactions,
    };
    for (final entry in repos.entries) {
      entry.value?.setSkippedRecordSink(_makeSink(entry.key));
    }
    _installed = true;
    AppLogger.info(
      '✅ مُثبَّت مخزن العلاقات المعلّقة على ${repos.keys.join(', ')} '
      '(لا تخطّي صامت بعد الآن — G-3).',
      tag: 'DEFERRED_RELATIONS',
    );
  }

  BaseRepository<dynamic, dynamic>? _repoOf(String collection) {
    switch (collection) {
      case 'salary_withdrawals':
        return registry.salaryWithdrawals;
      case 'salary_cycles':
        return registry.salaryCycles;
      case 'salary_carry_over_logs':
        return registry.salaryCarryOverLogs;
      case 'salary_payments':
        return registry.salaryPayments;
      case 'booking_nights':
        return registry.nights;
      case 'inventory_transactions':
        return registry.inventoryTransactions;
      default:
        return null;
    }
  }

  SkippedRecordSink _makeSink(String collection) {
    return (
      json, {
      required String tableName,
      required String collectionId,
      required Source src,
      required String? skipReason,
    }) => _capture(
      collection: collection,
      json: json,
      src: src,
      skipReason: skipReason,
    );
  }

  Future<void> _capture({
    required String collection,
    required Map<String, dynamic> json,
    required Source src,
    String? skipReason,
  }) async {
    final localUuid =
        (json['localUuid'] as String?) ?? (json['local_uuid'] as String?);
    if (localUuid == null || localUuid.isEmpty) return;

    final parent = parentByCollection[collection];
    final parentUuid = _firstNonEmpty(
      json,
      parentUuidKeysByCollection[collection],
    );
    final remoteParentId = _firstInt(json, const [
      'employeeId',
      'employee_id',
      'cycleId',
      'cycle_id',
      'bookingLocalId',
      'booking_local_id',
      'itemId',
      'item_id',
    ]);
    final deviceId =
        (json['deviceId'] as String?) ?? (json['device_id'] as String?);

    // ⚠️ الحمولة تُخزَّن بصيغة المزوّد الأصلية (نفس مفاتيح JSON الواردة)
    //    لتُعاد بنفس الدلالات عبر المحوّل نفسه — لا تحويل ولا فقدان حقول.
    final payload = Map<String, dynamic>.from(json);
    payload['localUuid'] = localUuid;
    // ⚠️ لا نخزّن `id` إطلاقاً: قد يكون معرّفاً محلياً حقنه
    // `upsertFromJson` قبل التخطي. إعادة التطبيق تُعيد اشتقاقه بنفسها
    // (تُحدّث السجل الموجود أو تُدرج جديداً) — فلا يتسرّب id محلي.
    payload.remove('id');

    await store.defer(
      collection: collection,
      localUuid: localUuid,
      payload: payload,
      source: src == Source.drive ? 'drive' : 'appwrite',
      reason: skipReason ?? 'unresolved FK reference',
      missingParent: parent,
      parentUuid: parentUuid,
      remoteParentId: remoteParentId,
      sourceDeviceId: deviceId,
    );
  }

  /// ⚙️ «إعادة تفعيل استباقية»: صفوف وصل أبُوها متأخراً (بعد استنفاد
  /// محاولاتها أو تصنيفها «غير مدعومة») تعود إلى `pending` بمجرد وجود الأب
  /// محلياً — بمطابقة **UUID فقط** (مع تجاهل الشرطات). لا حذف ولا تخمين.
  Future<int> rearmAvailableParents() async {
    var total = 0;
    for (final entry in parentByCollection.entries) {
      final parent = entry.value;
      final (String table, String column) = switch (parent) {
        'employee' => ('employees', 'local_uuid'),
        'salary_cycle' => ('salary_cycles', 'local_uuid'),
        'booking' => ('bookings', 'local_uuid'),
        'inventory_item' => ('inventory_items', 'local_uuid'),
        _ => ('', ''),
      };
      if (table.isEmpty) continue;
      final predicate =
          "state IN ('needs_review', 'unsupported') "
          'AND missing_parent = ? '
          "AND parent_uuid IS NOT NULL AND TRIM(parent_uuid) <> '' "
          'AND EXISTS (SELECT 1 FROM $table p WHERE '
          "  LOWER(REPLACE(p.$column, '-', '')) = "
          "  LOWER(REPLACE(parent_uuid, '-', '')) "
          '  AND p.deleted_at IS NULL)';
      try {
        final row = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM ${DeferredRelationStore.tableName} '
              'WHERE $predicate',
              variables: [Variable.withString(parent)],
            )
            .getSingle();
        final candidates = row.read<int>('c');
        if (candidates == 0) continue;
        await db.customStatement(
          'UPDATE ${DeferredRelationStore.tableName} '
          "SET state = 'pending', attempts = 0, last_attempt_at = ? "
          'WHERE $predicate',
          [Time.nowEpoch(), parent],
        );
        total += candidates;
      } catch (e) {
        AppLogger.warning(
          'تعذّرت إعادة تفعيل معلّقات «$parent»: $e',
          tag: 'DEFERRED_RELATIONS',
        );
      }
    }
    if (total > 0) {
      AppLogger.info(
        '🔁 أعيد تفعيل $total سجلاً معلّقاً بعد وصول آبائها (UUID).',
        tag: 'DEFERRED_RELATIONS',
      );
    }
    return total;
  }

  /// دورة إعادة ربط كاملة — تُستدعى بعد اكتمال السحب (أو بعده مباشرة).
  /// لا ترمي استثناءات أبداً (مسارات المزامنة لا يجوز أن تسقط بسببها).
  Future<DeferredRelinkResult> relinkAll({int limit = 200}) async {
    try {
      await rearmAvailableParents();
      final rows = await store.retryable(limit: limit);
      if (rows.isEmpty) {
        return DeferredRelinkResult(deferredTotal: await _totalCount());
      }

      var resolved = 0;
      var stillPending = 0;
      var movedToReview = 0;

      for (final row in rows) {
        final outcome = await _tryApply(row);
        switch (outcome) {
          case _RowOutcome.resolved:
            await store.markResolved(row.id);
            resolved++;
          case _RowOutcome.pending:
            await store.markAttemptFailed(
              row.id,
              reason:
                  'لم يصل الأب بعد (${row.missingParent ?? '?'}: '
                  '${row.parentUuid ?? row.remoteParentId ?? '—'})',
              forceState: DeferredRelationStore.nextStateAfterFailure(
                attempts: row.attempts,
              ),
            );
            stillPending++;
          case _RowOutcome.needsReview:
            await store.markAttemptFailed(
              row.id,
              reason:
                  'لا رابط هوية يمكن إثباته (${row.missingParent ?? '?'}) '
                  '— يحتاج مراجعة بشرية، لا ربط تخميني',
              forceState: DeferredRelationState.needsReview,
            );
            movedToReview++;
          case _RowOutcome.unsupported:
            await store.markAttemptFailed(
              row.id,
              reason:
                  'مجموعة غير مدعومة في إعادة الربط الآلي: '
                  '${row.collection}',
              forceState: DeferredRelationState.unsupported,
            );
            movedToReview++;
        }
      }

      final total = await _totalCount();
      AppLogger.info(
        '🔗 دورة إعادة الربط: attempted=${rows.length}, resolved=$resolved, '
        'pending=$stillPending, review=$movedToReview, total=$total',
        tag: 'DEFERRED_RELATIONS',
      );
      return DeferredRelinkResult(
        attempted: rows.length,
        resolved: resolved,
        stillPending: stillPending,
        movedToReview: movedToReview,
        deferredTotal: total,
      );
    } catch (e) {
      AppLogger.warning(
        'تعذّرت دورة إعادة الربط (لن تُسقط المزامنة): $e',
        tag: 'DEFERRED_RELATIONS',
      );
      return const DeferredRelinkResult();
    }
  }

  Future<int> _totalCount() async {
    final summary = await store.summary();
    return summary.values.fold<int>(0, (a, b) => a + b);
  }

  Future<_RowOutcome> _tryApply(DeferredRelationRow row) async {
    final repo = _repoOf(row.collection);
    if (repo == null) return _RowOutcome.unsupported;

    final parent = parentByCollection[row.collection];
    final parentUuid = (row.parentUuid ?? '').trim();
    if (parent != null && parentUuid.isEmpty) {
      // لا رابط هوية إطلاقاً — لا يمكن إثبات الربط (وكان الرفض الرقمي هو
      // سبب التعليق أصلاً) ⇒ مراجعة بشرية، لا تخمين.
      return _RowOutcome.needsReview;
    }

    final src = row.source == 'drive' ? Source.drive : Source.appwrite;
    final payload = row.payload;

    // حماية: لا نكتب فوق سجل محلي أحدث.
    if (await _localIsNewer(repo, row, payload)) {
      AppLogger.info(
        '⏭️ السجل ${row.collection}/${row.localUuid} موجود محلياً بأحدث '
        'نسخة — لا كتابة، تُعتبر العلاقة محلولة.',
        tag: 'DEFERRED_RELATIONS',
      );
      return _RowOutcome.resolved;
    }

    try {
      final id = await repo.upsertFromJson(payload, src: src);
      if (id > 0) {
        AppLogger.info(
          '✅ رُبط ${row.collection}/${row.localUuid} عبر UUID '
          '(${parent ?? '?'}=$parentUuid).',
          tag: 'DEFERRED_RELATIONS',
        );
        return _RowOutcome.resolved;
      }
      // -1: ما زال المرجع غير محلول ⇒ يبقى معلّقاً (يُعاد لاحقاً).
      return _RowOutcome.pending;
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('FOREIGN KEY constraint failed') ||
          errStr.contains('NOT NULL constraint failed')) {
        return _RowOutcome.pending;
      }
      AppLogger.warning(
        'تعذّر إعادة ربط ${row.collection}/${row.localUuid}: $e',
        tag: 'DEFERRED_RELATIONS',
      );
      return _RowOutcome.pending;
    }
  }

  /// يقارن `last_modified` المحلي مع طابع الحمولة (تسامح مع ثواني/ملي
  /// ثواني). إن تعذّر التحليل ⇒ لا قرار (نُطبّق؛ الحمولة لم تُطبَّق بعد
  /// أصلاً فلا خطر فقدان). محلي >= البعيد ⇒ مُطبَّق فعلاً (من مسار آخر)
  /// فلا داعي لإعادة الكتابة.
  Future<bool> _localIsNewer(
    BaseRepository<dynamic, dynamic> repo,
    DeferredRelationRow row,
    Map<String, dynamic> payload,
  ) async {
    final remoteTs = _parseEpoch(
      _firstInt(payload, const [
        'lastModified',
        'last_modified',
        'updatedAt',
        'updated_at',
      ]),
    );
    if (remoteTs == null) return false;

    try {
      final table = repo.table.actualTableName;
      final query = await db
          .customSelect(
            'SELECT last_modified FROM $table WHERE local_uuid = ? LIMIT 1',
            variables: [Variable.withString(row.localUuid)],
          )
          .getSingleOrNull();
      final localTs = query?.read<int>('last_modified');
      if (localTs == null) return false;
      return localTs >= remoteTs;
    } catch (_) {
      return false;
    }
  }

  /// تحويل طابع زمني متسامح إلى ثوانٍ (millis إذا كان كبيراً).
  static int? _parseEpoch(int? raw) {
    if (raw == null) return null;
    if (raw <= 0) return null;
    if (raw > 100000000000) return raw ~/ 1000; // millis
    return raw;
  }

  static String? _firstNonEmpty(Map<String, dynamic> json, List<String>? keys) {
    if (keys == null) return null;
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static int? _firstInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}

enum _RowOutcome { resolved, pending, needsReview, unsupported }
