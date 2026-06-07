import 'package:drift/drift.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../local_db.dart';
import '../sync_core/optimistic_lock_helper.dart';
import 'outbox_dao.dart';

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
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (from != null && to != null) {
      q.where(
        (t) =>
            t.date.isBiggerOrEqual(Variable(from)) &
            t.date.isSmallerOrEqual(Variable(to)),
      );
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.description.like(s) | t.expenseType.like(s));
    }
    return q.get();
  }

  Future<List<Expense>> listFiltered({
    String? from,
    String? to,
    String? expenseType,
    bool includeDeleted = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }

    if (from != null) {
      q.where((t) =>
          t.date.isBiggerOrEqual(Variable(from)) |
          t.date.like('$from%'));
    }
    if (to != null) {
      q.where((t) =>
          t.date.isSmallerOrEqual(Variable(to)) |
          t.date.like('$to%'));
    }
    if (expenseType != null && expenseType.isNotEmpty) {
      q.where((t) => t.expenseType.equals(expenseType));
    }

    q.orderBy([(t) => OrderingTerm.desc(t.date)]);
    return q.get();
  }

  /// فلترة حسب نطاق الأيام الفندقية — الطريقة الصحيحة للتقارير
  ///
  /// على عكس [listFiltered] التي تفلتر بحقل [date] التقويمي
  /// (وتشمل مصروفات الصباح التي تنتمي لليوم الفندقي السابق)،
  /// هذه الدالة تفلتر بحقل [hotelDayKey] وهو المفتاح الصحيح.
  ///
  /// مثال: إذا كان اليوم الفندقي "2026-05-18" والوقت 10:00 صباحاً
  /// فإن listFiltered(from:"2026-05-18") تجلب مصروفات صباح 18 مايو
  /// التي تنتمي لليوم الفندقي 17 مايو — بينما هذه الدالة تجلب فقط
  /// المصروفات التي hotelDayKey فيها بين fromHotelDay و toHotelDay.
  Future<List<Expense>> listFilteredByHotelDay({
    String? fromHotelDay,
    String? toHotelDay,
    String? expenseType,
    String? search,
    bool includeDeleted = false,
    bool excludeAdvance = false,
    bool excludeAdvance = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }

    if (fromHotelDay != null) {
      // hotelDayKey >= fromHotelDay، مع fallback لحقل date عند كون hotelDayKey فارغاً
      // ✅ إصلاح: استخدام like بدلاً من isBiggerOrEqualValue للمقارنة
      // لأن date قد يحتوي على وقت مثل "2026-05-18 10:30:00"
      // والمقارنة النصية "2026-05-18" >= "2026-05-18 10:30:00" تُعطي نتيجة خاطئة
      q.where((t) =>
          (t.hotelDayKey.isNotNull() &
              t.hotelDayKey.isBiggerOrEqual(Variable(fromHotelDay))) |
          (t.hotelDayKey.isNull() &
              (t.date.isBiggerOrEqual(Variable(fromHotelDay)) |
               t.date.like('$fromHotelDay%'))));
    }
    if (toHotelDay != null) {
      q.where((t) =>
          (t.hotelDayKey.isNotNull() &
              t.hotelDayKey.isSmallerOrEqual(Variable(toHotelDay))) |
          (t.hotelDayKey.isNull() &
              (t.date.isSmallerOrEqual(Variable(toHotelDay)) |
               t.date.like('$toHotelDay%'))));
    }
    if (expenseType != null && expenseType.isNotEmpty) {
      q.where((t) => t.expenseType.equals(expenseType));
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.description.like(s) | t.expenseType.like(s));
    }
    if (excludeAdvance) {
      q.where((t) => t.expenseType.notEquals('سلفة'));
    }

    q.orderBy([(t) => OrderingTerm.desc(t.date)]);
    return q.get();
  }

  /// فلترة حسب نطاق الأيام الفندقية مع دعم أنواع متعددة
  Future<List<Expense>> listFilteredByHotelDayMultiTypes({
    String? fromHotelDay,
    String? toHotelDay,
    required List<String> expenseTypes,
    String? search,
    bool includeDeleted = false,
    bool excludeAdvance = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }

    if (fromHotelDay != null) {
      q.where((t) =>
          (t.hotelDayKey.isNotNull() &
              t.hotelDayKey.isBiggerOrEqual(Variable(fromHotelDay))) |
          (t.hotelDayKey.isNull() &
              (t.date.isBiggerOrEqual(Variable(fromHotelDay)) |
               t.date.like('$fromHotelDay%'))));
    }
    if (toHotelDay != null) {
      q.where((t) =>
          (t.hotelDayKey.isNotNull() &
              t.hotelDayKey.isSmallerOrEqual(Variable(toHotelDay))) |
          (t.hotelDayKey.isNull() &
              (t.date.isSmallerOrEqual(Variable(toHotelDay)) |
               t.date.like('$toHotelDay%'))));
    }
    if (expenseTypes.isNotEmpty) {
      var typeCondition = t.expenseType.equals(expenseTypes.first);
      for (var i = 1; i < expenseTypes.length; i++) {
        typeCondition = typeCondition | t.expenseType.equals(expenseTypes[i]);
      }
      q.where((t) => typeCondition);
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.description.like(s) | t.expenseType.like(s));
    }
    if (excludeAdvance) {
      q.where((t) => t.expenseType.notEquals('سلفة'));
    }

    q.orderBy([(t) => OrderingTerm.desc(t.date)]);
    return q.get();
  }

  Stream<List<Expense>> watchList({bool includeDeleted = false}) {
    final q = select(expenses);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    return q.watch();
  }

  /// مراقبة المصروفات ليوم فندقي محدد (يتحدث فوراً عند الإضافة/التعديل)
  Stream<List<Expense>> watchByHotelDayKey(String hotelDayKey) {
    final q = select(expenses);
    q.where((t) => t.deletedAt.isNull());

    final byKey = expenses.hotelDayKey.equals(hotelDayKey);
    final byDateFallback =
        expenses.hotelDayKey.isNull() & expenses.date.like('$hotelDayKey%');

    q.where((t) => byKey | byDateFallback);
    return q.watch();
  }

  /// جلب المصروفات لتاريخ محدد
  Future<List<Expense>> listByDate(
    String date, {
    bool includeDeleted = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    q.where((t) => t.date.like('$date%'));
    return q.get();
  }

  Future<List<Expense>> listByHotelDayKey(
    String hotelDayKey, {
    bool includeDeleted = false,
  }) async {
    final q = select(expenses);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }

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
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  Future<Expense?> getByServerId(String serverId) {
    final parsedServerId = _parseServerId(serverId);
    if (parsedServerId == null) {
      return Future.value();
    }
    return (select(
      expenses,
    )..where((t) => t.serverId.equals(parsedServerId))).getSingleOrNull();
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
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified =
          originIsServer && data.lastModified.present
              ? data.lastModified
              : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        expenses,
      )..where((t) => t.id.equals(id))).write(comp);
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
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified =
          originIsServer && data.lastModified.present
              ? data.lastModified
              : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        expenses,
      )..where((t) => t.localUuid.equals(localUuid))).write(comp);
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
      if (parsedServerId == null) {
        return 0;
      }
      final now = Time.nowEpoch();
      final existing = await (select(
        expenses,
      )..where((t) => t.serverId.equals(parsedServerId))).getSingleOrNull();
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified =
          originIsServer && data.lastModified.present
              ? data.lastModified
              : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        expenses,
      )..where((t) => t.serverId.equals(parsedServerId))).write(comp);
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
      if (existing == null) {
        return 0;
      }
      final rows = await (update(expenses)..where((t) => t.id.equals(id)))
          .write(
            ExpensesCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      if (rows > 0 && !originIsServer) {
        // ✅ نستخدم 'update' بدلاً من 'delete' لأن softDelete يحدّث deletedAt
        // ولا يحذف المستند من Appwrite — الجهاز الآخر يحتاج رؤية deletedAt
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

  Future<Map<String, dynamic>?> _payloadForLocalUuid(String localUuid) async {
    final row =
        await (select(expenses)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return adapters.expenses.toJsonForSource(row, src: Source.appwrite);
  }

  Future<void> _mergeOutbox({
    required String op,
    required String localUuid,
    required int clientTs,
    int? serverId,
  }) async {
    final payload = await _payloadForLocalUuid(localUuid);
    if (payload == null) {
      return;
    }
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
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع المصروفات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final expensesList = await list();
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

  @override
  TableInfo<Expenses, Expense> get optimisticTable => expenses;

  @override
  String get optimisticTableName => 'expenses';

  @override
  GeneratedColumn<String> get optimisticLocalUuid => expenses.localUuid;

  @override
  GeneratedColumn<int> get optimisticVersion => expenses.version;
}
