import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MARINA HOTEL — THEME SYSTEM (Material 3, Marina Navy palette)
// ═══════════════════════════════════════════════════════════════════════════
//
// الهوية البصرية الجديدة لفندق مارينا — مستوحاة من الأسم (Marina = مرسى يخت):
//   • Primary    : Deep Marina Navy #003049 — الثقة والعمق البحري
//   • Secondary  : Brass Gold #B08D57      — الفخامة والتراث
//   • Tertiary   : Sea-Glass Teal #3D8B8B  — الهدوء الساحلي
//   • Surface    : Warm Cream #FAF7F2 (light) / Navy-Black #10171F (dark)
//
// المصدر الإلهام: Hilton (navy+gold)، Four Seasons (charcoal+gold)،
// واللوحات البحرية (nautical palettes). تم اختيار الألوان لتكون
// HCT-compatible لتعمل بسلاسة مع ColorScheme.fromSeed في Material 3.
//
// التوافق مع الكود القديم:
//   • AppColors محفوظ كـ deprecated wrapper يحوّل المراجع القديمة
//     (بنفسجي Bootstrap) إلى الألوان الجديدة (Marina Navy). صفر كسور.
//   • buildTheme() / buildDarkTheme() محفوظتان كـ public API.
//     تستدعيان buildMarinaLightTheme() / buildMarinaDarkTheme().
//
// لترحيل مرجع قديم إلى الثيم الجديد يدوياً:
//   AppColors.primaryColor  →  Theme.of(context).colorScheme.primary
//   AppColors.textPrimary   →  Theme.of(context).colorScheme.onSurface
//   AppColors.textSecondary →  Theme.of(context).colorScheme.onSurfaceVariant
//   AppColors.successColor  →  Theme.of(context).colorScheme.tertiary
//   AppColors.dangerColor   →  Theme.of(context).colorScheme.error
// ═══════════════════════════════════════════════════════════════════════════

/// ألوان العلامة التجارية الثابتة لفندق مارينا — لا تتغيّر بين الوضعين
/// الفاتح والداكن (للألوان التي يجب أن تبقى محايدة بصرياً).
class MarinaBrandColors {
  MarinaBrandColors._();

  // ─── Primary palette: Deep Marina Navy ───────────────────────────────
  /// Primary brand — Deep Marina Navy.
  /// يُستخدم في الأزرار الأساسية، الـ AppBar، الروابط، التركيز.
  static const Color navy = Color(0xFF003049);
  static const Color navyLight = Color(0xFF2C5780); // tone ~60
  static const Color navyDark = Color(0xFF001F33);  // tone ~20

  // ─── Secondary palette: Brass Gold ───────────────────────────────────
  /// Secondary brand — Brass Gold (لمسة الفخامة).
  /// يُستخدم في الأزرار الثانوية، الإبرازات، أيقونات الرفع.
  static const Color brass = Color(0xFFB08D57);
  static const Color brassLight = Color(0xFFE6CFA0);
  static const Color brassDark = Color(0xFF7A5F32);

  // ─── Tertiary palette: Sea-Glass Teal ────────────────────────────────
  /// Tertiary brand — Sea-Glass Teal (إحساس ساحلي، سبأ/هدوء).
  /// يُستخدم في مؤشرات النجاح، شارات التوفر، أيقونات الرفاهية.
  static const Color seaGlass = Color(0xFF3D8B8B);
  static const Color seaGlassLight = Color(0xFF9DD1D1);
  static const Color seaGlassDark = Color(0xFF1F5757);

  // ─── Surfaces ────────────────────────────────────────────────────────
  static const Color creamSurface = Color(0xFFFAF7F2); // warm cream (light)
  static const Color creamContainer = Color(0xFFF2EDE4);
  static const Color navyBlack = Color(0xFF10171F);    // navy-black (dark)
  static const Color navyBlackContainer = Color(0xFF1A242E);

