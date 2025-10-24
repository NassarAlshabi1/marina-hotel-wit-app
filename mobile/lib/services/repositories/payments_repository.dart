import 'dart:async';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';
import '../backup_sync_service.dart';

class PaymentsRepository {
  PaymentsRepository(this.db, {BackupSyncService? backupSyncService})
      : outbox = OutboxDao(db),
        dao = PaymentsDao(db, OutboxDao(db)),
        _backupSyncService = backupSyncService;
  final AppDatabase db;
  final OutboxDao outbox;
  final PaymentsDao dao;
  final BackupSyncService? _backupSyncService;

  void _scheduleAutoBackup() {
    unawaited(_backupSyncService?.triggerAutoBackup());
  }

  Stream<List<Payment>> paymentsByBooking(int bookingLocalId) => dao.watchList(bookingLocalId: bookingLocalId);
  Stream<List<Payment>> watchAll({bool includeDeleted = false}) => dao.watchList(includeDeleted: includeDeleted);
  Stream<Payment?> watchOne(int id) => dao.watchById(id);

  Future<int> create({int? bookingLocalId, int? serverBookingId, String? roomNumber, required double amount, required String paymentDate, String? notes, required String paymentMethod, required String revenueType}) async {
    final id = await dao.insertOne(
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
    _scheduleAutoBackup();
    return id;
  }

  Future<int> update(int id, {int? bookingLocalId, int? serverBookingId, String? roomNumber, double? amount, String? paymentDate, String? notes, String? paymentMethod, String? revenueType}) async {
    final rows = await dao.updateById(
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
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  Future<int> delete(int id) async {
    final rows = await dao.softDelete(id);
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
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
      _scheduleAutoBackup();
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
    _scheduleAutoBackup();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return await dao.getRecordCount();
  }
}
