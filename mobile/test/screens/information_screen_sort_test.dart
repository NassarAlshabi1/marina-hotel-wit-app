import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/information/information_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// بنّاء سريع لسجل نزيل لاختبار الترتيب فقط — باقي الحقول قيم ثابتة.
GuestInfo _info(int id, String roomNumber, {int updatedAt = 0}) {
  return GuestInfo(
    localUuid: 'uuid-$id',
    createdAt: 0,
    updatedAt: updatedAt,
    lastModified: 0,
    createdAtEpoch: 0,
    lastModifiedEpoch: 0,
    version: 1,
    origin: 'local',
    vectorClock: '{}',
    deviceId: 'test-device',
    syncTimestamp: 0,
    id: id,
    roomNumber: roomNumber,
    guestName: 'نزيل $id',
    nationality: 'يمني',
    idNumber: '000$id',
    idType: 'بطاقة شخصية',
  );
}

void main() {
  group('InformationScreen.sortedByRoomNumber', () {
    test('ترتيب تصاعدي رقمي صحيح (ليس أبجدياً) لأرقام الغرف', () {
      final entries = [
        _info(1, '10'),
        _info(2, '2'),
        _info(3, '101'),
        _info(4, '1'),
      ];

      final sorted = InformationScreen.sortedByRoomNumber(entries);

      expect(sorted.map((e) => e.roomNumber).toList(), ['1', '2', '10', '101']);
    });

    test('القيم الرقمية أولاً ثم القيم النصية أبجدياً', () {
      final entries = [
        _info(1, 'ب'),
        _info(2, 'أ'),
        _info(3, '12'),
        _info(4, '3'),
      ];

      final sorted = InformationScreen.sortedByRoomNumber(entries);

      expect(sorted.map((e) => e.roomNumber).toList(), ['3', '12', 'أ', 'ب']);
    });

    test(
      'ترتيب القادم من الـ provider (updatedAt DESC) يُعاد فرزه للـ PDF',
      () {
        // محاكاة الترتيب الفعلي القادم من GuestInfosRepository.watchAll:
        // آخر سجل تم تعديله يأتي أولاً — يجب أن يخرج الـ PDF مرتّباً بالغرفة.
        final entries = [
          _info(1, '5', updatedAt: 300),
          _info(2, '20', updatedAt: 200),
          _info(3, '3', updatedAt: 100),
        ];

        final sorted = InformationScreen.sortedByRoomNumber(entries);

        expect(sorted.map((e) => e.roomNumber).toList(), ['3', '5', '20']);
      },
    );

    test('لا تُعدَّل القائمة الأصلية وتُرجَع نسخة جديدة', () {
      final entries = [_info(1, '9'), _info(2, '1')];

      final sorted = InformationScreen.sortedByRoomNumber(entries);

      expect(entries.map((e) => e.roomNumber).toList(), ['9', '1']);
      expect(sorted.map((e) => e.roomNumber).toList(), ['1', '9']);
      expect(identical(sorted, entries), isFalse);
    });

    test('القائمة الفارغة تبقى فارغة دون أخطاء', () {
      expect(InformationScreen.sortedByRoomNumber(const []), isEmpty);
    });
  });

  group('InformationScreen.compareByRoomNumber', () {
    test('المقارنة متعدية (خاصية الترتيب الصحيح)', () {
      // لو لم تكن المقارنة متعدية لفسد sort تماماً — نموذج رقمي/نصي مختلط.
      final mixed = ['10', 'أ', '2', 'ب', '101', '1', '3', 'ج'];
      final parsed = mixed.map((r) => _info(r.hashCode, r)).toList();

      final sorted = InformationScreen.sortedByRoomNumber(parsed);

      expect(
        sorted.map((e) => e.roomNumber).toList(),
        ['1', '2', '3', '10', '101', 'أ', 'ب', 'ج'],
      );
    });
  });
}