  // ─── Status colors (تتطابق بين الوضعين) ─────────────────────────────
  static const Color success = Color(0xFF2E7D5B);
  static const Color successDark = Color(0xFF7FCFA0);
  static const Color warning = Color(0xFFE0A500);
  static const Color warningDark = Color(0xFFFFD66B);
  static const Color error = Color(0xFF9B2226);
  static const Color errorDark = Color(0xFFF2A0A4);
  static const Color info = Color(0xFF3D8B8B); // same as seaGlass

  // ─── Charcoal / neutral ──────────────────────────────────────────────
  static const Color charcoal = Color(0xFF1A1A1A);
  static const Color warmWhite = Color(0xFFE8E4DC);
  static const Color outline = Color(0xFFC9BFAE); // light mode outline
  static const Color outlineDark = Color(0xFF3A4753);
}

// ═══════════════════════════════════════════════════════════════════════════
// DEPRECATED AppColors — يُحوّل المراجع القديمة إلى الألوان الجديدة.
// ═══════════════════════════════════════════════════════════════════════════
//
// قبل الإصلاح: كان AppColors يحمل ألوان بنفسجية (#6A1B9A) لمطابقة PHP
// Bootstrap admin. بعد الإصلاح: يحمل ألوان Marina Navy الجديدة، مع
// إبقاء نفس أسماء الـ members لضمان توافق الكود الموجود (101 موقع
// استخدام عبر lib/).
//
// الاستراتيجية: كل اسم قديم يُحوَّل إلى أقرب لون جديد بصرياً:
//   primaryColor  → navy        (كان بنفسجي → أصبح navy، كلاهما primary)
//   primaryDark   → navyLight   (كان بنفسجي فاتح → navyLight للوضع الداكن)
//   primaryLight  → brass       (كان متوسط → brass كـ secondary)
//   successColor  → success
//   dangerColor   → error
//   warningColor  → warning
//   infoColor     → seaGlass    (كان أزرق → أصبح teal، كلاهما "معلومة")
//   textPrimary   → charcoal    (كان أسود → أسود فحمي دافئ)
//   textSecondary → mediumGray  (نفسه)
//   backgroundColor → creamSurface (كان رمادي → أصبح cream دافئ)
//   surfaceColor  → white       (نفسه)
//   sidebarColor  → navyDark    (كان أزرق غامق → navy غامق، أقرب بصرياً)
//   sidebarAccent → navy        (كان أزرق غامق → navy)
//   cardBackground → white      (نفسه)
//   dividerColor  → outline     (كان رمادي → outline دافئ)
//   lightGray     → outline     (نفسه بصرياً)
//   mediumGray    → mediumGray  (نفسه)
//   darkGray      → charcoal    (كان أسود → charcoal)

/// @deprecated استخدم MarinaBrandColors أو Theme.of(context).colorScheme بدلاً منه.
/// محفوظ مؤقتاً للتوافق مع 101 موقع استخدام في lib/. سيُزال تدريجياً.
class AppColors {
  AppColors._();

  // Primary colors — الآن Marina Navy بدلاً من البنفسجي
  @Deprecated('استخدم MarinaBrandColors.navy أو Theme.of(context).colorScheme.primary')
  static const Color primaryColor = MarinaBrandColors.navy;
  @Deprecated('استخدم MarinaBrandColors.navyLight')
  static const Color primaryDark = MarinaBrandColors.navyLight;
  @Deprecated('استخدم MarinaBrandColors.brass أو Theme.of(context).colorScheme.secondary')
  static const Color primaryLight = MarinaBrandColors.brass;

  // Background colors
  @Deprecated('استخدم Theme.of(context).colorScheme.surface')
  static const Color backgroundColor = MarinaBrandColors.creamSurface;
  @Deprecated('استخدم Theme.of(context).colorScheme.surface')
  static const Color surfaceColor = Colors.white;

