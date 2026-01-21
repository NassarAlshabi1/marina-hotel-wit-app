import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'local_db.dart';
import 'daos/bookings_dao.dart';
import 'daos/rooms_dao.dart';
import 'daos/payments_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/debts_dao.dart';
import '../utils/time.dart';
import '../utils/status_utils.dart';
import '../utils/id.dart';

/// نموذج لتخزين معلومات اللقطة الاحتياطية
class RestoreSnapshot {
  final String filePath;
  final DateTime createdAt;
  final Map<String, int> recordCounts;
  final int totalSizeBytes;

  RestoreSnapshot({
    required this.filePath,
    required this.createdAt,
    required this.recordCounts,
    required this.totalSizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'recordCounts': recordCounts,
        'totalSizeBytes': totalSizeBytes,
      };

  factory RestoreSnapshot.fromJson(Map<String, dynamic> json) =>
      RestoreSnapshot(
        filePath: json['filePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        recordCounts: Map<String, int>.from(json['recordCounts'] as Map),
        totalSizeBytes: json['totalSizeBytes'] as int,
      );
}

/// تقرير شامل عن عملية الإصلاح التلقائي
class RestoreFixReport {
  final bool success;
  final int bookingsFixed;
  final int roomsUpdated;
  final int paymentsRecalculated;
  final List<String> changes;
  final String? error;
  final DateTime executedAt;
  final int durationMs;

  RestoreFixReport({
    required this.success,
    required this.bookingsFixed,
    required this.roomsUpdated,
    required this.paymentsRecalculated,
    required this.changes,
    this.error,
    required this.executedAt,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'bookingsFixed': bookingsFixed,
        'roomsUpdated': roomsUpdated,
        'paymentsRecalculated': paymentsRecalculated,
        'changes': changes,
        'error': error,
        'executedAt': executedAt.toIso8601String(),
        'durationMs': durationMs,
      };

  factory RestoreFixReport.fromJson(Map<String, dynamic> json) =>
      RestoreFixReport(
        success: json['success'] as bool,
        bookingsFixed: json['bookingsFixed'] as int,
        roomsUpdated: json['roomsUpdated'] as int,
        paymentsRecalculated: json['paymentsRecalculated'] as int,
        changes: List<String>.from(json['changes'] as List),
        error: json['error'] as String?,
        executedAt: DateTime.parse(json['executedAt'] as String),
        durationMs: json['durationMs'] as int,
      );
}

/// خدمة الإصلاح التلقائي للنسخة الاحتياطية
/// تقوم بإعادة حساب الليالي، حالات الغرف، والمدفوعات بعد استعادة النسخة الاحتياطية
class RestoreFixService {
  final AppDatabase db;
  final BookingsDao bookingsDao;
  final RoomsDao roomsDao;
  final PaymentsDao paymentsDao;
  final DebtsDao debtsDao;
  final Future<void> Function()? onBeforeCommit;
  bool _conflictTableReady = false;

  RestoreFixService(this.db, {this.onBeforeCommit})
      : bookingsDao = BookingsDao(db, OutboxDao(db)),
        roomsDao = RoomsDao(db, OutboxDao(db)),
        paymentsDao = PaymentsDao(db, OutboxDao(db)),
        debtsDao = DebtsDao(db, OutboxDao(db));

  /// إنشاء لقطة احتياطية محلية قبل بدء عملية الإصلاح
  Future<RestoreSnapshot> createLocalSnapshot(String prefix) async {
    debugPrint(
        '📸 إنشاء لقطة احتياطية أمان: ${prefix}_restore_snapshot_${Time.nowEpoch()}.json');

    return await db.transaction<RestoreSnapshot>(() async {
      final directory = await getApplicationCacheDirectory();
      final timestamp = Time.nowEpoch();
      final filename = '${prefix}_restore_snapshot_$timestamp.json';
      final filePath = '${directory.path}/$filename';

      try {
        final bookingsData = await bookingsDao.exportToJson();
        final roomsData = await roomsDao.exportToJson();
        final paymentsData = await paymentsDao.exportToJson();
        final debtsData = await debtsDao.exportToJson(includeDeleted: true);

        final snapshotData = {
          'metadata': {
            'timestamp': timestamp,
            'createdAt': DateTime.now().toIso8601String(),
            'deviceId': 'local_device',
            'version': '1.0',
          },
          'bookings': bookingsData,
          'rooms': roomsData,
          'payments': paymentsData,
          'debts': debtsData,
        };

        final jsonString = jsonEncode(snapshotData);
        final file = File(filePath);
        await file.writeAsString(jsonString);

        final recordCounts = {
          'bookings': bookingsData.length,
          'rooms': roomsData.length,
          'payments': paymentsData.length,
          'debts': debtsData.length,
        };

        return RestoreSnapshot(
          filePath: filePath,
          createdAt: DateTime.now(),
          recordCounts: recordCounts,
          totalSizeBytes: await file.length(),
        );
      } catch (e) {
        debugPrint('❌ خطأ في إنشاء اللقطة الاحتياطية: $e');
        rethrow;
      }
    });
  }

  /// الدالة الرئيسية لتشغيل الإصلاح التلقائي
  Future<RestoreFixReport> runAutoFixAfterRestore(
      {DateTime? backupTimestamp}) async {
    debugPrint('🔄 بدء عملية الإصلاح التلقائي للنسخة الاحتياطية...');

    final startTime = DateTime.now();
    int bookingsFixed = 0;
    int roomsUpdated = 0;
    int paymentsChecked = 0;
    List<String> changes = [];
    RestoreSnapshot? snapshot;

    try {
      // إنشاء لقطة احتياطية للأمان
      snapshot = await createLocalSnapshot('auto_fix');

      // تنفيذ الإصلاح داخل معاملة واحدة
      await db.transaction(() async {
        final now = DateTime.now();
        final fixId = IdGen.uuid();

        // البحث عن الحجوزات التي تحتاج إصلاح
        final bookingsToFix =
            await _getBookingsNeedingFix(backupTimestamp, now);
        debugPrint('🔍 العثور على ${bookingsToFix.length} حجز يحتاج إلى إصلاح');

        for (final booking in bookingsToFix) {
          final bookingChanges =
              await _fixBookingDatesAndNights(booking, now, fixId);
          if (bookingChanges.isNotEmpty) {
            bookingsFixed++;
            changes.addAll(bookingChanges);
          }

          final updatedBooking = await (db.select(db.bookings)
                ..where((b) => b.id.equals(booking.id)))
              .getSingleOrNull();

          if (updatedBooking != null) {
            final paymentChanges =
                await _recalculateBookingFinancials(updatedBooking, fixId);
            if (paymentChanges.isNotEmpty) {
              paymentsChecked++;
              changes.addAll(paymentChanges);
            }
          }
        }

        // تحديث حالات الغرف
        final roomChanges = await _updateRoomStatusesFromBookings(fixId);
        changes.addAll(roomChanges);

        final _BookingStructuresResult structuresResult =
            await _rebuildBookingStructures(now);
        changes.addAll(structuresResult.changes);
        roomsUpdated = roomChanges.length + structuresResult.roomsTouched;
        paymentsChecked += structuresResult.paymentsProcessed;

        if (onBeforeCommit != null) {
          await onBeforeCommit!();
        }
      });

      // حذف اللقطة الاحتياطية عند النجاح
      final snapshotPath = snapshot?.filePath;
      if (snapshotPath != null) {
        await _deleteSnapshot(snapshotPath);
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      debugPrint('✅ اكتمل الإصلاح التلقائي بنجاح');
      debugPrint('📊 الإحصائيات:');
      debugPrint('   - الحجوزات المصلحة: $bookingsFixed');
      debugPrint('   - الغرف المحدثة: $roomsUpdated');
      debugPrint('   - الدفعات المتحقق منها: $paymentsChecked');
      debugPrint('   - المدة: ${(duration / 1000).toStringAsFixed(1)} ثانية');

      return RestoreFixReport(
        success: true,
        bookingsFixed: bookingsFixed,
        roomsUpdated: roomsUpdated,
        paymentsRecalculated: paymentsChecked,
        changes: changes,
        executedAt: startTime,
        durationMs: duration,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ فشل الإصلاح التلقائي: $e');
      debugPrint('Stack trace: $stackTrace');

      // استعادة اللقطة الاحتياطية في حالة الفشل
      final snapshotPath = snapshot?.filePath;
      if (snapshotPath != null) {
        try {
          await _restoreFromSnapshot(snapshotPath);
          debugPrint('✅ تم استعادة البيانات من اللقطة الاحتياطية');
        } catch (restoreError) {
          debugPrint('❌ فشل في استعادة اللقطة الاحتياطية: $restoreError');
        }
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      return RestoreFixReport(
        success: false,
        bookingsFixed: 0,
        roomsUpdated: 0,
        paymentsRecalculated: 0,
        changes: [],
        error: e.toString(),
        executedAt: startTime,
        durationMs: duration,
      );
    }
  }

  /// البحث عن الحجوزات التي تحتاج إصلاح
  Future<List<Booking>> _getBookingsNeedingFix(
      DateTime? backupDate, DateTime now) async {
    final query = db.select(db.bookings);

    // استثناء الحجوزات المحذوفة
    query.where((b) => b.deletedAt.isNull());

    // البحث عن الحجوزات النشطة (لم تسجل مغادرة فعلية)
    query.where((b) => b.actualCheckout.isNull());

    // تصفية الحجوزات النشطة فقط - سيتم التحقق باستخدام StatusUtils بعد الاستعلام

    // التأكد من وجود تاريخ الدخول
    query.where((b) => b.checkinDate.isNotNull());

    final allBookings = await query.get();

    // تصفية الحجوزات النشطة باستخدام StatusUtils
    return allBookings
        .where((b) => StatusUtils.isActiveBooking(b.status))
        .toList();
  }

  /// إصلاح تواريخ وليالي الحجز
  Future<List<String>> _fixBookingDatesAndNights(
      Booking booking, DateTime now, String fixId) async {
    List<String> changes = [];

    try {
      // تحليل تواريخ الدخول والخروج
      final checkinDate = DateTime.parse(booking.checkinDate);
      final checkoutDate = booking.actualCheckout != null
          ? DateTime.parse(booking.actualCheckout!)
          : now;

      // حساب الليالي باستخدام قاعدة الساعة 14:00
      final calculatedNights =
          Time.nightsWithCutoff(checkinDate, checkout: checkoutDate);

      // مقارنة مع القيم الحالية
      if (calculatedNights != booking.calculatedNights ||
          calculatedNights != booking.expectedNights) {
        // تسجيل التغيير
        await _logChange(
          fixId: fixId,
          targetTable: 'bookings',
          targetRecordId: booking.id,
          fieldName: 'calculatedNights',
          oldValue: booking.calculatedNights.toString(),
          newValue: calculatedNights.toString(),
          reason:
              'إعادة حساب الليالي بناءً على تاريخ الدخول والخروج مع قاعدة 14:00',
          fixType: 'nights_recalc',
        );

        await _logConflict(
          fixId: fixId,
          tableName: 'bookings',
          fixType: 'nights_recalc',
          localUuid: booking.localUuid,
          oldData: {
            'calculated_nights': booking.calculatedNights,
            'expected_nights': booking.expectedNights,
          },
          newData: {
            'calculated_nights': calculatedNights,
            'expected_nights': calculatedNights,
          },
        );

        await bookingsDao.updateById(
          booking.id,
          BookingsCompanion(
            calculatedNights: Value(calculatedNights),
            expectedNights: Value(calculatedNights),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ),
          originIsServer: false,
        );

        final changeMsg =
            'إصلاح الحجز #${booking.id}: تحديث الليالي من ${booking.calculatedNights} إلى $calculatedNights';
        changes.add(changeMsg);
        debugPrint('✏️ $changeMsg');
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في إصلاح الحجز #${booking.id}: $e');
    }

    return changes;
  }

  /// إعادة حساب المعاملات المالية للحجز
  Future<List<String>> _recalculateBookingFinancials(
      Booking booking, String fixId) async {
    final changes = <String>[];
    try {
      final payments = await (db.select(db.payments)
            ..where((p) => p.bookingLocalId.equals(booking.id))
            ..where((p) => p.deletedAt.isNull()))
          .get();
      final totalPaid =
          payments.fold<double>(0.0, (sum, payment) => sum + payment.amount);
      final room = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(booking.roomNumber)))
          .getSingleOrNull();
      double? expectedTotal;
      if (room != null) {
        expectedTotal = booking.calculatedNights * room.price;
        final remainingBalance = expectedTotal - totalPaid;
        final isFullyPaid = remainingBalance <= 0;

        if (booking.totalDueCached != expectedTotal ||
            booking.totalPaidCached != totalPaid ||
            booking.remainingBalanceCached != remainingBalance ||
            booking.isFullyPaid != isFullyPaid) {
          await bookingsDao.updateById(
            booking.id,
            BookingsCompanion(
              totalDueCached: Value(expectedTotal),
              totalPaidCached: Value(totalPaid),
              remainingBalanceCached: Value(remainingBalance),
              isFullyPaid: Value(isFullyPaid),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
            originIsServer: false,
          );

          changes.add(
              'تحديث المبالغ المخزنة للحجز #${booking.id}: الإجمالي=${expectedTotal.toStringAsFixed(2)}, المدفوع=${totalPaid.toStringAsFixed(2)}, المتبقي=${remainingBalance.toStringAsFixed(2)}');
          debugPrint('💰 ${changes.last}');
        }

        if ((totalPaid - expectedTotal).abs() > 0.01) {
          await _logChange(
            fixId: fixId,
            targetTable: 'payments',
            targetRecordId: booking.id,
            fieldName: 'amount_check',
            oldValue: totalPaid.toString(),
            newValue: expectedTotal.toString(),
            reason:
                'مبلغ الدفع لا يتطابق مع المبلغ المتوقع (${booking.calculatedNights} × ${room.price})',
            fixType: 'payment_check',
          );
          await _logConflict(
            fixId: fixId,
            tableName: 'payments',
            fixType: 'payment_check',
            localUuid: booking.localUuid,
            oldData: {
              'total_paid': totalPaid,
            },
            newData: {
              'expected_total': expectedTotal,
            },
          );
          final warningMsg =
              'تنبيه: الحجز #${booking.id} - إجمالي المدفوعات (${totalPaid.toStringAsFixed(2)}) لا يتطابق مع المتوقع (${expectedTotal.toStringAsFixed(2)})';
          changes.add(warningMsg);
          debugPrint('⚠️ $warningMsg');
        }
      }

      final debts = await (db.select(db.debts)
            ..where((d) => d.bookingLocalId.equals(booking.id))
            ..where((d) => d.deletedAt.isNull()))
          .get();
      if (debts.isNotEmpty && expectedTotal != null) {
        final expectedCents = (expectedTotal * 100).round();
        final paidCents = (totalPaid * 100).round();
        final remainingCents = expectedCents - paidCents;
        final isSettled = remainingCents <= 0 ? 1 : 0;
        for (final debt in debts) {
          final debtTotalCents = (debt.totalAmount * 100).round();
          final debtPaidCents = (debt.paidAmount * 100).round();
          final debtRemainingCents = (debt.remainingAmount * 100).round();
          final shouldUpdate = debtTotalCents != expectedCents ||
              debtPaidCents != paidCents ||
              debtRemainingCents != remainingCents ||
              debt.isSettled != isSettled;
          if (shouldUpdate) {
            await _logConflict(
              fixId: fixId,
              tableName: 'debts',
              fixType: 'debt_recalc',
              localUuid: debt.localUuid,
              oldData: {
                'total_amount': debt.totalAmount,
                'paid_amount': debt.paidAmount,
                'remaining_amount': debt.remainingAmount,
                'is_settled': debt.isSettled,
              },
              newData: {
                'total_amount': expectedTotal,
                'paid_amount': totalPaid,
                'remaining_amount': remainingCents / 100,
                'is_settled': isSettled,
              },
            );
            await (db.update(db.debts)..where((t) => t.id.equals(debt.id)))
                .write(DebtsCompanion(
              totalAmount: Value(expectedCents / 100),
              paidAmount: Value(paidCents / 100),
              remainingAmount: Value(remainingCents / 100),
              isSettled: Value(isSettled),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ));
            changes.add(
                'إعادة احتساب الدين للحجز #${booking.id}: المتبقي ${(remainingCents / 100).toStringAsFixed(2)}، تم ${isSettled == 1 ? 'إغلاق الدين' : 'تحديثه'}');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في فحص المدفوعات للحجز #${booking.id}: $e');
    }
    return changes;
  }

  /// تحديث حالات الغرف بناءً على الحجوزات النشطة
  Future<List<String>> _updateRoomStatusesFromBookings(String fixId) async {
    final changes = <String>[];
    try {
      final allBookings = await (db.select(db.bookings)
            ..where((b) => b.deletedAt.isNull()))
          .get();

      // تصفية الحجوزات النشطة باستخدام StatusUtils
      final activeBookings = allBookings
          .where((b) => StatusUtils.isActiveBooking(b.status))
          .toList();
      final occupiedRooms = activeBookings.map((b) => b.roomNumber).toSet();
      final rooms =
          await (db.select(db.rooms)..where((r) => r.deletedAt.isNull())).get();
      final updates = <_RoomStatusUpdate>[];
      for (final room in rooms) {
        final shouldBeOccupied = occupiedRooms.contains(room.roomNumber);
        final currentlyOccupied = StatusUtils.isRoomOccupied(room.status);
        if (shouldBeOccupied != currentlyOccupied) {
          final newStatus =
              StatusUtils.roomStatusForOccupancy(shouldBeOccupied);
          await _logChange(
            fixId: fixId,
            targetTable: 'rooms',
            targetRecordId: room.id,
            fieldName: 'status',
            oldValue: room.status,
            newValue: newStatus,
            reason: 'تحديث الحالة بناءً على الحجوزات النشطة',
            fixType: 'room_status',
          );
          await _logConflict(
            fixId: fixId,
            tableName: 'rooms',
            fixType: 'room_status',
            localUuid: room.localUuid,
            oldData: {
              'status': room.status,
            },
            newData: {
              'status': newStatus,
            },
          );
          updates.add(_RoomStatusUpdate(room: room, status: newStatus));
          final changeMsg =
              'إصلاح الغرفة ${room.roomNumber}: تحديث الحالة من \'${room.status}\' إلى \'$newStatus\'';
          changes.add(changeMsg);
          debugPrint('✏️ $changeMsg');
        }
      }
      if (updates.isNotEmpty) {
        final now = Time.nowEpoch();
        final isoNow = DateTime.now().toUtc().toIso8601String();
        await db.batch((batch) {
          for (final update in updates) {
            batch.update(
              db.rooms,
              RoomsCompanion(
                status: Value(update.status),
                updatedAt: Value(now),
                lastModified: Value(now),
                updatedAtIso: Value(isoNow),
                lastModifiedEpoch: Value(now),
              ),
              where: (tbl) => tbl.id.equals(update.room.id),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تحديث حالات الغرف: $e');
    }
    return changes;
  }

  Future<_BookingStructuresResult> _rebuildBookingStructures(
    DateTime restoreMoment,
  ) async {
    final bookings = await (db.select(db.bookings)
          ..where((b) => b.deletedAt.isNull()))
        .get();

    final rooms =
        await (db.select(db.rooms)..where((r) => r.deletedAt.isNull())).get();

    if (bookings.isEmpty) {
      await db.delete(db.bookingNights).go();
      await db.delete(db.hotelDayLedger).go();
      return const _BookingStructuresResult(
        changes: [],
        paymentsProcessed: 0,
        roomsTouched: 0,
        bookingNightCount: 0,
        ledgerEntryCount: 0,
      );
    }

    final roomsByNumber = <String, Room>{
      for (final room in rooms) room.roomNumber: room,
    };

    final int totalRooms = math.max(rooms.length, 1);
    final Map<String, _LedgerAccumulator> ledger = {};
    final List<BookingNightsCompanion> nightRows = [];
    final Map<int, String> roomLastOccupied = {};
    int paymentsProcessed = 0;
    int bookingNightCount = 0;

    await db.delete(db.bookingNights).go();

    for (final booking in bookings) {
      final room = roomsByNumber[booking.roomNumber];
      final bool bookingActive = booking.actualCheckout == null &&
          (StatusUtils.isBookingActive(booking) ||
              booking.checkoutDate == null);

      final DateTime checkin = _parseDate(booking.checkinDate) ?? restoreMoment;
      DateTime checkout = _parseDate(booking.actualCheckout) ??
          _parseDate(booking.checkoutDate) ??
          restoreMoment;

      if (bookingActive && restoreMoment.isAfter(checkin)) {
        checkout = restoreMoment;
      }

      if (!checkout.isAfter(checkin)) {
        checkout = checkin.add(const Duration(hours: 12));
      }

      final segments = _buildNightSegments(checkin, checkout);
      final double nightlyRate = room?.price ?? 0.0;

      int sequence = 0;
      DateTime? lastNightEnd;

      for (final segment in segments) {
        sequence++;
        lastNightEnd = segment.end;

        final int rowEpoch = Time.nowEpoch();
        final String rowIso = DateTime.now().toUtc().toIso8601String();
        nightRows.add(
          BookingNightsCompanion(
            localUuid: Value(IdGen.uuid()),
            serverId: const Value.absent(),
            createdAt: Value(rowEpoch),
            updatedAt: Value(rowEpoch),
            deletedAt: const Value.absent(),
            lastModified: Value(rowEpoch),
            createdAtIso: Value(rowIso),
            updatedAtIso: Value(rowIso),
            deletedAtIso: const Value.absent(),
            createdAtEpoch: Value(rowEpoch),
            lastModifiedEpoch: Value(rowEpoch),
            version: const Value(1),
            origin: const Value('auto_fix'),
            bookingLocalId: Value(booking.id),
            hotelDayKey: Value(segment.hotelDayKey),
            nightStart: Value(segment.start.toIso8601String()),
            nightEnd: Value(segment.end.toIso8601String()),
            nightlyRate: Value(nightlyRate),
            sequence: Value(sequence),
            isProcessedByAutoFix: const Value(true),
          ),
        );

        final accumulator =
            ledger.putIfAbsent(segment.hotelDayKey, () => _LedgerAccumulator());
        accumulator.totalIncome += nightlyRate;
        accumulator.bookingsProcessed += 1;
        if (bookingActive) {
          accumulator.occupiedRooms.add(booking.roomNumber);
        }
      }

      bookingNightCount += segments.length;

      final int totalNights = math.max(segments.length, 1);
      final double totalDue = nightlyRate * totalNights;
      final String stayDurationIso =
          '${checkin.toIso8601String()}/${checkout.toIso8601String()}';
      final int? lastNightEpoch = lastNightEnd != null
          ? lastNightEnd.millisecondsSinceEpoch ~/ 1000
          : null;
      final String hotelDayCheckin = _hotelDayKey(checkin);
      final String hotelDayCheckout = _hotelDayKey(checkout);
      final bool isOverdue = bookingActive &&
          checkout.isBefore(restoreMoment) &&
          segments.isNotEmpty;

      final paymentRows = await (db.select(db.payments)
            ..where((p) => p.bookingLocalId.equals(booking.id))
            ..where((p) => p.deletedAt.isNull()))
          .get();
      double totalPaid = 0;
      for (final payment in paymentRows) {
        totalPaid += payment.amount;
        final String key = payment.hotelDayKey ??
            _hotelDayKey(_parseDate(payment.paymentDate) ?? restoreMoment);
        final accumulator = ledger.putIfAbsent(key, () => _LedgerAccumulator());
        accumulator.paymentsProcessed += 1;
        accumulator.paymentsTotal += payment.amount;
      }
      paymentsProcessed += paymentRows.length;
      final double remainingRaw =
          double.parse((totalDue - totalPaid).toStringAsFixed(2));
      final double remaining = remainingRaw < 0 ? 0 : remainingRaw;
      final bool isFullyPaid = remaining <= 0.009;
      final bool needsReview = isOverdue || remaining > 0.009;

      final pendingAccumulator =
          ledger.putIfAbsent(hotelDayCheckout, () => _LedgerAccumulator());
      if (remaining > 0.009) {
        pendingAccumulator.pendingBalance += remaining;
        pendingAccumulator.debtsProcessed += 1;
      }

      final int stamp = Time.nowEpoch();
      final String stampIso = DateTime.now().toUtc().toIso8601String();
      await (db.update(db.bookings)..where((tbl) => tbl.id.equals(booking.id)))
          .write(
        BookingsCompanion(
          calculatedNights: Value(totalNights),
          expectedNights: Value(totalNights),
          totalNightsCached: Value(totalNights),
          stayDurationIso: Value(stayDurationIso),
          lastNightEpoch: Value(lastNightEpoch),
          isOverdue: Value(isOverdue),
          needsCheckoutReview: Value(needsReview),
          totalDueCached: Value(double.parse(totalDue.toStringAsFixed(2))),
          totalPaidCached: Value(double.parse(totalPaid.toStringAsFixed(2))),
          remainingBalanceCached:
              Value(double.parse(remaining.toStringAsFixed(2))),
          isFullyPaid: Value(isFullyPaid),
          hotelDayCheckin: Value(hotelDayCheckin),
          hotelDayCheckout: Value(hotelDayCheckout),
          updatedAt: Value(stamp),
          lastModified: Value(stamp),
          updatedAtIso: Value(stampIso),
          lastModifiedEpoch: Value(stamp),
        ),
      );

      if (room != null && segments.isNotEmpty) {
        roomLastOccupied[room.id] = segments.last.hotelDayKey;
      }
    }

    if (nightRows.isNotEmpty) {
      await db.batch((batch) {
        for (final row in nightRows) {
          batch.insert(db.bookingNights, row, mode: InsertMode.insertOrReplace);
        }
      });
    }

    final expenses = await (db.select(db.expenses)
          ..where((e) => e.deletedAt.isNull()))
        .get();
    for (final expense in expenses) {
      final String key = expense.hotelDayKey ??
          _hotelDayKey(_parseDate(expense.date) ?? restoreMoment);
      final accumulator = ledger.putIfAbsent(key, () => _LedgerAccumulator());
      accumulator.totalExpenses += expense.amount;
      accumulator.expensesProcessed += 1;
    }

    if (roomLastOccupied.isNotEmpty) {
      final int stamp = Time.nowEpoch();
      final String stampIso = DateTime.now().toUtc().toIso8601String();
      await db.batch((batch) {
        roomLastOccupied.forEach((roomId, hotelDayKey) {
          batch.update(
            db.rooms,
            RoomsCompanion(
              lastOccupiedHotelDay: Value(hotelDayKey),
              updatedAt: Value(stamp),
              lastModified: Value(stamp),
              updatedAtIso: Value(stampIso),
              lastModifiedEpoch: Value(stamp),
            ),
            where: (tbl) => tbl.id.equals(roomId),
          );
        });
      });
    }

    await db.delete(db.hotelDayLedger).go();

    final List<HotelDayLedgerCompanion> ledgerRows = [];
    ledger.forEach((key, accumulator) {
      final int stamp = Time.nowEpoch();
      final String stampIso = DateTime.now().toUtc().toIso8601String();
      final double occupancy = accumulator.occupiedRooms.isEmpty
          ? 0
          : accumulator.occupiedRooms.length / totalRooms;
      ledgerRows.add(
        HotelDayLedgerCompanion(
          localUuid: Value(IdGen.uuid()),
          serverId: const Value.absent(),
          createdAt: Value(stamp),
          updatedAt: Value(stamp),
          deletedAt: const Value.absent(),
          lastModified: Value(stamp),
          createdAtIso: Value(stampIso),
          updatedAtIso: Value(stampIso),
          deletedAtIso: const Value.absent(),
          createdAtEpoch: Value(stamp),
          lastModifiedEpoch: Value(stamp),
          version: const Value(1),
          origin: const Value('auto_fix'),
          hotelDayKey: Value(key),
          totalIncome:
              Value(double.parse(accumulator.totalIncome.toStringAsFixed(2))),
          totalExpenses:
              Value(double.parse(accumulator.totalExpenses.toStringAsFixed(2))),
          pendingBalances: Value(
              double.parse(accumulator.pendingBalance.toStringAsFixed(2))),
          occupancyRate:
              Value(double.parse(occupancy.clamp(0, 1).toStringAsFixed(4))),
          bookingsProcessed: Value(accumulator.bookingsProcessed),
          paymentsProcessed: Value(accumulator.paymentsProcessed),
          debtsProcessed: Value(accumulator.debtsProcessed),
          expensesProcessed: Value(accumulator.expensesProcessed),
          status: Value(
            (accumulator.totalIncome > 0 || accumulator.totalExpenses > 0)
                ? 'finalized'
                : 'draft',
          ),
        ),
      );
    });

    if (ledgerRows.isNotEmpty) {
      await db.batch((batch) {
        for (final row in ledgerRows) {
          batch.insert(db.hotelDayLedger, row,
              mode: InsertMode.insertOrReplace);
        }
      });
    }

    final List<String> changeLog = [];
    if (bookingNightCount > 0) {
      changeLog.add('🔁 إعادة بناء جدول الليالي: $bookingNightCount سجل');
    }
    if (ledgerRows.isNotEmpty) {
      changeLog.add('📊 تحديث دفتر HotelDayLedger: ${ledgerRows.length} يوم');
    }
    if (paymentsProcessed > 0) {
      changeLog
          .add('💰 تحديث مؤشرات المدفوعات: معالجة $paymentsProcessed دفعة');
    }

    return _BookingStructuresResult(
      changes: changeLog,
      paymentsProcessed: paymentsProcessed,
      roomsTouched: roomLastOccupied.length,
      bookingNightCount: bookingNightCount,
      ledgerEntryCount: ledgerRows.length,
    );
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  List<_NightSegment> _buildNightSegments(DateTime checkin, DateTime checkout) {
    final segments = <_NightSegment>[];
    var cursor = checkin;
    while (cursor.isBefore(checkout)) {
      final DateTime dayStart = _hotelDayStart(cursor);
      final DateTime dayEnd = dayStart.add(const Duration(days: 1));
      final DateTime segmentEnd = dayEnd.isBefore(checkout) ? dayEnd : checkout;
      if (!segmentEnd.isAfter(cursor)) {
        break;
      }
      segments.add(
        _NightSegment(
          hotelDayKey: _hotelDayKey(cursor),
          start: cursor,
          end: segmentEnd,
        ),
      );
      cursor = segmentEnd;
    }

    if (segments.isEmpty) {
      final fallbackEnd = checkin.add(const Duration(hours: 12));
      segments.add(
        _NightSegment(
          hotelDayKey: _hotelDayKey(checkin),
          start: checkin,
          end: fallbackEnd,
        ),
      );
    }

    return segments;
  }

  DateTime _hotelDayStart(DateTime value) {
    final start = DateTime(value.year, value.month, value.day, 14);
    if (value.isBefore(start)) {
      final previous = start.subtract(const Duration(days: 1));
      return DateTime(previous.year, previous.month, previous.day, 14);
    }
    return start;
  }

  String _hotelDayKey(DateTime value) =>
      Time.dateToString(_hotelDayStart(value));

  /// تسجيل التغيير في جدول RestoreFixLog
  Future<void> _logChange({
    required String fixId,
    required String targetTable,
    required int targetRecordId,
    required String fieldName,
    required String oldValue,
    required String newValue,
    required String reason,
    required String fixType,
  }) async {
    await db.into(db.restoreFixLog).insert(
          RestoreFixLogCompanion(
            fixId: Value(fixId),
            executedAt: Value(Time.nowEpoch()),
            targetTable: Value(targetTable),
            targetRecordId: Value(targetRecordId),
            fieldName: Value(fieldName),
            oldValue: Value(oldValue),
            newValue: Value(newValue),
            reason: Value(reason),
            fixType: Value(fixType),
          ),
        );
  }

  Future<void> _ensureConflictLogTable() async {
    if (_conflictTableReady) {
      return;
    }
    await db.customStatement(
        'CREATE TABLE IF NOT EXISTS restore_conflict_log (id INTEGER PRIMARY KEY AUTOINCREMENT, fix_id TEXT, fix_type TEXT, table_name TEXT, local_uuid TEXT, old_data TEXT, new_data TEXT, occurred_at INTEGER)');
    _conflictTableReady = true;
  }

  Future<void> _logConflict({
    required String fixId,
    required String tableName,
    required String fixType,
    String? localUuid,
    required Map<String, dynamic> oldData,
    required Map<String, dynamic> newData,
  }) async {
    await _ensureConflictLogTable();
    final epoch = Time.nowEpoch();
    final normalized = epoch < 1000000000000 ? epoch * 1000 : epoch;
    await db.customStatement(
      'INSERT INTO restore_conflict_log (fix_id, fix_type, table_name, local_uuid, old_data, new_data, occurred_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        fixId,
        fixType,
        tableName,
        localUuid,
        jsonEncode(oldData),
        jsonEncode(newData),
        normalized,
      ],
    );
  }

  /// استعادة البيانات من اللقطة الاحتياطية
  Future<void> _restoreFromSnapshot(String snapshotPath) async {
    try {
      final file = File(snapshotPath);
      if (!await file.exists()) {
        throw Exception('ملف اللقطة الاحتياطية غير موجود: $snapshotPath');
      }

      final jsonString = await file.readAsString();
      final snapshotData = jsonDecode(jsonString) as Map<String, dynamic>;

      await db.transaction(() async {
        // مسح الجداول المتأثرة
        await db.delete(db.bookings).go();
        await db.delete(db.rooms).go();
        await db.delete(db.payments).go();
        await db.delete(db.debts).go();

        // استعادة البيانات
        if (snapshotData.containsKey('bookings')) {
          await bookingsDao.importFromJson(
              List<Map<String, dynamic>>.from(snapshotData['bookings']),
              clearExisting: false);
        }
        if (snapshotData.containsKey('rooms')) {
          await roomsDao.importFromJson(
              List<Map<String, dynamic>>.from(snapshotData['rooms']),
              clearExisting: false);
        }
        if (snapshotData.containsKey('payments')) {
          await paymentsDao.importFromJson(
              List<Map<String, dynamic>>.from(snapshotData['payments']),
              clearExisting: false);
        }
        if (snapshotData.containsKey('debts')) {
          await debtsDao.importFromJson(
              List<Map<String, dynamic>>.from(snapshotData['debts']),
              clearExisting: false);
        }
      });
    } catch (e) {
      debugPrint('❌ فشل في استعادة اللقطة الاحتياطية: $e');
      rethrow;
    }
  }

  /// حذف ملف اللقطة الاحتياطية
  Future<void> _deleteSnapshot(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ تم حذف اللقطة الاحتياطية: $filePath');
      }
    } catch (e) {
      debugPrint('⚠️ تحذير: لا يمكن حذف اللقطة الاحتياطية: $e');
    }
  }

  /// الحصول على سجلات الإصلاح
  Future<List<RestoreFixLogData>> getFixLogs(
      {String? fixId, int? limit}) async {
    final query = db.select(db.restoreFixLog);

    if (fixId != null) {
      query.where((log) => log.fixId.equals(fixId));
    }

    query.orderBy([
      (log) => OrderingTerm(expression: log.executedAt, mode: OrderingMode.desc)
    ]);

    if (limit != null) {
      query.limit(limit);
    }

    return await query.get();
  }

  /// تصدير سجلات الإصلاح كـ JSON
  Future<Map<String, dynamic>> exportFixLogsAsJson({String? fixId}) async {
    final logs = await getFixLogs(fixId: fixId);

    return {
      'fix_id': fixId ?? 'all',
      'exported_at': DateTime.now().toIso8601String(),
      'total_logs': logs.length,
      'logs': logs
          .map((log) => {
                'id': log.id,
                'fix_id': log.fixId,
                'executed_at': log.executedAt,
                'executed_at_iso':
                    DateTime.fromMillisecondsSinceEpoch(log.executedAt * 1000)
                        .toIso8601String(),
                'target_table': log.targetTable,
                'target_record_id': log.targetRecordId,
                'field_name': log.fieldName,
                'old_value': log.oldValue,
                'new_value': log.newValue,
                'reason': log.reason,
                'fix_type': log.fixType,
              })
          .toList(),
    };
  }
}

class _BookingStructuresResult {
  const _BookingStructuresResult({
    required this.changes,
    required this.paymentsProcessed,
    required this.roomsTouched,
    required this.bookingNightCount,
    required this.ledgerEntryCount,
  });

  final List<String> changes;
  final int paymentsProcessed;
  final int roomsTouched;
  final int bookingNightCount;
  final int ledgerEntryCount;
}

class _LedgerAccumulator {
  double totalIncome = 0;
  double totalExpenses = 0;
  double pendingBalance = 0;
  double paymentsTotal = 0;
  int bookingsProcessed = 0;
  int paymentsProcessed = 0;
  int debtsProcessed = 0;
  int expensesProcessed = 0;
  final Set<String> occupiedRooms = <String>{};
}

class _NightSegment {
  const _NightSegment({
    required this.hotelDayKey,
    required this.start,
    required this.end,
  });

  final String hotelDayKey;
  final DateTime start;
  final DateTime end;
}

class _RoomStatusUpdate {
  _RoomStatusUpdate({required this.room, required this.status});

  final Room room;
  final String status;
}
