import 'dart:async';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/rooms_dao.dart';
import '../backup_sync_service.dart';

class RoomsRepository {
  RoomsRepository(this.db, {BackupSyncService? backupSyncService})
      : outbox = OutboxDao(db),
        dao = RoomsDao(db, OutboxDao(db)),
        _backupSyncService = backupSyncService;
  final AppDatabase db;
  final OutboxDao outbox;
  final RoomsDao dao;
  final BackupSyncService? _backupSyncService;

  void _scheduleAutoBackup() {
    unawaited(_backupSyncService?.triggerAutoBackup());
  }

  Stream<List<Room>> watchAll({String? search}) => dao.watchList(search: search);
  Stream<Room?> watchRoom(String roomNumber) => dao.watchByNumber(roomNumber);
  Stream<Room?> watchByNumber(String roomNumber) => dao.watchByNumber(roomNumber);

  Future<String> create({required String roomNumber, required String type, required double price, required String status, String? imageUrl}) async {
    final value = await dao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value(roomNumber),
        type: d.Value(type),
        price: d.Value(price),
        status: d.Value(status),
        imageUrl: d.Value(imageUrl),
      ),
    );
    _scheduleAutoBackup();
    return value;
  }

  Future<int> update(int id, {String? type, double? price, String? status, String? imageUrl}) async {
    final rows = await dao.updateById(
      id,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }
  
  Future<int> updateByRoomNumber(String roomNumber, {String? type, double? price, String? status, String? imageUrl}) async {
    final rows = await dao.updateByNumber(
      roomNumber,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  Future<int> delete(String roomNumber) async {
    final rows = await dao.softDelete(roomNumber);
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات الغرف
  Future<Map<String, dynamic>> exportData() async {
    final roomsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();
    
    return {
      'data': roomsData,
      'count': recordCount,
      'entity': 'rooms',
    };
  }

  /// استيراد بيانات الغرف
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
