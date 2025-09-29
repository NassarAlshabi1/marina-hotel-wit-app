import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'admin_sidebar.dart';

class AdminLayout extends StatelessWidget {
  final Widget body;
  final String currentRoute;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? appBar;
  final Function(String)? onRouteSelected;
  
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
              AdminSidebar(
            currentRoute: currentRoute,
            onRouteSelected: onRouteSelected ?? (route) {},
          ),
              Expanded(
                child: Column(
                  children: [
                    if (title != null || actions != null)
                      _buildTopBar(),
                    Expanded(
                      child: Container(
                        color: AppColors.backgroundColor,
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
    } else {
      // Mobile layout with drawer
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: appBar ?? _buildMobileAppBar(context),
          drawer: AdminSidebar(
        currentRoute: currentRoute,
        onRouteSelected: onRouteSelected ?? (route) {},
      ),
          body: Container(
            color: AppColors.backgroundColor,
            child: body,
          ),
          floatingActionButton: floatingActionButton,
        ),
      );
    }
  }

  Widget _buildTopBar() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            if (title != null) ...[
              Expanded(
                child: Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(BuildContext context) {
    return AppBar(
      title: title != null 
        ? Text(title!) 
        : const Text('فندق مارينا'),
      backgroundColor: AppColors.primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: actions,
    );
  }
}

// Bootstrap-like components for matching PHP design
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final double? elevation;
  final String? title;
  final Widget? trailing;
  
  const AdminCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.elevation,
    this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation ?? 1,
      color: color ?? Colors.white,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightGray,
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
          Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

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
            colors: [
              color,
              color.withOpacity(0.8),
            ],
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
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final bool striped;
  final bool bordered;
  
  const AdminTable({
    super.key,
    required this.headers,
    required this.rows,
    this.striped = true,
    this.bordered = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppColors.darkGray),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        decoration: bordered
            ? BoxDecoration(
                border: Border.all(color: AppColors.lightGray),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        columns: headers
            .map((header) => DataColumn(
                  label: Text(header),
                ))
            .toList(),
        rows: rows
            .asMap()
            .entries
            .map((entry) => DataRow(
                  color: striped && entry.key % 2 == 1
                      ? WidgetStateProperty.all(AppColors.lightGray.withOpacity(0.3))
                      : null,
                  cells: entry.value
                      .map((cell) => DataCell(cell))
                      .toList(),
                ))
            .toList(),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  
  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
  });

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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}