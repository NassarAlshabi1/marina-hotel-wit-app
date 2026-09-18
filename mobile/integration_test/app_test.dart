// Marina Hotel — Patrol smoke test for LoginScreen.
// Extended LoginScreen behaviors live in separate files so each invocation
// has an isolated Flutter/Instrumentation lifecycle.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
  patrolTest(
    'يعرض شاشة تسجيل الدخول بكامل عناصرها',
    config: const PatrolTesterConfig(),
    ($) async {
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

      expect($(LoginScreen), findsOneWidget);
      expect($('تسجيل الدخول'), findsOneWidget);
      expect($('اسم المستخدم'), findsOneWidget);
      expect($('كلمة المرور'), findsOneWidget);
      expect($('دخول'), findsOneWidget);
      expect($('تذكرني'), findsOneWidget);
      expect($(Icons.lock), findsOneWidget);
    },
  );
}
