import 'package:shared_preferences/shared_preferences.dart';

Future<T> migrateAutoSyncPreference<T>({
  required SharedPreferences prefs,
  required String newKey,
  required String legacyKey,
  required T defaultValue,
  required Future<void> Function(T value) apply,
}) async {
  if (T != int && T != bool) {
    throw UnsupportedError('Unsupported preference type: $T');
  }

  T value;
  if (T == int) {
    final resolved = prefs.getInt(newKey) ?? prefs.getInt(legacyKey) ?? defaultValue as int;
    await prefs.setInt(newKey, resolved);
    value = resolved as T;
  } else {
    final resolved = prefs.getBool(newKey) ?? prefs.getBool(legacyKey) ?? defaultValue as bool;
    await prefs.setBool(newKey, resolved);
    value = resolved as T;
  }

  await apply(value);
  return value;
}
