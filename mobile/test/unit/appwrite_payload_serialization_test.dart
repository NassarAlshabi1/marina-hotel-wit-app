import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';

void main() {
  group('Appwrite payload serialization', () {
    test('يسلسل vectorClock المركب إلى JSON صالح لحقل Appwrite النصي', () {
      final payload = AppwriteSyncUtils.filterPayloadForCollection('bookings', {
        'localUuid': '11111111-1111-1111-1111-111111111111',
        'vectorClock': <String, int>{'device-a': 3, 'device-b': 1},
      });

      final serialized = payload['vectorClock'];
      expect(serialized, isA<String>());
      expect(
        jsonDecode(serialized as String),
        equals(<String, dynamic>{'device-a': 3, 'device-b': 1}),
      );
      expect(serialized, isNot(contains('_Map')));
    });

    test('يسلسل القوائم في الحقول النصية دون تغيير النصوص الجاهزة', () {
      final payload = AppwriteSyncUtils.filterPayloadForCollection('bookings', {
        'notes': <String>['وصول متأخر', 'سرير إضافي'],
        'vectorClock': '{"device-a":3}',
      });

      expect(
        jsonDecode(payload['notes'] as String),
        equals(<String>['وصول متأخر', 'سرير إضافي']),
      );
      expect(payload['vectorClock'], '{"device-a":3}');
    });

    test('يستبدل vectorClock التالف بساعة فارغة آمنة', () {
      expect(AppwriteSyncUtils.normalizeVectorClock('device-a:3'), '{}');
      expect(
        AppwriteSyncUtils.normalizeVectorClock(<String>['not-a-clock']),
        '{}',
      );
    });

    test('لا يرسل vectorClock أطول من حد Appwrite', () {
      final oversized = <String, int>{
        for (var index = 0; index < 180; index++)
          'device-${index.toString().padLeft(3, '0')}-aaaaaaaa': index,
      };

      expect(AppwriteSyncUtils.normalizeVectorClock(oversized), '{}');
    });

    test('يحمي مسار النقل الأخير الحمولة غير المصفاة', () {
      final payload = AppwriteSyncUtils.normalizeVectorClockInPayload({
        'vectorClock': <String, dynamic>{'device-a': '5'},
        'status': 'محجوزة',
      });

      expect(payload['status'], 'محجوزة');
      expect(jsonDecode(payload['vectorClock'] as String), {'device-a': 5});
    });
  });
}
