import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
  patrolTest('يتحقق من صحة المدخلات قبل محاولة الدخول', ($) async {
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

    await $('دخول').tap();

    expect($('يرجى إدخال اسم المستخدم'), findsOneWidget);
    expect($('يرجى إدخال كلمة المرور'), findsOneWidget);
  });
}
