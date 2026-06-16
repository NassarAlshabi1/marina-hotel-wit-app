// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:marina_hotel_mobile/utils/app_logger.dart';

import '../local_db.dart';
import 'recalculate_booking_nights.dart';

/// Script لإعادة حساب عدد الليالي والحقول المشتقة لجميع الحجوزات
/// بناءً على التواريخ الفعلية
///
/// ⚠️ IMPORTANT: This is a standalone migration script
/// It should ONLY be run when the main application is NOT running.
///
/// الاستخدام:
/// ```bash
/// cd mobile
/// dart run lib/services/migrations/run_recalculate_nights.dart
/// ```
Future<void> main() async {
  AppLogger.info('🚀 Starting Booking Nights Recalculation Migration');
  AppLogger.info('=' * 80);
  AppLogger.info('⚠️  WARNING: Ensure the main application is NOT running!');
  AppLogger.info('=' * 80);
  AppLogger.info('هذه العملية ستقوم بـ:');
  AppLogger.info('1. قراءة جميع الحجوزات النشطة');
  AppLogger.info('2. إعادة حساب عدد الليالي من تاريخ الدخول حتى الآن');
  AppLogger.info('3. إعادة حساب المبالغ المستحقة والمدفوعة');
  AppLogger.info('4. تحديث booking_nights لكل حجز');
  AppLogger.info('=' * 80);
  AppLogger.info('');

  // إنشاء database connection
  final db = DatabaseManager.instance;

  try {
    // تشغيل الـ migration مع تقرير
    final migration = RecalculateBookingNightsMigration(db);
    final report = await migration.executeWithReport();

    // طباعة التقرير
    AppLogger.info(
  report.toString(),
);

    // حفظ التقرير في ملف JSON
    final reportFile = File(
      'recalculation_report_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    AppLogger.info('\n📄 Report saved to: ${reportFile.path}');

    // Exit code
    exit(report.success ? 0 : 1);
  } catch (e, stackTrace) {
    AppLogger.error('\n❌ Migration failed with error:');
    AppLogger.info(
  e.toString(),
);
    AppLogger.info('\nStack trace:');
    AppLogger.info(
  stackTrace.toString(),
);
    exit(1);
  } finally {
    // NOTE: We let the process exit clean up the database connection
    // instead of explicitly closing it. This avoids potential conflicts
    // with DatabaseManager's lifecycle tracking.
    //
    // If explicit cleanup is needed, use:
    // await DatabaseManager.close(); // NOT closeForRestore
    //
    // However, for standalone scripts, process exit is sufficient.
    AppLogger.info('✅ Migration script completed');
  }
}
