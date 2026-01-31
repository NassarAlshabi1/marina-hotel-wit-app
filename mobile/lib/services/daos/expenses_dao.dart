import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import '../sync_core/optimistic_lock_helper.dart';
import 'outbox_dao.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../validation/validation.dart';

part 'expenses_dao.g.dart';

@DriftAccessor(tables: [Expenses])
class ExpensesDao extends DatabaseAccessor<AppDatabase>
    with _$ExpensesDaoMixin, OptimisticLockDaoMixin<Expenses, Expense> {
  ExpensesDao(super.db, this.outboxDao) : adapters = AdapterRegistry(db);
  final OutboxDao outboxDao;
  final AdapterRegistry adapters;

  Future<List<Expense>> list({
    String? search,
    String? from,
    String? to,
    bool includeDeleted = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (from != null && to != null) {
      q.where(
        (t) =>
            t.date.isBiggerOrEqualValue(from) &
            t.date.isSmallerOrEqualValue(to),
      );
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.description.like(s) | t.expenseType.like(s));
    }
    return q.get();
  }

  Stream<List<Expense>> watchList({bool includeDeleted = false}) {
    final q = select(expenses);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    return q.watch();
  }

  /// جلب المصروفات لتاريخ محدد
  Future<List<Expense>> listByDate(
    String date, {
    bool includeDeleted = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    q.where((t) => t.date.like('$date%'));
    return q.get();
  }

  Future<List<Expense>> listByHotelDayKey(
    String hotelDayKey, {
    bool includeDeleted = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());

    final byKey = expenses.hotelDayKey.equals(hotelDayKey);
    final byDateFallback =
        expenses.hotelDayKey.isNull() & expenses.date.like('$hotelDayKey%');

    q.where((t) => byKey | byDateFallback);
    return q.get();
  }

  Future<Expense?> getById(int id) =>
      (select(expenses)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Expense?> watchById(int id) =>
      (select(expenses)..where((t) => t.id.equals(id))).watchSingleOrNull();
  Future<Expense?> getByLocalUuid(String localUuid) => (select(
        expenses,
      )..where((t) => t.localUuid.equals(localUuid)))
          .getSingleOrNull();
  Future<Expense?> getByServerId(String serverId) {
    final parsedServerId = _parseServerId(serverId);
    if (parsedServerId == null) return Future.value(null);
    return (select(
      expenses,
    )..where((t) => t.serverId.equals(parsedServerId)))
        .getSingleOrNull();
  }

  Future<int> insertOne(
    ExpensesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
      final comp = data.copyWith(
        localUuid: Value(uu),
        createdAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
        origin: Value(originIsServer ? 'server' : 'local'),
      );

      if (!originIsServer) {
        _validateExpenseData(comp);
      }

      final id = await into(expenses).insert(comp);
      if (!originIsServer) {
        await _mergeOutbox(
          op: 'create',
          localUuid: uu,
          serverId: comp.serverId.present ? comp.serverId.value : null,
          clientTs: now,
        );
      }
      return id;
    });
  }

  Future<int> updateById(
    int id,
    ExpensesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
        version: Value(existing.version + 1),
      );

      if (!originIsServer) {
        _validateExpenseData(comp);
      }

      final rows = await (update(
        expenses,
      )..where((t) => t.id.equals(id)))
          .write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> updateByLocalUuid(
    String localUuid,
    ExpensesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getByLocalUuid(localUuid);
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        expenses,
      )..where((t) => t.localUuid.equals(localUuid)))
          .write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> updateByServerId(
    String? serverId,
    ExpensesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final parsedServerId = _parseServerId(serverId);
      if (parsedServerId == null) return 0;
      final now = Time.nowEpoch();
      final existing = await (select(
        expenses,
      )..where((t) => t.serverId.equals(parsedServerId)))
          .getSingleOrNull();
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        expenses,
      )..where((t) => t.serverId.equals(parsedServerId)))
          .write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> hardDelete(int id) async {
    return (delete(expenses)..where((t) => t.id.equals(id))).go();
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final rows =
          await (update(expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<Map<String, dynamic>?> _payloadForLocalUuid(String localUuid) async {
    final row = await (select(expenses)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return adapters.expenses.toJsonForSource(row, src: Source.appwrite);
  }

  Future<void> _mergeOutbox({
    required String op,
    required String localUuid,
    required int clientTs,
    int? serverId,
  }) async {
    final payload = await _payloadForLocalUuid(localUuid);
    if (payload == null) return;
    await outboxDao.merge(
      entity: 'expenses',
      op: op,
      localUuid: localUuid,
      serverId: serverId,
      payload: payload,
      clientTs: clientTs,
    );
  }

  int? _parseServerId(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع المصروفات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final expensesList = await list(includeDeleted: false);
    return expensesList.map((expense) => expense.toJson()).toList();
  }

  /// استيراد المصروفات من JSON
  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      await delete(expenses).go();
    }

    for (final expenseJson in data) {
      final expense = Expense.fromJson(expenseJson);
      await into(expenses).insertOnConflictUpdate(
        ExpensesCompanion(
          expenseType: Value(expense.expenseType),
          relatedId: Value(expense.relatedId),
          description: Value(expense.description),
          amount: Value(expense.amount),
          date: Value(expense.date),
          cashTransactionId: Value(expense.cashTransactionId),
          localUuid: Value(expense.localUuid),
          serverId: Value(expense.serverId),
          createdAt: Value(expense.createdAt),
          updatedAt: Value(expense.updatedAt),
          deletedAt: Value(expense.deletedAt),
          lastModified: Value(expense.lastModified),
          version: Value(expense.version),
          origin: Value(expense.origin),
        ),
      );
    }
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(expenses)..addColumns([expenses.id.count()]);
    final result = await query.getSingle();
    return result.read(expenses.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(expenses).go();
  }

  void _validateExpenseData(ExpensesCompanion data) {
    final errors = EntityValidators.validateExpense(data);
    if (errors.isNotEmpty) {
      throw ValidationException(errors);
    }
  }

  @override
  TableInfo<Expenses, Expense> get optimisticTable => expenses;

  @override
  String get optimisticTableName => 'expenses';

  @override
  GeneratedColumn<String> get optimisticLocalUuid => expenses.localUuid;

  @override
  GeneratedColumn<int> get optimisticVersion => expenses.version;
}
