import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'auto_backup_manager.dart';
import 'local_db.dart';

/// مدد لتتبع التغييرات في قاعدة البيانات للنسخ التلقائي
typedef TablePredicate<TTable extends Table> =
    Expression<bool> Function(TTable table);

extension DatabaseAutoBackupExtension on AppDatabase {
  /// تهيئة تتبع التغييرات للنسخ التلقائي
  void initializeAutoBackup() {
    debugPrint('🔗 تهيئة تتبع التغييرات للنسخ التلقائي...');

    // لا حاجة لتعديل طرق Drift، سنقوم بإنشاء طرق wrapper
    // سيتم استدعاؤها من providers أو UI layers
  }

  /// تتبع إدراج سجل جديد
  Future<int>
  insertWithBackupTrigger<TTable extends Table, TData extends DataClass>(
    TableInfo<TTable, TData> table,
    Insertable<TData> entity, {
    InsertMode? mode,
    UpsertClause<TTable, TData>? onConflict,
  }) async {
    final result = await into(
      table,
    ).insert(entity, mode: mode, onConflict: onConflict);

    // تسجيل التغيير للنسخ التلقائي
    unawaited(
      AutoBackupManager.instance.onDataChange(
        table.actualTableName,
        'INSERT',
        recordData: entity.toColumns(false),
      ),
    );

    return result;
  }

  /// تتبع تحديث سجل
  Future<bool>
  updateWithBackupTrigger<TTable extends Table, TData extends DataClass>(
    TableInfo<TTable, TData> table,
    Insertable<TData> entity, {
    TablePredicate<TTable>? where,
  }) async {
    final statement = update(table);
    if (where != null) {
      statement.where(where);
    }

    final result = await statement.write(entity);

    if (result > 0) {
      // تسجيل التغيير للنسخ التلقائي
      unawaited(
        AutoBackupManager.instance.onDataChange(
          table.actualTableName,
          'UPDATE',
          recordData: entity.toColumns(false),
        ),
      );
    }

    return result > 0;
  }

  /// تتبع حذف سجل
  Future<int>
  deleteWithBackupTrigger<TTable extends Table, TData extends DataClass>(
    TableInfo<TTable, TData> table, {
    TablePredicate<TTable>? where,
    Map<String, dynamic>? recordData,
  }) async {
    final statement = delete(table);
    if (where != null) {
      statement.where(where);
    }

    final result = await statement.go();

    if (result > 0) {
      // تسجيل التغيير للنسخ التلقائي
      unawaited(
        AutoBackupManager.instance.onDataChange(
          table.actualTableName,
          'DELETE',
          recordData: recordData,
        ),
      );
    }

    return result;
  }
}

/// مساعد للتفاعل مع قاعدة البيانات مع النسخ التلقائي
class AutoBackupDatabaseHelper {
  static final AppDatabase _db = DatabaseManager.instance;

  // طرق مساعدة للحجوزات
  static Future<int> insertBooking(BookingsCompanion booking) async {
    final result = await _db.insertWithBackupTrigger(_db.bookings, booking);
    debugPrint(
      '📝 تم إضافة حجز جديد (${booking.guestName.value}) - سيتم النسخ التلقائي',
    );
    return result;
  }

  static Future<bool> updateBooking(int id, BookingsCompanion booking) async {
    final result = await _db.updateWithBackupTrigger(
      _db.bookings,
      booking,
      where: (t) => t.id.equals(id),
    );
    if (result) {
      debugPrint('✏️ تم تحديث حجز ($id) - سيتم النسخ التلقائي');
    }
    return result;
  }

  static Future<int> deleteBooking(int id, String guestName) async {
    final result = await _db.deleteWithBackupTrigger(
      _db.bookings,
      where: (t) => t.id.equals(id),
      recordData: {'id': id, 'guest_name': guestName},
    );
    if (result > 0) {
      debugPrint('🗑️ تم حذف حجز ($id - $guestName) - سيتم النسخ التلقائي');
    }
    return result;
  }

  // طرق مساعدة للغرف
  static Future<int> insertRoom(RoomsCompanion room) async {
    final result = await _db.insertWithBackupTrigger(_db.rooms, room);
    debugPrint(
      '🏠 تم إضافة غرفة جديدة (${room.roomNumber.value}) - سيتم النسخ التلقائي',
    );
    return result;
  }

