import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تفضيل المستخدم لوضع الثيم — ثلاثة خيارات بدلاً من bool.
///
/// - [light]  : الوضع الفاتح دائماً
/// - [dark]   : الوضع الداكن دائماً
/// - [system] : اتباع إعداد النظام (يتغيّر تلقائياً عند تبديل الوضع في
///              إعدادات الجهاز — مفيد للأجهزة التي تتبدّل تلقائياً عند
///              الغروب/الشروق)
enum ThemeModePreference {
  /// الوضع الفاتح دائماً.
  light,

  /// الوضع الداكن دائماً.
  dark,

  /// اتباع إعداد النظام (auto-switch at sunset/sunrise على الأجهزة المدعومة).
  system,
}

/// امتداد لـ ThemeModePreference يوفّر تحويلاً مريحاً إلى ThemeMode.
extension ThemeModePreferenceX on ThemeModePreference {
  /// يحوّل التفضيل إلى ThemeMode الفعلي لـ MaterialApp.
  ThemeMode toThemeMode() {
    switch (this) {
      case ThemeModePreference.light:
        return ThemeMode.light;
      case ThemeModePreference.dark:
        return ThemeMode.dark;
      case ThemeModePreference.system:
        return ThemeMode.system;
    }
  }

  /// تسمية عربية للعرض في الواجهة.
  String get arabicLabel {
    switch (this) {
      case ThemeModePreference.light:
        return 'فاتح';
      case ThemeModePreference.dark:
        return 'داكن';
      case ThemeModePreference.system:
        return 'تلقائي (حسب النظام)';
    }
  }

  /// وصف عربي مختصر للعرض تحت التسمية.
  String get arabicDescription {
    switch (this) {
      case ThemeModePreference.light:
        return 'الوضع الفاتح دائماً';
      case ThemeModePreference.dark:
        return 'الوضع الداكن دائماً';
      case ThemeModePreference.system:
        return 'يتبع إعداد النظام تلقائياً';
    }
  }

  /// أيقونة Material مناسبة لكل وضع.
  IconData get icon {
    switch (this) {
      case ThemeModePreference.light:
        return Icons.light_mode_outlined;
      case ThemeModePreference.dark:
        return Icons.dark_mode_outlined;
      case ThemeModePreference.system:
        return Icons.brightness_auto_outlined;
    }
  }
}

/// Notifier لإدارة تفضيل وضع الثيم مع حفظ دائم في SharedPreferences.
///
/// ✅ Migration من الإصدار القديم:
/// قبل الإصلاح: مفتاح SharedPreferences كان `dark_mode_enabled` (bool).
/// بعد الإصلاح: المفتاح الجديد `theme_mode_preference` (string: 'light'|
/// 'dark'|'system').
///
/// عند أول تشغيل بعد الترقية، إن وُجد المفتاح القديم ولم يُوجد الجديد،
/// نُهاجر القيمة:
///   false (light) → ThemeModePreference.light
///   true  (dark)  → ThemeModePreference.dark
/// ثم نحذف المفتاح القديم لتفادي إعادة الترحيل.
class ThemeSettingsNotifier extends StateNotifier<ThemeModePreference> {
  ThemeSettingsNotifier() : super(ThemeModePreference.system) {
    _load();
  }

  static const _kThemeModeKey = 'theme_mode_preference';
  static const _kLegacyDarkModeKey = 'dark_mode_enabled'; // ← مفتاح قديم

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) اقرأ المفتاح الجديد أولاً
    final stored = prefs.getString(_kThemeModeKey);
    if (stored != null) {
      final parsed = ThemeModePreference.values.firstWhere(
        (e) => e.name == stored,
        orElse: () => ThemeModePreference.system,
      );
      state = parsed;
      return;
    }

    // 2) Migration: حوّل المفتاح القديم إن وُجد
    if (prefs.containsKey(_kLegacyDarkModeKey)) {
      final legacyDark = prefs.getBool(_kLegacyDarkModeKey) ?? false;
      final migrated = legacyDark
          ? ThemeModePreference.dark
          : ThemeModePreference.light;
      await prefs.setString(_kThemeModeKey, migrated.name);
      await prefs.remove(_kLegacyDarkModeKey);
      debugPrint(
        '🎨 [Theme] migrated legacy dark_mode_enabled=$legacyDark → '
        'theme_mode_preference=${migrated.name}',
      );
      state = migrated;
      return;
    }

    // 3) افتراضي: system
    state = ThemeModePreference.system;
  }

  /// يضبط تفضيل الوضع ويحفظه.
  Future<void> setPreference(ThemeModePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, preference.name);
    state = preference;
  }

  // ─── توافق عكسي مع الـ API القديم (bool isDark) ──────────────────────
  //
  // محفوظ مؤقتاً لأن بعض الشاشات قد تستخدم ref.read(themeSettingsProvider)
  // كـ bool. سيُزال تدريجياً.
  // ignore: deprecated_member_use_from_same_package
  @Deprecated('استخدم preferenceProvider أو themeModeProvider بدلاً منه. '
      'محفوظ للتوافق عكسي مؤقتاً.')
  bool get isDark => state == ThemeModePreference.dark;

  @Deprecated('استخدم setPreference() بدلاً منه. محفوظ للتوافق عكسي.')
  Future<void> setDarkMode(bool enabled) =>
      setPreference(enabled ? ThemeModePreference.dark : ThemeModePreference.light);

  @Deprecated('استخدم setPreference() بدلاً منه. محفوظ للتوافق عكسي.')
  Future<void> toggle() => setPreference(
        state == ThemeModePreference.dark
            ? ThemeModePreference.light
            : ThemeModePreference.dark,
      );
}

/// مزوّد Riverpod لتفضيل وضع الثيم (light/dark/system).
///
/// الاستخدام:
/// ```dart
/// final pref = ref.watch(themeSettingsProvider); // ThemeModePreference
/// ref.read(themeSettingsProvider.notifier).setPreference(ThemeModePreference.dark);
/// ```
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeModePreference>((ref) {
  return ThemeSettingsNotifier();
});

/// مزوّد يُرجع ThemeMode الفعلي لـ MaterialApp (light/dark/system).
///
/// يُشتقّ من [themeSettingsProvider]. استخدمه مباشرة في MaterialApp.themeMode.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final pref = ref.watch(themeSettingsProvider);
  return pref.toThemeMode();
});

/// مزوّد يُرجع true إذا كان الوضع الحالي فعلياً داكن (يأخذ بعين الاعتبار
/// الوضع "system" والقرار الفعلي للنظام).
///
/// مفيد للـ widgets التي تحتاج لمعرفة الوضع الفعلي (مثلاً لاختيار صورة
/// أو لضبط alpha). للـ widgets التي تحتاج فقط لـ ThemeMode، استخدم
/// [themeModeProvider].
final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  switch (mode) {
    case ThemeMode.light:
      return false;
    case ThemeMode.dark:
      return true;
    case ThemeMode.system:
      // WidgetsBinding يوفّر PlatformDispatcher.brightness — لكن في الـ
      // provider layer نعتمد على ما يراه MaterialApp. هذا التقدير قد لا
      // يكون دقيقاً 100% قبل أول build، لكنه كافٍ للاستخدامات غير الحرجة.
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  }
});
