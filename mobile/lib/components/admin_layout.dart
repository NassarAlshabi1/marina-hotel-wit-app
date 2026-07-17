import 'package:flutter/material.dart';
import '../utils/performance_monitor.dart';
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
    final isTablet = MediaQuery.of(context).size.width >= 768;

    if (isTablet) {
      // Desktop/Tablet layout with sidebar (like PHP admin)
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Row(
            children: [
              AdminSidebar(currentRoute: currentRoute, onRouteSelected: onRouteSelected ?? (route) {}),
              Expanded(
                child: Column(
                  children: [
                    if (title != null || actions != null) _buildTopBar(context),
                    Expanded(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: PerformanceInspector(
                          name: title ?? currentRoute,
                          child: body,
                        ),
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
    } else {
      // Mobile layout with drawer
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: appBar ?? _buildMobileAppBar(context),
          drawer: AdminSidebar(currentRoute: currentRoute, onRouteSelected: onRouteSelected ?? (route) {}),
          body: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: PerformanceInspector(
              name: title ?? currentRoute,
              child: body,
            ),
          ),
          floatingActionButton: floatingActionButton,
        ),
      );
    }
  }

  Widget _buildTopBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF3D2048) : const Color(0xFFE0D0EA))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: title != null
                  ? Text(
                      title!,
                      style: TextStyle(
                        fontSize: 20,
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
      // ✅ إصلاح: titleTextStyle من الثيم يضع color=textPrimary (أسود)
      // لكن الخلفية primaryColor (أزرق غامق) → نص أبيض إجباري
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Tajawal',
      ),
      iconTheme: const IconThemeData(color: Colors.white),
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
    return Card(
      elevation: elevation ?? 1,
      color: color ?? (isDark ? const Color(0xFF1E1E1E) : Colors.white),
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C1E38) : AppColors.lightGray,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
          Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
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
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(20),
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
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(title, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 32, color: Colors.white),
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
                      onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                      tooltip: 'السابق',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    Text('${_currentPage + 1}/$totalPages', style: const TextStyle(fontSize: 12)),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                      tooltip: 'التالي',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ],
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2C1E38) : AppColors.darkGray,
            ),
            headingTextStyle: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE0D5F0) : Colors.white,
              fontWeight: FontWeight.w600,
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
            columns: widget.headers.map((header) => DataColumn(label: Text(header))).toList(),
            rows: visibleRows
                .asMap()
                .entries
                .map(
                  (entry) => DataRow(
                    color: widget.striped && (startIndex + entry.key).isOdd
                        ? WidgetStateProperty.all(AppColors.lightGray.withValues(alpha: 0.3))
                        : null,
                    cells: entry.value.map(DataCell.new).toList(),
                  ),
                )
                .toList(),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}
