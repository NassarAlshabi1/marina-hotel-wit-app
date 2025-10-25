import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/rooms_dao.dart';

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

  Future<String> create({required String roomNumber, required String type, required double price, required String status, String? imageUrl}) {
    return dao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value(roomNumber),
        type: d.Value(type),
        price: d.Value(price),
        status: d.Value(status),
        imageUrl: d.Value(imageUrl),
      ),
    );
  }

  Future<int> update(int id, {String? type, double? price, String? status, String? imageUrl}) {
    return dao.updateById(
      id,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
  }
  
  Future<int> updateByRoomNumber(String roomNumber, {String? type, double? price, String? status, String? imageUrl}) {
    return dao.updateByNumber(
      roomNumber,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
  }

  Future<int> delete(String roomNumber) => dao.softDelete(roomNumber);

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
}
