import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
  patrolTest('يقبل إدخال بيانات في حقلي المستخدم وكلمة المرور', ($) async {
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

    await $(TextFormField).at(0).enterText('admin');
    await $(TextFormField).at(1).enterText('wrongpass');

    expect($('admin'), findsOneWidget);
    expect($.tester.takeException(), isNull);
  });
}
