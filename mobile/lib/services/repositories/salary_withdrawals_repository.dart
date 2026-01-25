import '../local_db.dart';

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db);

  final AppDatabase _db;
  bool _tableEnsured = false;

  Future<void> _ensureTable() async {
    if (_tableEnsured) return;
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS salary_withdrawals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_id INTEGER UNIQUE,
        employee_id INTEGER,
        action TEXT,
        amount REAL,
        note TEXT,
        date TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    _tableEnsured = true;
  }

  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
  }) async {
    await _ensureTable();
    await _db.customStatement(
      '''
      INSERT INTO salary_withdrawals (expense_id, employee_id, action, amount, note, date, created_at)
      VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(expense_id) DO UPDATE SET
        employee_id = excluded.employee_id,
        action = excluded.action,
        amount = excluded.amount,
        note = excluded.note,
        date = excluded.date
      ''',
      [expenseId, employeeId, action, amount, note ?? '', date],
    );
  }

  Future<void> deleteByExpenseId(int expenseId) async {
    await _ensureTable();
    await _db.customStatement(
      'DELETE FROM salary_withdrawals WHERE expense_id = ?',
      [expenseId],
    );
  }

  Future<List<Map<String, Object?>>> listAll() async {
    await _ensureTable();
    final rows = await _db
        .customSelect(
          'SELECT * FROM salary_withdrawals ORDER BY created_at DESC',
        )
        .get();
    return rows.map((row) => row.data).toList();
  }
}
