import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../local_db.dart';
import '../../utils/time.dart';

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db);

  final AppDatabase _db;

  /// إنشاء سحب راتب جديد
  Future<int> create({
    required int employeeId,
    required String action,
    required int amount,
    required String date,
    int? expenseId,
    String? note,
  }) async {
    final now = Time.nowEpoch();
    final uuid = const Uuid().v4();
    
    return _db.into(_db.salaryWithdrawals).insert(
      SalaryWithdrawalsCompanion(
        localUuid: d.Value(uuid),
        expenseId: d.Value(expenseId),
        employeeId: d.Value(employeeId),
        action: d.Value(action),
        amount: d.Value(amount),
        note: d.Value(note),
        date: d.Value(date),
        createdAt: d.Value(now),
        updatedAt: d.Value(now),
        lastModified: d.Value(now),
        version: const d.Value(1),
        origin: const d.Value('local'),
      ),
    );
  }

  /// حفظ سحب الراتب من المصروف
  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required int amount,
    required String date,
    String? note,
  }) async {
    // التحقق من وجود سجل سابق بنفس expense_id
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .getSingleOrNull();

    final now = Time.nowEpoch();

    if (existing != null) {
      // تحديث السجل الموجود
      await (_db.update(_db.salaryWithdrawals)
            ..where((t) => t.expenseId.equals(expenseId)))
          .write(
        SalaryWithdrawalsCompanion(
          employeeId: d.Value(employeeId),
          action: d.Value(action),
          amount: d.Value(amount),
          note: d.Value(note),
          date: d.Value(date),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
        ),
      );
    } else {
      // إنشاء سجل جديد
      final uuid = const Uuid().v4();
      await _db.into(_db.salaryWithdrawals).insert(
        SalaryWithdrawalsCompanion(
          localUuid: d.Value(uuid),
          expenseId: d.Value(expenseId),
          employeeId: d.Value(employeeId),
          action: d.Value(action),
          amount: d.Value(amount),
          note: d.Value(note),
          date: d.Value(date),
          createdAt: d.Value(now),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
          version: const d.Value(1),
          origin: const d.Value('local'),
        ),
      );
    }
  }

  /// حذف سحب الراتب بواسطة معرف المصروف
  Future<void> deleteByExpenseId(int expenseId) async {
    await (_db.delete(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .go();
  }

  /// حذف سحب الراتب بواسطة الـ UUID
  Future<void> deleteByUuid(String localUuid) async {
    await (_db.delete(_db.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(localUuid)))
        .go();
  }

  /// جلب جميع سحوبات الرواتب
  Future<List<SalaryWithdrawal>> listAll() async {
    return _db.select(_db.salaryWithdrawals).get();
  }

  /// جلب سحوبات موظف معين
  Future<List<SalaryWithdrawal>> listByEmployee(int employeeId) async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.employeeId.equals(employeeId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.date)]))
        .get();
  }

  /// جلب سحوبات فترة معينة
  Future<List<SalaryWithdrawal>> listByDateRange(
    String fromDate,
    String toDate,
  ) async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.date.isBetweenValues(fromDate, toDate))
          ..orderBy([(t) => d.OrderingTerm.desc(t.date)]))
        .get();
  }

  /// جلب سحب راتب بواسطة الـ UUID
  Future<SalaryWithdrawal?> getByUuid(String localUuid) async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  /// جلب سحب راتب بواسطة معرف المصروف
  Future<SalaryWithdrawal?> getByExpenseId(int expenseId) async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .getSingleOrNull();
  }

  /// تحديث سحب راتب
  Future<void> update(
    String localUuid, {
    int? employeeId,
    String? action,
    int? amount,
    String? date,
    int? expenseId,
    String? note,
  }) async {
    final now = Time.nowEpoch();
    
    await (_db.update(_db.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(localUuid)))
        .write(
      SalaryWithdrawalsCompanion(
        employeeId: employeeId != null ? d.Value(employeeId) : const d.Value.absent(),
        action: action != null ? d.Value(action) : const d.Value.absent(),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        date: date != null ? d.Value(date) : const d.Value.absent(),
        expenseId: expenseId != null ? d.Value(expenseId) : const d.Value.absent(),
        note: note != null ? d.Value(note) : const d.Value.absent(),
        updatedAt: d.Value(now),
        lastModified: d.Value(now),
      ),
    );
  }

  /// تحديث أو إنشاء سحب راتب من JSON (للمزامنة)
  Future<void> upsertFromJson(Map<String, dynamic> json) async {
    final localUuid = json['local_uuid'] as String? ?? json['localUuid'] as String?;
    if (localUuid == null || localUuid.isEmpty) return;

    final now = Time.nowEpoch();
    
    final companion = SalaryWithdrawalsCompanion(
      localUuid: d.Value(localUuid),
      serverId: json['server_id'] != null 
          ? d.Value(json['server_id'] as int) 
          : json['serverId'] != null 
              ? d.Value(json['serverId'] as int)
              : const d.Value.absent(),
      expenseId: json['expense_id'] != null
          ? d.Value(json['expense_id'] as int)
          : json['expenseId'] != null
              ? d.Value(json['expenseId'] as int)
              : const d.Value.absent(),
      employeeId: d.Value(json['employee_id'] as int? ?? json['employeeId'] as int),
      action: d.Value(json['action'] as String),
      amount: d.Value((json['amount'] as num?)?.toInt() ?? 0),
      note: d.Value(json['note'] as String?),
      date: d.Value(json['date'] as String),
      createdAt: d.Value(json['created_at'] as int? ?? json['createdAt'] as int? ?? now),
      updatedAt: d.Value(json['updated_at'] as int? ?? json['updatedAt'] as int? ?? now),
      deletedAt: json['deleted_at'] != null
          ? d.Value(json['deleted_at'] as int?)
          : json['deletedAt'] != null
              ? d.Value(json['deletedAt'] as int?)
              : const d.Value.absent(),
      lastModified: d.Value(json['last_modified'] as int? ?? json['lastModified'] as int? ?? now),
      version: d.Value(json['version'] as int? ?? 1),
      origin: d.Value(json['origin'] as String? ?? 'sync'),
    );

    await _db.into(_db.salaryWithdrawals).insertOnConflictUpdate(companion);
  }

  /// مراقبة سحوبات موظف معين
  Stream<List<SalaryWithdrawal>> watchByEmployee(int employeeId) {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.employeeId.equals(employeeId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.date)]))
        .watch();
  }

  /// مراقبة جميع السحوبات
  Stream<List<SalaryWithdrawal>> watchAll() {
    return (_db.select(_db.salaryWithdrawals)
          ..orderBy([(t) => d.OrderingTerm.desc(t.date)]))
        .watch();
  }

  /// حساب إجمالي السحوبات لموظف معين
  Future<int> getTotalByEmployee(int employeeId) async {
    final withdrawals = await listByEmployee(employeeId);
    return withdrawals.fold<int>(0, (sum, w) => sum + w.amount);
  }
}
