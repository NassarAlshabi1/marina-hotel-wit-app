import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

class ThemeSettingsNotifier extends StateNotifier<bool> {
  ThemeSettingsNotifier() : super(false) {
    _load();
  }

  static const _kDarkMode = 'dark_mode_enabled';

  Future<void> _load() async {
    final prefs = getSharedPrefs();
    state = prefs.getBool(_kDarkMode) ?? false;
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = getSharedPrefs();
    await prefs.setBool(_kDarkMode, enabled);
    state = enabled;
  }

  Future<void> toggle() => setDarkMode(!state);
}

final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, bool>((ref) {
      return ThemeSettingsNotifier();
    });
