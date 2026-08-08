// test/unit/conflict_resolution_fix_test.dart
//
// ✅ اختبارات لإصلاحات معالجة التعارضات التلقائية (2026-08-08).
// تغطي:
//  - _findChangedFields عند غياب السلف (ancestor=null) يحسب الفرق الفعلي
//    بين النسختين بدل إرجاع كل الحقول → يحمي الدمج على مستوى الحقل عند
//    أول تعارض على سجل، ويمنع فقدان التعديلات المحلية (LWW صامت).
//  - newerWins tie-break عند تساوي timestamp يُحسم عبر deviceId بشكل حتمي
//    ومتماثل عبر الأجهزة (لا يربح البعيد تلقائياً).
//  - 3-way merge على مستوى الحقل يحافظ على الحقول غير المتعارضة محلياً.

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/conflict_detector.dart';
import 'package:marina_hotel_mobile/services/sync_core/smart_conflict_resolver.dart';

void main() {
  group('ConflictDetector._findChangedFields (ancestor=null fix)', () {
    const local = {
      'name': 'local-name',
      'amount': 100,
      'note': 'local-note',
      'lastModified': 5000,
      'version': 2,
      'vectorClock': '{"d1":2}',
    };
    const remote = {
      'name': 'remote-name', // مختلف
      'amount': 100, // متطابق
      'note': 'local-note', // متطابق
      'lastModified': 6000,
      'version': 3,
      'vectorClock': '{"d2":1}',
    };

    test('ancestor=null يُرجع الحقول المختلفة فعلياً فقط (ليس كل الحقول)', () {
      final changed = ConflictDetector.detect(
        localData: local,
        remoteData: remote,
        commonAncestor: null,
      );
      // فقط 'name' تغيّر فعلياً بين النسختين.
      expect(changed.localChangedFields, contains('name'));
      expect(changed.localChangedFields, isNot(contains('amount')));
      expect(changed.localChangedFields, isNot(contains('note')));
      // الحقول الوصفية مستبعدة دائماً.
      expect(changed.localChangedFields, isNot(contains('lastModified')));
      expect(changed.localChangedFields, isNot(contains('version')));
      expect(changed.localChangedFields, isNot(contains('vectorClock')));
    });

    test('نفس البيانات تماماً → لا حقول متغيرة (لا تعارض زائف)', () {
      final changed = ConflictDetector.detect(
        localData: local,
        remoteData: local,
        commonAncestor: null,
      );
      expect(changed.localChangedFields, isEmpty);
      expect(changed.remoteChangedFields, isEmpty);
    });
  });

  group('SmartConflictResolver newerWins tie-break (timestamp equality)', () {
    test('تساوي timestamp → القرار حتمي عبر deviceId (لا يفوز البعيد تلقائياً)', () {
      // local و remote بنفس lastModified تماماً.
      final localData = {
        'amount': 100,
        'lastModified': 5000,
        'deviceId': 'device-B',
        'vectorClock': '{"device-B":1}',
      };
      final remoteData = {
        'amount': 200,
        'lastModified': 5000,
        'deviceId': 'device-A',
        'vectorClock': '{"device-A":1}',
      };
      // كلا الساعتين متساويتان → concurrent → merge على مستوى الحقل.
      final result = SmartConflictResolver.resolve(
        entity: 'payments',
        localData: localData,
        remoteData: remoteData,
        commonAncestor: null,
      );
      expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
      // deviceId أصغر أبجدياً (device-A) يربح عند التعادل → remote.
      expect(result.mergedData['amount'], equals(200));
    });

    test('تساوي timestamp ومحلي له deviceId أصغر → يحافظ على المحلي', () {
      final localData = {
        'amount': 100,
        'lastModified': 5000,
        'deviceId': 'device-A',
        'vectorClock': '{"device-A":1}',
      };
      final remoteData = {
        'amount': 200,
        'lastModified': 5000,
        'deviceId': 'device-B',
        'vectorClock': '{"device-B":1}',
      };
      final result = SmartConflictResolver.resolve(
        entity: 'payments',
        localData: localData,
        remoteData: remoteData,
        commonAncestor: null,
      );
      expect(result.mergedData['amount'], equals(100));
    });

    test('remote أحدث صراحةً → يربح دائماً', () {
      final localData = {
        'amount': 100,
        'lastModified': 4000,
        'deviceId': 'device-A',
        'vectorClock': '{"device-A":1}',
      };
      final remoteData = {
        'amount': 200,
        'lastModified': 5000,
        'deviceId': 'device-B',
        'vectorClock': '{"device-B":1}',
      };
      final result = SmartConflictResolver.resolve(
        entity: 'payments',
        localData: localData,
        remoteData: remoteData,
        commonAncestor: null,
      );
      expect(result.mergedData['amount'], equals(200));
    });
  });

  group('3-way merge يحافظ على الحقول غير المتعارضة محلياً (ancestor=null)', () {
    test('حقل محلي فقط متغيّر → يبقى محلياً بعد الدمج', () {
      final localData = {
        'room': '101',
        'price': 500, // محلي تغيّر
        'guest': 'ahmed', // محلي لم يتغيّر
        'lastModified': 5000,
        'deviceId': 'device-A',
        'vectorClock': '{"device-A":1}',
      };
      final remoteData = {
        'room': '101',
        'price': 600, // بعيد تغيّر
        'guest': 'ahmed', // بعيد لم يتغيّر
        'lastModified': 5000,
        'deviceId': 'device-B',
        'vectorClock': '{"device-B":1}',
      };
      final result = SmartConflictResolver.resolve(
        entity: 'bookings',
        localData: localData,
        remoteData: remoteData,
        commonAncestor: null,
      );
      // guest غير متعارض → يبقى قيمته (متطابقة في النسختين).
      expect(result.mergedData['guest'], equals('ahmed'));
      // price متعارض → يُحسم عبر tie-break deviceId (device-A < device-B) → محلي.
      expect(result.mergedData['price'], equals(500));
    });
  });
}
