import '../local_db.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../daos/outbox_dao.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db)
      : _outbox = OutboxDao(_db),
        _adapters = AdapterRegistry(_db);

  final AppDatabase _db;
  final OutboxDao _outbox;
  final AdapterRegistry _adapters;

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

    String localUuid;
    int? recordId;

    if (existing != null) {
      // Update existing
      localUuid = existing.localUuid;
      recordId = existing.id;

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
      localUuid = _uuid.v4();

      recordId = await _db.into(_db.salaryWithdrawals).insert(
        SalaryWithdrawalsCompanion(
          expenseId: Value(expenseId),
          employeeId: Value(employeeId),
          action: Value(action),
          amount: Value(amount),
          note: Value(note),
          date: Value(date),
          localUuid: Value(localUuid),
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

    // ✅ إضافة للمزامنة عبر Outbox
    await _addToOutbox(
      localUuid: localUuid,
      recordId: recordId,
      expenseId: expenseId,
      employeeId: employeeId,
      action: action,
      amount: amount,
      date: date,
      note: note,
      now: now,
      nowIso: nowIso,
    );
  }

  /// إضافة سجل للـ Outbox للمزامنة مع Appwrite
  /// ✅ الحقول مطابقة لأنواع Appwrite Console
  Future<void> _addToOutbox({
    required String localUuid,
    required int recordId,
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
    required int now,
    required String nowIso,
  }) async {
    // ✅ بناء بيانات السجل للإرسال - مطابقة لأنواع Appwrite Console
    // ملاحظة: 'id' هو حقل integer مطلوب في Appwrite (منفصل عن $id)
    final payload = <String, dynamic>{
      // ✅ الحقول المطلوبة (required) - مطابقة لـ Appwrite Console
      'id': localUuid.hashCode.abs(),             // ✅ integer (required) - hash من UUID
      'localUuid': localUuid,                     // string (required)
      'employeeId': employeeId,                   // integer (required)
      'action': action,                           // string (required)
      'amount': amount.toInt(),                   // ✅ integer (required) - تحويل من double
      'date': date,                               // string (required)
      'createdAt': now,                           // integer (required)
      'updatedAt': now,                           // integer (required)
      'lastModified': now,                        // integer (required)
      'version': 1,                               // integer (required)
      'origin': 'local',                          // string (required)
      'vectorClock': '{}',                        // ✅ string (required)

      // ✅ الحقول الاختيارية
      'expenseId': expenseId,                     // integer (optional)
      if (note != null && note.isNotEmpty) 'note': note,  // string (optional)
      'createdAtIso': nowIso,                     // string (optional)
      'updatedAtIso': nowIso,                     // string (optional)
    };

    await _outbox.merge(
      entity: 'salary_withdrawals',
      op: 'upsert',
      localUuid: localUuid,
      serverId: recordId,
      payload: payload,
      clientTs: now ~/ 1000,
    );
  }

  Future<void> deleteByExpenseId(int expenseId) async {
    // جلب السجل قبل الحذف للحصول على localUuid
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .getSingleOrNull();

    if (existing != null) {
      // حذف من قاعدة البيانات المحلية
      await (_db.delete(_db.salaryWithdrawals)
            ..where((t) => t.expenseId.equals(expenseId)))
          .go();

      // ✅ إضافة عملية حذف للـ Outbox
      await _outbox.merge(
        entity: 'salary_withdrawals',
        op: 'delete',
        localUuid: existing.localUuid,
        payload: {'deleted': true, 'localUuid': existing.localUuid},
        clientTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    }
  }

  Future<List<SalaryWithdrawal>> listAll() async {
    return await (_db.select(_db.salaryWithdrawals)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// جلب سجل واحد بواسطة localUuid
  Future<SalaryWithdrawal?> getByUuid(String localUuid) async {
    return await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  /// تحويل السجل إلى JSON للإرسال
  Map<String, dynamic> toJson(SalaryWithdrawal record) {
    return _adapters.salaryWithdrawals.adapter.toJson(record, src: Source.appwrite);
  }
}
