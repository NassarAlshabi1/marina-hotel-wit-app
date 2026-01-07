import 'package:drift/drift.dart';
import '../local_db.dart';

class FixNightsMultiplicationMigration {
  FixNightsMultiplicationMigration(this.db);

  final AppDatabase db;

  Future<void> execute() async {
    print('🔧 Starting nights multiplication fix migration...');
    
    await db.transaction(() async {
      // 1. الحصول على جميع الحجوزات التي لديها قيم مضروبة في 1000
      final problematicBookings = await (db.select(db.bookings)
            ..where((b) => b.expectedNights.isBiggerThanValue(1000)))
          .get();

      if (problematicBookings.isEmpty) {
        print('✅ No bookings found with multiplied nights values');
        return;
      }

      print('⚠️  Found ${problematicBookings.length} bookings with incorrect night values');

      for (final booking in problematicBookings) {
        final correctedExpectedNights = booking.expectedNights ~/ 1000;
        final correctedCalculatedNights = booking.calculatedNights ~/ 1000;
        final correctedTotalNightsCached = booking.totalNightsCached ~/ 1000;

        print('   Fixing booking ${booking.id} (${booking.guestName}):');
        print('     expectedNights: ${booking.expectedNights} → $correctedExpectedNights');
        print('     calculatedNights: ${booking.calculatedNights} → $correctedCalculatedNights');
        print('     totalNightsCached: ${booking.totalNightsCached} → $correctedTotalNightsCached');

        await (db.update(db.bookings)..where((b) => b.id.equals(booking.id))).write(
          BookingsCompanion(
            expectedNights: Value(correctedExpectedNights),
            calculatedNights: Value(correctedCalculatedNights),
            totalNightsCached: Value(correctedTotalNightsCached),
          ),
        );
      }

      print('✅ Fixed ${problematicBookings.length} bookings');
    });

    print('✅ Nights multiplication fix migration completed');
  }

  Future<MigrationReport> executeWithReport() async {
    final report = MigrationReport();
    
    try {
      report.startTime = DateTime.now();
      
      await db.transaction(() async {
        final problematicBookings = await (db.select(db.bookings)
              ..where((b) => b.expectedNights.isBiggerThanValue(1000)))
            .get();

        report.totalBookingsFound = problematicBookings.length;

        if (problematicBookings.isEmpty) {
          report.success = true;
          report.message = 'No bookings with incorrect night values found';
          return;
        }

        for (final booking in problematicBookings) {
          try {
            final correctedExpectedNights = booking.expectedNights ~/ 1000;
            final correctedCalculatedNights = booking.calculatedNights ~/ 1000;
            final correctedTotalNightsCached = booking.totalNightsCached ~/ 1000;

            await (db.update(db.bookings)..where((b) => b.id.equals(booking.id))).write(
              BookingsCompanion(
                expectedNights: Value(correctedExpectedNights),
                calculatedNights: Value(correctedCalculatedNights),
                totalNightsCached: Value(correctedTotalNightsCached),
              ),
            );

            report.fixedBookings.add(BookingFixDetails(
              bookingId: booking.id,
              guestName: booking.guestName,
              roomNumber: booking.roomNumber,
              oldExpectedNights: booking.expectedNights,
              newExpectedNights: correctedExpectedNights,
              oldCalculatedNights: booking.calculatedNights,
              newCalculatedNights: correctedCalculatedNights,
            ));

            report.bookingsFixed++;
          } catch (e) {
            report.errors.add('Failed to fix booking ${booking.id}: $e');
          }
        }

        report.success = report.errors.isEmpty;
        report.message = report.success 
            ? 'Successfully fixed ${report.bookingsFixed} bookings'
            : 'Fixed ${report.bookingsFixed} bookings with ${report.errors.length} errors';
      });
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

class MigrationReport {
  DateTime? startTime;
  DateTime? endTime;
  bool success = false;
  String message = '';
  int totalBookingsFound = 0;
  int bookingsFixed = 0;
  List<BookingFixDetails> fixedBookings = [];
  List<String> errors = [];

  Duration? get duration => startTime != null && endTime != null 
      ? endTime!.difference(startTime!) 
      : null;

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'totalBookingsFound': totalBookingsFound,
      'bookingsFixed': bookingsFixed,
      'errors': errors,
      'duration': duration?.inMilliseconds,
      'fixedBookings': fixedBookings.map((b) => b.toJson()).toList(),
    };
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=' * 80);
    buffer.writeln('📊 Migration Report');
    buffer.writeln('=' * 80);
    buffer.writeln('Status: ${success ? "✅ SUCCESS" : "❌ FAILED"}');
    buffer.writeln('Message: $message');
    buffer.writeln('Bookings Found: $totalBookingsFound');
    buffer.writeln('Bookings Fixed: $bookingsFixed');
    if (duration != null) {
      buffer.writeln('Duration: ${duration!.inMilliseconds}ms');
    }
    
    if (errors.isNotEmpty) {
      buffer.writeln('\n❌ Errors (${errors.length}):');
      for (var error in errors) {
        buffer.writeln('  • $error');
      }
    }
    
    if (fixedBookings.isNotEmpty) {
      buffer.writeln('\n✅ Fixed Bookings (${fixedBookings.length}):');
      for (var booking in fixedBookings) {
        buffer.writeln('  • ${booking.guestName} (Room ${booking.roomNumber}):');
        buffer.writeln('    expectedNights: ${booking.oldExpectedNights} → ${booking.newExpectedNights}');
        buffer.writeln('    calculatedNights: ${booking.oldCalculatedNights} → ${booking.newCalculatedNights}');
      }
    }
    
    buffer.writeln('=' * 80);
    return buffer.toString();
  }
}

class BookingFixDetails {
  final int bookingId;
  final String guestName;
  final String roomNumber;
  final int oldExpectedNights;
  final int newExpectedNights;
  final int oldCalculatedNights;
  final int newCalculatedNights;

  BookingFixDetails({
    required this.bookingId,
    required this.guestName,
    required this.roomNumber,
    required this.oldExpectedNights,
    required this.newExpectedNights,
    required this.oldCalculatedNights,
    required this.newCalculatedNights,
  });

  Map<String, dynamic> toJson() {
    return {
      'bookingId': bookingId,
      'guestName': guestName,
      'roomNumber': roomNumber,
      'oldExpectedNights': oldExpectedNights,
      'newExpectedNights': newExpectedNights,
      'oldCalculatedNights': oldCalculatedNights,
      'newCalculatedNights': newCalculatedNights,
    };
  }
}
