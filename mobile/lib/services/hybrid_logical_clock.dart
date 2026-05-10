import 'package:shared_preferences/shared_preferences.dart';

/// Hybrid Logical Clock (HLC) - يجمع بين Physical Time و Logical Counter
/// يحل مشكلة اختلاف أوقات الأجهزة
class HybridLogicalClock {
  HybridLogicalClock._({
    required this.physicalTime,
    required this.logicalCounter,
    required this.deviceId,
  });

  final int physicalTime;
  final int logicalCounter;
  final String deviceId;

  static const String _prefsKeyPhysical = 'hlc_physical';
  static const String _prefsKeyLogical = 'hlc_logical';

  static HybridLogicalClock? _instance;

  static Future<HybridLogicalClock> getInstance(String deviceId) async {
    if (_instance != null && _instance!.deviceId == deviceId) {
      return _instance!;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedPhysical = prefs.getInt(_prefsKeyPhysical) ?? 0;
    final savedLogical = prefs.getInt(_prefsKeyLogical) ?? 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final physical = now > savedPhysical ? now : savedPhysical;

    _instance = HybridLogicalClock._(
      physicalTime: physical,
      logicalCounter: physical > savedPhysical ? 0 : savedLogical,
      deviceId: deviceId,
    );

    return _instance!;
  }

  Future<HybridLogicalClock> tick() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final newPhysical = now > physicalTime ? now : physicalTime;
    final newLogical = now > physicalTime ? 0 : logicalCounter + 1;

    final newClock = HybridLogicalClock._(
      physicalTime: newPhysical,
      logicalCounter: newLogical,
      deviceId: deviceId,
    );

    await _persist(newPhysical, newLogical);
    _instance = newClock;

    return newClock;
  }

  Future<HybridLogicalClock> update(HybridLogicalClock remote) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final newPhysical = _max3(now, physicalTime, remote.physicalTime);

    int newLogical;
    if (newPhysical == physicalTime && newPhysical == remote.physicalTime) {
      newLogical = _max(logicalCounter, remote.logicalCounter) + 1;
    } else if (newPhysical == physicalTime) {
      newLogical = logicalCounter + 1;
    } else if (newPhysical == remote.physicalTime) {
      newLogical = remote.logicalCounter + 1;
    } else {
      newLogical = 0;
    }

    final newClock = HybridLogicalClock._(
      physicalTime: newPhysical,
      logicalCounter: newLogical,
      deviceId: deviceId,
    );

    await _persist(newPhysical, newLogical);
    _instance = newClock;

    return newClock;
  }

  int compare(HybridLogicalClock other) {
    if (physicalTime < other.physicalTime) {
      return -1;
    }
    if (physicalTime > other.physicalTime) {
      return 1;
    }

    if (logicalCounter < other.logicalCounter) {
      return -1;
    }
    if (logicalCounter > other.logicalCounter) {
      return 1;
    }

    return deviceId.compareTo(other.deviceId);
  }

  bool happensBefore(HybridLogicalClock other) => compare(other) < 0;
  bool happensAfter(HybridLogicalClock other) => compare(other) > 0;
  bool isConcurrent(HybridLogicalClock other) => compare(other) == 0;

  String toJson() => '$physicalTime-$logicalCounter-$deviceId';

  static HybridLogicalClock? fromJson(String? json, String defaultDeviceId) {
    if (json == null || json.isEmpty) {
      return null;
    }

    try {
      final parts = json.split('-');
      if (parts.length != 3) {
        return null;
      }

      return HybridLogicalClock._(
        physicalTime: int.parse(parts[0]),
        logicalCounter: int.parse(parts[1]),
        deviceId: parts[2],
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _persist(int physical, int logical) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyPhysical, physical);
    await prefs.setInt(_prefsKeyLogical, logical);
  }

  int _max(int a, int b) => a > b ? a : b;
  int _max3(int a, int b, int c) => _max(_max(a, b), c);

  @override
  String toString() => 'HLC($physicalTime:$logicalCounter@$deviceId)';
}
