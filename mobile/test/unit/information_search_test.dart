// test/unit/information_search_test.dart
//
// ✅ (2026-10-06): بحث «سجل المعلومية» من رأس الشاشة (الهيد) بالاسم —
// إثبات دالة المطابقة (تطبيع عربي + تسامح مع الهمزات/التاء المربوطة/الأرقام)
// وواجهة شريط البحث داخل AppScaffold.header.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/components/app_scaffold.dart';
import 'package:marina_hotel_mobile/components/widgets/guest_search_field.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/utils/guest_info_search.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GuestInfo guest({
    required String name,
    required String room,
    String idNumber = '0000',
    String? governorate,
  }) => GuestInfo(
    localUuid: 'g-$room',
    id: 1,
    roomNumber: room,
    guestName: name,
    nationality: 'يمني',
    idNumber: idNumber,
    idType: 'بطاقة شخصية',
    governorate: governorate,
    createdAt: 0,
    updatedAt: 0,
    lastModified: 0,
    createdAtEpoch: 0,
    lastModifiedEpoch: 0,
    version: 1,
    origin: 'local',
    vectorClock: '{}',
    deviceId: 'test-device',
    syncTimestamp: 0,
  );

  group('مطابقة البحث في سجل المعلومية', () {
    test('تطبيع الهمزات والتاء المربوطة والياء والتشكيل', () {
      final normalized = GuestInfoSearch.normalize('أَحْمَدُ');
      expect(normalized, 'احمد');
      expect(GuestInfoSearch.normalize('فاطمة'), 'فاطمه');
      expect(GuestInfoSearch.normalize('مصطفى'), 'مصطفي');
      expect(GuestInfoSearch.normalize('٤١٢'), '412');
    });

    test('البحث بالاسم يعمل بأشكال كتابة مختلفة', () {
      final row = guest(name: 'أحمد علي', room: '101');

      for (final query in ['أحمد', 'احمد', 'أحمـد', 'أحمد علي']) {
        expect(
          GuestInfoSearch.matches(row, query),
          isTrue,
          reason: 'العبارة «$query» يجب أن تطابق الاسم',
        );
      }
      expect(GuestInfoSearch.matches(row, 'خالد'), isFalse);
    });

    test('البحث يشمل الغرفة ورقم الهوية والمحافظة', () {
      final row = guest(
        name: 'سالم',
        room: '12',
        idNumber: '998877',
        governorate: 'عدن',
      );
      expect(GuestInfoSearch.matches(row, '12'), isTrue);
      expect(GuestInfoSearch.matches(row, '998877'), isTrue);
      expect(GuestInfoSearch.matches(row, 'عدن'), isTrue);
    });

    test('عبارة فارغة تعني «لا فلترة»', () {
      final row = guest(name: 'مروان', room: '9');
      expect(GuestInfoSearch.matches(row, ''), isTrue);
      expect(GuestInfoSearch.matches(row, '   '), isTrue);
    });
  });

  group('مكوّن حقل البحث في الهيد (GuestSearchField)', () {
    testWidgets('يرسم حقل بحث ويُطلق onChanged عند الكتابة', (tester) async {
      final controller = TextEditingController();
      String? lastValue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuestSearchField(
              controller: controller,
              onChanged: (v) => lastValue = v,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('ابحث في سجل المعلومية'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'خالد');
      await tester.pump();
      expect(lastValue, 'خالد');
      controller.dispose();
    });

    testWidgets('زر ✕ يمسح النص ويُبلغ الشاشة (onCleared)', (tester) async {
      final controller = TextEditingController(text: 'أحمد');
      var cleared = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuestSearchField(
              controller: controller,
              onChanged: (_) {},
              onCleared: () => cleared = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('مسح البحث'), findsOneWidget);
      await tester.tap(find.byTooltip('مسح البحث'));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
      controller.dispose();
    });

    testWidgets('يظهر داخل رأس AppScaffold بلا حجب العنوان', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            simpleNotesUnreadCountProvider.overrideWith(
              (ref) => Stream.value(0),
            ),
          ],
          child: MaterialApp(
            home: AppScaffold(
              title: 'سجل المعلومية',
              header: GuestSearchField(
                controller: controller,
                onChanged: (_) {},
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('سجل المعلومية'), findsOneWidget);
      expect(find.byType(GuestSearchField), findsOneWidget);
      controller.dispose();
    });
  });
}
