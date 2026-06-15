import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';
import 'package:uuid/uuid.dart';

class IdGen {
  static const _uuid = Uuid();
  static String uuid() => _uuid.v4();

  static String? _cachedDeviceId;
  static Future<String> deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = getSharedPrefs();
    _cachedDeviceId = prefs.getString('device_id');
    if (_cachedDeviceId == null) {
      _cachedDeviceId = _uuid.v4();
      await prefs.setString('device_id', _cachedDeviceId!);
    }
    return _cachedDeviceId!;
  }

  static String get deviceIdSync {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    _cachedDeviceId = _uuid.v4();
    return _cachedDeviceId!;
  }
}
