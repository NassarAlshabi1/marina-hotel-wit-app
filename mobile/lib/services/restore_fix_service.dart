import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/id.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
import 'daos/bookings_dao.dart';
import 'daos/debts_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/payments_dao.dart';
import 'daos/rooms_dao.dart';
import 'enhanced_booking_calculation_service.dart';
import 'local_db.dart';

/// استثناء يُرمى عند فشل التحقق من صحة بيانات النسخة الاحتياطية
class RestoreValidationException implements Exception {

  RestoreValidationException(this.message);
  final String message;

  @override
  String toString() => 'RestoreValidationException: $message';
}

/// نموذج لتخزين معلومات اللقطة الاحتياطية
class RestoreSnapshot {

  RestoreSnapshot({
    required this.filePath,
    required this.createdAt,
    required this.recordCounts,
    required this.totalSizeBytes,
  });

  factory RestoreSnapshot.fromJson(Map<String, dynamic> json) =>
      RestoreSnapshot(
        filePath: json['filePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        recordCounts: Map<String, int>.from(json['recordCounts'] as Map),
        totalSizeBytes: json['totalSizeBytes'] as int,
      );
  final String filePath;
  final DateTime createdAt;
  final Map<String, int> recordCounts;
  final int totalSizeBytes;

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
    'recordCounts': recordCounts,
    'totalSizeBytes': totalSizeBytes,
  };
}

/// تقرير شامل عن عملية الإصلاح التلقائي
class RestoreFixReport {

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
  final bool success;
  final int bookingsFixed;
  final int roomsUpdated;
  final int paymentsRecalculated;
  final List<String> changes;
  final String? error;
  final DateTime executedAt;
  final int durationMs;

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
}

/// خدمة الإصلاح التلقائي للنسخة الاحتياطية
/// تقوم بإعادة حساب الليالي، حالات الغرف، والمدفوعات بعد استعادة النسخة الاحتياطية
class RestoreFixService {

  RestoreFixService(this.db, {this.onBeforeCommit})
    : bookingsDao = BookingsDao(db, OutboxDao(db)),
      roomsDao = RoomsDao(db, OutboxDao(db)),
      paymentsDao = PaymentsDao(db, OutboxDao(db)),
      debtsDao = DebtsDao(db, OutboxDao(db));
  final AppDatabase db;
  final BookingsDao bookingsDao;
  final RoomsDao roomsDao;
  final PaymentsDao paymentsDao;
  final DebtsDao debtsDao;
  final Future<void> Function()? onBeforeCommit;
  bool _conflictTableReady = false;

  // ملاحظة: جميع المبالغ المالية تستخدم int (الريال اليمني بدون كسور)

  /// إنشاء لقطة احتياطية محلية قبل بدء عملية الإصلاح
  Future<RestoreSnapshot> createLocalSnapshot(
    String prefix, {
    bool useTransaction = true,
  }) async {
    debugPrint(
      '📸 إنشاء لقطة احتياطية أمان: ${prefix}_restore_snapshot_${Time.nowEpoch()}.json',
    );

    Future<RestoreSnapshot> doCreate() async {
      final directory = await _resolveCacheDirectory();
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
    }

    if (useTransaction) {
      return db.transaction<RestoreSnapshot>(doCreate);
    }
    return doCreate();
  }

  Future<Directory> _resolveCacheDirectory() async {
    try {
      return await getApplicationCacheDirectory();
    } catch (_) {
      return Directory.systemTemp.createTemp('marina_cache_');
    }
  }

