import 'package:shared_preferences/shared_preferences.dart';

import '../utils/id.dart';

class DeviceIdentity {
  static const _primaryKey = 'sync_device_id';
  static const _legacyKeys = <String>[
    'smart_sync_device_id',
    'gd_delta_device_id',
    'appwrite_delta_device_id',
  ];

  static Future<String> ensure() async {
    final prefs = await SharedPreferences.getInstance();

    String? id = prefs.getString(_primaryKey);
    if (id != null && id.isNotEmpty) {
      await _syncLegacyKeys(prefs, id);
      return id;
    }

    for (final key in _legacyKeys) {
      final legacy = prefs.getString(key);
      if (legacy != null && legacy.isNotEmpty) {
        id = legacy;
        break;
      }
    }

    id ??= IdGen.uuid();
    await prefs.setString(_primaryKey, id);
    await _syncLegacyKeys(prefs, id);
    return id;
  }

  static Future<void> _syncLegacyKeys(SharedPreferences prefs, String id) async {
    for (final key in _legacyKeys) {
      final existing = prefs.getString(key);
      if (existing == id) continue;
      await prefs.setString(key, id);
    }
  }
}
