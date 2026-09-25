// ============================================================================
//  Marina Hotel — Integration Test: DashboardScreen (Patrol)
//  ============================================================================
//  السيناريو: Dashboard — لوحة التحكم تُبنى على جهاز حقيقي مع بطاقات
//  المدفوعات/المصروفات/المتبقي (النصوص مُتحقَّق منها من المصدر:
//  lib/screens/dashboard_screen.dart — 'مدفوعات اليوم' / 'المصروفات' /
//  'المتبقي').
//
//  ملاحظة تقنية: نستخدم pump بعدد ثابت بدل pumpAndSettle — شاشة لوحة
//  التحكم تحوي مؤشر مزامنة حيّ ومؤقّتات دورية قد تُبقي الإطارات
//  قيد الجدولة، و pumpAndSettle سينتظر حتى الـ timeout.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/dashboard_screen.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'يعرض لوحة التحكم مع بطاقات مدفوعات اليوم والمصروفات والمتبقي',
    config: const PatrolTesterConfig(),
    ($) async {
      await $.tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: DashboardScreen(),
            ),
          ),
        ),
      );

      // انتظار اكتمال أول إطارين + تحميل الـ providers غير المتزامن
      await $.tester.pump(const Duration(seconds: 1));
      await $.tester.pump(const Duration(seconds: 1));

      expect($(DashboardScreen), findsOneWidget);
      expect(
        $('مدفوعات اليوم'),
        findsWidgets,
        reason: 'بطاقة مدفوعات اليوم يجب أن تكون ظاهرة',
      );
      expect(
        $('المصروفات'),
        findsWidgets,
        reason: 'بطاقة المصروفات يجب أن تكون ظاهرة',
      );
      expect(
        $('المتبقي'),
        findsWidgets,
        reason: 'بطاقة المتبقي يجب أن تكون ظاهرة',
      );
    },
  );
}
