import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';
import '../booking_derived_fields_service.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';
import 'base_repository.dart';
import '../../utils/time.dart';

class PaymentsRepository extends BaseRepository<Payment, PaymentsCompanion> {
  PaymentsRepository(this.db)
      : outbox = OutboxDao(db),
        dao = PaymentsDao(db, OutboxDao(db)),
        derivedFields = BookingDerivedFieldsService(db);
  final AppDatabase db;
  final OutboxDao outbox;
  final PaymentsDao dao;
  final BookingDerivedFieldsService derivedFields;

  @override
  String get tableName => 'payments';

  Stream<List<Payment>> paymentsByBooking(int bookingLocalId) {
    final bookingStream = (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingLocalId)))
        .watchSingleOrNull();

    return bookingStream.asyncExpand((booking) {
      final q = db.select(db.payments);
      q.where((p) => p.deletedAt.isNull());

      if (booking == null) {
        q.where((p) => p.bookingLocalId.equals(bookingLocalId));
      } else {
        final byLocalId = db.payments.bookingLocalId.equals(bookingLocalId);
        final byUuid = db.payments.bookingUuidCache.equals(booking.localUuid);
        q.where((p) => byLocalId | byUuid);
      }

      q.orderBy([(p) => d.OrderingTerm.desc(p.paymentDate)]);
      return q.watch();
    });
  }

  Stream<List<Payment>> watchAll({bool includeDeleted = false}) =>
      dao.watchList(includeDeleted: includeDeleted);
  Stream<Payment?> watchOne(int id) => dao.watchById(id);

  Future<int> create(
      {int? bookingLocalId,
      int? serverBookingId,
      String? roomNumber,
      required double amount,
      required String paymentDate,
      String? notes,
      required String paymentMethod,
      required String revenueType}) async {
    final hotelDayKey = Time.hotelDayKeyFromIso(paymentDate);

    String? bookingUuidCache;
    if (bookingLocalId != null) {
      final booking = await (db.select(db.bookings)
            ..where((b) => b.id.equals(bookingLocalId)))
          .getSingleOrNull();
      bookingUuidCache = booking?.localUuid;
    }

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
        hotelDayKey: d.Value(hotelDayKey),
        bookingUuidCache: d.Value(bookingUuidCache),
      ),
    );
    if (bookingLocalId != null) {
      try {
        await derivedFields.refreshForBookingId(bookingLocalId);
      } catch (e) {
        debugPrint('⚠️ فشل تحديث الحقول المشتقة للحجز $bookingLocalId: $e');
      }
    }
    await notifyBackup('INSERT', {'amount': amount});
    return result;
  }

  Future<int> update(int id,
      {int? bookingLocalId,
      int? serverBookingId,
      String? roomNumber,
      double? amount,
      String? paymentDate,
      String? notes,
      String? paymentMethod,
      String? revenueType}) async {
    final before = await (db.select(db.payments)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    final oldBookingId = before?.bookingLocalId;

    final hotelDayKey =
        paymentDate != null ? Time.hotelDayKeyFromIso(paymentDate) : null;
    final result = await dao.updateById(
      id,
      PaymentsCompanion(
        bookingLocalId: bookingLocalId != null
            ? d.Value(bookingLocalId)
            : const d.Value.absent(),
        serverBookingId: serverBookingId != null
            ? d.Value(serverBookingId)
            : const d.Value.absent(),
        roomNumber:
            roomNumber != null ? d.Value(roomNumber) : const d.Value.absent(),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        paymentDate:
            paymentDate != null ? d.Value(paymentDate) : const d.Value.absent(),
        notes: notes != null ? d.Value(notes) : const d.Value.absent(),
        paymentMethod: paymentMethod != null
            ? d.Value(paymentMethod)
            : const d.Value.absent(),
        revenueType:
            revenueType != null ? d.Value(revenueType) : const d.Value.absent(),
        hotelDayKey:
            hotelDayKey != null ? d.Value(hotelDayKey) : const d.Value.absent(),
      ),
    );
    if (result > 0) {
      final newBookingId = bookingLocalId ?? oldBookingId;
      final bookingIds = <int>{};
      if (oldBookingId != null) {
        bookingIds.add(oldBookingId);
      }
      if (newBookingId != null) {
        bookingIds.add(newBookingId);
      }
      for (final bId in bookingIds) {
        try {
          await derivedFields.refreshForBookingId(bId);
        } catch (e) {
          debugPrint('⚠️ فشل تحديث الحقول المشتقة للحجز $bId: $e');
        }
      }
      await notifyBackup('UPDATE', {'id': id});
    }
    return result;
  }

  Future<int> delete(int id) async {
    final payment = await (db.select(db.payments)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    final bookingId = payment?.bookingLocalId;

    final result = await dao.softDelete(id);
    if (result > 0) {
      if (bookingId != null) {
        try {
          await derivedFields.refreshForBookingId(bookingId);
        } catch (e) {
          debugPrint('⚠️ فشل تحديث الحقول المشتقة للحجز $bookingId: $e');
        }
      }
      await notifyBackup('DELETE', {'id': id});
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

  Future<double> getTotalByHotelDayKey(String hotelDayKey,
      {String? revenueType}) async {
    final payments =
        await dao.listByHotelDayKey(hotelDayKey, revenueType: revenueType);
    double total = 0;
    for (final payment in payments) {
      total += payment.amount;
    }
    return total;
  }
}
