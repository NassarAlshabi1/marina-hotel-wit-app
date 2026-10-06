// test/unit/information_search_test.dart
//
// ✅ (2026-10-06): بحث «سجل المعلومية» من رأس الشاشة (الهيد) بالاسم —
// إثبات دالة المطابقة (تطبيع عربي + تسامح مع الهمزات/التاء المربوطة/الأرقام)
// وواجهة شريط البحث داخل AppScaffold.header.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/components/app_scaffold.dart';
import 'package:marina_hotel_mobile/screens/information/information_screen.dart';
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

  group('شريط البحث في الهيد (AppScaffold.header)', () {
    testWidgets('يظهر في الرأس ولا يحجب العنوان', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            title: 'سجل المعلومية',
            header: const TextField(
              decoration: InputDecoration(hintText: 'بحث بالاسم…'),
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('سجل المعلومية'), findsOneWidget);
      expect(find.text('بحث بالاسم…'), findsOneWidget);
    });

    testWidgets('بلا header: لا يتغير شيء في بقية الشاشات', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppScaffold(title: 'شاشة أخرى', body: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      expect(find.text('شاشة أخرى'), findsOneWidget);
    });
  });
}
