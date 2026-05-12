/// نظام الاستجابة الشامل لدعم جميع أحجام الشاشات
/// يدعم: الهاتف، التابلت، سطح المكتب (ويندوز)
library;

import 'package:flutter/material.dart';

/// ─── نقاط التوقف (Breakpoints) ───
/// متوافقة مع Material Design 3 و Bootstrap
class Breakpoints {
  static const double mobile = 0;
  static const double mobileLarge = 480;
  static const double tablet = 768;
  static const double tabletLarge = 1024;
  static const double desktop = 1200;
  static const double desktopLarge = 1440;
}

/// ─── نوع الجهاز ───
enum DeviceType {
  mobile,
  mobileLarge,
  tablet,
  tabletLarge,
  desktop,
  desktopLarge,
}

/// ─── ممدد BuildContext لسهولة الاستخدام ───
extension ResponsiveContext on BuildContext {
  /// عرض الشاشة الحالي
  double get screenWidth => MediaQuery.of(this).size.width;

  /// ارتفاع الشاشة الحالي
  double get screenHeight => MediaQuery.of(this).size.height;

  /// نوع الجهاز الحالي
  DeviceType get deviceType {
    final w = screenWidth;
    if (w >= Breakpoints.desktopLarge) return DeviceType.desktopLarge;
    if (w >= Breakpoints.desktop) return DeviceType.desktop;
    if (w >= Breakpoints.tabletLarge) return DeviceType.tabletLarge;
    if (w >= Breakpoints.tablet) return DeviceType.tablet;
    if (w >= Breakpoints.mobileLarge) return DeviceType.mobileLarge;
    return DeviceType.mobile;
  }

  /// هل الشاشة تابلت أو أكبر؟
  bool get isTabletOrAbove => screenWidth >= Breakpoints.tablet;

  /// هل الشاشة سطح مكتب أو أكبر؟
  bool get isDesktopOrAbove => screenWidth >= Breakpoints.desktop;

  /// هل الشاشة هاتف؟
  bool get isMobile => screenWidth < Breakpoints.tablet;

  /// هل الشاشة هاتف كبير؟
  bool get isMobileLarge =>
      screenWidth >= Breakpoints.mobileLarge && screenWidth < Breakpoints.tablet;

  /// هل الشاشة تابلت؟
  bool get isTablet =>
      screenWidth >= Breakpoints.tablet && screenWidth < Breakpoints.desktop;

  /// هل الشاشة سطح مكتب؟
  bool get isDesktop => screenWidth >= Breakpoints.desktop;

  /// عدد الأعمدة المناسب للشبكة
  int get gridColumns {
    if (screenWidth >= Breakpoints.desktopLarge) return 4;
    if (screenWidth >= Breakpoints.desktop) return 3;
    if (screenWidth >= Breakpoints.tabletLarge) return 3;
    if (screenWidth >= Breakpoints.tablet) return 2;
    return 1;
  }

  /// المسافة الداخلية حسب حجم الشاشة
  EdgeInsets get screenPadding {
    if (screenWidth >= Breakpoints.desktop) {
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    }
    if (screenWidth >= Breakpoints.tablet) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  /// ارتفاع شريط التطبيق حسب الجهاز
  double get appBarHeight {
    if (screenWidth >= Breakpoints.desktop) return 64;
    if (screenWidth >= Breakpoints.tablet) return 56;
    return 48;
  }

  /// عرض الشريط الجانبي حسب الجهاز
  double get sidebarWidth {
    if (screenWidth >= Breakpoints.desktopLarge) return 280;
    if (screenWidth >= Breakpoints.desktop) return 260;
    if (screenWidth >= Breakpoints.tabletLarge) return 240;
    return 220;
  }

  /// اختيار قيمة حسب حجم الشاشة
  T responsive<T>({
    required T mobile,
    T? mobileLarge,
    T? tablet,
    T? tabletLarge,
    T? desktop,
    T? desktopLarge,
  }) {
    if (screenWidth >= Breakpoints.desktopLarge && desktopLarge != null) {
      return desktopLarge;
    }
    if (screenWidth >= Breakpoints.desktop && desktop != null) {
      return desktop;
    }
    if (screenWidth >= Breakpoints.tabletLarge && tabletLarge != null) {
      return tabletLarge;
    }
    if (screenWidth >= Breakpoints.tablet && tablet != null) {
      return tablet;
    }
    if (screenWidth >= Breakpoints.mobileLarge && mobileLarge != null) {
      return mobileLarge;
    }
    return mobile;
  }
}

/// ─── ويدجت بنّاء استجابي ───
/// يبني ويدجت مختلف حسب حجم الشاشة
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.mobileLarge,
    this.tablet,
    this.tabletLarge,
    this.desktop,
    this.desktopLarge,
  });

  final Widget mobile;
  final Widget? mobileLarge;
  final Widget? tablet;
  final Widget? tabletLarge;
  final Widget? desktop;
  final Widget? desktopLarge;

  @override
  Widget build(BuildContext context) {
    return context.responsive<Widget>(
      mobile: mobile,
      mobileLarge: mobileLarge,
      tablet: tablet,
      tabletLarge: tabletLarge,
      desktop: desktop,
      desktopLarge: desktopLarge,
    );
  }
}

/// ─── شبكة استجابية ───
/// تعرض العناصر في أعمدة حسب حجم الشاشة
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.desktopLargeColumns = 4,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final int desktopLargeColumns;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    final columns = context.responsive<int>(
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
      desktopLarge: desktopLargeColumns,
    );

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children.map((child) {
        final width =
            (MediaQuery.of(context).size.width - (columns - 1) * spacing) /
                columns;
        return SizedBox(
          width: width,
          child: child,
        );
      }).toList(),
    );
  }
}

/// ─── حاوية محتوى استجابية ───
/// تحدد عرضاً أقصى للمحتوى وتوسّطه على الشاشات الكبيرة
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = 1400,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final screenPadding = padding ?? context.screenPadding;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: screenPadding,
          child: child,
        ),
      ),
    );
  }
}

/// ─── تخطيط مزدوج اللوح (Master-Detail) ───
/// للتتابلت وسطح المكتب: قائمة على اليسار + تفاصيل على اليمين
class MasterDetailLayout extends StatelessWidget {
  const MasterDetailLayout({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 380,
    this.divider = true,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    // على الهاتف: عرض عادي (القائمة فقط)
    if (context.isMobile) {
      return master;
    }

    // على التابلت وسطح المكتب: عرض مزدوج
    final actualMasterWidth =
        context.screenWidth > masterWidth * 2 ? masterWidth : context.screenWidth * 0.38;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: actualMasterWidth,
          child: master,
        ),
        if (divider)
          const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: detail,
        ),
      ],
    );
  }
}

/// ─── حاوية بطاقة استجابية ───
/// تتكيف حجمها مع الشاشة
class ResponsiveCard extends StatelessWidget {
  const ResponsiveCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.elevation,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation ?? 1,
      margin: margin ??
          EdgeInsets.symmetric(
            horizontal: context.isMobile ? 8 : 12,
            vertical: 4,
          ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius ?? 8),
      ),
      child: Padding(
        padding: padding ??
            EdgeInsets.all(context.isMobile ? 12 : 16),
        child: child,
      ),
    );
  }
}
