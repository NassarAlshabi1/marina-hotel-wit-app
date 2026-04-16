import 'package:flutter/material.dart';

// Color scheme matching PHP Bootstrap admin design
class AppColors {
  // Primary colors - main accent for borders and highlights
  static const Color primaryColor = Color(0xFF6A1B9A);  // Deep purple - light mode
  static const Color primaryDark = Color(0xFFB070DB);   // Lighter purple - dark mode accent
  static const Color primaryLight = Color(0xFF9650BE);  // Intermediate shade

  // Background colors
  static const Color backgroundColor = Color(0xFFf8f9fa); // Bootstrap bg-light
  static const Color surfaceColor = Color(0xFFffffff);

  // Text colors
  static const Color textPrimary = Color(0xFF212529); // Bootstrap text-dark
  static const Color textSecondary = Color(0xFF6c757d); // Bootstrap text-muted

  // Status colors - matching PHP badges
  static const Color successColor = Color(0xFF28a745); // Bootstrap success
  static const Color dangerColor = Color(0xFFdc3545); // Bootstrap danger
  static const Color warningColor = Color(0xFFffc107); // Bootstrap warning
  static const Color infoColor = Color(0xFF17a2b8); // Bootstrap info

  // Gray colors
  static const Color lightGray = Color(0xFFe9ecef); // Bootstrap gray-200
  static const Color mediumGray = Color(0xFF6c757d); // Bootstrap gray-600
  static const Color darkGray = Color(0xFF343a40); // Bootstrap dark

  // Card and component colors
  static const Color cardBackground = Colors.white;
  static const Color dividerColor = Color(0xFFdee2e6); // Bootstrap border color

  // Admin sidebar colors
  static const Color sidebarColor = Color(0xFF0F172A);
  static const Color sidebarAccent = Color(0xFF16213C);
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
      secondary: AppColors.infoColor,
      surface: AppColors.surfaceColor,
      background: AppColors.backgroundColor,
      error: AppColors.dangerColor,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: AppColors.textPrimary,
      onBackground: AppColors.textPrimary,
      onError: Colors.white,
    ),

    // AppBar theme - main accent color
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryColor,
      foregroundColor: Colors.white,
      elevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        fontFamily: 'Tajawal',
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),

    // Card theme matching Bootstrap cards
    cardTheme: const CardThemeData(
      color: AppColors.cardBackground,
      elevation: 1,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: Color(0xFFE8D5F0)), // Light purple border
      ),
    ),

    // Button themes matching Bootstrap buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryColor,
        side: const BorderSide(color: AppColors.primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    ),

    // Input theme - borders use primary purple
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: AppColors.lightGray),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: AppColors.lightGray),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      labelStyle: TextStyle(color: AppColors.textSecondary),
      hintStyle: TextStyle(color: AppColors.textSecondary),
    ),

    // Table theme
    dataTableTheme: const DataTableThemeData(
      headingRowColor: MaterialStatePropertyAll(AppColors.darkGray),
      headingTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      dataTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      columnSpacing: 24,
      horizontalMargin: 16,
      dataRowMinHeight: 44,
    ),

    // List tile theme
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
    ),

    // Divider color
    dividerColor: const Color(0xFFE0D0EA), // Soft purple divider

    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

ThemeData buildDarkTheme() {
  // Dark mode uses lighter primary for visibility on dark surfaces
  const darkPrimary = AppColors.primaryDark; // Lighter purple for dark mode
  const darkSurface = Color(0xFF1E1E1E);
  const darkBackground = Color(0xFF121212);
  const darkInputBorder = Color(0xFF2C2C2C);
  const darkAppBar = Color(0xFF4A1070); // Lighter purple for dark AppBar

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
      secondary: Color(0xFF5BACD4), // Lighter blue for dark mode
      surface: darkSurface,
      background: darkBackground,
      error: Color(0xFFEF5350), // Lighter red for dark mode
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFFE0E0E0), // Soft white text
      onBackground: Color(0xFFE0E0E0),
      onError: Colors.white,
    ),

    // Dark AppBar - lighter shade for contrast
    appBarTheme: const AppBarTheme(
      backgroundColor: darkAppBar,
      foregroundColor: Color(0xFFE0D5F0), // Light purple text/icons
      elevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE0D5F0),
        fontFamily: 'Tajawal',
      ),
      iconTheme: IconThemeData(color: Color(0xFFE0D5F0)),
    ),

    // Dark cards with purple tinted border
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 1,
      margin: const EdgeInsets.all(8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: Color(0xFF3D2048)), // Dark purple border for dark mode
      ),
    ),

    // Dark elevated buttons - lighter purple
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    ),

    // Dark outlined buttons
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkPrimary,
        side: const BorderSide(color: darkPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    ),

    // Dark inputs - purple tinted focus
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: darkInputBorder),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: darkInputBorder),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: darkPrimary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white54),
    ),

    // Dark table
    dataTableTheme: const DataTableThemeData(
      headingRowColor: MaterialStatePropertyAll(Color(0xFF2C2C2C)),
      headingTextStyle: TextStyle(
        color: Color(0xFFE0D5F0), // Light purple heading text
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      dataTextStyle: TextStyle(color: Colors.white, fontSize: 14),
      columnSpacing: 24,
      horizontalMargin: 16,
      dataRowMinHeight: 44,
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
      iconColor: Color(0xFFD4A0E8), // Light purple icons in dark
      textColor: Colors.white,
    ),

    // Dark divider - subtle purple tint
    dividerColor: const Color(0xFF3D2048),

    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

// Helper function to create MaterialColor from Color
MaterialColor _createMaterialColor(Color color) {
  final strengths = <double>[.05];
  final Map<int, Color> swatch = <int, Color>{};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.value, swatch);
}
