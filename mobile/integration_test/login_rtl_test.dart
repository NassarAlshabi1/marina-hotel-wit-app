import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
  patrolTest('يدعم اتجاه RTL من اليمين لليسار', ($) async {
    await $.pumpWidgetAndSettle(
      const ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: LoginScreen(),
          ),
        ),
      ),
    );

    final directionWidget = $.tester.widget<Directionality>(
      find
          .ancestor(
            of: $('تسجيل الدخول'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionWidget.textDirection, TextDirection.rtl);
  });
}
