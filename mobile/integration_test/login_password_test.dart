import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
  patrolTest('يتحكم في إظهار وإخفاء كلمة المرور', ($) async {
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

    await $(TextFormField).at(1).enterText('secret123');
    expect(
      $.tester.widget<TextFormField>($(TextFormField).at(1)).obscureText,
      isTrue,
    );

    await $(Icons.visibility).tap();
    expect(
      $.tester.widget<TextFormField>($(TextFormField).at(1)).obscureText,
      isFalse,
    );
    expect($('secret123'), findsOneWidget);
    expect($(Icons.visibility_off), findsOneWidget);

    await $(Icons.visibility_off).tap();
    expect(
      $.tester.widget<TextFormField>($(TextFormField).at(1)).obscureText,
      isTrue,
    );
    expect($(Icons.visibility), findsOneWidget);
  });
}
