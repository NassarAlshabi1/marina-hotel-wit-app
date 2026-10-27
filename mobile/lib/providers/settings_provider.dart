import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider {
  static const String _cutoffHourKey = 'hotel_cutoff_hour';

  /// الحصول على ساعة القطع لاحتساب الليالي (الافتراضي 14)
  static Future<int> getCutoffHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cutoffHourKey) ?? 14;
  }

  /// تعيين ساعة القطع لاحتساب الليالي (0-23)
  static Future<void> setCutoffHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cutoffHourKey, hour);
  }
}
