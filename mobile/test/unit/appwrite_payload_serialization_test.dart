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

    test('يُرسل createdAt في shift_notes كعدد صحيح مطابق للمخطط', () {
      const epoch = 1723603472;
      final payload =
          AppwriteSyncUtils.filterPayloadForCollection('shift_notes', {
            'localUuid': '11111111-1111-1111-1111-111111111111',
            'createdAt': '$epoch',
            'createdAtIso': '2026-08-14T04:44:32.000Z',
            'updatedAt': epoch,
          });

      expect(payload['createdAt'], epoch);
      expect(payload['createdAt'], isA<int>());
      expect(payload['createdAtIso'], isA<String>());
    });

    test('يحوّل طوابع blacklist النصية إلى integer وفق لقطة Appwrite', () {
      final payload =
          AppwriteSyncUtils.filterPayloadForCollection('blacklist', {
            'localUuid': '11111111-1111-1111-1111-111111111111',
            'createdAt': '1723603472',
            'updatedAt': '1723603473',
            'deletedAt': '1723603474',
          });

      expect(payload['createdAt'], 1723603472);
      expect(payload['updatedAt'], 1723603473);
      expect(payload['deletedAt'], 1723603474);
      expect(payload['createdAt'], isA<int>());
    });

    test('يحافظ على deviceId بطول 100 في payload الحجوزات والمدفوعات', () {
      final deviceId = 'd' * 100;
      for (final collectionId in ['bookings', 'payments']) {
        final payload = AppwriteSyncUtils.filterPayloadForCollection(
          collectionId,
          {'deviceId': deviceId},
        );

        expect(payload['deviceId'], deviceId);
        expect(payload['deviceId'], isA<String>());
      }
    });

    test('يرفض deviceId الأطول من 100 في الحجوزات والمدفوعات دون قصّه', () {
      final deviceId = 'd' * 101;
      for (final collectionId in ['bookings', 'payments']) {
        expect(
          () => AppwriteSyncUtils.filterPayloadForCollection(collectionId, {
            'deviceId': deviceId,
          }),
          throwsArgumentError,
        );
        expect(deviceId, 'd' * 101);
      }
    });

    test('يسمح بـ bookings.notes عند حد المخطط البالغ 1000 حرف', () {
      final notes = 'ن' * 1000;
      final payload = AppwriteSyncUtils.filterPayloadForCollection('bookings', {
        'notes': notes,
      });

      expect(payload['notes'], notes);
    });

    test('يرفض النص الزائد عن حد bookings.notes دون قصّه', () {
      final notes = 'ن' * 1200;

      expect(
        () => AppwriteSyncUtils.filterPayloadForCollection('bookings', {
          'notes': notes,
        }),
        throwsArgumentError,
      );
      expect(notes, 'ن' * 1200);
    });

    test('يرفض JSON للقائمة إذا تجاوز حد bookings.notes دون حذف عناصرها', () {
      final notes = List<String>.generate(
        40,
        (index) => 'note-$index ${'ن' * 40}',
      );

      expect(
        () => AppwriteSyncUtils.filterPayloadForCollection('bookings', {
          'notes': notes,
        }),
        throwsArgumentError,
      );
      expect(notes, hasLength(40));
      expect(notes.last, contains('note-39'));
    });

    test('يرفض JSON للخريطة إذا تجاوز الحد دون حذف مفاتيحها', () {
      final original = <String, String>{
        for (var index = 0; index < 30; index++)
          'key-$index': 'value-${'x' * 50}',
      };
      final originalJson = jsonEncode(original);

      expect(
        () => AppwriteSyncUtils.filterPayloadForCollection('bookings', {
          'notes': original,
        }),
        throwsArgumentError,
      );
      expect(original, hasLength(30));
      expect(jsonEncode(original), originalJson);
    });

    test('يرفض JSON النصي الجاهز إذا تجاوز حد notes دون تعديله', () {
      final original = jsonEncode(
        List<String>.generate(40, (i) => 'note-$i ${'x' * 40}'),
      );

      expect(
        () => AppwriteSyncUtils.filterPayloadForCollection('bookings', {
          'notes': original,
        }),
        throwsArgumentError,
      );
      expect(jsonDecode(original), isA<List<dynamic>>());
    });

    test('يرفض تجاوز حد notes دون قطع محارف Unicode', () {
      final original = '${'a' * 999}😀x';

      expect(
        () => AppwriteSyncUtils.filterPayloadForCollection('bookings', {
          'notes': original,
        }),
        throwsArgumentError,
      );
      expect(original, '${'a' * 999}😀x');
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
