// test/unit/vector_clock_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/vector_clock_service.dart';

void main() {
  group('VectorClock', () {
    group('Construction', () {
      test('empty constructor creates empty clock', () {
        final vc = VectorClock.empty();
        expect(vc.isEmpty, isTrue);
        expect(vc.deviceCount, equals(0));
        expect(vc.toString(), equals('{}'));
      });

      test('fromString parses valid JSON', () {
        final vc = VectorClock.fromString('{"device1": 5, "device2": 3}');
        expect(vc.get('device1'), equals(5));
        expect(vc.get('device2'), equals(3));
        expect(vc.get('device3'), equals(0)); // غير موجود
        expect(vc.deviceCount, equals(2));
      });

      test('fromString handles empty string', () {
        final vc = VectorClock.fromString('');
        expect(vc.isEmpty, isTrue);
      });

      test('fromString handles empty JSON object', () {
        final vc = VectorClock.fromString('{}');
        expect(vc.isEmpty, isTrue);
      });

      test('fromString handles malformed JSON gracefully', () {
        final vc = VectorClock.fromString('not valid json');
        expect(vc.isEmpty, isTrue);
      });
    });

    group('Increment', () {
      test('increment creates new entry if device not present', () {
        final vc = VectorClock.empty();
        vc.increment('device1');
        expect(vc.get('device1'), equals(1));
      });

      test('increment increases existing entry', () {
        final vc = VectorClock.fromString('{"device1": 5}');
        vc.increment('device1');
        expect(vc.get('device1'), equals(6));
      });

      test('multiple increments accumulate', () {
        final vc = VectorClock.empty();
        for (var i = 0; i < 10; i++) {
          vc.increment('device1');
        }
        expect(vc.get('device1'), equals(10));
      });

      test('independent devices have independent counters', () {
        final vc = VectorClock.empty();
        vc.increment('device1');
        vc.increment('device1');
        vc.increment('device2');
        expect(vc.get('device1'), equals(2));
        expect(vc.get('device2'), equals(1));
      });
    });

    group('Merge', () {
      test('merge takes max for each device', () {
        final vc1 = VectorClock.fromString('{"d1": 5, "d2": 3}');
        final vc2 = VectorClock.fromString('{"d1": 2, "d2": 7, "d3": 1}');

        vc1.merge(vc2);

        expect(vc1.get('d1'), equals(5)); // max(5, 2)
        expect(vc1.get('d2'), equals(7)); // max(3, 7)
        expect(vc1.get('d3'), equals(1)); // d3 جديد
      });

      test('merge with empty clock is no-op', () {
        final vc1 = VectorClock.fromString('{"d1": 5}');
        final vc2 = VectorClock.empty();

        vc1.merge(vc2);

        expect(vc1.get('d1'), equals(5));
        expect(vc1.deviceCount, equals(1));
      });

      test('merge is commutative', () {
        final vc1a = VectorClock.fromString('{"d1": 5, "d2": 3}');
        final vc2a = VectorClock.fromString('{"d1": 2, "d2": 7}');
        vc1a.merge(vc2a);

        final vc1b = VectorClock.fromString('{"d1": 2, "d2": 7}');
        final vc2b = VectorClock.fromString('{"d1": 5, "d2": 3}');
        vc1b.merge(vc2b);

        expect(vc1a.isEqual(vc1b), isTrue);
      });
    });

    group('Happens-Before', () {
      test('empty clock happens before non-empty', () {
        final empty = VectorClock.empty();
        final nonEmpty = VectorClock.fromString('{"d1": 1}');

        expect(empty.happensBefore(nonEmpty), isTrue);
        expect(nonEmpty.happensBefore(empty), isFalse);
      });

      test('sequential increments create happens-before chain', () {
        final vc1 = VectorClock.fromString('{"d1": 1}');
        final vc2 = VectorClock.fromString('{"d1": 2}');
        final vc3 = VectorClock.fromString('{"d1": 3}');

        expect(vc1.happensBefore(vc2), isTrue);
        expect(vc2.happensBefore(vc3), isTrue);
        expect(vc1.happensBefore(vc3), isTrue);

        // العكس غير صحيح
        expect(vc2.happensBefore(vc1), isFalse);
        expect(vc3.happensBefore(vc2), isFalse);
        expect(vc3.happensBefore(vc1), isFalse);
      });

      test('concurrent clocks do not happen before each other', () {
        // جهازان عدّلا بشكل مستقل
        final vc1 = VectorClock.fromString('{"d1": 1, "d2": 0}');
        final vc2 = VectorClock.fromString('{"d1": 0, "d2": 1}');

        expect(vc1.happensBefore(vc2), isFalse);
        expect(vc2.happensBefore(vc1), isFalse);
      });

      test('equal clocks do not happen before each other', () {
        final vc1 = VectorClock.fromString('{"d1": 5, "d2": 3}');
        final vc2 = VectorClock.fromString('{"d1": 5, "d2": 3}');

        expect(vc1.happensBefore(vc2), isFalse);
        expect(vc2.happensBefore(vc1), isFalse);
      });
    });

    group('Is Concurrent', () {
      test('concurrent clocks are detected', () {
        final vc1 = VectorClock.fromString('{"d1": 1, "d2": 0}');
        final vc2 = VectorClock.fromString('{"d1": 0, "d2": 1}');

        expect(vc1.isConcurrent(vc2), isTrue);
        expect(vc2.isConcurrent(vc1), isTrue);
      });

      test('sequential clocks are not concurrent', () {
        final vc1 = VectorClock.fromString('{"d1": 1}');
        final vc2 = VectorClock.fromString('{"d1": 2}');

        expect(vc1.isConcurrent(vc2), isFalse);
      });

      test('equal clocks are not concurrent', () {
        final vc1 = VectorClock.fromString('{"d1": 5}');
        final vc2 = VectorClock.fromString('{"d1": 5}');

        expect(vc1.isConcurrent(vc2), isFalse);
      });
    });

    group('Comparator', () {
      test('localNewer when remote happens before local', () {
        final local = VectorClock.fromString('{"d1": 5, "d2": 3}');
        final remote = VectorClock.fromString('{"d1": 2, "d2": 3}');

        final result = VectorClockComparator.compare(local, remote);
        expect(result, equals(VectorClockComparison.localNewer));
      });

      test('remoteNewer when local happens before remote', () {
        final local = VectorClock.fromString('{"d1": 2, "d2": 3}');
        final remote = VectorClock.fromString('{"d1": 5, "d2": 3}');

        final result = VectorClockComparator.compare(local, remote);
        expect(result, equals(VectorClockComparison.remoteNewer));
      });

      test('equal when clocks are identical', () {
        final local = VectorClock.fromString('{"d1": 5, "d2": 3}');
        final remote = VectorClock.fromString('{"d1": 5, "d2": 3}');

        final result = VectorClockComparator.compare(local, remote);
        expect(result, equals(VectorClockComparison.equal));
      });

      test('concurrent when clocks diverge', () {
        final local = VectorClock.fromString('{"d1": 5, "d2": 0}');
        final remote = VectorClock.fromString('{"d1": 0, "d2": 5}');

        final result = VectorClockComparator.compare(local, remote);
        expect(result, equals(VectorClockComparison.concurrent));
      });
    });

    group('shouldApplyRemote', () {
      test('returns true when remote is newer (vector clock)', () {
        final local = VectorClock.fromString('{"d1": 1}');
        final remote = VectorClock.fromString('{"d1": 2}');

        final shouldApply = VectorClockComparator.shouldApplyRemote(
          localVc: local,
          remoteVc: remote,
          localLastModified: 1000,
          remoteLastModified: 500, // حتى لو كان البعيد أقدم زمنياً
        );

        expect(shouldApply, isTrue);
      });

      test('returns false when local is newer (vector clock)', () {
        final local = VectorClock.fromString('{"d1": 5}');
        final remote = VectorClock.fromString('{"d1": 2}');

        final shouldApply = VectorClockComparator.shouldApplyRemote(
          localVc: local,
          remoteVc: remote,
          localLastModified: 500,
          remoteLastModified: 1000, // حتى لو كان البعيد أحدث زمنياً
        );

        expect(shouldApply, isFalse);
      });

      test('returns false when clocks are equal', () {
        final local = VectorClock.fromString('{"d1": 5}');
        final remote = VectorClock.fromString('{"d1": 5}');

        final shouldApply = VectorClockComparator.shouldApplyRemote(
          localVc: local,
          remoteVc: remote,
          localLastModified: 1000,
          remoteLastModified: 2000,
        );

        expect(shouldApply, isFalse);
      });

      test('uses LWW fallback for concurrent clocks', () {
        final local = VectorClock.fromString('{"d1": 1, "d2": 0}');
        final remote = VectorClock.fromString('{"d1": 0, "d2": 1}');

        // البعيد أحدث زمنياً
        expect(
          VectorClockComparator.shouldApplyRemote(
            localVc: local,
            remoteVc: remote,
            localLastModified: 1000,
            remoteLastModified: 2000,
          ),
          isTrue,
        );

        // المحلي أحدث زمنياً
        expect(
          VectorClockComparator.shouldApplyRemote(
            localVc: local,
            remoteVc: remote,
            localLastModified: 2000,
            remoteLastModified: 1000,
          ),
          isFalse,
        );
      });
    });

    group('Round-trip serialization', () {
      test('toString and fromString are inverses', () {
        final original = VectorClock.fromString('{"d1": 5, "d2": 3, "d3": 1}');
        final serialized = original.toString();
        final deserialized = VectorClock.fromString(serialized);

        expect(deserialized.isEqual(original), isTrue);
      });
    });

    group('Multi-device scenario', () {
      test('simulates checkout on Device 1 → pull on Device 2', () {
        // جهاز 1: يسجل مغادرة
        final vc1 = VectorClock.empty();
        vc1.increment('device1');
        vc1.increment('device1'); // حدثان: تحديث الحجز + تحديث الغرفة

        // جهاز 2: عنده نسخة قديمة
        final vc2 = VectorClock.empty();
        vc2.increment('device2'); // حدث واحد محلي قديم

        // السحب: جهاز 2 يستلم من جهاز 1
        final result = VectorClockComparator.compare(vc2, vc1);
        expect(result, equals(VectorClockComparison.concurrent));

        // لكن مع LWW fallback: جهاز 1 أحدث زمنياً → يُطبّق
        final shouldApply = VectorClockComparator.shouldApplyRemote(
          localVc: vc2,
          remoteVc: vc1,
          localLastModified: 1000, // جهاز 2 قديم
          remoteLastModified: 2000, // جهاز 1 جديد
        );
        expect(shouldApply, isTrue);

        // بعد التطبيق: جهاز 2 يدمج الساعتين
        final merged = VectorClockComparator.mergeAfterApply(vc2, vc1);
        expect(merged.get('device1'), equals(2));
        expect(merged.get('device2'), equals(1));
      });
    });
  });
}
