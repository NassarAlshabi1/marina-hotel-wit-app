import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/screens/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAtSize(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomsListProvider.overrideWith((ref) => Stream.value(const [])),
          bookingsListProvider.overrideWith((ref) => Stream.value(const [])),
          employeesListProvider.overrideWith((ref) => Stream.value(const [])),
          usersCountProvider.overrideWith((ref) async => 0),
          simpleNotesUnreadCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.implicitView;
    view?.resetPhysicalSize();
    view?.resetDevicePixelRatio();
  });

  testWidgets('لا يحدث overflow في الهاتف وتبقى الأقسام قابلة للوصول', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(360, 800));

    expect(find.text('الوصول السريع'), findsOneWidget);
    expect(find.text('إدارة البيانات'), findsOneWidget);
    expect(find.text('المزامنة والنسخ الاحتياطي'), findsOneWidget);
    expect(find.text('الإشعارات والتقارير'), findsOneWidget);
    expect(find.text('التطبيق والخدمات'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('إدارة البيانات'));
    await tester.pumpAndSettle();
    expect(find.text('إدارة الضيوف'), findsOneWidget);
    expect(find.text('القائمة السوداء'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('يبقى التخطيط مستقراً على اللوحي وWindows', (tester) async {
    for (final size in <Size>[
      const Size(800, 600),
      const Size(1366, 768),
      const Size(1920, 1080),
    ]) {
      await pumpAtSize(tester, size);
      expect(find.text('الوصول السريع'), findsOneWidget, reason: 'size=$size');
      expect(tester.takeException(), isNull, reason: 'size=$size');

      final syncSection = find.byType(ExpansionTile).at(1);
      await tester.ensureVisible(syncSection);
      await tester.pumpAndSettle();
      await tester.tap(syncSection);
      await tester.pumpAndSettle();
      expect(find.text('النسخ الاحتياطي والاستعادة'), findsOneWidget);
      expect(find.text('Appwrite'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'size=$size');
    }
  });
}
