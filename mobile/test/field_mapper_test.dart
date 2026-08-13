// ============================================================================
//  FieldMapper — Unit Tests
//  ============================================================================
//  اختبارات FieldMapper:
//    - toPhpField / toFlutterField — تحويل أسماء الحقول
//    - toPhpMap / toFlutterMap — تحويل خرائط كاملة
//    - prepareForInsert / prepareForUpdate — تجهيز البيانات لـ PHP API
//    - validateRequiredFields — فحص الحقول المطلوبة
//    - extractSyncFields / excludeSyncFields — فصل حقول المزامنة
//    - getSupportedEntities / isEntitySupported — استعلامات الكيانات
// ============================================================================

library marina_hotel_mobile.test.field_mapper_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/field_mapper.dart';

void main() {
  group('toPhpField', () {
    test('يُحوّل الحقول المعروفة إلى أسماء PHP', () {
      expect(FieldMapper.toPhpField('rooms', 'localUuid'), 'local_uuid');
      expect(FieldMapper.toPhpField('rooms', 'roomNumber'), 'room_number');
      expect(FieldMapper.toPhpField('rooms', 'price'), 'price');
      expect(FieldMapper.toPhpField('rooms', 'createdAt'), 'created_at');
    });

    test('يُحوّل الحقول غير المعروفة باستخدام camelToSnake', () {
      expect(
        FieldMapper.toPhpField('rooms', 'unknownFieldName'),
        'unknown_field_name',
      );
      expect(FieldMapper.toPhpField('rooms', 'guestName'), 'guest_name');
    });

    test('يُحوّل حقول bookings', () {
      expect(FieldMapper.toPhpField('bookings', 'guestName'), 'guest_name');
      expect(FieldMapper.toPhpField('bookings', 'checkinDate'), 'checkin_date');
      expect(
        FieldMapper.toPhpField('bookings', 'actualCheckout'),
        'actual_checkout',
      );
    });
  });

  group('toFlutterField', () {
    test('يُحوّل أسماء PHP إلى Flutter', () {
      expect(FieldMapper.toFlutterField('rooms', 'local_uuid'), 'localUuid');
      expect(FieldMapper.toFlutterField('rooms', 'room_number'), 'roomNumber');
      expect(FieldMapper.toFlutterField('rooms', 'price'), 'price');
    });

    test('يُحوّل الحقول غير المعروفة باستخدام snakeToCamel', () {
      expect(
        FieldMapper.toFlutterField('rooms', 'unknown_field_name'),
        'unknownFieldName',
      );
    });
  });

  group('toPhpMap', () {
    test('يُحوّل خريطة Flutter إلى PHP', () {
      final flutter = <String, dynamic>{
        'localUuid': 'abc-123',
        'roomNumber': '101',
        'price': 15000,
        'status': 'محجوزة',
      };

      final php = FieldMapper.toPhpMap('rooms', flutter);

      expect(php['local_uuid'], 'abc-123');
      expect(php['room_number'], '101');
      expect(php['price'], 15000);
      expect(php['status'], 'محجوزة');
    });

    test('يُحوّل bool إلى int (0/1)', () {
      final flutter = <String, dynamic>{
        'requiresMaintenance': true,
        'isActive': false,
      };

      final php = FieldMapper.toPhpMap('rooms', flutter);

      expect(php['requires_maintenance'], 1);
      expect(php['is_active'], 0);
    });

    test('يُحوّل DateTime إلى ISO string', () {
      final dt = DateTime(2026, 8, 6, 14, 30);
      final flutter = <String, dynamic>{'createdAt': dt};

      final php = FieldMapper.toPhpMap('rooms', flutter);

      expect(php['created_at'], isA<String>());
      expect(php['created_at'], contains('2026-08-06'));
    });

    test('يُحوّل List بشكل متكرر', () {
      final flutter = <String, dynamic>{
        'items': [
          {'isActive': true},
          {'isActive': false},
        ],
      };

      final php = FieldMapper.toPhpMap('rooms', flutter);

      expect(php['items'], isA<List>());
      final items = php['items'] as List;
      expect(items[0]['is_active'], 1);
      expect(items[1]['is_active'], 0);
    });

    test('يُحوّل Map بشكل متكرر', () {
      final flutter = <String, dynamic>{
        'meta': {'isActive': true, 'count': 5},
      };

      final php = FieldMapper.toPhpMap('rooms', flutter);

      expect(php['meta'], isA<Map>());
      final meta = php['meta'] as Map;
      expect(meta['is_active'], 1);
      expect(meta['count'], 5);
    });

    test('null يبقى null', () {
      final flutter = <String, dynamic>{'notes': null};

      final php = FieldMapper.toPhpMap('rooms', flutter);

      expect(php['notes'], isNull);
    });
  });

  group('toFlutterMap', () {
    test('يُحوّل خريطة PHP إلى Flutter', () {
      final php = <String, dynamic>{
        'local_uuid': 'abc-123',
        'room_number': '101',
        'price': 15000,
      };

      final flutter = FieldMapper.toFlutterMap('rooms', php);

      expect(flutter['localUuid'], 'abc-123');
      expect(flutter['roomNumber'], '101');
      expect(flutter['price'], 15000);
    });

    test('يُحوّل string تاريخ إلى DateTime', () {
      final php = <String, dynamic>{'created_at': '2026-08-06 14:30:00'};

      final flutter = FieldMapper.toFlutterMap('rooms', php);

      expect(flutter['created_at'], isA<DateTime>());
    });

    test('يحافظ على int 0/1 كما هو (لا يحوّله إلى bool)', () {
      final php = <String, dynamic>{'is_active': 1, 'is_disabled': 0};

      final flutter = FieldMapper.toFlutterMap('rooms', php);

      // حسب التصميم: int 0/1 يبقى int (يُحوَّل في طبقة أعلى)
      expect(flutter['is_active'], 1);
      expect(flutter['is_disabled'], 0);
    });
  });

  group('toPhpList / toFlutterList', () {
    test('toPhpList يُحوّل قائمة خرائط', () {
      final flutterList = [
        {'roomNumber': '101'},
        {'roomNumber': '102'},
      ];

      final phpList = FieldMapper.toPhpList('rooms', flutterList);

      expect(phpList.length, 2);
      expect(phpList[0]['room_number'], '101');
      expect(phpList[1]['room_number'], '102');
    });

    test('toFlutterList يُحوّل قائمة PHP', () {
      final phpList = [
        {'room_number': '101'},
        {'room_number': '102'},
      ];

      final flutterList = FieldMapper.toFlutterList('rooms', phpList);

      expect(flutterList.length, 2);
      expect(flutterList[0]['roomNumber'], '101');
      expect(flutterList[1]['roomNumber'], '102');
    });
  });

  group('prepareForInsert', () {
    test('يُزيل local_uuid افتراضياً', () {
      final flutter = <String, dynamic>{
        'localUuid': 'abc-123',
        'roomNumber': '101',
        'serverId': 5,
      };

      final php = FieldMapper.prepareForInsert('rooms', flutter);

      expect(php.containsKey('local_uuid'), isFalse);
      expect(
        php.containsKey('id'),
        isFalse,
        reason: 'includeId=false افتراضياً',
      );
      expect(php['room_number'], '101');
    });

    test('يُبقي id عند includeId=true', () {
      final flutter = <String, dynamic>{'localUuid': 'abc-123', 'serverId': 5};

      final php = FieldMapper.prepareForInsert(
        'rooms',
        flutter,
        includeId: true,
      );

      expect(php['id'], 5);
      expect(php.containsKey('local_uuid'), isFalse);
    });
  });

  group('prepareForUpdate', () {
    test('يُزيل id و local_uuid و created_at', () {
      final flutter = <String, dynamic>{
        'localUuid': 'abc-123',
        'serverId': 5,
        'roomNumber': '101',
        'createdAt': DateTime(2026, 1, 1),
      };

      final php = FieldMapper.prepareForUpdate('rooms', flutter);

      expect(php.containsKey('id'), isFalse);
      expect(php.containsKey('local_uuid'), isFalse);
      expect(php.containsKey('created_at'), isFalse);
      expect(php['room_number'], '101');
    });

    test('يُحدّث updated_at بتاريخ اليوم', () {
      final flutter = <String, dynamic>{'roomNumber': '101'};

      final php = FieldMapper.prepareForUpdate('rooms', flutter);

      expect(php['updated_at'], isNotNull);
      expect(php['updated_at'], isA<String>());
      // يجب أن يحتوي على تاريخ اليوم (يقبل اختلاف الدقائق)
      final now = DateTime.now();
      expect(php['updated_at'], contains(now.year.toString()));
    });
  });

  group('validateRequiredFields', () {
    test('يُرجع قائمة فارغة عندما تكون جميع الحقول موجودة', () {
      final php = <String, dynamic>{
        'room_number': '101',
        'type': 'عادية',
        'price': 15000,
        'status': 'شاغرة',
      };

      final missing = FieldMapper.validateRequiredFields('rooms', php);
      expect(missing, isEmpty);
    });

    test('يُرجع الحقول المفقودة', () {
      final php = <String, dynamic>{
        'room_number': '101',
        // type missing
        // price missing
        'status': 'شاغرة',
      };

      final missing = FieldMapper.validateRequiredFields('rooms', php);
      expect(missing.length, 2);
      expect(missing, contains('type'));
      expect(missing, contains('price'));
    });

    test('يُرجع الحقول null كـ missing', () {
      final php = <String, dynamic>{
        'room_number': '101',
        'type': null,
        'price': 15000,
        'status': 'شاغرة',
      };

      final missing = FieldMapper.validateRequiredFields('rooms', php);
      expect(missing, contains('type'));
    });

    test('يُرجع قائمة فارغة للكيان غير المعروف', () {
      final php = <String, dynamic>{};
      final missing = FieldMapper.validateRequiredFields('unknown', php);
      expect(missing, isEmpty);
    });
  });

  group('extractSyncFields / excludeSyncFields', () {
    test('extractSyncFields يُرجع حقول المزامنة فقط', () {
      final data = <String, dynamic>{
        'localUuid': 'abc',
        'serverId': 5,
        'createdAt': '2026-01-01',
        'roomNumber': '101',
        'price': 15000,
      };

      final sync = FieldMapper.extractSyncFields(data);

      expect(sync.length, 3);
      expect(sync.containsKey('localUuid'), isTrue);
      expect(sync.containsKey('serverId'), isTrue);
      expect(sync.containsKey('createdAt'), isTrue);
      expect(sync.containsKey('roomNumber'), isFalse);
    });

    test('excludeSyncFields يُرجع الحقول غير المتعلقة بالمزامنة', () {
      final data = <String, dynamic>{
        'localUuid': 'abc',
        'serverId': 5,
        'createdAt': '2026-01-01',
        'roomNumber': '101',
        'price': 15000,
      };

      final nonSync = FieldMapper.excludeSyncFields(data);

      expect(nonSync.length, 2);
      expect(nonSync.containsKey('roomNumber'), isTrue);
      expect(nonSync.containsKey('price'), isTrue);
      expect(nonSync.containsKey('localUuid'), isFalse);
    });
  });

  group('getSupportedEntities / isEntitySupported / getEntityFields', () {
    test('getSupportedEntities يُرجع قائمة غير فارغة', () {
      final entities = FieldMapper.getSupportedEntities();
      expect(entities, isNotEmpty);
      expect(entities, contains('rooms'));
      expect(entities, contains('bookings'));
    });

    test('isEntitySupported يُرجع true للكيانات المعروفة', () {
      expect(FieldMapper.isEntitySupported('rooms'), isTrue);
      expect(FieldMapper.isEntitySupported('bookings'), isTrue);
    });

    test('isEntitySupported يُرجع false للكيانات غير المعروفة', () {
      expect(FieldMapper.isEntitySupported('unknown'), isFalse);
      expect(FieldMapper.isEntitySupported(''), isFalse);
    });

    test('getEntityFields يُرجع قائمة حقول الكيان', () {
      final fields = FieldMapper.getEntityFields('rooms');
      expect(fields, isNotEmpty);
      expect(fields, contains('localUuid'));
      expect(fields, contains('roomNumber'));
    });

    test('getEntityFields يُرجع قائمة فارغة للكيان غير المعروف', () {
      final fields = FieldMapper.getEntityFields('unknown');
      expect(fields, isEmpty);
    });
  });
}
