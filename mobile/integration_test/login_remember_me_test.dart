import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
  patrolTest('يتحكم في خيار تذكرني', ($) async {
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

    Checkbox checkbox = $.tester.widget<Checkbox>($(Checkbox));
    expect(checkbox.value, isNotNull);
    final initialValue = checkbox.value!;

    await $(Checkbox).tap();
    checkbox = $.tester.widget<Checkbox>($(Checkbox));
    expect(checkbox.value, !initialValue);

    await $(Checkbox).tap();
    checkbox = $.tester.widget<Checkbox>($(Checkbox));
    expect(checkbox.value, initialValue);
  });
}