  // Text colors
  @Deprecated('استخدم Theme.of(context).colorScheme.onSurface')
  static const Color textPrimary = MarinaBrandColors.charcoal;
  @Deprecated('استخدم Theme.of(context).colorScheme.onSurfaceVariant')
  static const Color textSecondary = Color(0xFF6c757d);

  // Status colors — الآن بألوان Marina الموحّدة
  @Deprecated('استخدم MarinaBrandColors.success أو Theme.of(context).colorScheme.tertiary')
  static const Color successColor = MarinaBrandColors.success;
  @Deprecated('استخدم MarinaBrandColors.error أو Theme.of(context).colorScheme.error')
  static const Color dangerColor = MarinaBrandColors.error;
  @Deprecated('استخدم MarinaBrandColors.warning')
  static const Color warningColor = MarinaBrandColors.warning;
  @Deprecated('استخدم MarinaBrandColors.seaGlass')
  static const Color infoColor = MarinaBrandColors.seaGlass;

  // Gray colors
  @Deprecated('استخدم MarinaBrandColors.outline')
  static const Color lightGray = MarinaBrandColors.outline;
  @Deprecated('استخدم MarinaBrandColors.outline')
  static const Color mediumGray = Color(0xFF6c757d);
  @Deprecated('استخدم MarinaBrandColors.charcoal')
  static const Color darkGray = MarinaBrandColors.charcoal;

  // Card and component colors
  @Deprecated('استخدم Theme.of(context).cardTheme.color')
  static const Color cardBackground = Colors.white;
  @Deprecated('استخدم Theme.of(context).dividerColor')
  static const Color dividerColor = MarinaBrandColors.outline;

  // Admin sidebar colors — الآن navy بدلاً من الأزرق العشوائي
  @Deprecated('استخدم MarinaBrandColors.navyDark')
  static const Color sidebarColor = MarinaBrandColors.navyDark;
  @Deprecated('استخدم MarinaBrandColors.navy')
  static const Color sidebarAccent = MarinaBrandColors.navy;
}

// ═══════════════════════════════════════════════════════════════════════════
// THEME BUILDERS — Marina Navy (Material 3)
// ═══════════════════════════════════════════════════════════════════════════

/// يبني ThemeData للوضع الفاتح (Marina Navy + Material 3).
ThemeData buildMarinaLightTheme() {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: MarinaBrandColors.navy,
    // brightness افتراضي = light — لا حاجة لتمريره صراحة
    primary: MarinaBrandColors.navy,
    onPrimary: Colors.white,
    secondary: MarinaBrandColors.brass,
    onSecondary: Colors.white,
    tertiary: MarinaBrandColors.seaGlass,
    onTertiary: Colors.white,
    error: MarinaBrandColors.error,
    onError: Colors.white,
    surface: MarinaBrandColors.creamSurface,
    onSurface: MarinaBrandColors.charcoal,
    surfaceContainerHighest: MarinaBrandColors.creamContainer,
  );

  return _buildMarinaTheme(colorScheme, Brightness.light);
}

/// يبني ThemeData للوضع الداكن (Marina Navy + Material 3).
ThemeData buildMarinaDarkTheme() {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: MarinaBrandColors.navy,
    brightness: Brightness.dark,
    primary: MarinaBrandColors.navyLight, // tone 80 للوضوح على خلفية داكنة
    onPrimary: Colors.white,
    secondary: MarinaBrandColors.brassLight,
    onSecondary: MarinaBrandColors.navyDark,
    tertiary: MarinaBrandColors.seaGlassLight,
    onTertiary: MarinaBrandColors.navyDark,
    error: MarinaBrandColors.errorDark,
    onError: MarinaBrandColors.navyDark,
    surface: MarinaBrandColors.navyBlack,
    onSurface: MarinaBrandColors.warmWhite,
    surfaceContainerHighest: MarinaBrandColors.navyBlackContainer,
  );

  return _buildMarinaTheme(colorScheme, Brightness.dark);
}

