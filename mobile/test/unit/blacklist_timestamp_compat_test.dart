import 'package:appwrite/models.dart' as models;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync/blacklist_timestamp_compat.dart';

models.Document _doc(String id, {required Map<String, dynamic> data}) {
  return models.Document(
    $id: id,
    $sequence: 1,
    $collectionId: 'blacklist',
    $databaseId: 'test_db',
    $createdAt: '2026-11-26T00:00:00.000Z',
    $updatedAt: '2026-11-26T00:00:00.000Z',
    $permissions: const <String>[],
    data: data,
  );
}

void main() {
  group('BlacklistTimestampCompat.normalizeDocs', () {
    test('يحوّل طوابع epoch الصحيحة إلى ISO ويترك بقية الحقول', () {
      final docs = [
        _doc(
          'doc-1',
          data: <String, dynamic>{
            'localUuid': 'uuid-1',
            'name': 'نزيل مطلوب',
            'createdAt': 1766440000, // epoch seconds (int من السحابة)
            'updatedAt': 1766440100,
            'deletedAt': null,
            'serverId': 7, // حقل رقمي غير طابع — يجب أن يبقى int
            'active': true,
          },
        ),
      ];

      final out = BlacklistTimestampCompat.normalizeDocs(docs);

      expect(out.single.data['createdAt'], isA<String>());
      expect(out.single.data['updatedAt'], isA<String>());
      expect(
        DateTime.parse(
              out.single.data['createdAt'] as String,
            ).millisecondsSinceEpoch ~/
            1000,
        equals(1766440000),
        reason: 'التحويل يجب أن يحفظ قيمة الـ epoch نفسها',
      );
      expect(out.single.data['deletedAt'], isNull);
      // الحقول غير الطوابع لا تُلمس
      expect(out.single.data['serverId'], equals(7));
      expect(out.single.data['name'], equals('نزيل مطلوب'));
      expect(out.single.data['active'], isTrue);
    });

    test('يُبقي المستندات ذات الطوابع النصية ISO كما هي دون نسخ', () {
      final docs = [
        _doc(
          'doc-2',
          data: <String, dynamic>{
            'localUuid': 'uuid-2',
            'createdAt': '2026-11-25T10:00:00.000Z',
            'updatedAt': '2026-11-25T10:00:00.000Z',
          },
        ),
      ];

      final out = BlacklistTimestampCompat.normalizeDocs(docs);

      expect(
        out.single,
        same(docs.single),
        reason: 'لا تغيير → نفس الكائن يُعاد (no-op)',
      );
      expect(out.single.data['createdAt'], equals('2026-11-25T10:00:00.000Z'));
    });

    test('epoch=0 يصبح ISO لعام 1970 لا حذفاً ولا غياباً', () {
      // وثائق كُتبت بالخطأ القديم (قيمة 0) يجب أن تبقى سجلات حية،
      // لا أن تُفسَّر 0 كمحذوف — نفس عقد تدقيق 2026-11-24.
      final docs = [
        _doc(
          'doc-3',
          data: <String, dynamic>{
            'localUuid': 'uuid-3',
            'createdAt': 0,
            'updatedAt': 0,
          },
        ),
      ];

      final out = BlacklistTimestampCompat.normalizeDocs(docs);

      expect(out.single.data['createdAt'], isA<String>());
      expect(out.single.data['createdAt'], equals('1970-01-01T00:00:00.000Z'));
    });

    test('قائمة فارغة تُعاد كما هي', () {
      final empty = <models.Document>[];
      expect(BlacklistTimestampCompat.normalizeDocs(empty), isEmpty);
    });

    test('قائمة مختلطة: فقط التي تحتاج تطبيعاً تُنشأ نسخاً منها', () {
      final withInt = _doc('a', data: <String, dynamic>{'createdAt': 60});
      final withStr = _doc(
        'b',
        data: <String, dynamic>{'createdAt': '2026-01-01T00:00:00.000Z'},
      );

      final out = BlacklistTimestampCompat.normalizeDocs([withInt, withStr]);

      expect(out[0], isNot(same(withInt)));
      expect(out[1], same(withStr));
      expect(out[0].data['createdAt'], equals('1970-01-01T00:01:00.000Z'));
    });
  });
}