  /// الدالة الرئيسية لتشغيل الإصلاح التلقائي
  Future<RestoreFixReport> runAutoFixAfterRestore({
    DateTime? backupTimestamp,
  }) async {
    debugPrint('🔄 بدء عملية الإصلاح التلقائي للنسخة الاحتياطية...');

    final startTime = DateTime.now();
    int bookingsFixed = 0;
    int roomsUpdated = 0;
    int paymentsChecked = 0;
    final List<String> changes = [];
    RestoreSnapshot? snapshot;

    try {
      // تنفيذ الإصلاح داخل معاملة واحدة
      await db.transaction(() async {
        // إنشاء لقطة احتياطية للأمان داخل نفس المعاملة
        snapshot = await createLocalSnapshot('auto_fix', useTransaction: false);
        final now = DateTime.now();
        final fixId = IdGen.uuid();

        // البحث عن الحجوزات التي تحتاج إصلاح
        final bookingsToFix = await _getBookingsNeedingFix(
          backupTimestamp,
          now,
        );
        debugPrint('🔍 العثور على ${bookingsToFix.length} حجز يحتاج إلى إصلاح');

        for (final booking in bookingsToFix) {
          final bookingChanges = await _fixBookingDatesAndNights(
            booking,
            now,
            fixId,
          );
          if (bookingChanges.isNotEmpty) {
            bookingsFixed++;
            changes.addAll(bookingChanges);
          }

          final updatedBooking = await (db.select(
            db.bookings,
          )..where((b) => b.id.equals(booking.id))).getSingleOrNull();

          if (updatedBooking != null) {
            final paymentChanges = await _recalculateBookingFinancials(
              updatedBooking,
              fixId,
            );
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
    DateTime? backupDate,
    DateTime now,
  ) async {
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
    Booking booking,
    DateTime now,
    String fixId,
  ) async {
    final List<String> changes = [];

    try {
      // تحليل تواريخ الدخول والخروج
      final checkinDate = DateTime.parse(booking.checkinDate);
      final checkoutDate = booking.actualCheckout != null
          ? DateTime.parse(booking.actualCheckout!)
          : (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty
                ? DateTime.parse(booking.checkoutDate!)
                : now);

      // حساب الليالي باستخدام قاعدة الساعة 14:00
      final calculatedNights = Time.nightsWithCutoff(
        checkinDate,
        checkout: checkoutDate,
      );

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
    Booking booking,
    String fixId,
  ) async {
    final changes = <String>[];
    try {
      final payments =
          await (db.select(db.payments)
                ..where((p) => p.bookingLocalId.equals(booking.id))
                ..where((p) => p.deletedAt.isNull()))
              .get();

      final totalPaid = payments.fold<double>(
        0,
        (sum, payment) => sum + payment.amount,
      );

      final room =
          await (db.select(db.rooms)
                ..where((r) => r.roomNumber.equals(booking.roomNumber)))
              .getSingleOrNull();
      double? expectedTotal;
      if (room != null) {
        final nights = await (db.select(db.bookingNights)
              ..where((n) => n.bookingLocalId.equals(booking.id))
              ..where((n) => n.deletedAt.isNull()))
            .get();
        
        final double totalNightAmount;
        if (nights.isNotEmpty) {
          totalNightAmount = nights.fold<double>(0, (sum, n) => sum + n.nightlyRate);
        } else {
          final baseRate = room.price;
          final discount = booking.discount;
          final discountType = booking.discountType;
          if (discountType == 'total') {
            totalNightAmount = (baseRate * booking.calculatedNights - discount)
                .clamp(0, baseRate * booking.calculatedNights)
                .toDouble();
          } else if (discount > 0) {
            final discountedRate = (baseRate - discount)
                .clamp(0, baseRate)
                .toDouble();
            totalNightAmount = discountedRate * booking.calculatedNights;
          } else {
            totalNightAmount = baseRate * booking.calculatedNights;
          }
        }
        
        // ✅ إصلاح الخصم المزدوج: الخصم تم حسابه بالفعل في totalNightAmount أعلاه
        expectedTotal = totalNightAmount;

        final remainingBalance = (expectedTotal - totalPaid)
            .clamp(0, expectedTotal)
            .toDouble();
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
          );

          changes.add(
            'تحديث المبالغ المخزنة للحجز #${booking.id}: الإجمالي=$expectedTotal, المدفوع=$totalPaid, المتبقي=$remainingBalance',
          );
          debugPrint('💰 ${changes.last}');
        }

        if ((totalPaid - expectedTotal).abs() > 0 && totalPaid != expectedTotal) {
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
            oldData: {'total_paid': totalPaid},
            newData: {'expected_total': expectedTotal},
          );
          final warningMsg =
              'تنبيه: الحجز #${booking.id} - إجمالي المدفوعات ($totalPaid) لا يتطابق مع المتوقع ($expectedTotal)';
          changes.add(warningMsg);
          debugPrint('⚠️ $warningMsg');
        }
      }

      final debts =
          await (db.select(db.debts)
                ..where((d) => d.bookingLocalId.equals(booking.id))
                ..where((d) => d.deletedAt.isNull()))
              .get();
      if (debts.isNotEmpty && expectedTotal != null) {
        final remaining = (expectedTotal - totalPaid)
            .clamp(0, expectedTotal)
            .toDouble();
        final isSettled = remaining <= 0 ? 1 : 0;
        for (final debt in debts) {
          final shouldUpdate =
              debt.totalAmount != expectedTotal ||
              debt.paidAmount != totalPaid ||
              debt.remainingAmount != remaining ||
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
                'remaining_amount': remaining,
                'is_settled': isSettled,
              },
            );
            await (db.update(
              db.debts,
            )..where((t) => t.id.equals(debt.id))).write(
              DebtsCompanion(
                totalAmount: Value(expectedTotal),
                paidAmount: Value(totalPaid),
                remainingAmount: Value(remaining),
                isSettled: Value(isSettled),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
            changes.add(
              'إعادة احتساب الدين للحجز #${booking.id}: المتبقي $remaining، تم ${isSettled == 1 ? 'إغلاق الدين' : 'تحديثه'}',
            );
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
      final allBookings = await (db.select(
        db.bookings,
      )..where((b) => b.deletedAt.isNull())).get();

      // تصفية الحجوزات النشطة باستخدام StatusUtils
      final activeBookings = allBookings
          .where((b) => StatusUtils.isActiveBooking(b.status))
          .toList();
      final occupiedRooms = activeBookings.map((b) => b.roomNumber).toSet();
      final rooms = await (db.select(
        db.rooms,
      )..where((r) => r.deletedAt.isNull())).get();
      final updates = <_RoomStatusUpdate>[];
      for (final room in rooms) {
        final shouldBeOccupied = occupiedRooms.contains(room.roomNumber);
        final currentlyOccupied = StatusUtils.isRoomOccupied(room.status);
        if (shouldBeOccupied != currentlyOccupied) {
          final newStatus = StatusUtils.roomStatusForOccupancy(
            shouldBeOccupied,
          );
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
            oldData: {'status': room.status},
            newData: {'status': newStatus},
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
    final context = await _prepareRebuildContext(restoreMoment);

    if (context.bookings.isEmpty) {
      return _handleEmptyBookings();
    }

    final nightsResult = await _rebuildBookingNights(context);
    final ledgerResult = await _rebuildHotelDayLedger(context, nightsResult);
    final roomsResult = await _updateRoomsLastOccupied(context, nightsResult);

    return _combineResults(nightsResult, ledgerResult, roomsResult);
  }

  Future<_RebuildContext> _prepareRebuildContext(DateTime restoreMoment) async {
    final bookings = await (db.select(
      db.bookings,
    )..where((b) => b.deletedAt.isNull())).get();

    final rooms = await (db.select(
      db.rooms,
    )..where((r) => r.deletedAt.isNull())).get();

    final roomsByNumber = <String, Room>{
      for (final room in rooms) room.roomNumber: room,
    };

    final int totalRooms = math.max(rooms.length, 1);

    return _RebuildContext(
      bookings: bookings,
      rooms: rooms,
      roomsByNumber: roomsByNumber,
      totalRooms: totalRooms,
      restoreMoment: restoreMoment,
    );
  }

  Future<_BookingStructuresResult> _handleEmptyBookings() async {
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

  Future<_NightsRebuildResult> _rebuildBookingNights(
    _RebuildContext context,
  ) async {
    final Map<String, _LedgerAccumulator> ledger = {};
    final List<BookingNightsCompanion> nightRows = [];
    final Map<int, String> roomLastOccupied = {};
    final List<String> changes = [];
    int bookingNightCount = 0;
    int paymentsProcessed = 0;

    await db.delete(db.bookingNights).go();

    for (final booking in context.bookings) {
      final room = context.roomsByNumber[booking.roomNumber];

      if (room == null) {
        debugPrint(
          '⚠️ تحذير: الغرفة ${booking.roomNumber} غير موجودة للحجز #${booking.id}',
        );
        changes.add(
          'تحذير: حجز #${booking.id} مرتبط بغرفة غير موجودة (${booking.roomNumber})',
        );
        continue;
      }

      final bookingResult = await _processBookingForNights(
        booking: booking,
        room: room,
        restoreMoment: context.restoreMoment,
        ledger: ledger,
      );

      nightRows.addAll(bookingResult.nightRows);
      bookingNightCount += bookingResult.nightCount;
      paymentsProcessed += bookingResult.paymentsCount;

      if (bookingResult.lastOccupiedDay != null) {
        roomLastOccupied[room.id] = bookingResult.lastOccupiedDay!;
      }
    }

    if (nightRows.isNotEmpty) {
      await db.batch((batch) {
        for (final row in nightRows) {
          batch.insert(db.bookingNights, row, mode: InsertMode.insertOrReplace);
        }
      });
    }

    await _processExpenses(context, ledger);

    return _NightsRebuildResult(
      ledger: ledger,
      nightRows: nightRows,
      roomLastOccupied: roomLastOccupied,
      changes: changes,
      bookingNightCount: bookingNightCount,
      paymentsProcessed: paymentsProcessed,
    );
  }

  Future<_BookingProcessingResult> _processBookingForNights({
    required Booking booking,
    required Room room,
    required DateTime restoreMoment,
    required Map<String, _LedgerAccumulator> ledger,
  }) async {
    final calcService = EnhancedBookingCalculationService(db);
    final calculation =
        await calcService.calculateForBooking(booking, now: restoreMoment);
    final breakdown = calculation.breakdown;

    final List<BookingNightsCompanion> nightRows = [];
    int sequence = 0;

    for (final night in breakdown) {
      sequence++;
      final int rowEpoch = Time.nowEpoch();
      final String rowIso = DateTime.now().toUtc().toIso8601String();
      final appliedJson = night.appliedAdjustments.isEmpty
          ? null
          : jsonEncode(
              night.appliedAdjustments.map((a) => a.toJson()).toList(),
            );
      final appliedUuid = night.appliedAdjustments.length == 1
          ? night.appliedAdjustments.first.uuid
          : null;

      nightRows.add(
        BookingNightsCompanion(
          localUuid: Value(IdGen.uuid()),
          createdAt: Value(rowEpoch),
          updatedAt: Value(rowEpoch),
          lastModified: Value(rowEpoch),
          createdAtIso: Value(rowIso),
          updatedAtIso: Value(rowIso),
          createdAtEpoch: Value(rowEpoch),
          lastModifiedEpoch: Value(rowEpoch),
          version: const Value(1),
          origin: const Value('auto_fix'),
          bookingLocalId: Value(booking.id),
          hotelDayKey: Value(night.hotelDayKey),
          nightStart: Value(night.nightStart.toIso8601String()),
          nightEnd: Value(night.nightEnd.toIso8601String()),
          nightlyRate: Value(night.finalRate.toDouble()),
          baseRate: Value(night.baseRate.toDouble()),
          adjustment: Value(night.adjustmentAmount.toDouble()),
          finalRate: Value(night.finalRate.toDouble()),
          appliedAdjustmentUuid: Value(appliedUuid),
          appliedAdjustmentsJson: Value(appliedJson),
          sequence: Value(sequence),
          isProcessedByAutoFix: const Value(true),
        ),
      );

      final accumulator = ledger.putIfAbsent(
        night.hotelDayKey,
        _LedgerAccumulator.new,
      );
      accumulator.totalIncome += night.finalRate;
      accumulator.bookingsProcessed += 1;
      if (calculation.bookingActive) {
        accumulator.occupiedRooms.add(booking.roomNumber);
      }
    }

    final int totalNights = math.max(breakdown.length, 1);
    final double totalDue = calculation.financialSummary.totalDue.toDouble();

    final paymentRows =
        await (db.select(db.payments)
              ..where(
                (p) =>
                    (p.bookingLocalId.equals(booking.id) |
                    p.bookingUuidCache.equals(booking.localUuid)),
              )
              ..where((p) => p.deletedAt.isNull())
              ..where((p) => p.isPendingBalance.equals(false))
              ..where(
                (p) =>
                    p.revenueType.equals('room') |
                    p.revenueType.equals('') |
                    p.revenueType.isNull(),
              ))
            .get();
    double totalPaid = 0;
    for (final payment in paymentRows) {
      totalPaid += payment.amount;
      final String key =
          payment.hotelDayKey ??
          _hotelDayKey(_parseDate(payment.paymentDate) ?? restoreMoment);
      final accumulator = ledger.putIfAbsent(key, _LedgerAccumulator.new);
      accumulator.paymentsProcessed += 1;
      accumulator.paymentsTotal += payment.amount;
    }

    double remaining = totalDue - totalPaid;
    if (remaining < 0) {
      remaining = 0;
    }

    final bool isFullyPaid = remaining <= 0;
    final bool isOverdue =
        calculation.bookingActive &&
        calculation.checkout.isBefore(restoreMoment) &&
        breakdown.isNotEmpty;
    final bool needsReview = isOverdue || remaining > 0;

    final pendingAccumulator = ledger.putIfAbsent(
      calculation.hotelDayCheckout,
      _LedgerAccumulator.new,
    );
    if (remaining > 0) {
      pendingAccumulator.pendingBalance += remaining;
      pendingAccumulator.debtsProcessed += 1;
    }

    final int stamp = Time.nowEpoch();
    final String stampIso = DateTime.now().toUtc().toIso8601String();
    await (db.update(
      db.bookings,
    )..where((tbl) => tbl.id.equals(booking.id))).write(
      BookingsCompanion(
        calculatedNights: Value(totalNights),
        expectedNights: Value(totalNights),
        totalNightsCached: Value(totalNights),
        stayDurationIso: Value(calculation.stayDurationIso),
        lastNightEpoch: Value(calculation.lastNightEpoch),
        isOverdue: Value(isOverdue),
        needsCheckoutReview: Value(needsReview),
        totalDueCached: Value(totalDue),
        totalPaidCached: Value(totalPaid),
        remainingBalanceCached: Value(remaining),
        isFullyPaid: Value(isFullyPaid),
        hotelDayCheckin: Value(calculation.hotelDayCheckin),
        hotelDayCheckout: Value(calculation.hotelDayCheckout),
        updatedAt: Value(stamp),
        lastModified: Value(stamp),
        updatedAtIso: Value(stampIso),
        lastModifiedEpoch: Value(stamp),
      ),
    );

    return _BookingProcessingResult(
      nightRows: nightRows,
      nightCount: breakdown.length,
      paymentsCount: paymentRows.length,
      lastOccupiedDay: breakdown.isNotEmpty ? breakdown.last.hotelDayKey : null,
    );
  }

  Future<void> _processExpenses(
    _RebuildContext context,
    Map<String, _LedgerAccumulator> ledger,
  ) async {
    final expenses = await (db.select(
      db.expenses,
    )..where((e) => e.deletedAt.isNull())).get();
    for (final expense in expenses) {
      final String key =
          expense.hotelDayKey ??
          _hotelDayKey(_parseDate(expense.date) ?? context.restoreMoment);
      final accumulator = ledger.putIfAbsent(key, _LedgerAccumulator.new);
      accumulator.totalExpenses += expense.amount;
      accumulator.expensesProcessed += 1;
    }
  }

  Future<_LedgerRebuildResult> _rebuildHotelDayLedger(
    _RebuildContext context,
    _NightsRebuildResult nightsResult,
  ) async {
    await db.delete(db.hotelDayLedger).go();

    final List<HotelDayLedgerCompanion> ledgerRows = [];
    nightsResult.ledger.forEach((key, accumulator) {
      final int stamp = Time.nowEpoch();
      final String stampIso = DateTime.now().toUtc().toIso8601String();
      final double occupancy = accumulator.occupiedRooms.isEmpty
          ? 0
          : accumulator.occupiedRooms.length / context.totalRooms;
      ledgerRows.add(
        HotelDayLedgerCompanion(
          localUuid: Value(IdGen.uuid()),
          createdAt: Value(stamp),
          updatedAt: Value(stamp),
          lastModified: Value(stamp),
          createdAtIso: Value(stampIso),
          updatedAtIso: Value(stampIso),
          createdAtEpoch: Value(stamp),
          lastModifiedEpoch: Value(stamp),
          version: const Value(1),
          origin: const Value('auto_fix'),
          hotelDayKey: Value(key),
          totalIncome: Value(accumulator.totalIncome),
          totalExpenses: Value(accumulator.totalExpenses),
          pendingBalances: Value(accumulator.pendingBalance),
          occupancyRate: Value(
            double.parse(occupancy.clamp(0, 1).toStringAsFixed(4)),
          ),
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
          batch.insert(
            db.hotelDayLedger,
            row,
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }

    return _LedgerRebuildResult(ledgerEntryCount: ledgerRows.length);
  }

  Future<_RoomsUpdateResult> _updateRoomsLastOccupied(
    _RebuildContext context,
    _NightsRebuildResult nightsResult,
  ) async {
    if (nightsResult.roomLastOccupied.isEmpty) {
      return const _RoomsUpdateResult(roomsTouched: 0);
    }

    final int stamp = Time.nowEpoch();
    final String stampIso = DateTime.now().toUtc().toIso8601String();
    await db.batch((batch) {
      nightsResult.roomLastOccupied.forEach((roomId, hotelDayKey) {
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

    return _RoomsUpdateResult(
      roomsTouched: nightsResult.roomLastOccupied.length,
    );
  }

  _BookingStructuresResult _combineResults(
    _NightsRebuildResult nightsResult,
    _LedgerRebuildResult ledgerResult,
    _RoomsUpdateResult roomsResult,
  ) {
    final List<String> changeLog = [...nightsResult.changes];
    if (nightsResult.bookingNightCount > 0) {
      changeLog.add(
        '🔁 إعادة بناء جدول الليالي: ${nightsResult.bookingNightCount} سجل',
      );
    }
    if (ledgerResult.ledgerEntryCount > 0) {
      changeLog.add(
        '📊 تحديث دفتر HotelDayLedger: ${ledgerResult.ledgerEntryCount} يوم',
      );
    }
    if (nightsResult.paymentsProcessed > 0) {
      changeLog.add(
        '💰 تحديث مؤشرات المدفوعات: معالجة ${nightsResult.paymentsProcessed} دفعة',
      );
    }

    return _BookingStructuresResult(
      changes: changeLog,
      paymentsProcessed: nightsResult.paymentsProcessed,
      roomsTouched: roomsResult.roomsTouched,
      bookingNightCount: nightsResult.bookingNightCount,
      ledgerEntryCount: ledgerResult.ledgerEntryCount,
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

  // ignore: unused_element
  List<_NightSegment> _buildNightSegments(DateTime checkin, DateTime checkout, {int cutoffHour = 14}) {
    final segments = <_NightSegment>[];

    final checkinDate = DateTime(checkin.year, checkin.month, checkin.day);
    final checkoutDate = DateTime(checkout.year, checkout.month, checkout.day);
    int days = checkoutDate.difference(checkinDate).inDays;

    if (days == 0) {
      days = 1;
    }

    if (checkout.hour > cutoffHour ||
        (checkout.hour == cutoffHour && checkout.minute > 0) ||
        (checkout.hour == cutoffHour && checkout.minute == 0 && checkout.second > 0)) {
      days += 1;
    }

    for (int i = 0; i < days; i++) {
      final dayDate = checkinDate.add(Duration(days: i));
      final dayKey = Time.dateToString(dayDate);
      final segStart = i == 0 ? checkin : dayDate;
      final nextDay = dayDate.add(const Duration(days: 1));
      final segEnd = i == days - 1
          ? (checkout.isAfter(segStart) ? checkout : segStart.add(const Duration(minutes: 1)))
          : nextDay;

      segments.add(
        _NightSegment(
          hotelDayKey: dayKey,
          start: segStart,
          end: segEnd,
        ),
      );
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

  String _hotelDayKey(DateTime value) =>
      Time.dateToString(DateTime(value.year, value.month, value.day));

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
    final logId = IdGen.uuid();
    await db
        .into(db.restoreFixLog)
        .insert(
          RestoreFixLogCompanion(
            fixId: Value(logId),
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
      'CREATE TABLE IF NOT EXISTS restore_conflict_log (id INTEGER PRIMARY KEY AUTOINCREMENT, fix_id TEXT, fix_type TEXT, table_name TEXT, local_uuid TEXT, old_data TEXT, new_data TEXT, occurred_at INTEGER)',
    );
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
      if (!file.existsSync()) {
        throw RestoreValidationException(
          'ملف اللقطة الاحتياطية غير موجود: $snapshotPath',
        );
      }

      final jsonString = await file.readAsString();
      final snapshotData = jsonDecode(jsonString) as Map<String, dynamic>;

      _validateSnapshotData(snapshotData);

      await db.transaction(() async {
        // مسح الجداول المتأثرة (احذف children أولًا لتفادي كسر قيود FK)
        await db.delete(db.payments).go();
        await db.delete(db.debts).go();
        await db.delete(db.bookingNights).go();
        await db.delete(db.hotelDayLedger).go();
        await db.delete(db.bookings).go();
        await db.delete(db.rooms).go();

        // استعادة البيانات (أدخل parents أولًا ثم children)
        if (snapshotData.containsKey('rooms')) {
          await roomsDao.importFromJson(
            List<Map<String, dynamic>>.from(snapshotData['rooms'] as List),
          );
        }
        if (snapshotData.containsKey('bookings')) {
          await bookingsDao.importFromJson(
            List<Map<String, dynamic>>.from(snapshotData['bookings'] as List),
          );
        }
        if (snapshotData.containsKey('payments')) {
          await paymentsDao.importFromJson(
            List<Map<String, dynamic>>.from(snapshotData['payments'] as List),
          );
        }
        if (snapshotData.containsKey('debts')) {
          await debtsDao.importFromJson(
            List<Map<String, dynamic>>.from(snapshotData['debts'] as List),
          );
        }

        // إعادة بناء الجداول المشتقة لضمان الاتساق
        await _rebuildBookingStructures(DateTime.now());
      });
    } catch (e) {
      debugPrint('❌ فشل في استعادة اللقطة الاحتياطية: $e');
      rethrow;
    }
  }

  /// التحقق من صحة بيانات النسخة الاحتياطية قبل الاستعادة
  void _validateSnapshotData(Map<String, dynamic> data) {
    final requiredTables = ['bookings', 'rooms', 'payments'];
    for (final table in requiredTables) {
      if (!data.containsKey(table)) {
        throw RestoreValidationException(
          'جدول $table مفقود من النسخة الاحتياطية',
        );
      }

      if (data[table] is! List) {
        throw RestoreValidationException(
          'بيانات جدول $table غير صحيحة (يجب أن تكون قائمة)',
        );
      }
    }

    if (data.containsKey('metadata')) {
      final metadata = data['metadata'];
      if (metadata is! Map) {
        throw RestoreValidationException('بيانات metadata غير صحيحة');
      }
      if (!metadata.containsKey('timestamp')) {
        throw RestoreValidationException('timestamp مفقود من metadata');
      }
    }
  }

  /// حذف ملف اللقطة الاحتياطية
  Future<void> _deleteSnapshot(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        debugPrint('🗑️ تم حذف اللقطة الاحتياطية: $filePath');
      }
    } catch (e) {
      debugPrint('⚠️ تحذير: لا يمكن حذف اللقطة الاحتياطية: $e');
    }
  }

  /// الحصول على سجلات الإصلاح
  Future<List<RestoreFixLogData>> getFixLogs({
    String? fixId,
    int? limit,
  }) async {
    final query = db.select(db.restoreFixLog);

    if (fixId != null) {
      query.where((log) => log.fixId.equals(fixId));
    }

    query.orderBy([
      (log) =>
          OrderingTerm(expression: log.executedAt, mode: OrderingMode.desc),
    ]);

    if (limit != null) {
      query.limit(limit);
    }

    return query.get();
  }

  /// تصدير سجلات الإصلاح كـ JSON
  Future<Map<String, dynamic>> exportFixLogsAsJson({String? fixId}) async {
    final logs = await getFixLogs(fixId: fixId);

    return {
      'fix_id': fixId ?? 'all',
      'exported_at': DateTime.now().toIso8601String(),
      'total_logs': logs.length,
      'logs': logs
          .map(
            (log) => {
              'id': log.id,
              'fix_id': log.fixId,
              'executed_at': log.executedAt,
              'executed_at_iso': DateTime.fromMillisecondsSinceEpoch(
                log.executedAt * 1000,
              ).toIso8601String(),
              'target_table': log.targetTable,
              'target_record_id': log.targetRecordId,
              'field_name': log.fieldName,
              'old_value': log.oldValue,
              'new_value': log.newValue,
              'reason': log.reason,
              'fix_type': log.fixType,
            },
          )
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

class _RebuildContext {
  const _RebuildContext({
    required this.bookings,
    required this.rooms,
    required this.roomsByNumber,
    required this.totalRooms,
    required this.restoreMoment,
  });

  final List<Booking> bookings;
  final List<Room> rooms;
  final Map<String, Room> roomsByNumber;
  final int totalRooms;
  final DateTime restoreMoment;
}

class _NightsRebuildResult {
  const _NightsRebuildResult({
    required this.ledger,
    required this.nightRows,
    required this.roomLastOccupied,
    required this.changes,
    required this.bookingNightCount,
    required this.paymentsProcessed,
  });

  final Map<String, _LedgerAccumulator> ledger;
  final List<BookingNightsCompanion> nightRows;
  final Map<int, String> roomLastOccupied;
  final List<String> changes;
  final int bookingNightCount;
  final int paymentsProcessed;
}

class _LedgerRebuildResult {
  const _LedgerRebuildResult({required this.ledgerEntryCount});

  final int ledgerEntryCount;
}

class _RoomsUpdateResult {
  const _RoomsUpdateResult({required this.roomsTouched});

  final int roomsTouched;
}

class _BookingProcessingResult {
  const _BookingProcessingResult({
    required this.nightRows,
    required this.nightCount,
    required this.paymentsCount,
    required this.lastOccupiedDay,
  });

  final List<BookingNightsCompanion> nightRows;
  final int nightCount;
  final int paymentsCount;
  final String? lastOccupiedDay;
}
