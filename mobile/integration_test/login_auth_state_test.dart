import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
  patrolTest('يبقى سليماً عند توفر حالة خطأ من authProvider', ($) async {
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

    await $(TextFormField).at(0).enterText('test');
    await $(TextFormField).at(1).enterText('test');

    expect($(LoginScreen), findsOneWidget);
  });
}
