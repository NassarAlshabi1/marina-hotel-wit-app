import 'package:flutter/material.dart';

// Color scheme matching PHP Bootstrap admin design
class AppColors {
  // Primary colors - matching PHP header/sidebar
  static const Color primaryColor = Color(0xFF007bff);  // Bootstrap primary blue
  static const Color primaryDark = Color(0xFF0056b3);
  static const Color primaryLight = Color(0xFF66b2ff);
  
  // Background colors
  static const Color backgroundColor = Color(0xFFf8f9fa);  // Bootstrap bg-light
  static const Color surfaceColor = Color(0xFFffffff);
  
  // Text colors
  static const Color textPrimary = Color(0xFF212529);     // Bootstrap text-dark
  static const Color textSecondary = Color(0xFF6c757d);   // Bootstrap text-muted
  
  // Status colors - matching PHP badges
  static const Color successColor = Color(0xFF28a745);    // Bootstrap success
  static const Color dangerColor = Color(0xFFdc3545);     // Bootstrap danger  
  static const Color warningColor = Color(0xFFffc107);    // Bootstrap warning
  static const Color infoColor = Color(0xFF17a2b8);      // Bootstrap info
  
  // Gray colors
  static const Color lightGray = Color(0xFFe9ecef);      // Bootstrap gray-200
  static const Color mediumGray = Color(0xFF6c757d);     // Bootstrap gray-600
  static const Color darkGray = Color(0xFF343a40);       // Bootstrap dark
  
  // Card and component colors
  static const Color cardBackground = Colors.white;
  static const Color dividerColor = Color(0xFFdee2e6);   // Bootstrap border color
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: false,  // Use Material 2 for better Bootstrap compatibility
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
    
    // AppBar theme matching PHP header
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
    ),
    
    // Card theme matching Bootstrap cards
    cardTheme: const CardTheme(
      color: AppColors.cardBackground,
      elevation: 1,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    
    // Button themes matching Bootstrap buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryColor,
        side: const BorderSide(color: AppColors.primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
    ),
    
    // Input theme matching Bootstrap forms
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
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
      dataTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
      columnSpacing: 24,
      horizontalMargin: 16,
      minWidth: 600,
    ),
    
    // List tile theme
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
    ),
    
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

// Helper function to create MaterialColor from Color
MaterialColor _createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = <int, Color>{};
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
