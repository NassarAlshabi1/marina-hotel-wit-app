// مثال على كيفية دمج النسخ التلقائي مع repository موجود
// يمكن تطبيق هذا النمط على أي repository في التطبيق

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../auto_backup_manager.dart';

/// Mixin لإضافة النسخ التلقائي لأي repository
mixin AutoBackupMixin {
  void triggerAutoBackup(
    String tableName,
    String operation, {
    Map<String, dynamic>? recordData,
  }) {
    AutoBackupManager.instance.onDataChange(
      tableName,
      operation,
      recordData: recordData,
    );
  }
}

/// مثال على تحديث PaymentsRepository للدعم النسخ التلقائي
class PaymentsRepositoryWithAutoBackup with AutoBackupMixin {
  PaymentsRepositoryWithAutoBackup(this.db);
  final AppDatabase db;

  Future<int> addPayment({
    required int bookingId,
    required double amount,
    required String paymentDate,
    required String paymentMethod,
    String? notes,
  }) async {
    // إضافة الدفعة بالطريقة العادية
    final paymentId = await db
        .into(db.payments)
        .insert(
          PaymentsCompanion(
            bookingLocalId: d.Value(bookingId),
            amount: d.Value(amount),
            paymentDate: d.Value(paymentDate),
            paymentMethod: d.Value(paymentMethod),
            notes: d.Value(notes),
            revenueType: const d.Value('room'),
            // ... باقي القيم المطلوبة
          ),
        );

    // تشغيل النسخ التلقائي
    triggerAutoBackup(
      'payments',
      'CREATE',
      recordData: {
        'id': paymentId,
        'booking_id': bookingId,
        'amount': amount,
        'payment_method': paymentMethod,
      },
    );

    return paymentId;
  }

  Future<bool> updatePayment(
    int id, {
    double? amount,
    String? paymentDate,
    String? paymentMethod,
    String? notes,
  }) async {
    final updatedRows =
        await (db.update(db.payments)..where((p) => p.id.equals(id))).write(
          PaymentsCompanion(
            amount: amount != null ? d.Value(amount) : const d.Value.absent(),
            paymentDate: paymentDate != null
                ? d.Value(paymentDate)
                : const d.Value.absent(),
            paymentMethod: paymentMethod != null
                ? d.Value(paymentMethod)
                : const d.Value.absent(),
            notes: notes != null ? d.Value(notes) : const d.Value.absent(),
          ),
        );

    if (updatedRows > 0) {
      // تشغيل النسخ التلقائي
      triggerAutoBackup(
        'payments',
        'UPDATE',
        recordData: {
          'id': id,
          'amount': amount,
          'payment_method': paymentMethod,
        },
      );
    }

    return updatedRows > 0;
  }

  Future<bool> deletePayment(int id) async {
    // الحصول على بيانات الدفعة قبل الحذف
    final payment = await (db.select(
      db.payments,
    )..where((p) => p.id.equals(id))).getSingleOrNull();

    final deletedRows = await (db.delete(
      db.payments,
    )..where((p) => p.id.equals(id))).go();

    if (deletedRows > 0 && payment != null) {
      // تشغيل النسخ التلقائي
      triggerAutoBackup(
        'payments',
        'DELETE',
        recordData: {
          'id': id,
          'amount': payment.amount,
          'payment_method': payment.paymentMethod,
          'booking_id': payment.bookingLocalId,
        },
      );
    }

    return deletedRows > 0;
  }
}

/// مثال آخر على RoomsRepository
class RoomsRepositoryWithAutoBackup with AutoBackupMixin {
  RoomsRepositoryWithAutoBackup(this.db);
  final AppDatabase db;

  Future<int> addRoom({
    required String roomNumber,
    required String type,
    required double price,
    required String status,
    String? imageUrl,
  }) async {
    final roomId = await db
        .into(db.rooms)
        .insert(
          RoomsCompanion(
            roomNumber: d.Value(roomNumber),
            type: d.Value(type),
            price: d.Value(price),
            status: d.Value(status),
            imageUrl: d.Value(imageUrl),
          ),
        );

    // تشغيل النسخ التلقائي
    triggerAutoBackup(
      'rooms',
      'CREATE',
      recordData: {
        'id': roomId,
        'room_number': roomNumber,
        'type': type,
        'price': price,
        'status': status,
      },
    );

    return roomId;
  }

  Future<bool> updateRoomStatus(String roomNumber, String newStatus) async {
    final updatedRows =
        await (db.update(db.rooms)
              ..where((r) => r.roomNumber.equals(roomNumber)))
            .write(RoomsCompanion(status: d.Value(newStatus)));

    if (updatedRows > 0) {
      // تشغيل النسخ التلقائي
      triggerAutoBackup(
        'rooms',
        'UPDATE',
        recordData: {'room_number': roomNumber, 'new_status': newStatus},
      );
    }

    return updatedRows > 0;
  }
}

/// مثال على ExpensesRepository
class ExpensesRepositoryWithAutoBackup with AutoBackupMixin {
  ExpensesRepositoryWithAutoBackup(this.db);
  final AppDatabase db;

  Future<int> addExpense({
    required String expenseType,
    required String description,
    required double amount,
    required String date,
    int? relatedId,
  }) async {
    final expenseId = await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: d.Value(expenseType),
            description: d.Value(description),
            amount: d.Value(amount),
            date: d.Value(date),
            relatedId: d.Value(relatedId),
          ),
        );

    // تشغيل النسخ التلقائي
    triggerAutoBackup(
      'expenses',
      'CREATE',
      recordData: {
        'id': expenseId,
        'expense_type': expenseType,
        'amount': amount,
        'description': description,
      },
    );

    return expenseId;
  }
}
