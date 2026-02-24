import 'package:drift/drift.dart' as d;
import '../booking_derived_fields_service.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/bookings_dao.dart';
import '../auto_backup_manager.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';

class BookingsRepository {
  BookingsRepository(this.db)
      : outbox = OutboxDao(db),
        dao = BookingsDao(db, OutboxDao(db)),
        derivedFields = BookingDerivedFieldsService(db);
  final AppDatabase db;
  final OutboxDao outbox;
  final BookingsDao dao;
  final BookingDerivedFieldsService derivedFields;

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
    double discount = 0,
    String discountType = 'per_night',
    String? discountStartDate,
  }) async {
    final result = await dao.insertOne(
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
        discount: d.Value(discount),
        discountType: d.Value(discountType),
        discountStartDate: d.Value(discountStartDate),
      ),
    );

    await derivedFields.refreshForBookingId(result);
    AutoBackupManager.instance.onDataChange(
      'bookings',
      'INSERT',
      recordData: {'id': result},
    );
    return result;
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
    double? discount,
    String? discountType,
    String? discountStartDate,
  }) async {
    final result = await dao.updateById(
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
        discount: discount != null ? d.Value(discount) : const d.Value.absent(),
        discountType: discountType != null
            ? d.Value(discountType)
            : const d.Value.absent(),
        discountStartDate: discountStartDate != null
            ? d.Value(discountStartDate)
            : const d.Value.absent(),
      ),
    );
    if (result > 0) {

      await derivedFields.refreshForBookingId(id);
      AutoBackupManager.instance.onDataChange(
        'bookings',
        'UPDATE',
        recordData: {'id': id},
      );
    }
    return result;
  }

  Future<int> delete(int id) async {
    final result = await dao.softDelete(id);
    if (result > 0) {
      AutoBackupManager.instance.onDataChange(
        'bookings',
        'DELETE',
        recordData: {'id': id},
      );
    }
    return result;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات الحجوزات
  Future<Map<String, dynamic>> exportData() async {
    final bookingsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': bookingsData, 'count': recordCount, 'entity': 'bookings'};
  }

  /// استيراد بيانات الحجوزات
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
    return dao.getRecordCount();
  }

  Future<void> syncLegacyDiscountToAdjustments(int bookingId) async {
    final booking = await (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingleOrNull();
    if (booking == null) return;

    final discount = booking.discount;
    if (discount <= 0 || booking.discountType == 'total') {
      return;
    }

    final effectiveHotelDay = Time.hotelDayKeyFromIso(
      booking.discountStartDate ?? booking.checkinDate,
    );

    final existing = await (db.select(db.bookingPriceAdjustments)
          ..where((a) => a.bookingLocalId.equals(bookingId))
          ..where((a) => a.isActive.equals(true))
          ..where((a) => a.deletedAt.isNull()))
        .get();

    final hasMatch = existing.any(
      (a) =>
          a.adjustmentType == 0 &&
          a.amount == discount &&
          a.effectiveHotelDay == effectiveHotelDay,
    );

    if (hasMatch) return;

    final now = Time.nowEpoch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.into(db.bookingPriceAdjustments).insert(
          BookingPriceAdjustmentsCompanion(
            localUuid: d.Value(IdGen.uuid()),
            bookingLocalUuid: d.Value(booking.localUuid),
            bookingLocalId: d.Value(booking.id),
            adjustmentType: const d.Value(0),
            amount: d.Value(discount),
            effectiveHotelDay: d.Value(effectiveHotelDay),
            isActive: const d.Value(true),
            reason: const d.Value('legacy_discount'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            createdAtIso: d.Value(nowIso),
            updatedAtIso: d.Value(nowIso),
            createdAtEpoch: d.Value(now),
            lastModifiedEpoch: d.Value(now),
          ),
        );
  }

  /// الحصول على الحجز النشط (المحجوز) للغرفة كما هو مخزن في SQLite
  Future<Booking?> getActiveBookingForRoom(String roomNumber) async {
    return (db.select(db.bookings)
          ..where((b) => b.roomNumber.equals(roomNumber))
          ..where((b) => b.status.equals('محجوزة'))
          ..orderBy([(b) => d.OrderingTerm.desc(b.checkinDate)])
          ..limit(1))
        .getSingleOrNull();
  }
}
