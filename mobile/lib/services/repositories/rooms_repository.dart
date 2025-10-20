import 'package:drift/drift.dart' as d;
import '../drive_backup_service.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/rooms_dao.dart';

class RoomsRepository {
  RoomsRepository(this.db, this.backupService)
      : outbox = OutboxDao(db),
        dao = RoomsDao(db, OutboxDao(db));
  final AppDatabase db;
  final GoogleDriveBackupService backupService;
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
    backupService.scheduleAutoBackup('rooms-create');
    return result;
  }

  Future<int> update(int id, {String? type, double? price, String? status, String? imageUrl}) async {
    final affected = await dao.updateById(
      id,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
    if (affected > 0) {
      backupService.scheduleAutoBackup('rooms-update');
    }
    return affected;
  }

  Future<int> updateByRoomNumber(String roomNumber, {String? type, double? price, String? status, String? imageUrl}) async {
    final affected = await dao.updateByNumber(
      roomNumber,
      RoomsCompanion(
        type: type != null ? d.Value(type) : const d.Value.absent(),
        price: price != null ? d.Value(price) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        imageUrl: imageUrl != null ? d.Value(imageUrl) : const d.Value.absent(),
      ),
    );
    if (affected > 0) {
      backupService.scheduleAutoBackup('rooms-update');
    }
    return affected;
  }

  Future<int> delete(String roomNumber) async {
    final affected = await dao.softDelete(roomNumber);
    if (affected > 0) {
      backupService.scheduleAutoBackup('rooms-delete');
    }
    return affected;
  }
}
