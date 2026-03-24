import '../local_db.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db);

  final AppDatabase _db;

  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();
    
    // Check if record exists
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .getSingleOrNull();
    
    if (existing != null) {
      // Update existing
      await (_db.update(_db.salaryWithdrawals)
            ..where((t) => t.expenseId.equals(expenseId)))
          .write(SalaryWithdrawalsCompanion(
            employeeId: Value(employeeId),
            action: Value(action),
            amount: Value(amount),
            note: Value(note),
            date: Value(date),
            updatedAt: Value(now),
            lastModified: Value(now),
            updatedAtIso: Value(nowIso),
          ));
    } else {
      // Insert new
      await _db.into(_db.salaryWithdrawals).insert(
        SalaryWithdrawalsCompanion(
          expenseId: Value(expenseId),
          employeeId: Value(employeeId),
          action: Value(action),
          amount: Value(amount),
          note: Value(note),
          date: Value(date),
          localUuid: Value(_uuid.v4()),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
          createdAtIso: Value(nowIso),
          updatedAtIso: Value(nowIso),
          version: const Value(1),
          origin: const Value('local'),
        ),
      );
    }
  }

  Future<void> deleteByExpenseId(int expenseId) async {
    await (_db.delete(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .go();
  }

  Future<List<SalaryWithdrawal>> listAll() async {
    return await (_db.select(_db.salaryWithdrawals)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}
