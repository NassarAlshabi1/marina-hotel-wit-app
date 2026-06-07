import 'package:drift/drift.dart' as d;

import '../../utils/expense_reason_matcher.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

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
      expenseId: d.Value(expenseId),
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

  /// حفظ أو تحديث سجل سحب راتب مرتبط بمصروف (UPSERT via expenseId)
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
    // البحث عن سجل موجود مرتبط بنفس expenseId (الطريقة المباشرة)
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)
              & t.deletedAt.isNull(),))
        .getSingleOrNull();

    final now = Time.nowEpoch();
    final reasonText = 'exp_$expenseId';

    await _db.transaction(() async {
      if (existing != null) {
        // تحديث السجل الموجود
        await (_db.update(_db.salaryWithdrawals)
              ..where((t) => t.id.equals(existing.id)))
            .write(SalaryWithdrawalsCompanion(
              employeeId: d.Value(employeeId),
              expenseId: d.Value(expenseId),
              amount: d.Value(amount),
              withdrawDate: d.Value(date),
              reason: d.Value(reasonText),
              withdrawalType: d.Value(action),
              description: d.Value(note),
              hotelDayKey: d.Value(hotelDayKey ?? ''),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              version: d.Value(existing.version + 1),
            ),);

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: existing.localUuid,
            serverId: existing.serverId,
            payload: {
              'employeeId': employeeId,
              'expenseId': expenseId,
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
            expenseId: d.Value(expenseId),
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
            payload: {
              'employeeId': employeeId,
              'expenseId': expenseId,
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

  /// حذف ناعم بسحوبات الراتب المرتبطة بمصروف معين
  Future<void> deleteByExpenseId(int expenseId) async {
    final candidates = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId) & t.deletedAt.isNull()))
        .get();

    final now = Time.nowEpoch();
    await _db.transaction(() async {
      for (final item in candidates) {
        await (_db.update(_db.salaryWithdrawals)
              ..where((t) => t.id.equals(item.id)))
            .write(SalaryWithdrawalsCompanion(
          deletedAt: d.Value(now),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
          version: d.Value(item.version + 1),
        ),);

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

  /// 🔧 ترحيل لمرة واحدة: إصلاح الـ reason في السجلات القديمة (بدون exp_)
  /// يربط السحوبات القديمة بالمصروفات عبر (الموظف، اليوم الفندقي، المبلغ)
  Future<int> migrateOldRecords() async {
    int fixed = 0;
    final all = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull()))
        .get();

    final targets = all.where((sw) {
      if (sw.reason == null || sw.reason!.isEmpty) return true;
      return !sw.reason!.contains('exp_');
    }).toList();

    if (targets.isEmpty) {
      return 0;
    }

    final now = Time.nowEpoch();
    for (final sw in targets) {
      final matchingExpenses = await (_db.select(_db.expenses)
            ..where((t) => t.deletedAt.isNull())
            ..where((t) => t.relatedId.equals(sw.employeeId))
            ..where((t) => t.hotelDayKey.equals(sw.hotelDayKey ?? ''))
            ..where((t) => t.amount.equals(sw.amount.abs())))
          .get();

      if (matchingExpenses.isEmpty) continue;

      final expense = matchingExpenses.first;
      final newReason = 'exp_${expense.id}';

      await (_db.update(_db.salaryWithdrawals)
            ..where((t) => t.id.equals(sw.id)))
          .write(SalaryWithdrawalsCompanion(
            reason: d.Value(newReason),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(sw.version + 1),
          ));

      await _outboxDao.merge(
        entity: 'salary_withdrawals',
        op: 'update',
        localUuid: sw.localUuid,
        serverId: sw.serverId,
        payload: {
          'reason': newReason,
          'lastModified': now,
        },
        clientTs: now,
      );

      fixed++;
    }
    return fixed;
  }

  /// جلب السحوبات النشطة (غير المحذوفة)
  Future<List<SalaryWithdrawal>> listActive() async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull()))
        .get();
  }
}
