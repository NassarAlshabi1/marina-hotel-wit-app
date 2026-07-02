// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/theme.dart';

/// اختبارات smoke عملية للثيم الجديد (Marina Navy + Material 3).
///
/// تتحقّق من:
/// - buildMarinaLightTheme/buildMarinaDarkTheme يُرجعان ThemeData صالحين.
/// - الألوان الأساسية (navy/brass/seaGlass) موجودة في ColorScheme.
/// - Material 3 مُفعّل.
/// - ThemeExtension<MarinaSemanticColors> مُسجّل في الثيم.
/// - AppColors (deprecated wrapper) يُرجع الألوان الجديدة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Marina Theme — Smoke Test', () {
    test('buildMarinaLightTheme يُرجع ThemeData صالح', () {
      final theme = buildMarinaLightTheme();
      expect(theme, isA<ThemeData>());
      expect(theme.useMaterial3, isTrue,
          reason: 'يجب أن يكون Material 3 مُفعّل');
      expect(theme.brightness, Brightness.light);
    });

    test('buildMarinaDarkTheme يُرجع ThemeData صالح', () {
      final theme = buildMarinaDarkTheme();
      expect(theme, isA<ThemeData>());
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
    });

    test('buildTheme (deprecated) = buildMarinaLightTheme', () {
      // ✅ التوافق: buildTheme ما زال يعمل ويُرجع نفس الثيم الجديد
      final theme1 = buildTheme();
      final theme2 = buildMarinaLightTheme();
      expect(theme1.brightness, theme2.brightness);
      expect(theme1.useMaterial3, theme2.useMaterial3);
      expect(theme1.colorScheme.primary, theme2.colorScheme.primary);
    });

    test('buildDarkTheme (deprecated) = buildMarinaDarkTheme', () {
      final theme1 = buildDarkTheme();
      final theme2 = buildMarinaDarkTheme();
      expect(theme1.brightness, theme2.brightness);
      expect(theme1.colorScheme.primary, theme2.colorScheme.primary);
    });

    test('Marina Navy #003049 = primary في الوضع الفاتح', () {
      final theme = buildMarinaLightTheme();
      expect(theme.colorScheme.primary, const Color(0xFF003049),
          reason: 'Primary يجب أن يكون Deep Marina Navy #003049');
    });

    test('Brass Gold #B08D57 = secondary في الوضع الفاتح', () {
      final theme = buildMarinaLightTheme();
      expect(theme.colorScheme.secondary, const Color(0xFFB08D57),
          reason: 'Secondary يجب أن يكون Brass Gold #B08D57');
    });

    test('Sea-Glass Teal #3D8B8B = tertiary في الوضع الفاتح', () {
      final theme = buildMarinaLightTheme();
      expect(theme.colorScheme.tertiary, const Color(0xFF3D8B8B),
          reason: 'Tertiary يجب أن يكون Sea-Glass Teal #3D8B8B');
    });

    test('ThemeExtension<MarinaSemanticColors> مُسجّل في الثيم', () {
      final lightTheme = buildMarinaLightTheme();
      final darkTheme = buildMarinaDarkTheme();

      final lightExt = lightTheme.extension<MarinaSemanticColors>();
      final darkExt = darkTheme.extension<MarinaSemanticColors>();

      expect(lightExt, isNotNull,
          reason: 'MarinaSemanticColors يجب أن تكون مُسجّلة في الثيم الفاتح');
      expect(darkExt, isNotNull,
          reason: 'MarinaSemanticColors يجب أن تكون مُسجّلة في الثيم الداكن');

      // ألوان semantic موجودة
      expect(lightExt!.success, isA<Color>());
      expect(lightExt.warning, isA<Color>());
      expect(lightExt.error, isA<Color>());
      expect(lightExt.info, isA<Color>());

      // الفرق بين الفاتح والداكن في ألوان semantic
      expect(lightExt.success, isNot(equals(darkExt!.success)),
          reason: 'success في الفاتح ≠ الداكن (درجات مختلفة)');
    });

    test('AppColors (deprecated) يُرجع Marina Navy', () {
      // ignore: deprecated_member_use_from_same_package
      expect(AppColors.primaryColor, const Color(0xFF003049),
          reason: 'AppColors.primaryColor يجب أن يُرجع Marina Navy '
              '(وليس البنفسجي القديم #6A1B9A)');
      // ignore: deprecated_member_use_from_same_package
      expect(AppColors.sidebarColor, const Color(0xFF001F33),
          reason: 'AppColors.sidebarColor يجب أن يُرجع navyDark');
    });

    test('MarinaBrandColors يحتوي على كل ألوان الهوية', () {
      expect(MarinaBrandColors.navy, const Color(0xFF003049));
      expect(MarinaBrandColors.brass, const Color(0xFFB08D57));
      expect(MarinaBrandColors.seaGlass, const Color(0xFF3D8B8B));
      expect(MarinaBrandColors.creamSurface, const Color(0xFFFAF7F2));
      expect(MarinaBrandColors.navyBlack, const Color(0xFF10171F));
      expect(MarinaBrandColors.charcoal, const Color(0xFF1A1A1A));
    });

    test('textTheme يستخدم Tajawal', () {
      final theme = buildMarinaLightTheme();
      // كل أوزان text theme يجب أن تستخدم Tajawal
      expect(theme.textTheme.bodyLarge?.fontFamily, 'Tajawal');
      expect(theme.textTheme.titleLarge?.fontFamily, 'Tajawal');
      expect(theme.textTheme.labelSmall?.fontFamily, 'Tajawal');
    });

    test('cardTheme: حواف دائرية 12 + حدود ناعمة', () {
      final theme = buildMarinaLightTheme();
      final cardShape = theme.cardTheme.shape;
      expect(cardShape, isA<RoundedRectangleBorder>());
      final radius = (cardShape as RoundedRectangleBorder).borderRadius;
      expect(radius.resolve(TextDirection.ltr).topLeft, const Radius.circular(12));
    });

    test('inputDecorationTheme: filled = true + حواف 8', () {
      final theme = buildMarinaLightTheme();
      expect(theme.inputDecorationTheme.filled, isTrue,
          reason: 'Inputs يجب أن تكون filled (M3 style)');
      final border = theme.inputDecorationTheme.enabledBorder;
      expect(border, isA<OutlineInputBorder>(),
          reason: 'enabledBorder يجب أن يكون OutlineInputBorder');
      final radius = (border as OutlineInputBorder).borderRadius;
      expect(radius.resolve(TextDirection.ltr).topLeft,
          const Radius.circular(8));
    });
  });
}
