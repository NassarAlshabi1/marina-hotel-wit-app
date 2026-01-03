import 'package:drift/drift.dart' as d;
import '../../utils/status_utils.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/rooms_dao.dart';
import '../auto_backup_manager.dart';

class RoomsRepository {
  RoomsRepository(this.db)
      : outbox = OutboxDao(db),
        dao = RoomsDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final RoomsDao dao;

  Stream<List<Room>> watchAll({String? search}) => dao.watchList(search: search);
  Stream<Room?> watchRoom(String roomNumber) => dao.watchByNumber(roomNumber);
  Stream<Room?> watchByNumber(String roomNumber) => dao.watchByNumber(roomNumber);

  Future<String> create({required String roomNumber, required String type, required double price, required String status, String? imageUrl}) async {
    final result = await dao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value(roomNumber),
        type: d.Value(type),
        price: d.Value(price),
        status: d.Value(status),
        imageUrl: d.Value(imageUrl),
      ),
    );
    AutoBackupManager.instance.onDataChange('rooms', 'INSERT', recordData: {'room_number': roomNumber});
    return result;
  }

  Future<int> update(int id, {String? type, double? price, String? status, String? imageUrl}) async {
    final result = await dao.updateById(
      id,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
    if (result > 0) {
      AutoBackupManager.instance.onDataChange('rooms', 'UPDATE', recordData: {'id': id});
    }
    return result;
  }
  
  Future<int> updateByRoomNumber(String roomNumber, {String? type, double? price, String? status, String? imageUrl}) async {
    final result = await dao.updateByNumber(
      roomNumber,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
    if (result > 0) {
      AutoBackupManager.instance.onDataChange('rooms', 'UPDATE', recordData: {'room_number': roomNumber});
    }
    return result;
  }

  Future<int> delete(String roomNumber) async {
    final result = await dao.softDelete(roomNumber);
    if (result > 0) {
      AutoBackupManager.instance.onDataChange('rooms', 'DELETE', recordData: {'room_number': roomNumber});
    }
    return result;
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

  Future<void> refreshAllRoomOccupancy() async {
    final bookings = await (db.select(db.bookings)..where((tbl) => tbl.deletedAt.isNull())).get();
    final occupiedRooms = <String>{};
    
    for (final booking in bookings) {
      if (StatusUtils.isActiveBooking(booking.status)) {
        occupiedRooms.add(booking.roomNumber);
      }
    }
    
    final rooms = await (db.select(db.rooms)..where((tbl) => tbl.deletedAt.isNull())).get();
    for (final room in rooms) {
      final shouldBeOccupied = occupiedRooms.contains(room.roomNumber);
      final isCurrentlyOccupied = StatusUtils.isRoomOccupied(room.status);
      final isCurrentlyAvailable = StatusUtils.isRoomAvailable(room.status);
      final target = StatusUtils.roomStatusForOccupancy(shouldBeOccupied);
      
      if (shouldBeOccupied && !isCurrentlyOccupied) {
        await updateByRoomNumber(room.roomNumber, status: target);
      } else if (!shouldBeOccupied && !isCurrentlyAvailable) {
        await updateByRoomNumber(room.roomNumber, status: target);
      }
    }
  }
}
