import 'dart:convert';

/// Vector Clock لاكتشاف التعارضات الحقيقية بين الأجهزة
class VectorClock {
  VectorClock(this.clocks);

  factory VectorClock.empty() => VectorClock({});

  factory VectorClock.fromJson(String json) {
    if (json.isEmpty) return VectorClock.empty();
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return VectorClock(map.map((k, v) => MapEntry(k, v as int)));
    } catch (e) {
      return VectorClock.empty();
    }
  }

  final Map<String, int> clocks;

  String toJson() => jsonEncode(clocks);

  VectorClock increment(String deviceId) {
    final newClocks = Map<String, int>.from(clocks);
    newClocks[deviceId] = (newClocks[deviceId] ?? 0) + 1;
    return VectorClock(newClocks);
  }

  VectorClock merge(VectorClock other) {
    final newClocks = Map<String, int>.from(clocks);
    for (final entry in other.clocks.entries) {
      final currentValue = newClocks[entry.key] ?? 0;
      newClocks[entry.key] =
          currentValue > entry.value ? currentValue : entry.value;
    }
    return VectorClock(newClocks);
  }

  /// مقارنة vector clocks
  /// Returns: 'before', 'after', 'concurrent', 'equal'
  String compare(VectorClock other) {
    bool thisBefore = false;
    bool thisAfter = false;

    final allDevices = <String>{...clocks.keys, ...other.clocks.keys};

    for (final device in allDevices) {
      final thisValue = clocks[device] ?? 0;
      final otherValue = other.clocks[device] ?? 0;

      if (thisValue < otherValue) {
        thisBefore = true;
      } else if (thisValue > otherValue) {
        thisAfter = true;
      }
    }

    if (!thisBefore && !thisAfter) return 'equal';
    if (thisBefore && !thisAfter) return 'before';
    if (!thisBefore && thisAfter) return 'after';
    return 'concurrent';
  }

  bool happensBefore(VectorClock other) => compare(other) == 'before';
  bool happensAfter(VectorClock other) => compare(other) == 'after';
  bool isConcurrent(VectorClock other) => compare(other) == 'concurrent';
  bool isEqual(VectorClock other) => compare(other) == 'equal';

  @override
  String toString() => 'VectorClock($clocks)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VectorClock &&
          runtimeType == other.runtimeType &&
          const MapEquality().equals(clocks, other.clocks);

  @override
  int get hashCode => const MapEquality().hash(clocks);
}

class MapEquality<K, V> {
  const MapEquality();

  bool equals(Map<K, V>? a, Map<K, V>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  int hash(Map<K, V>? map) {
    if (map == null) return 0;
    int hash = 0;
    for (final entry in map.entries) {
      hash ^= entry.key.hashCode;
      hash ^= entry.value.hashCode;
    }
    return hash;
  }
}
