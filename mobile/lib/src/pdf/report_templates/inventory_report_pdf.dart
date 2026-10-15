/// قالب PDF للتقرير المخزني — نظام قوالب مستقل.
///
/// الشاشة تُمرّر بيانات فقط، والقالب يتولى التصميم كاملاً من نظام
/// التصميم الموحّد في lib/src/pdf/enhanced_pdf_utils.dart.
library;

import 'package:pdf/widgets.dart' as pw;

import '../enhanced_pdf_utils.dart';
import '../report_pdf_builder.dart';

/// صف صنف مخزني واحد.
class InventoryReportRow {
  const InventoryReportRow({
    required this.name,
    required this.unit,
    required this.category,
    required this.quantity,
    required this.minimumQuantity,
    required this.totalIn,
    required this.totalOut,
    required this.totalAdjustment,
    required this.movementCount,
  });

  final String name;
  final String unit;
  final String? category;
  final int quantity;
  final int minimumQuantity;
  final int totalIn;
  final int totalOut;
  final int totalAdjustment;
  final int movementCount;
}

/// ملخص التقرير المخزني.
class InventoryReportSummary {
  const InventoryReportSummary({
    required this.itemCount,
    required this.lowStockCount,
    required this.totalIn,
    required this.totalOut,
    required this.totalAdjustment,
    required this.movementCount,
  });

  final int itemCount;
  final int lowStockCount;
  final int totalIn;
  final int totalOut;
  final int totalAdjustment;
  final int movementCount;
}

/// بيانات التقرير المخزني.
class InventoryReportData {
  InventoryReportData({
    required this.rows,
    required this.summary,
    this.fromDate,
    this.toDate,
    this.categoryLabel,
  });

  final List<InventoryReportRow> rows;
  final InventoryReportSummary summary;
  final DateTime? fromDate;
  final DateTime? toDate;

  /// تسمية التصنيف المفلتر أو 'الأصناف النشطة'.
  final String? categoryLabel;
}

/// قالب التقرير المخزني.
class InventoryReportPdf {
  InventoryReportPdf._();

  /// مشاركة التقرير المخزني.
  static Future<void> share(InventoryReportData data) async {
    final dataRows = [
      for (final entry in data.rows.asMap().entries)
        [
          '${entry.key + 1}',
          entry.value.name,
          entry.value.category ?? '-',
          '${entry.value.quantity} ${entry.value.unit}',
          '${entry.value.minimumQuantity}',
          '${entry.value.totalIn}',
          '${entry.value.totalOut}',
          '${entry.value.totalAdjustment}',
          '${entry.value.movementCount}',
        ],
    ];

    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'التقرير المخزني',
        fromDate: data.fromDate,
        toDate: data.toDate,
        extraHeaderLine: data.categoryLabel ?? 'الأصناف النشطة',
        buildContent: (fonts) => [
          EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص التقرير',
            fonts: fonts,
            content: [
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'عدد الأصناف',
                value: '${data.summary.itemCount}',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'تحت الحد الأدنى',
                value: '${data.summary.lowStockCount}',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'إجمالي الوارد',
                value: '${data.summary.totalIn}',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'إجمالي الصرف',
                value: '${data.summary.totalOut}',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'إجمالي التسويات',
                value: '${data.summary.totalAdjustment}',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'عدد الحركات',
                value: '${data.summary.movementCount}',
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          ...EnhancedPdfUtils.buildChunkedTable(
            headers: [
              'م',
              'الصنف',
              'التصنيف',
              'الرصيد',
              'الحد الأدنى',
              'وارد',
              'صرف',
              'تسويات',
              'الحركات',
            ],
            data: dataRows,
            fonts: fonts,
          ),
        ],
        fileName: ReportPdfBuilder.generateFileName('التقرير المخزني'),
      ),
    );
  }
}
