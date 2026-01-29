// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
  debugPrint('🚀 Starting Booking Nights Recalculation Migration');
  debugPrint('=' * 80);
  debugPrint('⚠️  WARNING: Ensure the main application is NOT running!');
  debugPrint('=' * 80);
  debugPrint('هذه العملية ستقوم بـ:');
  debugPrint('1. قراءة جميع الحجوزات النشطة');
  debugPrint('2. إعادة حساب عدد الليالي من تاريخ الدخول حتى الآن');
  debugPrint('3. إعادة حساب المبالغ المستحقة والمدفوعة');
  debugPrint('4. تحديث booking_nights لكل حجز');
  debugPrint('=' * 80);
  debugPrint('');

  // إنشاء database connection
  final db = DatabaseManager.instance;

  try {
    // تشغيل الـ migration مع تقرير
    final migration = RecalculateBookingNightsMigration(db);
    final report = await migration.executeWithReport();

    // طباعة التقرير
    debugPrint(report.toString());

    // حفظ التقرير في ملف JSON
    final reportFile = File(
      'recalculation_report_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    debugPrint('\n📄 Report saved to: ${reportFile.path}');

    // Exit code
    exit(report.success ? 0 : 1);
  } catch (e, stackTrace) {
    debugPrint('\n❌ Migration failed with error:');
    debugPrint(e);
    debugPrint('\nStack trace:');
    debugPrint(stackTrace);
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
    debugPrint('✅ Migration script completed');
  }
}
