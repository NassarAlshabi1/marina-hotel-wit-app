// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeSettingsNotifier extends StateNotifier<bool> {
  ThemeSettingsNotifier() : super(false) {
    _load();
  }

  static const _kDarkMode = 'dark_mode_enabled';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kDarkMode) ?? false;
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkMode, enabled);
    state = enabled;
  }

  Future<void> toggle() => setDarkMode(!state);
}

final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, bool>((ref) {
      return ThemeSettingsNotifier();
    });
