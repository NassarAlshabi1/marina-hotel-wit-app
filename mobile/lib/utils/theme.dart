import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MarketKy Theme — مستوحى من https://github.com/mrezkys/marketky
// ═══════════════════════════════════════════════════════════════════════════
//
// لوحة الألوان:
//   Primary     : #242476 (Indigo عميق — اللون الأساسي)
//   PrimarySoft : #EAEAF2 (لافندر فاتح — خلفيات ناعمة)
//   Secondary   : #0A0E2F (كحلي داكن — نص/أسطح داكنة)
//   Accent      : #FABA3E (ذهبي — إبرازات)
//   Border      : #D3D3E4 (رمادي لافندر — فواصل)
//
// الخطوط: Nunito (body) + Poppins (headings) — نُبقي Tajawal للعربية
// ═══════════════════════════════════════════════════════════════════════════

class AppColors {
  // ─── Primary: MarketKy Indigo #242476 ────────────────────────────────
  static const Color primaryColor = Color(0xFF242476);   // MarketKy primary
  static const Color primaryDark = Color(0xFF3D3D9E);    // أخف للوضع الداكن
  static const Color primaryLight = Color(0xFFEAEAF2);   // MarketKy primarySoft

  // ─── Background colors ───────────────────────────────────────────────
  static const Color backgroundColor = Color(0xFFF8F8FC); // أبيض مائل لللافندر
  static const Color surfaceColor = Color(0xFFFFFFFF);

  // ─── Text colors ─────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0A0E2F);    // MarketKy secondary
  static const Color textSecondary = Color(0xFF6C6F8F);  // كحلي باهت

  // ─── Status colors ───────────────────────────────────────────────────
  static const Color successColor = Color(0xFF2E7D5B);
  static const Color dangerColor = Color(0xFFE5484D);
  static const Color warningColor = Color(0xFFFABA3E);   // MarketKy accent
  static const Color infoColor = Color(0xFF242476);      // نفس primary

  // ─── Gray colors ─────────────────────────────────────────────────────
  static const Color lightGray = Color(0xFFEAEAF2);      // primarySoft
  static const Color mediumGray = Color(0xFF6C6F8F);
  static const Color darkGray = Color(0xFF0A0E2F);       // secondary

  // ─── Card and component colors ───────────────────────────────────────
  static const Color cardBackground = Colors.white;
  static const Color dividerColor = Color(0xFFD3D3E4);   // MarketKy border

  // ─── Admin sidebar colors ────────────────────────────────────────────
  static const Color sidebarColor = Color(0xFF0A0E2F);   // MarketKy secondary
  static const Color sidebarAccent = Color(0xFF242476);  // MarketKy primary

  // ─── MarketKy accent (جديد) ──────────────────────────────────────────
  static const Color accentColor = Color(0xFFFABA3E);    // MarketKy accent
  static const Color accentSoft = Color(0xFFFFF3DC);     // accent فاتح
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: false, // Use Material 2 for better Bootstrap compatibility
    brightness: Brightness.light,
    primarySwatch: _createMaterialColor(AppColors.primaryColor),
    fontFamily: 'Tajawal',
    scaffoldBackgroundColor: AppColors.backgroundColor,
  );

  return base.copyWith(
    primaryColor: AppColors.primaryColor,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryColor,
      secondary: AppColors.accentColor,
      error: AppColors.dangerColor,
      // مطابق للقيمة الافتراضية، لكن نُبقيه صراحةً للقراءة (نص أبيض على اللون الأساسي).
      onPrimary: Colors.white, // ignore: avoid_redundant_argument_values
      onSecondary: Color(0xFF0A0E2F),
      onSurface: AppColors.textPrimary,
      // مطابق للقيمة الافتراضية حاليًا (أبيض)، لكن نُبقي الإشارة إلى
      // AppColors.surfaceColor لضمان تبعية الثيم لأي تغيير مستقبلي على هذا الثابت الدلالي.
      surface: AppColors.surfaceColor, // ignore: avoid_redundant_argument_values
    ),

    // AppBar theme — MarketKy style: خلفية بيضاء + نص كحلي
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        fontFamily: 'Tajawal',
      ),
      iconTheme: IconThemeData(color: AppColors.primaryColor),
    ),

    // Card theme — MarketKy style: حواف 12 + حدود لافندر
    cardTheme: const CardThemeData(
      color: AppColors.cardBackground,
      elevation: 0,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.dividerColor),
      ),
    ),

    // Button themes — MarketKy style
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryColor,
        side: const BorderSide(color: AppColors.primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),

    // Input theme — MarketKy border
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: AppColors.textSecondary),
      hintStyle: TextStyle(color: AppColors.textSecondary),
    ),

    // Table theme
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(AppColors.primaryColor),
      headingTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
      dataTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
      columnSpacing: 24,
      horizontalMargin: 16,
      dataRowMinHeight: 48,
    ),

    // List tile theme
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
      iconColor: AppColors.primaryColor,
      textColor: AppColors.textPrimary,
    ),

    // Divider color — MarketKy border
    dividerColor: AppColors.dividerColor,

    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

