// test/unit/identity_gate_p2_test.dart
//
// ✅ (P2-9 / P2-10 — 2026-10-06): بوابتان نقيّتان للمزامنة:
//   • لا تُعلن السجلات المؤجَّلة (ناقصة الربط) كسجلات مطبَّقة.
//   • لا يُكتب `server_id` من رد رفع يخصّ سجلاً آخر (المطابقة بالهوية لا
//     بالموضع).
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/utils/identity_gate.dart';

void main() {
  group('P2-9 — عدّاد السحب لا يعلن المؤجَّل كمطبَّق', () {
    test('يخصم المؤجَّل من المُعلَن', () {
      expect(
        UuidIdentity.appliedRecordsInPull(reported: 120, deferredDelta: 7),
        113,
      );
    });

    test('لا نتيجة سالبة ولا انقلاب عند تجاوز العدّاد', () {
      expect(
        UuidIdentity.appliedRecordsInPull(reported: 3, deferredDelta: 9),
        0,
      );
      expect(
        UuidIdentity.appliedRecordsInPull(reported: 0, deferredDelta: 5),
        0,
      );
      expect(
        UuidIdentity.appliedRecordsInPull(reported: 10, deferredDelta: 0),
        10,
      );
    });
  });

  group('P2-10 — بوابة هوية رد الرفع', () {
    const changeUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001';

    test('هوية مُعادة مطابقة (بأي شكل شرطات) ⇒ يُطبَّق', () {
      expect(
        UuidIdentity.mayApplyServerId(
          changeLocalUuid: changeUuid,
          echoedLocalUuid: changeUuid,
        ),
        isTrue,
      );
      expect(
        UuidIdentity.mayApplyServerId(
          changeLocalUuid: changeUuid,
          echoedLocalUuid: 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEFFFF0001',
        ),
        isTrue,
      );
    });

    test('هوية مُعادة لسجل آخر ⇒ لا يُطبَّق (لا رقم أجنبي على صف بريء)', () {
      expect(
        UuidIdentity.mayApplyServerId(
          changeLocalUuid: changeUuid,
          echoedLocalUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0002',
        ),
        isFalse,
      );
    });

    test('بلا هوية مُعادة ⇒ توافق خلفي (يُطبَّق) لكن المستدعي يحذّر', () {
      expect(
        UuidIdentity.mayApplyServerId(
          changeLocalUuid: changeUuid,
          echoedLocalUuid: null,
        ),
        isTrue,
      );
    });

    test('استخراج الهوية من الرد: camel ثم snake', () {
      expect(
        UuidIdentity.echoedFrom({'localUuid': 'x-1', 'uuid': 'y-2'}),
        'x-1',
      );
      expect(
        UuidIdentity.echoedFrom({'local_uuid': 'x-2', 'uuid': 'y-2'}),
        'x-2',
      );
      expect(UuidIdentity.echoedFrom({'uuid': 'y-2'}), 'y-2');
      expect(UuidIdentity.echoedFrom({'localUuid': '   '}), isNull);
      expect(UuidIdentity.echoedFrom(const {}), isNull);
    });

    test('sameIdentity لا يقبل فراغاً ولا يخلط سجلين', () {
      expect(UuidIdentity.sameIdentity('', ''), isFalse);
      expect(UuidIdentity.sameIdentity('abc', '  ABC '), isTrue);
      expect(UuidIdentity.sameIdentity('abc', 'abd'), isFalse);
    });
  });
}
