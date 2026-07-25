// ============================================================================
<<<<<<< HEAD
//  Marina Hotel — Integration Test: App Smoke Test (Patrol)
//  ============================================================================
=======
//  Marina Hotel — Integration Test: App Smoke Test
>>>>>>> origin/refactor/clean-v2
//  يتحقق من: شاشة تسجيل الدخول تُعرَض بشكل صحيح →
//            التحقق من صحة المدخلات →
//            التحكم في إظهار/إخفاء كلمة المرور →
//            خيار "تذكرني" →
//            دعم اتجاه RTL
//
//  ملاحظة: نتجنَّب استدعاء main() كاملاً لأنه يُهيِّئ Firebase + Appwrite
//  التي تحتاج إعدادات سرية لا تتوفر في CI. نختبر LoginScreen مباشرة.
<<<<<<< HEAD
//
//  ✅ migrated to Patrol 4.7.x — uses patrolTest + $ custom finders
//     Run with: patrol test --target integration_test/app_test.dart
=======
>>>>>>> origin/refactor/clean-v2
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
<<<<<<< HEAD
import 'package:patrol/patrol.dart';
=======
import 'package:integration_test/integration_test.dart';
>>>>>>> origin/refactor/clean-v2

import 'package:marina_hotel_mobile/screens/auth/login_screen.dart';

