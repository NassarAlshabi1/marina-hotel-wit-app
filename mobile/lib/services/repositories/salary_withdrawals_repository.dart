import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/expense_reason_matcher.dart';
import '../daos/outbox_dao.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db) : _outboxDao = OutboxDao(_db);
  final AppDatabase _db;
  final OutboxDao _outboxDao;

  /// إنشاء سجل سحب راتب مرتبط بمصروف
  Future<int> createFromExpense({
    required int expenseId,
    required int employeeId,
    required String reason,
    required double amount,
    required String date,
    String? hotelDayKey,
    String? withdrawalType,
    String? description,
    bool originIsServer = false,
  }) async {
    final now = Time.nowEpoch();
    final uuid = IdGen.uuid();
    final companion = SalaryWithdrawalsCompanion(
      localUuid: d.Value(uuid),
      serverId: const d.Value(null),
      employeeId: d.Value(employeeId),
      amount: d.Value(amount),
      withdrawDate: d.Value(date),
      reason: d.Value(reason),
      hotelDayKey: d.Value(hotelDayKey ?? ''),
      withdrawalType: d.Value(withdrawalType),
      description: d.Value(description),
      createdAt: d.Value(now),
      updatedAt: d.Value(now),
      deletedAt: const d.Value(null),
      lastModified: d.Value(now),
      createdAtEpoch: d.Value(now),
      lastModifiedEpoch: d.Value(now),
      version: const d.Value(1),
      origin: d.Value(originIsServer ? 'server' : 'local'),
      vectorClock: const d.Value('{}'),
    );
    final id = await _db.into(_db.salaryWithdrawals).insert(companion);

    if (!originIsServer) {
      await _outboxDao.merge(
        entity: 'salary_withdrawals',
        op: 'create',
        localUuid: uuid,
        serverId: null,
        payload: {
          'employeeId': employeeId,
          'amount': amount,
          'withdrawDate': date,
          'reason': reason,
          'hotelDayKey': hotelDayKey ?? '',
          'withdrawalType': withdrawalType,
          'description': description,
        },
        clientTs: now,
      );
    }

    return id;
  }

  /// حفظ أو تحديث سجل سحب راتب مرتبط بمصروف (UPSERT via expense_id)
  /// ملاحظة: الجدول لا يحتوي expense_id مباشرة،
  /// لذلك نستخدم الربط عبر حقل reason الذي يحتوي [exp_ID]
  /// ✅ إصلاح: تغليف العملية في معاملة لضمان اتساق البيانات
  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
    String? hotelDayKey,
    bool originIsServer = false,
  }) async {
    // محاولة البحث عن سجل موجود مرتبط بنفس المصروف
    // SQL WHERE يضيق النتائج قبل الفلترة بالـ regex في Dart
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.reason.like('%exp_$expenseId%')
              & t.deletedAt.isNull()))
        .get();

    final matched = existing.where((w) =>
        matchesExpenseRef(w.reason, expenseId)).firstOrNull;

    final now = Time.nowEpoch();
    // reason يحتوي فقط على علامة الربط بالمصروف
    final reasonText = 'exp_$expenseId';

    // جمع السجلات القديمة غير المطابقة لمنع التكرار عند التعديل
    // (مثلاً عند تغيير التاريخ أو الموظف)
    final staleRecords = existing.where((w) =>
        w.id != matched?.id &&
        matchesExpenseRef(w.reason, expenseId)).toList();

    await _db.transaction(() async {
      // ─── حذف السجلات القديمة داخل المعاملة لضمان اتساق المزامنة ───
      for (final stale in staleRecords) {
        await (_db.update(_db.salaryWithdrawals)
              ..where((t) => t.id.equals(stale.id)))
            .write(SalaryWithdrawalsCompanion(
          deletedAt: d.Value(now),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
          version: d.Value(stale.version + 1),
        ));

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'delete',
            localUuid: stale.localUuid,
            serverId: stale.serverId,
            payload: {
              'deletedAt': now,
              'lastModified': now,
            },
            clientTs: now,
          );
        }
      }

      // ─── إنشاء أو تحديث السجل الرئيسي ───
      if (matched != null) {
        // تحديث السجل الموجود
        await (_db.update(_db.salaryWithdrawals)
              ..where((t) => t.id.equals(matched.id)))
            .write(SalaryWithdrawalsCompanion(
              employeeId: d.Value(employeeId),
              amount: d.Value(amount),
              withdrawDate: d.Value(date),
              reason: d.Value(reasonText),
              withdrawalType: d.Value(action),
              description: d.Value(note),
              hotelDayKey: d.Value(hotelDayKey ?? ''),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              version: d.Value(matched.version + 1),
            ));

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: matched.localUuid,
            serverId: matched.serverId,
            payload: {
              'amount': amount,
              'withdrawDate': date,
              'reason': reasonText,
              'withdrawalType': action,
              'description': note,
              'hotelDayKey': hotelDayKey ?? '',
              'lastModified': now,
            },
            clientTs: now,
          );
        }
      } else {
        // إنشاء سجل جديد
        final uuid = IdGen.uuid();
        await _db.into(_db.salaryWithdrawals).insert(
          SalaryWithdrawalsCompanion(
            localUuid: d.Value(uuid),
            serverId: const d.Value(null),
            employeeId: d.Value(employeeId),
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            reason: d.Value(reasonText),
            withdrawalType: d.Value(action),
            description: d.Value(note),
            hotelDayKey: d.Value(hotelDayKey ?? ''),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            deletedAt: const d.Value(null),
            lastModified: d.Value(now),
            createdAtEpoch: d.Value(now),
            lastModifiedEpoch: d.Value(now),
            version: const d.Value(1),
            origin: d.Value(originIsServer ? 'server' : 'local'),
            vectorClock: const d.Value('{}'),
          ),
        );

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'create',
            localUuid: uuid,
            serverId: null,
            payload: {
              'employeeId': employeeId,
              'amount': amount,
              'withdrawDate': date,
              'reason': reasonText,
              'withdrawalType': action,
              'description': note,
              'hotelDayKey': hotelDayKey ?? '',
            },
            clientTs: now,
          );
        }
      }
    });
  }

  /// ✅ إصلاح: حذف ناعم (soft delete) بدلاً من الحذف الفعلي
  /// لتوافق مع آلية المزامنة التي تعتمد على deletedAt
  /// كذلك إصلاح خطأ regex: استخدام matchesExpenseRef لمنع مطابقة exp_1 مع exp_10
  Future<void> deleteByExpenseId(int expenseId) async {
    // SQL WHERE يضيق النتائج قبل الفلترة بالـ regex في Dart
    final candidates = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.reason.like('%exp_$expenseId%') & t.deletedAt.isNull()))
        .get();

    final toDelete = candidates
        .where((w) => matchesExpenseRef(w.reason, expenseId))
        .toList();

    final now = Time.nowEpoch();

    // ✅ حذف ناعم في معاملة واحدة لضمان الاتساق
    await _db.transaction(() async {
      for (final item in toDelete) {
        await (_db.update(_db.salaryWithdrawals)
              ..where((t) => t.id.equals(item.id)))
            .write(SalaryWithdrawalsCompanion(
          deletedAt: d.Value(now),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
          version: d.Value(item.version + 1),
        ));

        await _outboxDao.merge(
          entity: 'salary_withdrawals',
          op: 'delete',
          localUuid: item.localUuid,
          serverId: item.serverId,
          payload: {
            'deletedAt': now,
            'lastModified': now,
          },
          clientTs: now,
        );
      }
    });
  }

  /// جلب كل سحوبات الرواتب
  Future<List<SalaryWithdrawal>> listAll() async {
    return _db.select(_db.salaryWithdrawals).get();
  }

  /// جلب سحوبات موظف معين
  Future<List<SalaryWithdrawal>> listByEmployeeId(int employeeId) async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.employeeId.equals(employeeId)))
        .get();
  }

  /// جلب السحوبات النشطة (غير المحذوفة)
  Future<List<SalaryWithdrawal>> listActive() async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull()))
        .get();
  }
}
