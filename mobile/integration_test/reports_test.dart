// ============================================================================
//  Marina Hotel — Integration Test: ReportsScreen (Patrol)
//  ============================================================================
//  السيناريو: Reports — شاشة التقارير تُبنى على جهاز حقيقي مع عنوان
//  «التقارير» (مُتحقَّق منه من المصدر:
//  lib/screens/reports/reports_screen.dart — السطر 302).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/reports/reports_screen.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'يعرض شاشة التقارير الرئيسية',
    config: const PatrolTesterConfig(),
    ($) async {
      await $.tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: ReportsScreen(),
            ),
          ),
        ),
      );

      await $.tester.pump(const Duration(seconds: 1));
      await $.tester.pump(const Duration(seconds: 1));

      expect($(ReportsScreen), findsOneWidget);
      expect(
        $('التقارير'),
        findsWidgets,
        reason: 'عنوان شاشة التقارير يجب أن يكون ظاهراً',
      );
    },
  );
}
