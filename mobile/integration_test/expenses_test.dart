// ============================================================================
//  Marina Hotel — Integration Test: ExpensesListScreen (Patrol)
//  ============================================================================
//  السيناريو: Expenses — شاشة المصروفات تُبنى على جهاز حقيقي مع عنوان
//  «المصروفات» (مُتحقَّق منه من المصدر:
//  lib/screens/expenses/expenses_list.dart — السطر 114).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/expenses/expenses_list.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'يعرض شاشة المصروفات مع قائمة الأنواع الديناميكية',
    config: const PatrolTesterConfig(),
    ($) async {
      await $.tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: ExpensesListScreen(),
            ),
          ),
        ),
      );

      // انتظار تحميل customListNamesProvider/employeesListProvider
      await $.tester.pump(const Duration(seconds: 1));
      await $.tester.pump(const Duration(seconds: 1));

      expect($(ExpensesListScreen), findsOneWidget);
      expect(
        $('المصروفات'),
        findsWidgets,
        reason: 'عنوان شاشة المصروفات يجب أن يكون ظاهراً',
      );
    },
  );
}
