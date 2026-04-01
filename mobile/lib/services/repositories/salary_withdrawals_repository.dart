import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db);
  final AppDatabase _db;

  /// إنشاء سجل سحب راتب مرتبط بمصروف
  Future<int> createFromExpense({
    required int expenseId,
    required int employeeId,
    required String reason,
    required double amount,
    required String date,
    String? hotelDayKey,
  }) async {
    final now = Time.nowEpoch();
    final companion = SalaryWithdrawalsCompanion(
      localUuid: d.Value(IdGen.uuid()),
      serverId: const d.Value(null),
      employeeId: d.Value(employeeId),
      amount: d.Value(amount),
      withdrawDate: d.Value(date),
      reason: d.Value(reason),
      hotelDayKey: d.Value(hotelDayKey ?? ''),
      createdAt: d.Value(now),
      updatedAt: d.Value(now),
      deletedAt: const d.Value(null),
      lastModified: d.Value(now),
      createdAtEpoch: d.Value(now),
      lastModifiedEpoch: d.Value(now),
      version: const d.Value(1),
      origin: const d.Value('local'),
      vectorClock: const d.Value('{}'),
    );
    return _db.into(_db.salaryWithdrawals).insert(companion);
  }

  /// حفظ أو تحديث سجل سحب راتب مرتبط بمصروف (UPSERT via expense_id)
  /// ملاحظة: الجدول الجديد لا يحتوي expense_id مباشرة،
  /// لذلك نستخدم localUuid كمعرّز مرتبط بالمصروف
  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
  }) async {
    // محاولة البحث عن سجل موجود مرتبط بنفس الموظف والتاريخ والمبلغ
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.employeeId.equals(employeeId)))
        .get();

    final matched = existing.where((w) =>
        w.withdrawDate == date &&
        (w.reason?.contains('exp_$expenseId') ?? false)).firstOrNull;

    final now = Time.nowEpoch();
    final reasonText = note != null && note.isNotEmpty
        ? '${note} [exp_$expenseId]'
        : 'سحب راتب [exp_$expenseId]';

    if (matched != null) {
      // تحديث السجل الموجود
      await (_db.update(_db.salaryWithdrawals)
            ..where((t) => t.id.equals(matched.id)))
          .write(SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            reason: d.Value(reasonText),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(matched.version + 1),
          ));
    } else {
      // إنشاء سجل جديد
      await _db.into(_db.salaryWithdrawals).insert(
        SalaryWithdrawalsCompanion(
          localUuid: d.Value(IdGen.uuid()),
          serverId: const d.Value(null),
          employeeId: d.Value(employeeId),
          amount: d.Value(amount),
          withdrawDate: d.Value(date),
          reason: d.Value(reasonText),
          hotelDayKey: d.Value(''),
          createdAt: d.Value(now),
          updatedAt: d.Value(now),
          deletedAt: const d.Value(null),
          lastModified: d.Value(now),
          createdAtEpoch: d.Value(now),
          lastModifiedEpoch: d.Value(now),
          version: const d.Value(1),
          origin: const d.Value('local'),
          vectorClock: const d.Value('{}'),
        ),
      );
    }
  }

  /// حذف سحوبات مرتبطة بمصروف معين (via reason contains exp_id)
  Future<void> deleteByExpenseId(int expenseId) async {
    final all = await _db.select(_db.salaryWithdrawals).get();
    final toDelete = all
        .where((w) => (w.reason?.contains('exp_$expenseId') ?? false))
        .toList();
    for (final item in toDelete) {
      await (_db.delete(_db.salaryWithdrawals)
            ..where((t) => t.id.equals(item.id)))
          .go();
    }
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