void main() {
<<<<<<< HEAD
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
      expect($(LoginScreen), findsOneWidget, reason: 'يجب أن تظهر شاشة تسجيل الدخول');

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

  patrolTest(
    'يتحقق من صحة المدخلات قبل محاولة الدخول',
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

      // الضغط على زر الدخول بدون إدخال بيانات
      await $('دخول').tap();

      // يجب أن تظهر رسالة خطأ تطلب إدخال اسم المستخدم
      expect($('يرجى إدخال اسم المستخدم'), findsOneWidget,
          reason: 'يجب أن تظهر رسالة تحقق عند ترك الحقل فارغاً');

      // يجب أن تظهر رسالة خطأ تطلب إدخال كلمة المرور
      expect($('يرجى إدخال كلمة المرور'), findsOneWidget,
          reason: 'يجب أن تظهر رسالة تحقق عند ترك كلمة المرور فارغة');
    },
  );

  patrolTest(
    'يقبل إدخال بيانات في حقلي المستخدم وكلمة المرور',
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
    },
  );

  patrolTest(
    'يتحكم في إظهار/إخفاء كلمة المرور',
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

      // إدخال كلمة مرور
      await $(TextFormField).at(1).enterText('secret123');

      // افتراضياً كلمة المرور مخفية (obscured)
      expect($('secret123'), findsNothing, reason: 'كلمة المرور يجب أن تكون مخفية افتراضياً');

      // الضغط على أيقونة إظهار كلمة المرور
      await $(Icons.visibility).tap();

      // الآن كلمة المرور ظاهرة
      expect($('secret123'), findsOneWidget,
          reason: 'كلمة المرور يجب أن تكون ظاهرة بعد الضغط على أيقونة العين');

      // الأيقونة تغيَّرت إلى visibility_off
      expect($(Icons.visibility_off), findsOneWidget);

      // الضغط مرة أخرى لإخفائها
      await $(Icons.visibility_off).tap();

      // كلمة المرور مخفية مرة أخرى
      expect($('secret123'), findsNothing);
      expect($(Icons.visibility), findsOneWidget);
    },
  );

  patrolTest(
    'يتحكم في خيار "تذكرني"',
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

      // افتراضياً "تذكرني" قد يكون مفعل أو لا — نسجِّل القيمة الأولية
      Checkbox checkbox = $.tester.widget<Checkbox>($(Checkbox));
=======
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Marina Hotel — Login Screen Smoke Test', () {
    // helper لالتفاف LoginScreen بـ MaterialApp + RTL
    Widget buildApp() {
      return const ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: LoginScreen(),
          ),
        ),
      );
    }

    testWidgets('يعرض شاشة تسجيل الدخول بكامل عناصرها', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // التحقق من ظهور شاشة تسجيل الدخول
      expect(find.byType(LoginScreen), findsOneWidget,
          reason: 'يجب أن تظهر شاشة تسجيل الدخول');

      // التحقق من وجود عنوان "تسجيل الدخول"
      expect(find.text('تسجيل الدخول'), findsOneWidget);

      // التحقق من وجود حقلي اسم المستخدم وكلمة المرور
      expect(find.text('اسم المستخدم'), findsOneWidget);
      expect(find.text('كلمة المرور'), findsOneWidget);

      // التحقق من وجود زر الدخول
      expect(find.text('دخول'), findsOneWidget);

      // التحقق من وجود خيار "تذكرني"
      expect(find.text('تذكرني'), findsOneWidget);

      // التحقق من وجود أيقونة القفل (header)
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('يتحقق من صحة المدخلات قبل محاولة الدخول', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // الضغط على زر الدخول بدون إدخال بيانات
      await tester.tap(find.text('دخول'));
      await tester.pumpAndSettle();

      // يجب أن تظهر رسالة خطأ تطلب إدخال اسم المستخدم
      expect(find.text('يرجى إدخال اسم المستخدم'), findsOneWidget,
          reason: 'يجب أن تظهر رسالة تحقق عند ترك الحقل فارغاً');

      // يجب أن تظهر رسالة خطأ تطلب إدخال كلمة المرور
      expect(find.text('يرجى إدخال كلمة المرور'), findsOneWidget,
          reason: 'يجب أن تظهر رسالة تحقق عند ترك كلمة المرور فارغة');
    });

    testWidgets('يقبل إدخال بيانات في حقلي المستخدم وكلمة المرور', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // إدخال اسم المستخدم في الحقل الأول
      await tester.enterText(find.byType(TextFormField).first, 'admin');
      await tester.pumpAndSettle();

      // إدخال كلمة المرور في الحقل الثاني
      await tester.enterText(find.byType(TextFormField).last, 'wrongpass');
      await tester.pumpAndSettle();

      // التحقق من أن النص أصبح في حقل اسم المستخدم
      expect(find.text('admin'), findsOneWidget);

      // الضغط على زر الدخول — سيفشل لأن لا backend، لكن يجب ألا يرمي استثناء
      await tester.tap(find.text('دخول'));
      await tester.pump(const Duration(seconds: 1));

      // التطبيق لا ينهار — هذا نجاح الاختبار
      expect(tester.takeException(), isNull);
    });

    testWidgets('يتحكم في إظهار/إخفاء كلمة المرور', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // إدخال كلمة مرور
      await tester.enterText(find.byType(TextFormField).last, 'secret123');
      await tester.pumpAndSettle();

      // افتراضياً كلمة المرور مخفية (obscured)
      expect(find.text('secret123'), findsNothing,
          reason: 'كلمة المرور يجب أن تكون مخفية افتراضياً');

      // الضغط على أيقونة إظهار كلمة المرور
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();

      // الآن كلمة المرور ظاهرة
      expect(find.text('secret123'), findsOneWidget,
          reason: 'كلمة المرور يجب أن تكون ظاهرة بعد الضغط على أيقونة العين');

      // الأيقونة تغيَّرت إلى visibility_off
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);

      // الضغط مرة أخرى لإخفائها
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      // كلمة المرور مخفية مرة أخرى
      expect(find.text('secret123'), findsNothing);
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('يتحكم في خيار "تذكرني"', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // افتراضياً "تذكرني" قد يكون مفعل أو لا — نسجِّل القيمة الأولية
      Checkbox checkbox = tester.widget(find.byType(Checkbox));
>>>>>>> origin/refactor/clean-v2
      expect(checkbox.value, isNotNull);
      final initialValue = checkbox.value!;

      // الضغط على الـ Checkbox
<<<<<<< HEAD
      await $(Checkbox).tap();

      // القيمة انقلبت
      checkbox = $.tester.widget<Checkbox>($(Checkbox));
      expect(checkbox.value, !initialValue, reason: 'الضغط على Checkbox يجب أن يقلب قيمته');

      // الضغط مرة أخرى لإعادتها
      await $(Checkbox).tap();
      checkbox = $.tester.widget<Checkbox>($(Checkbox));
      expect(checkbox.value, initialValue);
    },
  );

  patrolTest(
    'يدعم اتجاه RTL (من اليمين لليسار)',
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

      // التحقق من أن شاشة تسجيل الدخول في وضع RTL
      // (LoginScreen نفسها تستخدم Directionality(textDirection: TextDirection.rtl))
      final directionWidget = $.tester.widget<Directionality>(
        find.ancestor(
          of: $('تسجيل الدخول'),
=======
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // القيمة انقلبت
      checkbox = tester.widget(find.byType(Checkbox));
      expect(checkbox.value, !initialValue,
          reason: 'الضغط على Checkbox يجب أن يقلب قيمته');

      // الضغط مرة أخرى لإعادتها
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      checkbox = tester.widget(find.byType(Checkbox));
      expect(checkbox.value, initialValue);
    });

    testWidgets('يدعم اتجاه RTL (من اليمين لليسار)', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // التحقق من أن شاشة تسجيل الدخول في وضع RTL
      // (LoginScreen نفسها تستخدم Directionality(textDirection: TextDirection.rtl))
      final directionWidget = tester.widget<Directionality>(
        find.ancestor(
          of: find.text('تسجيل الدخول'),
>>>>>>> origin/refactor/clean-v2
          matching: find.byType(Directionality),
        ).first,
      );
      expect(directionWidget.textDirection, TextDirection.rtl,
          reason: 'التطبيق يجب أن يكون في وضع RTL للعربية');
<<<<<<< HEAD
    },
  );

  patrolTest(
    'يعرض رسالة خطأ عند توفرها من authProvider',
    ($) async {
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
    },
  );
=======
    });

    testWidgets('يعرض رسالة خطأ عند توفرها من authProvider', (tester) async {
      // ملاحظة: authProvider.error يُحدَّث فقط بعد محاولة تسجيل دخول فاشلة
      // لا نستطيع محاكاة ذلك بدون backend حقيقي، لذا نتحقق فقط من
      // أن الـ widget شجرة سليمة وتقبل التحديثات
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // إدخال بيانات
      await tester.enterText(find.byType(TextFormField).first, 'test');
      await tester.enterText(find.byType(TextFormField).last, 'test');
      await tester.pumpAndSettle();

      // محاولة الدخول
      await tester.tap(find.text('دخول'));
      await tester.pump();

      // التطبيق ما زال يعمل بدون انهيار
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
>>>>>>> origin/refactor/clean-v2
}