ThemeData _buildMarinaTheme(ColorScheme colorScheme, Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final brandSuccess =
      isLight ? MarinaBrandColors.success : MarinaBrandColors.successDark;
  final brandWarning =
      isLight ? MarinaBrandColors.warning : MarinaBrandColors.warningDark;
  final brandError =
      isLight ? MarinaBrandColors.error : MarinaBrandColors.errorDark;
  final outlineColor =
      isLight ? MarinaBrandColors.outline : MarinaBrandColors.outlineDark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    fontFamily: 'Tajawal',
    scaffoldBackgroundColor: colorScheme.surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,

    // ─── AppBar: لون الـ surface (ليس primary) لمظهر M3 الحديث ────────
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: colorScheme.primary,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
        fontFamily: 'Tajawal',
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
    ),

    // ─── Card: حواف دائرية 12، ارتفاع خفيف، حدود ناعمة ────────────────
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      surfaceTintColor: colorScheme.primary,
      elevation: 1,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: outlineColor.withValues(alpha: 0.4)),
      ),
    ),

    // ─── Buttons: M3 style مع حواف 8 ───────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Tajawal',
        ),
      ),
    ),

    // ─── Inputs: حدود ناعمة، تركيز بـ primary ──────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: outlineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: outlineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: brandError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: brandError, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    ),

    // ─── DataTable: رأس بـ primary، صفوف بـ surface ────────────────────
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(colorScheme.primary),
      headingTextStyle: TextStyle(
        color: colorScheme.onPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
      dataTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
      columnSpacing: 24,
      horizontalMargin: 16,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 56,
      dividerThickness: 0.5,
    ),

    // ─── ListTile ──────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
      iconColor: colorScheme.primary,
      textColor: colorScheme.onSurface,
    ),

    // ─── Dividers, switches, sliders ───────────────────────────────────
    dividerColor: outlineColor.withValues(alpha: 0.6),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.onPrimary;
        }
        return colorScheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return colorScheme.surfaceContainerHighest;
      }),
    ),

    // ─── Chip theme (للشارات) ──────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.primary,
      labelStyle: TextStyle(
        color: colorScheme.onSurface,
        fontFamily: 'Tajawal',
        fontSize: 12,
      ),
      side: BorderSide(color: outlineColor.withValues(alpha: 0.5)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),

    // ─── Navigation (BottomNavBar, NavigationRail, Drawer) ─────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontFamily: 'Tajawal',
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          size: 22,
        );
      }),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: colorScheme.surface,
      scrimColor: Colors.black.withValues(alpha: 0.5),
    ),

    // ─── SnackBar ──────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: colorScheme.onInverseSurface,
        fontFamily: 'Tajawal',
        fontSize: 14,
      ),
      actionTextColor: colorScheme.inversePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),

    // ─── Dialog ────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.primary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Tajawal',
      ),
      contentTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
    ),

    // ─── Floating Action Button ────────────────────────────────────────
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),

    // ─── Progress indicators ───────────────────────────────────────────
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      circularTrackColor: colorScheme.surfaceContainerHighest,
      linearTrackColor: colorScheme.surfaceContainerHighest,
    ),

    // ─── TabBar ────────────────────────────────────────────────────────
    tabBarTheme: TabBarThemeData(
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      indicatorColor: colorScheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        fontFamily: 'Tajawal',
      ),
    ),

    // ─── Tooltip ───────────────────────────────────────────────────────
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(
        color: colorScheme.onInverseSurface,
        fontSize: 12,
        fontFamily: 'Tajawal',
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),

    // ─── Text theme (يحترم Tajawal) ────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
      displayMedium: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
      displaySmall: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
      headlineLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
    ),

    // ─── Extensions: ألوان brand الثابتة + ألوان الحالة ───────────────
    extensions: [
      MarinaSemanticColors(
        success: brandSuccess,
        warning: brandWarning,
        error: brandError,
        info: MarinaBrandColors.seaGlass,
        onSuccess: Colors.white,
        onWarning: Colors.white,
        onError: Colors.white,
        onInfo: Colors.white,
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SEMANTIC COLORS THEME EXTENSION
// ═══════════════════════════════════════════════════════════════════════════
//
// Material 3 ColorScheme لا يوفّر ألوان success/warning/info. هذه الألوان
// مهمة للوحات تحكم الفنادق (حجوزات ناجحة، تحذيرات، أخطاء). لذلك نُعرّفها
// كـ ThemeExtension يمكن الوصول إليها عبر:
//   Theme.of(context).extension<MarinaSemanticColors>()!.success
//
// هذا النمط هو الموصى به في توثيق M3 الرسمي للألوان المخصّصة:
// https://m3.material.io/styles/color/advanced/define-new-colors

/// ألوان دلالية (semantic) خارج نطاق ColorScheme الأساسي.
///
/// تشمل: success (نجاح)، warning (تحذير)، error (خطأ — مكرّر من
/// ColorScheme.error للتوافق)، info (معلومة). هذه الألوان مهمة لشاشات
/// الفندق حيث تتكرّر حالات "حجز ناجح / غرفة محجوزة / دفعة متأخرة".
@immutable
class MarinaSemanticColors extends ThemeExtension<MarinaSemanticColors> {
  const MarinaSemanticColors({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.onSuccess,
    required this.onWarning,
    required this.onError,
    required this.onInfo,
  });

  /// لون النجاح (حجز مؤكد، دفعة مستلمة) — أخضر بحري.
  final Color success;

  /// لون التحذير (دفعة متأخرة، غرفة تحتاج صيانة) — ذهبي.
  final Color warning;

  /// لون الخطأ (إلغاء، فشل مزامنة) — أحمر داكن.
  final Color error;

  /// لون المعلومة (إشعارات غير عاجلة) — teal بحري.
  final Color info;

  /// لون النص/الأيقونة فوق [success].
  final Color onSuccess;

  /// لون النص/الأيقونة فوق [warning].
  final Color onWarning;

  /// لون النص/الأيقونة فوق [error].
  final Color onError;

  /// لون النص/الأيقونة فوق [info].
  final Color onInfo;

  @override
  MarinaSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? onSuccess,
    Color? onWarning,
    Color? onError,
    Color? onInfo,
  }) {
    return MarinaSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      onSuccess: onSuccess ?? this.onSuccess,
      onWarning: onWarning ?? this.onWarning,
      onError: onError ?? this.onError,
      onInfo: onInfo ?? this.onInfo,
    );
  }

  @override
  MarinaSemanticColors lerp(
    ThemeExtension<MarinaSemanticColors>? other,
    double t,
  ) {
    if (other is! MarinaSemanticColors) {
      return this;
    }
    return MarinaSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC API — توافق مع الكود القديم
// ═══════════════════════════════════════════════════════════════════════════

/// @deprecated استخدم buildMarinaLightTheme() بدلاً منه.
/// محفوظ للتوافق مع main.dart. يُرجع ThemeData الفاتح الجديد (Marina Navy).
ThemeData buildTheme() => buildMarinaLightTheme();

/// @deprecated استخدم buildMarinaDarkTheme() بدلاً منه.
/// محفوظ للتوافق مع main.dart. يُرجع ThemeData الداكن الجديد (Marina Navy).
ThemeData buildDarkTheme() => buildMarinaDarkTheme();

// ═══════════════════════════════════════════════════════════════════════════
// HELPER — إنشاء MaterialColor من Color (محفوظ للتوافق)
// ═══════════════════════════════════════════════════════════════════════════

/// @deprecated غير ضروري مع Material 3 و ColorScheme.fromSeed.
/// محفوظ فقط في حال كان هناك كود خارجي يستدعيه.
MaterialColor createMaterialColor(Color color) {
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
