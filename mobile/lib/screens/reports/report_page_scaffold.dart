import 'package:flutter/material.dart';

import '../../components/app_scaffold.dart';
import '../../widgets/report_date_filter.dart';

/// ويدجت مشتركة لبناء هيكل صفحات التقارير (AppScaffold + فلتر تاريخ + زر بحث PDF)
/// لتجنب تكرار كود البنية المشتركة بين شاشات التقارير المختلفة
class ReportPageScaffold extends StatelessWidget {
  const ReportPageScaffold({
    super.key,
    required this.title,
    required this.filterController,
    required this.onDateRangeChanged,
    required this.onExportPdf,
    this.onSearch,
    required this.isPdfEnabled,
    required this.isLoading,
    required this.filterWidgets,
    required this.summaryWidget,
    required this.contentWidget,
    this.searchBar,
  });

  final String title;
  final DateFilterController filterController;
  final void Function(DateRange range) onDateRangeChanged;
  final VoidCallback onExportPdf;

  /// زر البحث — اختياري، إذا كان null لا يظهر زر البحث
  /// (للشاشات التي تفلتر تلقائياً بدون الحاجة لزر بحث)
  final VoidCallback? onSearch;

  final bool isPdfEnabled;
  final bool isLoading;
  final List<Widget> filterWidgets;
  final Widget summaryWidget;
  final Widget contentWidget;

  /// شريط بحث اختياري يظهر بين فلتر التاريخ وفلاتر الأنواع
  final Widget? searchBar;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: title,
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: isPdfEnabled ? onExportPdf : null,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReportDateFilterWidget(
              controller: filterController,
              onDateRangeChanged: onDateRangeChanged,
            ),
            if (searchBar != null) ...[
              const SizedBox(height: 6),
              searchBar,
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...filterWidgets,
                if (onSearch != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    onPressed: isLoading ? null : onSearch,
                    icon: const Icon(Icons.search, size: 16),
                    label: Text(isLoading ? 'جارٍ...' : 'بحث'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            summaryWidget,
            const SizedBox(height: 8),
            Expanded(child: contentWidget),
          ],
        ),
      ),
    );
  }
}
