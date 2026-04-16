import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/vector_clock.dart';

void main() {
  test('increment bumps device counter and is immutable', () {
    final v1 = VectorClock.empty();
    final v2 = v1.increment('d1');
    expect(v1.clocks.containsKey('d1'), isFalse);
    expect(v2.clocks['d1'], 1);
    final v3 = v2.increment('d1');
    expect(v3.clocks['d1'], 2);
  });

  test('merge keeps max per device', () {
    final a = VectorClock({'a': 1, 'b': 2});
    final b = VectorClock({'b': 3, 'c': 1});
    final merged = a.merge(b);
    expect(merged.clocks, {'a': 1, 'b': 3, 'c': 1});
  });

  test('compare covers before/after/equal/concurrent', () {
    final base = VectorClock({'a': 1, 'b': 2});
    expect(base.compare(VectorClock({'a': 1, 'b': 2})), 'equal');
    expect(base.compare(VectorClock({'a': 2, 'b': 3})), 'before');
    expect(base.compare(VectorClock({'a': 0, 'b': 1})), 'after');
    expect(base.compare(VectorClock({'a': 1, 'b': 2, 'c': 5})), 'before');
    expect(base.compare(VectorClock({'a': 0, 'b': 3})), 'concurrent');
  });

  test('json roundtrip and invalid json', () {
    final v = VectorClock({'x': 4});
    final json = v.toJson();
    expect(VectorClock.fromJson(json).clocks, {'x': 4});
    expect(VectorClock.fromJson('').clocks, isEmpty);
    expect(VectorClock.fromJson('{"not": "clock"}').clocks, isEmpty);
  });

  test('equality uses map equality', () {
    final a = VectorClock({'d': 1});
    final b = VectorClock({'d': 1});
    final c = VectorClock({'d': 2});
    expect(a, equals(b));
    expect(a == c, isFalse);
    expect(a.hashCode, equals(b.hashCode));
  });
}
