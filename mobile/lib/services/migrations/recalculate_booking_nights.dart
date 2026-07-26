import 'package:flutter/foundation.dart';

import '../booking_derived_fields_service.dart';
import '../local_db.dart';

/// Migration لإعادة حساب عدد الليالي والحقول المشتقة لجميع الحجوزات
/// بناءً على التواريخ الفعلية بدلاً من الاعتماد على القيم المحفوظة
class RecalculateBookingNightsMigration {
  RecalculateBookingNightsMigration(this.db);

  final AppDatabase db;

  Future<void> execute() async {
    debugPrint('🔧 Starting booking nights recalculation migration...');

    final derivedFieldsService = BookingDerivedFieldsService(db);

    // الحصول على جميع الحجوزات النشطة (غير المحذوفة)
    final bookings = await (db.select(
      db.bookings,
    )..where((b) => b.deletedAt.isNull())).get();

    if (bookings.isEmpty) {
      debugPrint('✅ No bookings found');
      return;
    }

    debugPrint('📋 Found ${bookings.length} bookings to recalculate');

    int successCount = 0;
    int errorCount = 0;

    for (final booking in bookings) {
      try {
        debugPrint(
          '   Processing ${booking.guestName} (${booking.roomNumber})...',
        );

        // إعادة حساب جميع الحقول المشتقة بناءً على التواريخ
        await derivedFieldsService.refreshForBooking(
          booking,
          forceRebuild: true,
        );

        successCount++;
      } catch (e) {
        debugPrint('   ❌ Error processing booking ${booking.id}: $e');
        errorCount++;
      }
    }

    debugPrint('');
    debugPrint('✅ Migration completed:');
    debugPrint('   - Success: $successCount');
    debugPrint('   - Errors: $errorCount');
  }

  Future<RecalculationReport> executeWithReport() async {
    final report = RecalculationReport();

    try {
      report.startTime = DateTime.now();

      final derivedFieldsService = BookingDerivedFieldsService(db);

      final bookings = await (db.select(
        db.bookings,
      )..where((b) => b.deletedAt.isNull())).get();

      report.totalBookingsFound = bookings.length;

      if (bookings.isEmpty) {
        report.success = true;
        report.message = 'No bookings found';
        return report;
      }

      for (final booking in bookings) {
        try {
          // حفظ القيم القديمة
          final oldExpectedNights = booking.expectedNights;
          final oldCalculatedNights = booking.calculatedNights;
          final oldTotalDue = booking.totalDueCached;

          // إعادة الحساب
          await derivedFieldsService.refreshForBooking(
            booking,
            forceRebuild: true,
          );

          // الحصول على القيم الجديدة
          final updatedBooking = await (db.select(
            db.bookings,
          )..where((b) => b.id.equals(booking.id))).getSingleOrNull();

          if (updatedBooking != null) {
            report.recalculatedBookings.add(
              BookingRecalculationDetails(
                bookingId: booking.id,
                guestName: booking.guestName,
                roomNumber: booking.roomNumber,
                checkinDate: booking.checkinDate,
                checkoutDate: booking.checkoutDate,
                oldExpectedNights: oldExpectedNights,
                newExpectedNights: updatedBooking.expectedNights,
                oldCalculatedNights: oldCalculatedNights,
                newCalculatedNights: updatedBooking.calculatedNights,
                oldTotalDue: oldTotalDue,
                newTotalDue: updatedBooking.totalDueCached,
                changed:
                    oldExpectedNights != updatedBooking.expectedNights ||
                    oldCalculatedNights != updatedBooking.calculatedNights ||
                    (oldTotalDue - updatedBooking.totalDueCached).abs() > 0.01,
              ),
            );

            report.bookingsRecalculated++;
          }
        } catch (e) {
          report.errors.add(
            'Failed to recalculate booking ${booking.id} (${booking.guestName}): $e',
          );
        }
      }

      report.success = report.errors.isEmpty;
      report.message = report.success
          ? 'Successfully recalculated ${report.bookingsRecalculated} bookings'
          : 'Recalculated ${report.bookingsRecalculated} bookings with ${report.errors.length} errors';
    } catch (e) {
      report.success = false;
      report.message = 'Migration failed: $e';
      report.errors.add(e.toString());
    } finally {
      report.endTime = DateTime.now();
    }

    return report;
  }
}

