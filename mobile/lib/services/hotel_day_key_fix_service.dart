import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import '../utils/hotel_time_engine.dart';
import 'local_db.dart';

/// ✅ خدمة إصلاح hotelDayKey لجميع الجداول
///
/// **المشكلة:**
/// البيانات القديمة على Appwrite Cloud قد تحتوي على `hotelDayKey`
/// محسوب بقاعدة 14:00 القديمة بدل 14:01.
/// - السجلات بين 14:00 و 14:01 (دقيقة واحدة) تحتوي على hotelDayKey خاطئ
/// - بعض السجلات القديمة لا تحتوي على hotelDayKey أصلاً (null)
///
/// **الحل:**
/// عند تشغيل التطبيق، نعيد حساب hotelDayKey لكل سجل إذا كان خاطئًا.
/// هذا يُصلح البيانات المحلية (SQLite) — وعند المزامنة التالية
/// سيُرفع hotelDayKey المصحح إلى Appwrite Cloud عبر Outbox.
///
/// **الجداول المعالجة:**
/// - expenses (حقل التاريخ: date)
/// - salary_withdrawals (حقل التاريخ: withdrawDate)
/// - payments (حقل التاريخ: paymentDate)
/// - booking_nights (حقل التاريخ: nightStart)
/// - salary_payments (حقل التاريخ: paymentDateIso)
/// - payment_voids (حقل التاريخ: voidedAtIso)
/// - audit_logs (حقل التاريخ: timestampIso)
///
/// **ملاحظة:** booking_price_adjustments لا تحتوي على hotelDayKey
/// لكنها تحتوي على effectiveHotelDay (مفتاح اليوم الفندقي نفسه)
/// لذلك لا تحتاج إصلاح.
class HotelDayKeyFixService {
  HotelDayKeyFixService._();
  static final HotelDayKeyFixService instance = HotelDayKeyFixService._();

  /// هل تم الإصلاح بالفعل في هذه الجلسة؟
  bool _applied = false;

