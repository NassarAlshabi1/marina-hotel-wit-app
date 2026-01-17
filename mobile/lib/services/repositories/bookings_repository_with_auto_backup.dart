import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../auto_backup_manager.dart';
import '../daos/outbox_dao.dart';
import '../daos/bookings_dao.dart';

/// Repository للحجوزات مع دعم النسخ التلقائي
class BookingsRepositoryWithAutoBackup {
  BookingsRepositoryWithAutoBackup(this.db)
      : outbox = OutboxDao(db),
        dao = BookingsDao(db, OutboxDao(db));

  final AppDatabase db;
  final OutboxDao outbox;
  final BookingsDao dao;

  Stream<List<Booking>> watch({String? roomNumber, String? status}) =>
      dao.watchList(roomNumber: roomNumber, status: status);
  Stream<List<Booking>> watchList({String? roomNumber, String? status}) =>
      dao.watchList(roomNumber: roomNumber, status: status);
  Stream<Booking?> watchOne(int id) => dao.watchById(id);

  Future<int> create({
    required String roomNumber,
    required String guestName,
    required String guestPhone,
    String guestIdType = 'بطاقة شخصية',
    String guestIdNumber = '',
    String? guestIdIssueDate,
    String? guestIdIssuePlace,
    required String guestNationality,
    String? guestEmail,
    String? guestAddress,
    required String checkinDate,
    String? checkoutDate,
    String? actualCheckout,
    required String status,
    String? notes,
    int expectedNights = 1,
    int? calculatedNights,
  }) async {
    final bookingId = await dao.insertOne(
      BookingsCompanion(
        roomNumber: d.Value(roomNumber),
        guestName: d.Value(guestName),
        guestPhone: d.Value(guestPhone),
        guestIdType: d.Value(guestIdType),
        guestIdNumber: d.Value(guestIdNumber),
        guestIdIssueDate: d.Value(guestIdIssueDate),
        guestIdIssuePlace: d.Value(guestIdIssuePlace),
        guestNationality: d.Value(guestNationality),
        guestEmail: d.Value(guestEmail),
        guestAddress: d.Value(guestAddress),
        checkinDate: d.Value(checkinDate),
        checkoutDate: d.Value(checkoutDate),
        actualCheckout: d.Value(actualCheckout),
        status: d.Value(status),
        notes: d.Value(notes),
        expectedNights: d.Value(expectedNights),
        calculatedNights: calculatedNights != null
            ? d.Value(calculatedNights)
            : const d.Value.absent(),
      ),
    );

    // تسجيل التغيير للنسخ التلقائي
    AutoBackupManager.instance.onDataChange(
      'bookings',
      'CREATE',
      recordData: {
        'id': bookingId,
        'guest_name': guestName,
        'room_number': roomNumber,
        'status': status,
      },
    );

    return bookingId;
  }

  Future<int> update(
    int id, {
    String? roomNumber,
    String? guestName,
    String? guestPhone,
    String? guestIdType,
    String? guestIdNumber,
    String? guestIdIssueDate,
    String? guestIdIssuePlace,
    String? guestNationality,
    String? guestEmail,
    String? guestAddress,
    String? checkinDate,
    String? checkoutDate,
    String? actualCheckout,
    String? status,
    String? notes,
    int? expectedNights,
    int? calculatedNights,
  }) async {
    final updatedRows = await dao.updateById(
      id,
      BookingsCompanion(
        roomNumber:
            roomNumber != null ? d.Value(roomNumber) : const d.Value.absent(),
        guestName:
            guestName != null ? d.Value(guestName) : const d.Value.absent(),
        guestPhone:
            guestPhone != null ? d.Value(guestPhone) : const d.Value.absent(),
        guestIdType:
            guestIdType != null ? d.Value(guestIdType) : const d.Value.absent(),
        guestIdNumber: guestIdNumber != null
            ? d.Value(guestIdNumber)
            : const d.Value.absent(),
        guestIdIssueDate: guestIdIssueDate != null
            ? d.Value(guestIdIssueDate)
            : const d.Value.absent(),
        guestIdIssuePlace: guestIdIssuePlace != null
            ? d.Value(guestIdIssuePlace)
            : const d.Value.absent(),
        guestNationality: guestNationality != null
            ? d.Value(guestNationality)
            : const d.Value.absent(),
        guestEmail:
            guestEmail != null ? d.Value(guestEmail) : const d.Value.absent(),
        guestAddress: guestAddress != null
            ? d.Value(guestAddress)
            : const d.Value.absent(),
        checkinDate:
            checkinDate != null ? d.Value(checkinDate) : const d.Value.absent(),
        checkoutDate: checkoutDate != null
            ? d.Value(checkoutDate)
            : const d.Value.absent(),
        actualCheckout: actualCheckout != null
            ? d.Value(actualCheckout)
            : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        notes: notes != null ? d.Value(notes) : const d.Value.absent(),
        expectedNights: expectedNights != null
            ? d.Value(expectedNights)
            : const d.Value.absent(),
        calculatedNights: calculatedNights != null
            ? d.Value(calculatedNights)
            : const d.Value.absent(),
      ),
    );

    if (updatedRows > 0) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'bookings',
        'UPDATE',
        recordData: {
          'id': id,
          'guest_name': guestName,
          'room_number': roomNumber,
          'status': status,
        },
      );
    }

    return updatedRows;
  }

  Future<bool> delete(int id) async {
    // الحصول على بيانات الحجز قبل الحذف
    final booking = await (db.select(db.bookings)
          ..where((b) => b.id.equals(id)))
        .getSingleOrNull();

    final deletedRows = await dao.deleteById(id);

    if (deletedRows > 0 && booking != null) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'bookings',
        'DELETE',
        recordData: {
          'id': id,
          'guest_name': booking.guestName,
          'room_number': booking.roomNumber,
          'status': booking.status,
        },
      );
    }

    return deletedRows > 0;
  }

  // باقي الدوال بدون تعديل
  Future<Booking?> getById(int id) => dao.getById(id);
  Future<List<Booking>> getByRoomNumber(String roomNumber) =>
      dao.getByRoomNumber(roomNumber);
  Future<List<Booking>> getByStatus(String status) => dao.getByStatus(status);
  Future<List<Booking>> getAll() => dao.getAll();
}
