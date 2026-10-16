import 'package:flutter/widgets.dart';

/// نقاط الانقطاع الاستجابية للتطبيق.
///
/// القاعدة: العرض < [tablet] هو مسار الهاتف (لا يُلمس)، والأعرض هو مسار
/// اللوحي/سطح المكتب الذي يبنيه `AdminLayout` أصلاً. كل الاستدعاءات
/// يجب أن تحافظ على ناتج الهاتف نفسه تحت [tablet] حتى لا تنكسر شاشات
/// الموبايل.
class AppBreakpoints {
  AppBreakpoints._();

  /// حد الهاتف/اللوحي — مطابق لشرط `AdminLayout` الحالي (768).
  static const double tablet = 768;

  /// عرض كافٍ ليُعتبر «سطح مكتب» (نافذة ويندوز/شاشة عريضة).
  static const double desktop = 1100;

  /// أقصى عرض لمنطقة المحتوى على الشاشات الواسعة — يبقي النماذج
  /// والقوائم مقروءة بدل التمدد على كامل الشاشة.
  static const double contentMaxWidth = 1400;
}

/// مساعدات قياس العرض على `BuildContext`.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// مسار اللوحي/سطح المكتب (نفس شرط `AdminLayout`).
  bool get isWide => screenWidth >= AppBreakpoints.tablet;

  /// نافذة سطح مكتب/شاشة عريضة.
  bool get isDesktop => screenWidth >= AppBreakpoints.desktop;

  /// عدد أعمدة تكيفي للشبكات: يُرجع [mobile] حرفياً تحت حد اللوحي
  /// (سلوك الهاتف الحالي بلا تغيير)، وفوقه يوسع الأعمدة بما يسمح به
  /// العرض بحيث لا يقل عرض العمود عن [itemMinWidth] ولا يتجاوز العدد
  /// [max].
  int adaptiveColumns({
    required int mobile,
    double itemMinWidth = 220,
    int max = 8,
  }) {
    if (!isWide) {
      return mobile;
    }
    final cols = (screenWidth / itemMinWidth).floor();
    return cols < mobile ? mobile : (cols > max ? max : cols);
  }
}

/// حاوية المحتوى على الشاشات الواسعة: يمركز المحتوى ويحدّ عرضه بـ
/// [AppBreakpoints.contentMaxWidth] مع هامش جانبي. تحت حد اللوحي يعيد
/// [child] كما هو — لا أثر على الهاتف.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({required this.child, super.key, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.isWide) {
      return child;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? AppBreakpoints.contentMaxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}