  static Future<bool> updateRoom(int id, RoomsCompanion room) async {
    final result = await _db.updateWithBackupTrigger(
      _db.rooms,
      room,
      where: (t) => t.id.equals(id),
    );
    if (result) {
      debugPrint('✏️ تم تحديث غرفة ($id) - سيتم النسخ التلقائي');
    }
    return result;
  }

  // طرق مساعدة للمدفوعات
  static Future<int> insertPayment(PaymentsCompanion payment) async {
    final result = await _db.insertWithBackupTrigger(_db.payments, payment);
    debugPrint(
      '💰 تم إضافة دفعة جديدة (${payment.amount.value}) - سيتم النسخ التلقائي',
    );
    return result;
  }

  static Future<bool> updatePayment(int id, PaymentsCompanion payment) async {
    final result = await _db.updateWithBackupTrigger(
      _db.payments,
      payment,
      where: (t) => t.id.equals(id),
    );
    if (result) {
      debugPrint('✏️ تم تحديث دفعة ($id) - سيتم النسخ التلقائي');
    }
    return result;
  }

  // طرق مساعدة للمصروفات
  static Future<int> insertExpense(ExpensesCompanion expense) async {
    final result = await _db.insertWithBackupTrigger(_db.expenses, expense);
    debugPrint(
      '🧾 تم إضافة مصروف جديد (${expense.amount.value}) - سيتم النسخ التلقائي',
    );
    return result;
  }

  static Future<bool> updateExpense(int id, ExpensesCompanion expense) async {
    final result = await _db.updateWithBackupTrigger(
      _db.expenses,
      expense,
      where: (t) => t.id.equals(id),
    );
    if (result) {
      debugPrint('✏️ تم تحديث مصروف ($id) - سيتم النسخ التلقائي');
    }
    return result;
  }

  // طرق مساعدة للمعاملات النقدية
  static Future<int> insertCashTransaction(
    CashTransactionsCompanion transaction,
  ) async {
    final result = await _db.insertWithBackupTrigger(
      _db.cashTransactions,
      transaction,
    );
    debugPrint(
      '💳 تم إضافة معاملة نقدية (${transaction.amount.value}) - سيتم النسخ التلقائي',
    );
    return result;
  }

  // طرق مساعدة للموظفين
  static Future<int> insertEmployee(EmployeesCompanion employee) async {
    final result = await _db.insertWithBackupTrigger(_db.employees, employee);
    debugPrint(
      '👤 تم إضافة موظف جديد (${employee.name.value}) - سيتم النسخ التلقائي',
    );
    return result;
  }

  static Future<bool> updateEmployee(
    int id,
    EmployeesCompanion employee,
  ) async {
    final result = await _db.updateWithBackupTrigger(
      _db.employees,
      employee,
      where: (t) => t.id.equals(id),
    );
    if (result) {
      debugPrint('✏️ تم تحديث موظف ($id) - سيتم النسخ التلقائي');
    }
    return result;
  }

  // طرق مساعدة لملاحظات الحجز
  static Future<int> insertBookingNote(BookingNotesCompanion note) async {
    final result = await _db.insertWithBackupTrigger(_db.bookingNotes, note);
    debugPrint('📝 تم إضافة ملاحظة حجز - سيتم النسخ التلقائي');
    return result;
  }

  static Future<bool> updateBookingNote(
    int id,
    BookingNotesCompanion note,
  ) async {
    final result = await _db.updateWithBackupTrigger(
      _db.bookingNotes,
      note,
      where: (t) => t.id.equals(id),
    );
    if (result) {
      debugPrint('✏️ تم تحديث ملاحظة حجز ($id) - سيتم النسخ التلقائي');
    }
    return result;
  }

  // طرق مساعدة للديون
  static Future<int> insertDebt(DebtsCompanion debt) async {
    final result = await _db.insertWithBackupTrigger(_db.debts, debt);
    debugPrint(
      '💳 تم إضافة دين جديد (${debt.totalAmount.value}) - سيتم النسخ التلقائي',
    );
    return result;
  }

  static Future<bool> updateDebt(int id, DebtsCompanion debt) async {
    final result = await _db.updateWithBackupTrigger(
      _db.debts,
      debt,
      where: (t) => t.id.equals(id),
    );
    if (result) {
      debugPrint('✏️ تم تحديث دين ($id) - سيتم النسخ التلقائي');
    }
    return result;
  }
}