class RecalculationReport {
  DateTime? startTime;
  DateTime? endTime;
  bool success = false;
  String message = '';
  int totalBookingsFound = 0;
  int bookingsRecalculated = 0;
  List<BookingRecalculationDetails> recalculatedBookings = [];
  List<String> errors = [];

  Duration? get duration => startTime != null && endTime != null
      ? endTime!.difference(startTime!)
      : null;

  int get changedBookingsCount =>
      recalculatedBookings.where((b) => b.changed).length;

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'totalBookingsFound': totalBookingsFound,
      'bookingsRecalculated': bookingsRecalculated,
      'changedBookings': changedBookingsCount,
      'errors': errors,
      'duration': duration?.inMilliseconds,
      'recalculatedBookings': recalculatedBookings
          .map((b) => b.toJson())
          .toList(),
    };
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=' * 80);
    buffer.writeln('📊 Booking Nights Recalculation Report');
    buffer.writeln('=' * 80);
    buffer.writeln('Status: ${success ? '✅ SUCCESS' : '❌ FAILED'}');
    buffer.writeln('Message: $message');
    buffer.writeln('Bookings Found: $totalBookingsFound');
    buffer.writeln('Bookings Recalculated: $bookingsRecalculated');
    buffer.writeln('Bookings Changed: $changedBookingsCount');
    if (duration != null) {
      buffer.writeln('Duration: ${duration!.inMilliseconds}ms');
    }

    if (errors.isNotEmpty) {
      buffer.writeln('\n❌ Errors (${errors.length}):');
      for (final error in errors) {
        buffer.writeln('  • $error');
      }
    }

    final changedBookings = recalculatedBookings
        .where((b) => b.changed)
        .toList();
    if (changedBookings.isNotEmpty) {
      buffer.writeln('\n🔄 Changed Bookings (${changedBookings.length}):');
      for (final booking in changedBookings) {
        buffer.writeln(
          '  • ${booking.guestName} (Room ${booking.roomNumber}):',
        );
        if (booking.oldExpectedNights != booking.newExpectedNights) {
          buffer.writeln(
            '    expectedNights: ${booking.oldExpectedNights} → ${booking.newExpectedNights}',
          );
        }
        if (booking.oldCalculatedNights != booking.newCalculatedNights) {
          buffer.writeln(
            '    calculatedNights: ${booking.oldCalculatedNights} → ${booking.newCalculatedNights}',
          );
        }
        if ((booking.oldTotalDue - booking.newTotalDue).abs() > 0.01) {
          buffer.writeln(
            '    totalDue: ${booking.oldTotalDue.toStringAsFixed(2)} → ${booking.newTotalDue.toStringAsFixed(2)}',
          );
        }
      }
    }

    final unchangedCount = recalculatedBookings.length - changedBookings.length;
    if (unchangedCount > 0) {
      buffer.writeln(
        '\n✅ Unchanged Bookings: $unchangedCount (already correct)',
      );
    }

    buffer.writeln('=' * 80);
    return buffer.toString();
  }
}

class BookingRecalculationDetails {
  BookingRecalculationDetails({
    required this.bookingId,
    required this.guestName,
    required this.roomNumber,
    required this.checkinDate,
    required this.checkoutDate,
    required this.oldExpectedNights,
    required this.newExpectedNights,
    required this.oldCalculatedNights,
    required this.newCalculatedNights,
    required this.oldTotalDue,
    required this.newTotalDue,
    required this.changed,
  });
  final int bookingId;
  final String guestName;
  final String roomNumber;
  final String checkinDate;
  final String? checkoutDate;
  final int oldExpectedNights;
  final int newExpectedNights;
  final int oldCalculatedNights;
  final int newCalculatedNights;
  final double oldTotalDue;
  final double newTotalDue;
  final bool changed;

  Map<String, dynamic> toJson() {
    return {
      'bookingId': bookingId,
      'guestName': guestName,
      'roomNumber': roomNumber,
      'checkinDate': checkinDate,
      'checkoutDate': checkoutDate,
      'oldExpectedNights': oldExpectedNights,
      'newExpectedNights': newExpectedNights,
      'oldCalculatedNights': oldCalculatedNights,
      'newCalculatedNights': newCalculatedNights,
      'oldTotalDue': oldTotalDue,
      'newTotalDue': newTotalDue,
      'changed': changed,
    };
  }
}