ThemeData buildDarkTheme() {
  // ✅ MarketKy dark mode: كحلي داكن (#0A0E2F) + indigo أخف
  const darkPrimary = AppColors.primaryDark;   // #3D3D9E
  const darkSurface = Color(0xFF11142B);        // كحلي داكن للأسطح
  const darkBackground = Color(0xFF0A0E2F);     // خلفية كحلي
  const darkInputBorder = Color(0xFF2A2D4A);    // حدود داكنة
  const darkAccent = AppColors.accentColor;     // #FABA3E

  final base = ThemeData(
    useMaterial3: false,
    brightness: Brightness.dark,
    primarySwatch: _createMaterialColor(darkPrimary),
    fontFamily: 'Tajawal',
    scaffoldBackgroundColor: darkBackground,
  );

  return base.copyWith(
    primaryColor: darkPrimary,
    colorScheme: const ColorScheme.dark(
      primary: darkPrimary,
      secondary: darkAccent,
      surface: darkSurface,
      error: Color(0xFFF25555),
      onPrimary: Colors.white,
      onSecondary: Color(0xFF0A0E2F),
      onSurface: Color(0xFFE8E8F0),
      onError: Colors.white,
    ),

    // Dark AppBar — MarketKy style: خلفية كحلي + نص فاتح
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        fontFamily: 'Tajawal',
      ),
      iconTheme: IconThemeData(color: darkAccent),
    ),

    // Dark cards — MarketKy style: حواف 12 + حدود داكنة
    cardTheme: const CardThemeData(
      color: darkSurface,
      elevation: 0,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: darkInputBorder),
      ),
    ),

    // Dark elevated buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),

    // Dark outlined buttons
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkPrimary,
        side: const BorderSide(color: darkPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),

    // Dark inputs
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: darkInputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: darkInputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: darkPrimary, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: Color(0xFFAAAAD0)),
      hintStyle: TextStyle(color: Color(0xFF707090)),
    ),

    // Dark table
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(darkPrimary),
      headingTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
      dataTextStyle: TextStyle(
        color: Color(0xFFE8E8F0),
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
      columnSpacing: 24,
      horizontalMargin: 16,
      dataRowMinHeight: 48,
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
      iconColor: darkAccent,
      textColor: Colors.white,
    ),

    // Dark divider
    dividerColor: darkInputBorder,

    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

// Helper function to create MaterialColor from Color
MaterialColor _createMaterialColor(Color color) {
  final strengths = <double>[.05];
  final Map<int, Color> swatch = <int, Color>{};
  final int r = (color.r * 255.0).round().clamp(0, 255);
  final int g = (color.g * 255.0).round().clamp(0, 255);
  final int b = (color.b * 255.0).round().clamp(0, 255);

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (final strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.toARGB32(), swatch);
}
