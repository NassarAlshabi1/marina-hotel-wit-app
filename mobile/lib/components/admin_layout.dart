import 'package:flutter/material.dart';
import '../core/responsive/responsive.dart';
import '../utils/theme.dart';
import 'admin_sidebar.dart';

class AdminLayout extends StatelessWidget {

  const AdminLayout({
    super.key,
    required this.body,
    required this.currentRoute,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.appBar,
    this.onRouteSelected,
  });
  final Widget body;
  final String currentRoute;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? appBar;
  final void Function(String)? onRouteSelected;

  @override
  Widget build(BuildContext context) {
    // ─── سطح المكتب (ويندوز): شريط جانبي ثابت + محتوى واسع ───
    if (context.isDesktopOrAbove) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Row(
            children: [
              // شريط جانبي بعرض متجاوب
              AdminSidebar(
                currentRoute: currentRoute,
                onRouteSelected: onRouteSelected ?? (route) {},
              ),
              Expanded(
                child: Column(
                  children: [
                    if (title != null || actions != null) _buildTopBar(context),
                    Expanded(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: body,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: floatingActionButton,
        ),
      );
    }

    // ─── تابلت: شريط جانبي مضغوط أو قابل للطي + محتوى ───
    if (context.isTablet) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Row(
            children: [
              AdminSidebar(
                currentRoute: currentRoute,
                onRouteSelected: onRouteSelected ?? (route) {},
              ),
              Expanded(
                child: Column(
                  children: [
                    if (title != null || actions != null) _buildTopBar(context),
                    Expanded(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: body,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: floatingActionButton,
        ),
      );
    }

    // ─── هاتف: Drawer + شريط تطبيق ───
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: appBar ?? _buildMobileAppBar(context),
        drawer: AdminSidebar(
          currentRoute: currentRoute,
          onRouteSelected: onRouteSelected ?? (route) {},
        ),
        body: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: body),
        floatingActionButton: floatingActionButton,
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final height = context.appBarHeight;
    final horizontalPadding = context.isDesktopOrAbove ? 32.0 : 24.0;
    final fontSize = context.isDesktopOrAbove ? 22.0 : 20.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3D2048) : const Color(0xFFE0D0EA),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            Expanded(
              child: title != null
                  ? Text(
                      title!,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFE0D5F0) : AppColors.textPrimary,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(BuildContext context) {
    return AppBar(
      title: title != null ? Text(title!) : const Text('فندق مارينا'),
      backgroundColor: AppColors.primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [if (actions != null) ...actions!],
    );
  }
}

// Bootstrap-like components for matching PHP design
class AdminCard extends StatelessWidget {

  const AdminCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.elevation,
    this.title,
    this.trailing,
  });
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final double? elevation;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardPadding = padding ?? EdgeInsets.all(context.isMobile ? 12 : 16);
    final cardMargin = EdgeInsets.symmetric(
      horizontal: context.isMobile ? 6 : 10,
      vertical: 4,
    );
    final headerPadding = EdgeInsets.all(context.isMobile ? 12 : 16);
    final titleFontSize = context.isDesktopOrAbove ? 18.0 : 16.0;

    return Card(
      elevation: elevation ?? 1,
      color: color ?? (isDark ? const Color(0xFF1E1E1E) : Colors.white),
      margin: cardMargin,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Container(
              padding: headerPadding,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C1E38) : AppColors.lightGray,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
          Padding(padding: cardPadding, child: child),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final valueFontSize = context.responsive<double>(
      mobile: 22,
      tablet: 26,
      desktop: 28,
    );
    final iconSize = context.responsive<double>(
      mobile: 24,
      tablet: 28,
      desktop: 32,
    );
    final iconPadding = context.responsive<double>(
      mobile: 10,
      tablet: 14,
      desktop: 16,
    );
    final cardPadding = context.responsive<double>(
      mobile: 14,
      tablet: 18,
      desktop: 20,
    );

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        horizontal: context.isMobile ? 6 : 8,
        vertical: 4,
      ),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [color, color.withValues(alpha: 0.8)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: context.isMobile ? 12 : 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: context.isMobile ? 10 : 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(iconPadding),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: iconSize, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminTable extends StatefulWidget {

  const AdminTable({
    super.key,
    required this.headers,
    required this.rows,
    this.striped = true,
    this.bordered = true,
    this.rowsPerPage = 50,
  });
  final List<String> headers;
  final List<List<Widget>> rows;
  final bool striped;
  final bool bordered;
  final int rowsPerPage;

  @override
  State<AdminTable> createState() => _AdminTableState();
}

class _AdminTableState extends State<AdminTable> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final totalRows = widget.rows.length;
    final totalPages = (totalRows / widget.rowsPerPage).ceil();
    final startIndex = _currentPage * widget.rowsPerPage;
    final endIndex = (startIndex + widget.rowsPerPage).clamp(0, totalRows);
    final visibleRows = widget.rows.sublist(startIndex, endIndex);
    final dataRowHeight = context.isMobile ? 48.0 : 56.0;
    final headingRowHeight = context.isMobile ? 52.0 : 64.0;

    return Column(
      children: [
        if (totalRows > widget.rowsPerPage)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'عرض ${startIndex + 1}-$endIndex من $totalRows',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage--)
                          : null,
                      tooltip: 'السابق',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    Text(
                      '${_currentPage + 1}/$totalPages',
                      style: const TextStyle(fontSize: 12),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage++)
                          : null,
                      tooltip: 'التالي',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width -
                  (context.isTabletOrAbove ? context.sidebarWidth + 48 : 24),
            ),
            child: DataTable(
              dataRowMinHeight: dataRowHeight,
              dataRowMaxHeight: dataRowHeight + 16,
              headingRowHeight: headingRowHeight,
              headingRowColor: WidgetStateProperty.all(
                Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2C1E38)
                    : AppColors.darkGray,
              ),
              headingTextStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFE0D5F0)
                    : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: context.isMobile ? 12 : 14,
              ),
              decoration: widget.bordered
                  ? BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF3D2048)
                            : AppColors.lightGray,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              columns: widget.headers
                  .map((header) => DataColumn(label: Text(header)))
                  .toList(),
              rows: visibleRows
                  .asMap()
                  .entries
                  .map(
                    (entry) => DataRow(
                      color: widget.striped && (startIndex + entry.key).isOdd
                          ? WidgetStateProperty.all(
                              AppColors.lightGray.withValues(alpha: 0.3),
                            )
                          : null,
                      cells: entry.value.map(DataCell.new).toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {

  const StatusBadge({super.key, required this.text, required this.color});

  factory StatusBadge.success(String text) {
    return StatusBadge(text: text, color: Colors.green);
  }

  factory StatusBadge.danger(String text) {
    return StatusBadge(text: text, color: Colors.red);
  }

  factory StatusBadge.warning(String text) {
    return StatusBadge(text: text, color: Colors.orange);
  }

  factory StatusBadge.info(String text) {
    return StatusBadge(text: text, color: Colors.blue);
  }
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fontSize = context.isMobile ? 11.0 : 12.0;
    final hPadding = context.isMobile ? 8.0 : 12.0;
    final vPadding = context.isMobile ? 4.0 : 6.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
