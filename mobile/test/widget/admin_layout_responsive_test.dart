import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/components/admin_layout.dart';
import 'package:marina_hotel_mobile/components/admin_sidebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAtSize(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AdminLayout(
            currentRoute: '/dashboard',
            title: 'اختبار التخطيط',
            body: SizedBox.expand(child: Center(child: Text('محتوى الشاشة'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() {
    // إعادة حجم النافذة حتى لا يؤثر الاختبار في الاختبارات التالية.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.implicitView;
    view?.resetPhysicalSize();
    view?.resetDevicePixelRatio();
  });

  testWidgets('يعرض تخطيط الهاتف في نافذة ضيقة', (tester) async {
    await pumpAtSize(tester, const Size(360, 800));

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.text('محتوى الشاشة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('يعرض تخطيط الكمبيوتر في 1024×768', (tester) async {
    await pumpAtSize(tester, const Size(1024, 768));

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(AdminSidebar), findsOneWidget);
    expect(find.text('اختبار التخطيط'), findsOneWidget);
    expect(find.text('محتوى الشاشة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('يبقى التخطيط مستقراً في أحجام الكمبيوتر الشائعة', (
    tester,
  ) async {
    for (final size in <Size>[const Size(1366, 768), const Size(1920, 1080)]) {
      await pumpAtSize(tester, size);
      expect(find.byType(AppBar), findsNothing, reason: 'size=$size');
      expect(find.byType(AdminSidebar), findsOneWidget, reason: 'size=$size');
      expect(find.text('محتوى الشاشة'), findsOneWidget, reason: 'size=$size');
      expect(tester.takeException(), isNull, reason: 'size=$size');
    }
  });
}