  /// تشغيل الإصلاح (مرة واحدة فقط لكل جلسة)
  Future<void> runIfNeeded(AppDatabase db) async {
    if (_applied) return;
    _applied = true;

    debugPrint('🔧 HotelDayKeyFixService: بدء فحص وإصلاح hotelDayKey...');

    int totalFixed = 0;

    try {
      totalFixed += await _fixExpenses(db);
      totalFixed += await _fixSalaryWithdrawals(db);
      totalFixed += await _fixPayments(db);
      totalFixed += await _fixBookingNights(db);
      totalFixed += await _fixSalaryPayments(db);
      totalFixed += await _fixPaymentVoids(db);
      totalFixed += await _fixAuditLogs(db);
    } catch (e) {
      debugPrint('⚠️ HotelDayKeyFixService: خطأ أثناء الإصلاح: $e');
    }

    if (totalFixed > 0) {
      debugPrint('✅ HotelDayKeyFixService: تم إصلاح $totalFixed سجل إجمالاً');
    } else {
      debugPrint('✅ HotelDayKeyFixService: لا توجد سجلات تحتاج إصلاح');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // حساب hotelDayKey الصحيح من التاريخ
  // ═══════════════════════════════════════════════════════════════

  /// حساب مفتاح اليوم الفندقي من تاريخ (تقويمي أو ISO)
  ///
  /// - تاريخ تقويمي (yyyy-MM-dd): يمرّر 14:01 لضمان اليوم الفندقي الصحيح
  /// - تاريخ ISO مع وقت (yyyy-MM-dd HH:mm): يستخدم الوقت مباشرة
  static String computeCorrectHotelDayKey(String date) {
    try {
      final trimmed = date.trim();
      // إذا كان التاريخ يحتوي على وقت (مثل "2026-05-19 14:30")
      if (trimmed.length > 10) {
        return HotelTimeEngine.getHotelDayKeyFromIso(trimmed);
      }
      // تاريخ تقويمي بدون وقت — نمرّر 14:01:00
      final parts = trimmed.split('-');
      if (parts.length != 3) {
        return HotelTimeEngine.getHotelDayKey();
      }
      final year = int.tryParse(parts[0]) ?? 1;
      final month = int.tryParse(parts[1]) ?? 1;
      final day = int.tryParse(parts[2]) ?? 1;
      return HotelTimeEngine.getHotelDayKey(
        dateTime: DateTime(year, month, day, 14, 1),
      );
    } catch (_) {
      return HotelTimeEngine.getHotelDayKey();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // إصلاح كل جدول
  // ═══════════════════════════════════════════════════════════════

  /// إصلاح expenses
  /// حقل التاريخ: date (yyyy-MM-dd تقويمي)
  /// hotelDayKey: nullable text
  Future<int> _fixExpenses(AppDatabase db) async {
    try {
      final rows = await (db.select(db.expenses)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      int fixed = 0;
      for (final row in rows) {
        final correctKey = computeCorrectHotelDayKey(row.date);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.expenses)
                ..where((t) => t.id.equals(row.id)))
              .write(ExpensesCompanion(
            hotelDayKey: d.Value(correctKey),
          ));
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 expenses: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ expenses: خطأ $e');
      return 0;
    }
  }

  /// إصلاح salary_withdrawals
  /// حقل التاريخ: withdrawDate (yyyy-MM-dd تقويمي)
  /// hotelDayKey: nullable text
  Future<int> _fixSalaryWithdrawals(AppDatabase db) async {
    try {
      final rows = await (db.select(db.salaryWithdrawals)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      int fixed = 0;
      for (final row in rows) {
        final correctKey = computeCorrectHotelDayKey(row.withdrawDate);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.salaryWithdrawals)
                ..where((t) => t.id.equals(row.id)))
              .write(SalaryWithdrawalsCompanion(
            hotelDayKey: d.Value(correctKey),
          ));
          fixed++;
        }
      }
      if (fixed > 0) {
        debugPrint('  📋 salary_withdrawals: تم إصلاح $fixed سجل');
      }
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ salary_withdrawals: خطأ $e');
      return 0;
    }
  }

  /// إصلاح payments
  /// حقل التاريخ: paymentDate (ISO format مع وقت)
  /// hotelDayKey: nullable text
  Future<int> _fixPayments(AppDatabase db) async {
    try {
      final rows = await (db.select(db.payments)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      int fixed = 0;
      for (final row in rows) {
        if (row.paymentDate.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.paymentDate);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.payments)
                ..where((t) => t.id.equals(row.id)))
              .write(PaymentsCompanion(
            hotelDayKey: d.Value(correctKey),
          ));
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 payments: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ payments: خطأ $e');
      return 0;
    }
  }

  /// إصلاح booking_nights
  /// حقل التاريخ: nightStart (ISO format)
  /// hotelDayKey: text (غير nullable)
  Future<int> _fixBookingNights(AppDatabase db) async {
    try {
      final rows = await db.select(db.bookingNights).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.nightStart.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.nightStart);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.bookingNights)
                ..where((t) => t.id.equals(row.id)))
              .write(BookingNightsCompanion(
            hotelDayKey: d.Value(correctKey),
          ));
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 booking_nights: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ booking_nights: خطأ $e');
      return 0;
    }
  }

  /// إصلاح salary_payments
  /// حقل التاريخ: paymentDateIso (ISO format)
  /// hotelDayKey: nullable text
  Future<int> _fixSalaryPayments(AppDatabase db) async {
    try {
      final rows = await db.select(db.salaryPayments).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.paymentDateIso.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.paymentDateIso);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.salaryPayments)
                ..where((t) => t.id.equals(row.id)))
              .write(SalaryPaymentsCompanion(
            hotelDayKey: d.Value(correctKey),
          ));
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 salary_payments: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ salary_payments: خطأ $e');
      return 0;
    }
  }

  /// إصلاح payment_voids
  /// حقل التاريخ: voidedAtIso (ISO format)
  /// hotelDayKey: text (غير nullable)
  Future<int> _fixPaymentVoids(AppDatabase db) async {
    try {
      final rows = await db.select(db.paymentVoids).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.voidedAtIso.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.voidedAtIso);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.paymentVoids)
                ..where((t) => t.id.equals(row.id)))
              .write(PaymentVoidsCompanion(
            hotelDayKey: d.Value(correctKey),
          ));
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 payment_voids: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ payment_voids: خطأ $e');
      return 0;
    }
  }

  /// إصلاح audit_logs
  /// حقل التاريخ: timestampIso (ISO format)
  /// hotelDayKey: text (غير nullable)
  Future<int> _fixAuditLogs(AppDatabase db) async {
    try {
      final rows = await db.select(db.auditLogs).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.timestampIso.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.timestampIso);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.auditLogs)
                ..where((t) => t.id.equals(row.id)))
              .write(AuditLogsCompanion(
            hotelDayKey: d.Value(correctKey),
          ));
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 audit_logs: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ audit_logs: خطأ $e');
      return 0;
    }
  }
}
