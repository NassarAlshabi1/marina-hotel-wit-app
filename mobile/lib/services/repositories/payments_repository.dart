import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';
import '../auto_backup_manager.dart';
import '../sync_guardian.dart';

class PaymentsRepository {
  PaymentsRepository(this.db)
      : outbox = OutboxDao(db),
        dao = PaymentsDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final PaymentsDao dao;

  Stream<List<Payment>> paymentsByBooking(int bookingLocalId) => dao.watchList(bookingLocalId: bookingLocalId);
  Stream<List<Payment>> watchAll({bool includeDeleted = false}) => dao.watchList(includeDeleted: includeDeleted);
  Stream<Payment?> watchOne(int id) => dao.watchById(id);

  Future<int> create({int? bookingLocalId, int? serverBookingId, String? roomNumber, required double amount, required String paymentDate, String? notes, required String paymentMethod, required String revenueType}) async {
    debugPrint('PaymentsRepository.create: bookingLocalId=$bookingLocalId, amount=$amount, method=$paymentMethod');
    try {
      final result = await dao.insertOne(
        PaymentsCompanion(
          bookingLocalId: d.Value(bookingLocalId),
          serverBookingId: d.Value(serverBookingId),
          roomNumber: d.Value(roomNumber),
          amount: d.Value(amount),
          paymentDate: d.Value(paymentDate),
          notes: d.Value(notes),
          paymentMethod: d.Value(paymentMethod),
          revenueType: d.Value(revenueType),
        ),
      );
      debugPrint('PaymentsRepository.create: success, id=$result');
      AutoBackupManager.instance.onDataChange('payments', 'INSERT', recordData: {'amount': amount});
      SyncGuardian.instance.notifyLocalChange(table: 'payments', operation: 'INSERT');
      return result;
    } catch (e, stackTrace) {
      debugPrint('PaymentsRepository.create: error=$e');
      debugPrint('StackTrace: $stackTrace');
      rethrow;
    }
  }

  Future<int> update(int id, {int? bookingLocalId, int? serverBookingId, String? roomNumber, double? amount, String? paymentDate, String? notes, String? paymentMethod, String? revenueType}) async {
    final result = await dao.updateById(
      id,
      PaymentsCompanion(
        bookingLocalId: d.Value(bookingLocalId),
        serverBookingId: d.Value(serverBookingId),
        roomNumber: d.Value(roomNumber),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        paymentDate: paymentDate != null ? d.Value(paymentDate) : const d.Value.absent(),
        notes: notes != null ? d.Value(notes) : const d.Value.absent(),
        paymentMethod: paymentMethod != null ? d.Value(paymentMethod) : const d.Value.absent(),
        revenueType: revenueType != null ? d.Value(revenueType) : const d.Value.absent(),
      ),
    );
    if (result > 0) {
      AutoBackupManager.instance.onDataChange('payments', 'UPDATE', recordData: {'id': id});
      SyncGuardian.instance.notifyLocalChange(table: 'payments', operation: 'UPDATE');
    }
    return result;
  }

  Future<int> delete(int id) async {
    final result = await dao.softDelete(id);
    if (result > 0) {
      AutoBackupManager.instance.onDataChange('payments', 'DELETE', recordData: {'id': id});
      SyncGuardian.instance.notifyLocalChange(table: 'payments', operation: 'DELETE');
    }
    return result;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المدفوعات
  Future<Map<String, dynamic>> exportData() async {
    final paymentsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();
    
    return {
      'data': paymentsData,
      'count': recordCount,
      'entity': 'payments',
    };
  }

  /// استيراد بيانات المدفوعات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data']), 
        clearExisting: false,
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return await dao.getRecordCount();
  }

  /// الحصول على إجمالي المدفوعات لتاريخ محدد
  Future<double> getTotalByDate(String date) async {
    final payments = await dao.listByDate(date);
    double total = 0;
    for (final payment in payments) {
      total += payment.amount;
    }
    return total;
  }
}
