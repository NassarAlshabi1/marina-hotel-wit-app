// ============================================================================
//  Marina Hotel — Integration Test: Booking Payment Screen (Patrol)
//  ============================================================================
//  يتحقق من: شاشة معالجة المدفوعات تعرض بيانات الحجز →
//            زر "إرسال كشف حساب" يفتح نافذة بها جدول الدفعات المفصّل
//
//  ✅ migrated to Patrol 4.7.x — uses patrolTest + $ custom finders
//     Run with: patrol test --target integration_test/booking_payment_test.dart
// ============================================================================

// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/payments/booking_payment_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart' as db;

void main() {
  // إنشاء حجز وهمي للاختبار
  db.Booking createMockBooking() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.Booking(
      localUuid: 'test-booking-001',
      serverId: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      lastModified: now,
      createdAtIso: null,
      updatedAtIso: null,
      deletedAtIso: null,
      createdAtEpoch: now,
      lastModifiedEpoch: now,
      version: 1,
      origin: 'local',
      vectorClock: 'device1:1',
      deviceId: 'test-device',
      idempotencyKey: null,
      id: 1,
      serverBookingId: null,
      roomNumber: '101',
      guestName: 'أحمد محمد',
      guestPhone: '+9677734587456',
      guestIdType: 'passport',
      guestIdNumber: 'A12345678',
      guestIdIssueDate: null,
      guestIdIssuePlace: null,
      guestNationality: 'يمني',
      guestEmail: null,
      guestAddress: null,
      checkinDate: '2026-07-15',
      checkoutDate: '2026-07-18',
      actualCheckout: null,
      status: 'checked_in',
      notes: null,
      discount: 0,
      discountType: 'fixed',
      discountStartDate: null,
      expectedNights: 3,
      calculatedNights: 3,
      totalNightsCached: 3,
      stayDurationIso: null,
      lastNightEpoch: null,
      isOverdue: false,
      needsCheckoutReview: false,
      totalDueCached: 1500.0,
      totalPaidCached: 0,
      remainingBalanceCached: 1500.0,
      isFullyPaid: false,
      hotelDayCheckin: '2026-07-15',
      hotelDayCheckout: null,
    );
  }

  patrolTest(
    'يعرض شاشة المدفوعات اسم النزيل ورقم الغرفة',
    ($) async {
      final booking = createMockBooking();

      await $.pumpWidgetAndSettle(
        ProviderScope(
          child: MaterialApp(
            home: BookingPaymentScreen(booking: booking),
          ),
        ),
      );

      // التحقق من وجود شاشة المدفوعات
      expect($(BookingPaymentScreen), findsOneWidget);

      // التحقق من اسم النزيل
      expect($('أحمد محمد'), findsWidgets);

      // التحقق من رقم الغرفة
      expect($('101'), findsWidgets);
    },
  );

  patrolTest(
    'يعرض زر "إرسال كشف حساب" في قائمة الإجراءات',
    ($) async {
      final booking = createMockBooking();

      await $.pumpWidgetAndSettle(
        ProviderScope(
          child: MaterialApp(
            home: BookingPaymentScreen(booking: booking),
          ),
        ),
      );

      // التمرير لأسفل للعثور على زر إرسال كشف الحساب
      await $('إرسال كشف حساب').scrollTo();

      // التحقق من وجود الزر
      expect(
        $('إرسال كشف حساب'),
        findsOneWidget,
        reason: 'زر إرسال كشف حساب يجب أن يكون ظاهراً',
      );
    },
  );

  patrolTest(
    'يفتح نافذة "إرسال كشف حساب" عند الضغط على الزر',
    ($) async {
      final booking = createMockBooking();

      await $.pumpWidgetAndSettle(
        ProviderScope(
          child: MaterialApp(
            home: BookingPaymentScreen(booking: booking),
          ),
        ),
      );

      // التمرير لأسفل والضغط على زر إرسال كشف الحساب
      await $('إرسال كشف حساب').scrollTo();
      await $('إرسال كشف حساب').tap();

      // ✅ التحقق من ظهور نافذة الحوار
      expect(
        $(AlertDialog),
        findsOneWidget,
        reason: 'نافذة الحوار يجب أن تظهر عند الضغط على زر إرسال كشف حساب',
      );

      // ✅ التحقق من وجود بيانات العميل في النافذة
      expect($('العميل'), findsOneWidget);
      expect($('الغرفة'), findsOneWidget);
      expect($('الهاتف'), findsOneWidget);

      // ✅ التحقق من وجود الملخص المالي
      expect($('الإجمالي'), findsOneWidget);
      expect($('المدفوع'), findsOneWidget);
      expect($('المتبقي'), findsOneWidget);

      // ✅ التحقق من وجود زر معاينة رسالة WhatsApp
      expect($('معاينة رسالة WhatsApp'), findsOneWidget);

      // ✅ التحقق من وجود أزرار المشاركة
      expect($('إرسال كنص'), findsOneWidget);
      expect($('مشاركة PDF'), findsOneWidget);
    },
  );

  patrolTest(
    'يعرض جدول المدفوعات المفصّل عند فتح نافذة كشف الحساب',
    ($) async {
      final booking = createMockBooking();

      await $.pumpWidgetAndSettle(
        ProviderScope(
          child: MaterialApp(
            home: BookingPaymentScreen(booking: booking),
          ),
        ),
      );

      // فتح نافذة كشف الحساب
      await $('إرسال كشف حساب').scrollTo();
      await $('إرسال كشف حساب').tap();

      // ✅ التحقق من وجود قسم سجل المدفوعات في النافذة
      // (سواء كان فارغاً أو به دفعات — كلاهما يحمل نفس الـ key)
      expect(
        const ValueKey('payments_section'),
        findsOneWidget,
        reason: 'يجب أن يوجد قسم لسجل المدفوعات في نافذة كشف الحساب',
      );
    },
  );

  patrolTest(
    'يعرض معاينة رسالة WhatsApp عند الضغط على زر المعاينة',
    ($) async {
      final booking = createMockBooking();

      await $.pumpWidgetAndSettle(
        ProviderScope(
          child: MaterialApp(
            home: BookingPaymentScreen(booking: booking),
          ),
        ),
      );

      // فتح نافذة كشف الحساب
      await $('إرسال كشف حساب').scrollTo();
      await $('إرسال كشف حساب').tap();

      // الضغط على زر المعاينة
      await $('معاينة رسالة WhatsApp').tap();

      // ✅ التحقق من ظهور معاينة الرسالة
      expect(
        $('إخفاء المعاينة'),
        findsOneWidget,
        reason: 'زر المعاينة يجب أن يتحول إلى "إخفاء المعاينة"',
      );

      // ✅ التحقق من ظهور عدّاد الأحرف
      expect(
        find.textContaining('1000 حرف'),
        findsOneWidget,
        reason: 'عدّاد الأحرف يجب أن يظهر في معاينة WhatsApp',
      );

      // ✅ التحقق من ظهور رأس رسالة كشف الحساب في المعاينة
      expect(find.textContaining('كشف حساب'), findsWidgets);
      expect(find.textContaining('MARINA HOTEL'), findsWidgets);
    },
  );

  patrolTest(
    'يغلق نافذة الحوار عند الضغط على زر إلغاء',
    ($) async {
      final booking = createMockBooking();

      await $.pumpWidgetAndSettle(
        ProviderScope(
          child: MaterialApp(
            home: BookingPaymentScreen(booking: booking),
          ),
        ),
      );

      // فتح نافذة كشف الحساب
      await $('إرسال كشف حساب').scrollTo();
      await $('إرسال كشف حساب').tap();

      expect($(AlertDialog), findsOneWidget);

      // الضغط على زر إلغاء
      await $('إلغاء').tap();

      // ✅ النافذة أُغلقت
      expect(
        $(AlertDialog),
        findsNothing,
        reason: 'نافذة الحوار يجب أن تُغلق عند الضغط على إلغاء',
      );
    },
  );
}
