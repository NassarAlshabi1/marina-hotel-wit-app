// ============================================================================
//  Marina Hotel — Integration Test: BookingsListScreen (Patrol)
//  ============================================================================
//  السيناريو: Bookings — قائمة الحجوزات تُبنى على جهاز حقيقي مع عنوان
//  «الحجوزات» وزر «حجز جديد» (النصوص مُتحقَّق منها من المصدر:
//  lib/screens/bookings/bookings_list.dart — السطران 68 و87).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/bookings/bookings_list.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'يعرض شاشة الحجوزات مع زر حجز جديد',
    config: const PatrolTesterConfig(),
    ($) async {
      await $.tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: BookingsListScreen(),
            ),
          ),
        ),
      );

      // انتظار تحميل bookingsListProvider/roomsListProvider من قاعدة البيانات
      await $.tester.pump(const Duration(seconds: 1));
      await $.tester.pump(const Duration(seconds: 1));

      expect($(BookingsListScreen), findsOneWidget);
      expect(
        $('الحجوزات'),
        findsWidgets,
        reason: 'عنوان شاشة الحجوزات يجب أن يكون ظاهراً',
      );
      expect(
        find.byTooltip('حجز جديد'),
        findsOneWidget,
        reason: 'زر الحجز الجديد (FloatingActionButton) يجب أن يكون موجوداً',
      );
    },
  );
}
