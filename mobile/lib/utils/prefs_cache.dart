/// ============================================================
/// Marina Hotel - SharedPreferences Cache
/// ============================================================
/// يمنع 326 استدعاء I/O بـ getInstance() باستخدام Singleton
/// الفضل: مرة واحدة فقط لقراءة الملف، الباقي من الذاكرة
/// ============================================================
library;

import 'package:shared_preferences/shared_preferences.dart';


/// كاش مركزي لـ SharedPreferences
/// جميع الاستدعاءات تذهب إلى instance واحد (I/O مرة واحدة)
class PrefsCache {
  PrefsCache._();
  static SharedPreferences? _prefs;

  /// تهيئة الكاش — يُستدعى مرة واحدة من main()
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    assert(_prefs != null, '⚠️ PrefsCache لم يُهيّأ — استدعِ PrefsCache.init() في main()');
    return _prefs!;
  }

  // ─── Readers ───
  static String getString(String key, [String? defaultValue]) =>
      _p.getString(key) ?? defaultValue ?? '';

  static bool getBool(String key, [bool defaultValue = false]) =>
      _p.getBool(key) ?? defaultValue;

  static int getInt(String key, [int defaultValue = 0]) =>
      _p.getInt(key) ?? defaultValue;

  static double getDouble(String key, [double defaultValue = 0.0]) =>
      _p.getDouble(key) ?? defaultValue;

  static List<String> getStringList(String key) =>
      _p.getStringList(key) ?? [];

  static Set<String> getKeys() => _p.getKeys();

  static bool containsKey(String key) => _p.containsKey(key);

  // ─── Writers ───
  static Future<bool> setString(String key, String value) =>
      _p.setString(key, value);

  static Future<bool> setBool(String key, bool value) =>
      _p.setBool(key, value);

  static Future<bool> setInt(String key, int value) =>
      _p.setInt(key, value);

  static Future<bool> setDouble(String key, double value) =>
      _p.setDouble(key, value);

  static Future<bool> setStringList(String key, List<String> value) =>
      _p.setStringList(key, value);

  static Future<bool> remove(String key) => _p.remove(key);

  static Future<void> clearAll() => _p.clear();

  // ─── Async versions (للاستخدام في الكود الموجود بدون تغيير) ───
  static Future<String?> getAsync(String key) async => _p.getString(key);

  static Future<bool?> getBoolAsync(String key) async => _p.getBool(key);

  static Future<int?> getIntAsync(String key) async => _p.getInt(key);

  static Future<double?> getDoubleAsync(String key) async =>
      _p.getDouble(key);
}

/// استبدال مباشر لـ getSharedPrefs()
/// دون تغيير بقية الكود
Future<SharedPreferences> getSharedPrefs() async {
  PrefsCache._prefs ??= await SharedPreferences.getInstance();
  return PrefsCache._prefs!;
}
