import 'package:drift/drift.dart' as d;

import '../../utils/status_utils.dart';
import '../auto_backup_manager.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../daos/rooms_dao.dart';
import '../local_db.dart';

class RoomsRepository {
  RoomsRepository(this.db) {
    outbox = OutboxDao(db);
    dao = RoomsDao(db, outbox);
  }
  final AppDatabase db;
  late final OutboxDao outbox;
  late final RoomsDao dao;

  Stream<List<Room>> watchAll({String? search}) =>
      dao.watchList(search: search);
  Stream<Room?> watchRoom(String roomNumber) => dao.watchByNumber(roomNumber);
  Stream<Room?> watchByNumber(String roomNumber) =>
      dao.watchByNumber(roomNumber);

  Future<String> create({
    required String roomNumber,
    required String type,
    required double price,
    required String status,
    String? imageUrl,
  }) async {
    try {
      final result = await dao.insertOne(
        RoomsCompanion(
          roomNumber: d.Value(roomNumber),
          type: d.Value(type),
          price: d.Value(price),
          status: d.Value(status),
          imageUrl: d.Value(imageUrl),
        ),
      );
      AutoBackupManager.instance.onDataChange(
        'rooms',
        'INSERT',
        recordData: {'room_number': roomNumber},
      );
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'RoomsRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'roomNumber': roomNumber, 'type': type},
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    String? type,
    double? price,
    String? status,
    String? imageUrl,
  }) async {
    try {
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
        AutoBackupManager.instance.onDataChange(
          'rooms',
          'UPDATE',
          recordData: {'id': id},
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'RoomsRepository',
        action: 'update',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  Future<int> updateByRoomNumber(
    String roomNumber, {
    String? type,
    double? price,
    String? status,
    String? imageUrl,
  }) async {
    try {
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
        AutoBackupManager.instance.onDataChange(
          'rooms',
          'UPDATE',
          recordData: {'room_number': roomNumber},
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'RoomsRepository',
        action: 'updateByRoomNumber',
        error: e,
        stackTrace: stack,
        extra: {'roomNumber': roomNumber},
      );
      rethrow;
    }
  }

  Future<int> delete(String roomNumber) async {
    try {
      // ✅ فحص وجود حجوزات نشطة قبل الحذف
      final activeBooking = await (db.select(db.bookings)
            ..where((b) => b.roomNumber.equals(roomNumber))
            ..where((b) => b.deletedAt.isNull())
            ..where((b) => b.status.isIn(StatusUtils.activeBookingStatuses))
            ..limit(1))
          .getSingleOrNull();
      if (activeBooking != null) {
        throw StateError(
          'لا يمكن حذف الغرفة $roomNumber: يوجد حجز نشط '
          '(الضيف: ${activeBooking.guestName})',
        );
      }
      final result = await dao.softDelete(roomNumber);
      if (result > 0) {
        AutoBackupManager.instance.onDataChange(
          'rooms',
          'DELETE',
          recordData: {'room_number': roomNumber},
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'RoomsRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'roomNumber': roomNumber},
      );
      rethrow;
    }
  }

  Future<int> updateStatus(int id, String status) async {
    return update(id, status: status);
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات الغرف
  Future<Map<String, dynamic>> exportData() async {
    final roomsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': roomsData, 'count': recordCount, 'entity': 'rooms'};
  }

  /// استيراد بيانات الغرف
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data'] as List),
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return dao.getRecordCount();
  }

  Future<void> refreshAllRoomOccupancy() async {
    final bookings = await (db.select(
      db.bookings,
    )..where((tbl) => tbl.deletedAt.isNull())).get();
    final occupiedRooms = <String>{};

    for (final booking in bookings) {
      if (StatusUtils.isActiveBooking(booking.status)) {
        occupiedRooms.add(booking.roomNumber);
      }
    }

    final rooms = await (db.select(
      db.rooms,
    )..where((tbl) => tbl.deletedAt.isNull())).get();
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
