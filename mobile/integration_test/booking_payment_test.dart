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
import 'package:intl/date_symbol_data_local.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/payments/booking_payment_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart' as db;

void main() {
  setUpAll(() async {
    // PaymentSummaryCard uses DateFormat during build. Patrol runs in a
    // fresh process where intl locale data is not initialized automatically.
    await initializeDateFormatting();
  });

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
      // حقل إلزامي من SyncFields؛ يجب أن يطابق شكل البيانات المنتجة.
      syncTimestamp: now,
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

  patrolTest('يعرض شاشة المدفوعات اسم النزيل ورقم الغرفة', ($) async {
    final booking = createMockBooking();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        child: MaterialApp(
          home: BookingPaymentScreen(
            booking: booking,
            refreshDerivedFieldsOnInit: false,
            listenToHotelDayTicker: false,
          ),
        ),
      ),
    );

    // التحقق من وجود شاشة المدفوعات
    expect($(BookingPaymentScreen), findsOneWidget);

    // التحقق من اسم النزيل
    expect($('أحمد محمد'), findsWidgets);

    // التحقق من رقم الغرفة
    expect($('101'), findsWidgets);
  });

  patrolTest('يعرض زر "إرسال كشف حساب" في قائمة الإجراءات', ($) async {
    final booking = createMockBooking();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        child: MaterialApp(
          home: BookingPaymentScreen(
            booking: booking,
            refreshDerivedFieldsOnInit: false,
            listenToHotelDayTicker: false,
          ),
        ),
      ),
    );

    // زر كشف الحساب موجود داخل تبويب الإجراءات، وليس في التبويب الافتراضي.
    await $('الإجراءات').tap();
    await $.pumpAndSettle();
    final statementFinder = find.text('إرسال كشف حساب');
    await $.tester.ensureVisible(statementFinder);

    // التحقق من وجود الزر
    expect(
      $('إرسال كشف حساب'),
      findsOneWidget,
      reason: 'زر إرسال كشف حساب يجب أن يكون ظاهراً',
    );
  });

  patrolTest('يفتح نافذة "إرسال كشف حساب" عند الضغط على الزر', ($) async {
    final booking = createMockBooking();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        child: MaterialApp(
          home: BookingPaymentScreen(
            booking: booking,
            refreshDerivedFieldsOnInit: false,
            listenToHotelDayTicker: false,
          ),
        ),
      ),
    );

    // فتح تبويب الإجراءات ثم الضغط على بطاقة كشف الحساب.
    await $('الإجراءات').tap();
    await $.pumpAndSettle();
    final statementFinder = find.text('إرسال كشف حساب');
    await $.tester.ensureVisible(statementFinder);
    await $.tester.tap(find.text('إرسال كشف حساب'));
    await $.pumpAndSettle();

    // ✅ التحقق من ظهور نافذة الحوار
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'نافذة الحوار يجب أن تظهر عند الضغط على زر إرسال كشف حساب',
    );

    // ✅ التحقق من وجود بيانات العميل في النافذة
    expect(find.text('العميل'), findsOneWidget);
    expect(find.text('الغرفة'), findsOneWidget);
    expect(find.text('الهاتف'), findsOneWidget);

    // ✅ التحقق من وجود الملخص المالي
    // يظهر العنوان في الملخص وفي صف الإجمالي داخل الحوار.
    expect(find.text('الإجمالي'), findsWidgets);
    expect(find.text('المدفوع'), findsOneWidget);
    expect(find.text('المتبقي'), findsOneWidget);

    // ✅ التحقق من وجود زر معاينة رسالة WhatsApp
    expect(find.text('معاينة رسالة WhatsApp'), findsOneWidget);

    // ✅ التحقق من وجود أزرار المشاركة
    expect(find.text('إرسال كنص'), findsOneWidget);
    expect(find.text('مشاركة PDF'), findsOneWidget);
  });

  patrolTest('يعرض جدول المدفوعات المفصّل عند فتح نافذة كشف الحساب', ($) async {
    final booking = createMockBooking();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        child: MaterialApp(
          home: BookingPaymentScreen(
            booking: booking,
            refreshDerivedFieldsOnInit: false,
            listenToHotelDayTicker: false,
          ),
        ),
      ),
    );

    // فتح تبويب الإجراءات ثم بطاقة كشف الحساب.
    await $('الإجراءات').tap();
    await $.pumpAndSettle();
    final statementFinder = find.text('إرسال كشف حساب');
    await $.tester.ensureVisible(statementFinder);
    await $.tester.tap(find.text('إرسال كشف حساب'));
    await $.pumpAndSettle();

    // ✅ التحقق من وجود قسم سجل المدفوعات في النافذة
    // (سواء كان فارغاً أو به دفعات — كلاهما يحمل نفس الـ key)
    expect(
      find.byKey(const ValueKey('payments_section')),
      findsOneWidget,
      reason: 'يجب أن يوجد قسم لسجل المدفوعات في نافذة كشف الحساب',
    );
  });

  patrolTest('يعرض معاينة رسالة WhatsApp عند الضغط على زر المعاينة', ($) async {
    final booking = createMockBooking();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        child: MaterialApp(
          home: BookingPaymentScreen(
            booking: booking,
            refreshDerivedFieldsOnInit: false,
            listenToHotelDayTicker: false,
          ),
        ),
      ),
    );

    // فتح تبويب الإجراءات ثم بطاقة كشف الحساب.
    await $('الإجراءات').tap();
    await $.pumpAndSettle();
    final statementFinder = find.text('إرسال كشف حساب');
    await $.tester.ensureVisible(statementFinder);
    await $.tester.tap(find.text('إرسال كشف حساب'));

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
  });

  patrolTest('يغلق نافذة الحوار عند الضغط على زر إلغاء', ($) async {
    final booking = createMockBooking();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        child: MaterialApp(
          home: BookingPaymentScreen(
            booking: booking,
            refreshDerivedFieldsOnInit: false,
            listenToHotelDayTicker: false,
          ),
        ),
      ),
    );

    // فتح تبويب الإجراءات ثم بطاقة كشف الحساب.
    await $('الإجراءات').tap();
    await $.pumpAndSettle();
    final statementFinder = find.text('إرسال كشف حساب');
    await $.tester.ensureVisible(statementFinder);
    await $.tester.tap(find.text('إرسال كشف حساب'));
    await $.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    // الضغط على زر إلغاء
    await $('إلغاء').tap();
    await $.pumpAndSettle();

    // ✅ النافذة أُغلقت
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'نافذة الحوار يجب أن تُغلق عند الضغط على إلغاء',
    );
  });
}
