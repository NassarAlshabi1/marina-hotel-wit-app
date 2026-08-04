import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// ويدجت تحميل متوهج لاستخدامه في التقارير والقوائم
///
/// يوفر تأثير shimmer احترافي كبديل لـ CircularProgressIndicator.
/// يمكن استخدامه مباشرة أو تخصيصه عبر [customShimmer].
///
/// مثال:
/// ```dart
/// ShimmerLoading(itemCount: 8, itemHeight: 56)
/// ```
class ShimmerLoading extends StatelessWidget {
  const ShimmerLoading({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 56.0,
    this.customShimmer,
    this.baseColor,
    this.highlightColor,
    this.borderRadius = 8.0,
    this.spacing = 8.0,
    this.padding,
  });

  /// عدد العناصر الوهمية التي سيتم عرضها
  final int itemCount;

  /// ارتفاع كل عنصر وهمي
  final double itemHeight;

  /// ويدجت shimmer مخصص (يتجاوز العرض الافتراضي)
  final Widget? customShimmer;

  /// لون الخلفية الأساسي للتوهج
  final Color? baseColor;

  /// لون التوهج المميز
  final Color? highlightColor;

  /// نصف قطر الحواف المستديرة
  final double borderRadius;

  /// المسافة بين العناصر
  final double spacing;

  /// حشوة خارجية
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // ألوان Shimmer تتكيف مع وضع السمة (فاتح/داكن)
    final effectiveBaseColor =
        baseColor ??
        (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0));
    final effectiveHighlightColor =
        highlightColor ??
        (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5));

    if (customShimmer != null) {
      return customShimmer!;
    }

    return Shimmer.fromColors(
      baseColor: effectiveBaseColor,
      highlightColor: effectiveHighlightColor,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: List.generate(itemCount, (index) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < itemCount - 1 ? spacing : 0,
              ),
              child: _buildDefaultShimmerItem(context),
            );
          }),
        ),
      ),
    );
  }

  /// بناء عنصر وهمي افتراضي (بطاقة مع نص وهمي)
  Widget _buildDefaultShimmerItem(BuildContext context) {
    return Container(
      height: itemHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // دائرة وهمية على اليسار
          _buildShimmerCircle(diameter: itemHeight * 0.55),
          const SizedBox(width: 12),
          // نصوص وهمية
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildShimmerLine(height: 14, widthFraction: 0.7),
                const SizedBox(height: 8),
                _buildShimmerLine(height: 10, widthFraction: 0.45),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // نص وهمي على اليمين (مثلاً مبلغ)
          _buildShimmerLine(height: 16, widthFraction: 0.2),
        ],
      ),
    );
  }

  /// بناء خط وهمي
  Widget _buildShimmerLine({
    required double height,
    required double widthFraction,
  }) {
    return FractionallySizedBox(
      widthFactor: widthFraction,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  /// بناء دائرة وهمية
  Widget _buildShimmerCircle({required double diameter}) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// ويدجت تحميل متوهج مخصص لصفوف الجدول
///
/// يُستخدم في شاشات التقارير لمحاكاة مظهر صفوف الجدول أثناء التحميل.
/// يتيح تحديد أعرض الأعمدة لتناسب التخطيط الفعلي للجدول.
///
/// مثال:
/// ```dart
/// ShimmerTableRow(
///   columnWidths: [0.15, 0.25, 0.2, 0.2, 0.2],
///   rowHeight: 48,
///   rowCount: 10,
/// )
/// ```
class ShimmerTableRow extends StatelessWidget {
  const ShimmerTableRow({
    super.key,
    this.columnWidths = const [0.2, 0.3, 0.2, 0.15, 0.15],
    this.rowHeight = 48.0,
    this.rowCount = 6,
    this.baseColor,
    this.highlightColor,
    this.borderRadius = 4.0,
    this.headerHeight = 40.0,
    this.showHeader = true,
    this.spacing = 6.0,
    this.padding,
  });

  /// أعرض الأعمدة كأجزاء من العرض الكلي (يجب أن يكون المجموع ≤ 1.0)
  final List<double> columnWidths;

  /// ارتفاع كل صف
  final double rowHeight;

  /// عدد الصفوف الوهمية
  final int rowCount;

  /// لون الخلفية الأساسي للتوهج
  final Color? baseColor;

  /// لون التوهج المميز
  final Color? highlightColor;

  /// نصف قطر الحواف المستديرة لكل خلية
  final double borderRadius;

  /// ارتفاع صف الرأس الوهمي
  final double headerHeight;

  /// هل يتم عرض رأس وهمي؟
  final bool showHeader;

  /// المسافة بين الصفوف
  final double spacing;

  /// حشوة خارجية
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBaseColor =
        baseColor ??
        (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0));
    final effectiveHighlightColor =
        highlightColor ??
        (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5));

    return Shimmer.fromColors(
      baseColor: effectiveBaseColor,
      highlightColor: effectiveHighlightColor,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            // رأس وهمي
            if (showHeader)
              Padding(
                padding: EdgeInsets.only(bottom: spacing),
                child: _buildRow(height: headerHeight, isHeader: true),
              ),
            // صفوف وهمية
            ...List.generate(rowCount, (index) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < rowCount - 1 ? spacing : 0,
                ),
                child: _buildRow(height: rowHeight),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// بناء صف وهمي
  Widget _buildRow({required double height, bool isHeader = false}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: List.generate(columnWidths.length, (index) {
          final width = columnWidths[index];
          final isLast = index == columnWidths.length - 1;

          // خلايا الرأس أطول قليلاً وأكثر سمكاً
          final cellHeight = isHeader ? 12.0 : 14.0;
          // أول عمود (الرقم) والعمود الأخير (المبلغ) أقصر
          final widthFraction = (index == 0 || isLast)
              ? width * 0.6
              : width * 0.85;

          return Expanded(
            flex: (width * 100).round().clamp(1, 100),
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: isLast ? 0 : 8.0),
              child: FractionallySizedBox(
                widthFactor: widthFraction.clamp(0.1, 1.0),
                alignment: isLast
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: Container(
                  height: cellHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// ويدجت تحميل متوهج لبطاقات ملخص التقارير
///
/// يعرض بطاقة واحدة أو أكثر مع حقول وهمية تشبه ملخصات التقارير.
///
/// مثال:
/// ```dart
/// ShimmerSummaryCard(itemCount: 4)
/// ```
class ShimmerSummaryCard extends StatelessWidget {
  const ShimmerSummaryCard({
    super.key,
    this.itemCount = 4,
    this.baseColor,
    this.highlightColor,
    this.padding,
  });

  /// عدد بطاقات الملخص الوهمية
  final int itemCount;

  /// لون الخلفية الأساسي للتوهج
  final Color? baseColor;

  /// لون التوهج المميز
  final Color? highlightColor;

  /// حشوة خارجية
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBaseColor =
        baseColor ??
        (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0));
    final effectiveHighlightColor =
        highlightColor ??
        (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5));

    return Shimmer.fromColors(
      baseColor: effectiveBaseColor,
      highlightColor: effectiveHighlightColor,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(itemCount, (index) {
            // البطاقات في صفين (2 في كل صف)
            final width =
                (MediaQuery.of(context).size.width - 44) /
                (itemCount > 2 ? 2 : itemCount);
            return SizedBox(
              width: width,
              height: 90,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // عنوان وهمي صغير
                    Container(
                      height: 10,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // مبلغ وهمي كبير
                    Container(
                      height: 22,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
