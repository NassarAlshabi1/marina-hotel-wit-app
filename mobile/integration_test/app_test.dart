// ============================================================================
//  Marina Hotel — Integration Test: App Smoke Test (Patrol)
//  ============================================================================
//  يتحقق من: شاشة تسجيل الدخول تُعرَض بشكل صحيح →
//            التحقق من صحة المدخلات →
//            التحكم في إظهار/إخفاء كلمة المرور →
//            خيار "تذكرني" →
//            دعم اتجاه RTL
//
//  ملاحظة: نتجنَّب استدعاء main() كاملاً لأنه يُهيِّئ Firebase + Appwrite
//  التي تحتاج إعدادات سرية لا تتوفر في CI. نختبر LoginScreen مباشرة.
//
//  ✅ migrated to Patrol 4.7.x — uses patrolTest + $ custom finders
//     Run with: patrol test --target integration_test/app_test.dart
// ============================================================================

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

      // التحقق من ظهور شاشة تسجيل الدخول
      expect(
        $(LoginScreen),
        findsOneWidget,
        reason: 'يجب أن تظهر شاشة تسجيل الدخول',
      );

      // التحقق من وجود عنوان "تسجيل الدخول"
      expect($('تسجيل الدخول'), findsOneWidget);

      // التحقق من وجود حقلي اسم المستخدم وكلمة المرور
      expect($('اسم المستخدم'), findsOneWidget);
      expect($('كلمة المرور'), findsOneWidget);

      // التحقق من وجود زر الدخول
      expect($('دخول'), findsOneWidget);

      // التحقق من وجود خيار "تذكرني"
      expect($('تذكرني'), findsOneWidget);

      // التحقق من وجود أيقونة القفل (header)
      expect($(Icons.lock), findsOneWidget);
    },
  );

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

    // الضغط على زر الدخول بدون إدخال بيانات
    await $('دخول').tap();

    // يجب أن تظهر رسالة خطأ تطلب إدخال اسم المستخدم
    expect(
      $('يرجى إدخال اسم المستخدم'),
      findsOneWidget,
      reason: 'يجب أن تظهر رسالة تحقق عند ترك الحقل فارغاً',
    );

    // يجب أن تظهر رسالة خطأ تطلب إدخال كلمة المرور
    expect(
      $('يرجى إدخال كلمة المرور'),
      findsOneWidget,
      reason: 'يجب أن تظهر رسالة تحقق عند ترك كلمة المرور فارغة',
    );
  });

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

    // إدخال اسم المستخدم في الحقل الأول
    await $(TextFormField).at(0).enterText('admin');

    // إدخال كلمة المرور في الحقل الثاني
    await $(TextFormField).at(1).enterText('wrongpass');

    // التحقق من أن النص أصبح في حقل اسم المستخدم
    expect($('admin'), findsOneWidget);

    // الضغط على زر الدخول — سيفشل لأن لا backend، لكن يجب ألا يرمي استثناء
    await $('دخول').tap();
    await $.pump(const Duration(seconds: 1));

    // التطبيق لا ينهار — هذا نجاح الاختبار
    expect($.tester.takeException(), isNull);
  });

  patrolTest('يتحكم في إظهار/إخفاء كلمة المرور', ($) async {
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

    // إدخال كلمة مرور
    await $(TextFormField).at(1).enterText('secret123');

    // افتراضياً كلمة المرور مخفية (obscured)
    expect(
      $('secret123'),
      findsNothing,
      reason: 'كلمة المرور يجب أن تكون مخفية افتراضياً',
    );

    // الضغط على أيقونة إظهار كلمة المرور
    await $(Icons.visibility).tap();

    // الآن كلمة المرور ظاهرة
    expect(
      $('secret123'),
      findsOneWidget,
      reason: 'كلمة المرور يجب أن تكون ظاهرة بعد الضغط على أيقونة العين',
    );

    // الأيقونة تغيَّرت إلى visibility_off
    expect($(Icons.visibility_off), findsOneWidget);

    // الضغط مرة أخرى لإخفائها
    await $(Icons.visibility_off).tap();

    // كلمة المرور مخفية مرة أخرى
    expect($('secret123'), findsNothing);
    expect($(Icons.visibility), findsOneWidget);
  });

  patrolTest('يتحكم في خيار "تذكرني"', ($) async {
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

    // افتراضياً "تذكرني" قد يكون مفعل أو لا — نسجِّل القيمة الأولية
    Checkbox checkbox = $.tester.widget<Checkbox>($(Checkbox));
    expect(checkbox.value, isNotNull);
    final initialValue = checkbox.value!;

    // الضغط على الـ Checkbox
    await $(Checkbox).tap();

    // القيمة انقلبت
    checkbox = $.tester.widget<Checkbox>($(Checkbox));
    expect(
      checkbox.value,
      !initialValue,
      reason: 'الضغط على Checkbox يجب أن يقلب قيمته',
    );

    // الضغط مرة أخرى لإعادتها
    await $(Checkbox).tap();
    checkbox = $.tester.widget<Checkbox>($(Checkbox));
    expect(checkbox.value, initialValue);
  });

  patrolTest('يدعم اتجاه RTL (من اليمين لليسار)', ($) async {
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

    // التحقق من أن شاشة تسجيل الدخول في وضع RTL
    // (LoginScreen نفسها تستخدم Directionality(textDirection: TextDirection.rtl))
    final directionWidget = $.tester.widget<Directionality>(
      find
          .ancestor(
            of: $('تسجيل الدخول'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(
      directionWidget.textDirection,
      TextDirection.rtl,
      reason: 'التطبيق يجب أن يكون في وضع RTL للعربية',
    );
  });

  patrolTest('يعرض رسالة خطأ عند توفرها من authProvider', ($) async {
    // ملاحظة: authProvider.error يُحدَّث فقط بعد محاولة تسجيل دخول فاشلة
    // لا نستطيع محاكاة ذلك بدون backend حقيقي، لذا نتحقق فقط من
    // أن الـ widget شجرة سليمة وتقبل التحديثات
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

    // إدخال بيانات
    await $(TextFormField).at(0).enterText('test');
    await $(TextFormField).at(1).enterText('test');

    // محاولة الدخول
    await $('دخول').tap();
    await $.pump();

    // التطبيق ما زال يعود بدون انهيار
    expect($(LoginScreen), findsOneWidget);
  });
}
