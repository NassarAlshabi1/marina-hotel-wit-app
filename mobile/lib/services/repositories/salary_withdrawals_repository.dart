import 'dart:async';

import 'package:drift/drift.dart' as d;

import '../../utils/expense_reason_matcher.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../telegram/telegram_notification_service.dart';
import '../telegram/whatsapp_notification_service.dart';

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db) : _outboxDao = OutboxDao(_db);
  final AppDatabase _db;
  final OutboxDao _outboxDao;

  /// ✅ كتابة expense_id في عمود SQL خام بعد كل إدراج/تحديث
  /// العمود أُضيف عبر Migration 40 ولا يوجد في الـ data class المُولّد
  Future<void> _setExpenseIdRaw(int salaryWithdrawalId, int expenseId) async {
    try {
      await _db.customStatement(
        'UPDATE salary_withdrawals SET expense_id = ? WHERE id = ?',
        [expenseId, salaryWithdrawalId],
      );
    } catch (_) {
      // العمود قد لا يكون موجوداً في الإصدارات القديمة — نتخطى بصمت
    }
  }

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
      hotelDayKey: d.Value(hotelDayKey ?? _computeHotelDayKey(date)),
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

    // ✅ كتابة expense_id في العمود الخام (إذا كان expenseId > 0)
    if (expenseId > 0) {
      await _setExpenseIdRaw(id, expenseId);
    }

    // إشعارات فورية (fire-and-forget)
    unawaited(WhatsAppNotificationService.instance.notifyNewExpense(
      category: 'سحب راتب',
      amount: amount,
      description: reason,
    ));
    unawaited(TelegramNotificationService.instance.notifyNewExpense(
      category: 'سحب راتب',
      amount: amount,
      description: reason,
    ));

    if (!originIsServer) {
      final payload = <String, dynamic>{
        'employeeId': employeeId,
        'amount': amount,
        'withdrawDate': date,
        'reason': reason,
        'hotelDayKey': hotelDayKey ?? _computeHotelDayKey(date),
        'withdrawalType': withdrawalType,
        'description': description,
      };
      // ✅ إضافة expenseId للحمولة لمزامنته مع Appwrite
      if (expenseId > 0) {
        payload['expenseId'] = expenseId;
      }
      await _outboxDao.merge(
        entity: 'salary_withdrawals',
        op: 'create',
        localUuid: uuid,
        payload: payload,
        clientTs: now,
      );
    }

    return id;
  }

  /// حفظ أو تحديث سجل سحب راتب مرتبط بمصروف (UPSERT via expense_id)
  /// ✅ إصلاح خبير: البحث أولاً عبر عمود expense_id ثم عبر reason
  /// تغليف العملية في معاملة لضمان اتساق البيانات
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
    // ✅ البحث عن سجل موجود — محاولة عبر عمود expense_id أولاً
    SalaryWithdrawal? matched;

    // الطريقة 1: بحث عبر عمود expense_id (الأكثر موثوقية)
    try {
      final rows = await _db.customSelect(
        'SELECT * FROM salary_withdrawals WHERE expense_id = ? AND deleted_at IS NULL LIMIT 1',
        variables: [d.Variable.withInt(expenseId)],
      ).get();
      if (rows.isNotEmpty) {
        // نقرأ بيانات السجل من جدول salary_withdrawals عبر Drift
        final byId = await (_db.select(_db.salaryWithdrawals)
              ..where((t) => t.id.equals(rows.first.read<int>('id')))
              ..limit(1))
            .getSingleOrNull();
        if (byId != null) {
          matched = byId;
        }
      }
    } catch (_) {
      // العمود قد لا يكون موجوداً
    }

    // الطريقة 2: بحث عبر reason (الطريقة القديمة)
    if (matched == null) {
      final existing = await (_db.select(_db.salaryWithdrawals)
            ..where((t) => t.reason.like('%exp_$expenseId%')
                & t.deletedAt.isNull(),))
          .get();
      matched = existing.where((w) =>
          matchesExpenseRef(w.reason, expenseId),).firstOrNull;
    }

    final now = Time.nowEpoch();
    // reason يحتوي فقط على علامة الربط بالمصروف
    final reasonText = 'exp_$expenseId';

    // جمع السجلات القديمة غير المطابقة لمنع التكرار عند التعديل
    final staleRecords = <SalaryWithdrawal>[];
    if (matched != null) {
      // البحث عن سجلات أخرى بنفس expense_id أو exp_XX
      final allExisting = await (_db.select(_db.salaryWithdrawals)
            ..where((t) => t.deletedAt.isNull()
                & t.id.equals(matched!.id).not()))
          .get();
      for (final w in allExisting) {
        if (matchesExpenseRef(w.reason, expenseId)) {
          staleRecords.add(w);
        }
      }
    }

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
        ),);

        if (!originIsServer) {
          // ✅ إصلاح حرج: استخدام op:'update' بدلاً من op:'delete'
          // الحذف الناعم (soft-delete) يجب أن يستخدم 'update' لكي يُحدث سجل Appwrite
          // بدلاً من حذفه نهائياً — هذا يضمن رؤية deletedAt على الأجهزة الأخرى
          // ✅ إصلاح: إضافة employeeId للحمولة لضمان مزامنة relatedId/employeeId بشكل صحيح
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: stale.localUuid,
            serverId: stale.serverId,
            payload: {
              'employeeId': stale.employeeId,
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
              ..where((t) => t.id.equals(matched!.id)))
            .write(SalaryWithdrawalsCompanion(
              employeeId: d.Value(employeeId),
              amount: d.Value(amount),
              withdrawDate: d.Value(date),
              reason: d.Value(reasonText),
              withdrawalType: d.Value(action),
              description: d.Value(note),
              hotelDayKey: d.Value(hotelDayKey ?? _computeHotelDayKey(date)),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              version: d.Value(matched.version + 1),
            ),);

        // ✅ تحديث expense_id في العمود الخام
        await _setExpenseIdRaw(matched.id, expenseId);

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: matched.localUuid,
            serverId: matched.serverId,
            payload: {
              'employeeId': employeeId,
              'amount': amount,
              'withdrawDate': date,
              'reason': reasonText,
              'withdrawalType': action,
              'description': note,
              'hotelDayKey': hotelDayKey ?? _computeHotelDayKey(date),
              'lastModified': now,
              'expenseId': expenseId,
            },
            clientTs: now,
          );
        }
        // إشعارات فورية (fire-and-forget) عند التحديث
        unawaited(WhatsAppNotificationService.instance.notifyNewExpense(
          category: 'سحب راتب',
          amount: amount,
          description: note ?? reasonText,
        ));
        unawaited(TelegramNotificationService.instance.notifyNewExpense(
          category: 'سحب راتب',
          amount: amount,
          description: note ?? reasonText,
        ));
      } else {
        // إنشاء سجل جديد
        final uuid = IdGen.uuid();
        final newId = await _db.into(_db.salaryWithdrawals).insert(
          SalaryWithdrawalsCompanion(
            localUuid: d.Value(uuid),
            serverId: const d.Value(null),
            employeeId: d.Value(employeeId),
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            reason: d.Value(reasonText),
            withdrawalType: d.Value(action),
            description: d.Value(note),
            hotelDayKey: d.Value(hotelDayKey ?? _computeHotelDayKey(date)),
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

        // ✅ كتابة expense_id في العمود الخام
        await _setExpenseIdRaw(newId, expenseId);
        unawaited(WhatsAppNotificationService.instance.notifyNewExpense(
          category: 'سحب راتب',
          amount: amount,
          description: note,
        ));
        unawaited(TelegramNotificationService.instance.notifyNewExpense(
          category: 'سحب راتب',
          amount: amount,
          description: note,
        ));

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'create',
            localUuid: uuid,
            payload: {
              'employeeId': employeeId,
              'amount': amount,
              'withdrawDate': date,
              'reason': reasonText,
              'withdrawalType': action,
              'description': note,
              'hotelDayKey': hotelDayKey ?? _computeHotelDayKey(date),
              'expenseId': expenseId,
            },
            clientTs: now,
          );
        }
      }
    });
  }

  /// ✅ إصلاح: حذف ناعم (soft delete) بدلاً من الحذف الفعلي
  /// لتوافق مع آلية المزامنة التي تعتمد على deletedAt
  /// ✅ إصلاح خبير: البحث أولاً عبر عمود expense_id ثم عبر reason
  Future<void> deleteByExpenseId(int expenseId, {bool originIsServer = false}) async {
    // الطريقة 1: بحث عبر عمود expense_id
    List<SalaryWithdrawal> toDelete = [];
    try {
      final rows = await _db.customSelect(
        'SELECT id FROM salary_withdrawals WHERE expense_id = ? AND deleted_at IS NULL',
        variables: [d.Variable.withInt(expenseId)],
      ).get();
      if (rows.isNotEmpty) {
        final ids = rows.map((r) => r.read<int>('id')).toList();
        toDelete = await (_db.select(_db.salaryWithdrawals)
              ..where((t) => t.id.isIn(ids)))
            .get();
      }
    } catch (_) {
      // العمود قد لا يكون موجوداً
    }

    // الطريقة 2: بحث عبر reason (الطريقة القديمة) إذا لم نجد عبر expense_id
    if (toDelete.isEmpty) {
      final candidates = await (_db.select(_db.salaryWithdrawals)
            ..where((t) => t.reason.like('%exp_$expenseId%') & t.deletedAt.isNull()))
          .get();
      toDelete = candidates
          .where((w) => matchesExpenseRef(w.reason, expenseId))
          .toList();
    }

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
        ),);

        // ✅ إصلاح حرج: استخدام op:'update' بدلاً من op:'delete'
        // الحذف الناعم (soft-delete) يجب أن يستخدم 'update' لكي يُحدث سجل Appwrite
        // بدلاً من حذفه نهائياً — هذا يضمن رؤية deletedAt على الأجهزة الأخرى
        // ✅ إصلاح: إضافة employeeId للحمولة لضمان مزامنة relatedId/employeeId بشكل صحيح
        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: item.localUuid,
            serverId: item.serverId,
            payload: {
              'employeeId': item.employeeId,
              'deletedAt': now,
              'lastModified': now,
            },
            clientTs: now,
          );
        }
      }
    });
  }

  /// جلب كل سحوبات الرواتب (غير المحذوفة فقط)
  Future<List<SalaryWithdrawal>> listAll() async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull()))
        .get();
  }

  /// جلب سحوبات موظف معين
  Future<List<SalaryWithdrawal>> listByEmployeeId(int employeeId) async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.employeeId.equals(employeeId) & t.deletedAt.isNull()))
        .get();
  }

  /// جلب السحوبات النشطة (غير المحذوفة)
  Future<List<SalaryWithdrawal>> listActive() async {
    return (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull()))
        .get();
  }

  /// حساب مفتاح اليوم الفندقي من تاريخ السحب
  /// إذا كان التاريخ يحتوي على وقت (yyyy-MM-dd HH:mm)، يستخدمه مباشرة
  /// إذا كان تاريخاً تقويمياً فقط (yyyy-MM-dd)، يمرّر 14:01 لضمان اليوم الصحيح
  static String _computeHotelDayKey(String date) {
    try {
      final trimmed = date.trim();
      final hasTime = trimmed.length > 10;
      if (hasTime) {
        return HotelTimeEngine.getHotelDayKeyFromIso(trimmed);
      }
      // تاريخ تقويمي بدون وقت — نمرّر 14:01:00 لضمان اليوم الفندقي الصحيح
      final parts = trimmed.split('-');
      if (parts.length != 3) {
        return HotelTimeEngine.getHotelDayKey();
      }
      final year = int.tryParse(parts[0]) ?? 1;
      final month = int.tryParse(parts[1]) ?? 1;
      final day = int.tryParse(parts[2]) ?? 1;
      return HotelTimeEngine.getHotelDayKey(
        dateTime: DateTime(year, month, day, 14, 1),
      );
    } catch (_) {
      return HotelTimeEngine.getHotelDayKey();
    }
  }
}
