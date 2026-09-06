import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../components/widgets/empty_state.dart';
import '../../providers/repository_providers.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../widgets/report_date_filter.dart';
import 'report_page_scaffold.dart';

class InventoryReportScreen extends ConsumerStatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  ConsumerState<InventoryReportScreen> createState() =>
      _InventoryReportScreenState();
}

class _InventoryReportScreenState extends ConsumerState<InventoryReportScreen> {
  final DateFilterController _filterController = DateFilterController();
  final NumberFormat _numberFormat = NumberFormat('#,##0', 'en_US');

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedCategory;
  List<String> _categories = const [];
  List<_InventoryReportRow> _rows = const [];
  _InventoryReportSummary _summary = const _InventoryReportSummary.empty();
  bool _loading = false;
  bool _initialized = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from;
    _toDate = range.to;
    await _loadCategories();
    await _fetchReport();
  }

  Future<void> _loadCategories() async {
    try {
      final db = ref.read(databaseProvider);
      final result = await db
          .customSelect(
            'SELECT DISTINCT category FROM inventory_items '
            'WHERE is_active = 1 AND category IS NOT NULL AND TRIM(category) <> "" '
            'ORDER BY category COLLATE NOCASE',
            readsFrom: {db.inventoryItems},
          )
          .get();
      if (!mounted) return;
      setState(() {
        _categories = result
            .map((row) => row.data['category']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _categories = const [];
        _error = 'تعذر تحميل تصنيفات المخزون: $error';
      });
    }
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    final fromDate = _fromDate;
    final toDate = _toDate;
    if (fromDate == null || toDate == null || fromDate.isAfter(toDate)) {
      setState(() => _error = 'نطاق التاريخ غير صالح');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final variables = <drift.Variable<Object>>[
        drift.Variable.withInt(fromDate.millisecondsSinceEpoch ~/ 1000),
        drift.Variable.withInt(toDate.millisecondsSinceEpoch ~/ 1000),
      ];
      var categoryClause = '';
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        categoryClause = ' AND i.category = ?';
        variables.add(drift.Variable.withString(_selectedCategory!));
      }

      // تجميع على مستوى الصنف: لا يتم تحميل كل الحركات إلى الذاكرة.
      final result = await db
          .customSelect(
            '''
        SELECT
          i.id,
          i.name,
          i.unit,
          i.category,
          i.quantity,
          i.minimum_quantity,
          COALESCE(SUM(CASE
            WHEN t.movement_type IN ('in', 'opening') THEN t.quantity
            ELSE 0 END), 0) AS total_in,
          COALESCE(SUM(CASE
            WHEN t.movement_type = 'out' THEN t.quantity
            ELSE 0 END), 0) AS total_out,
          COALESCE(SUM(CASE
            WHEN t.movement_type = 'adjustment' THEN t.quantity
            ELSE 0 END), 0) AS total_adjustment,
          COUNT(t.id) AS movement_count
        FROM inventory_items i
        LEFT JOIN inventory_transactions t
          ON t.item_id = i.id
          AND t.created_at >= ?
          AND t.created_at <= ?
          AND t.deleted_at IS NULL
        WHERE i.is_active = 1$categoryClause
        GROUP BY i.id, i.name, i.unit, i.category,
                 i.quantity, i.minimum_quantity
        ORDER BY
          CASE WHEN i.minimum_quantity > 0
                AND i.quantity <= i.minimum_quantity THEN 0 ELSE 1 END,
          i.name COLLATE NOCASE
        ''',
            variables: variables,
            readsFrom: {db.inventoryItems, db.inventoryTransactions},
          )
          .get();

      final rows = result.map(_InventoryReportRow.fromData).toList();
      final summary = _InventoryReportSummary.fromRows(rows);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _summary = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل التقرير المخزني: $error';
      });
    }
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final dataRows = [
      for (final entry in _rows.asMap().entries)
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
        fromDate: _fromDate,
        toDate: _toDate,
        extraHeaderLine: _selectedCategory?.isNotEmpty == true
            ? 'التصنيف: $_selectedCategory'
            : 'الأصناف النشطة',
        buildContent: (fonts) => [
          EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص التقرير',
            content: [
              pw.Text('عدد الأصناف: ${_summary.itemCount}'),
              pw.Text('أصناف تحت الحد الأدنى: ${_summary.lowStockCount}'),
              pw.Text('إجمالي الوارد: ${_summary.totalIn}'),
              pw.Text('إجمالي الصرف: ${_summary.totalOut}'),
              pw.Text('إجمالي التسويات: ${_summary.totalAdjustment}'),
              pw.Text('عدد الحركات: ${_summary.movementCount}'),
            ],
            fonts: fonts,
          ),
          pw.SizedBox(height: 12),
          EnhancedPdfUtils.buildProfessionalTable(
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
            headerColor: PdfColors.primary,
            alternateRowColor: PdfColors.backgroundLight,
          ),
        ],
        fileName: ReportPdfBuilder.generateFileName('التقرير المخزني'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportPageScaffold(
      title: 'التقرير المخزني',
      filterController: _filterController,
      onDateRangeChanged: (range) {
        setState(() {
          _fromDate = range.from;
          _toDate = range.to;
        });
        unawaited(_fetchReport());
      },
      onExportPdf: _exportPdf,
      onSearch: _fetchReport,
      isPdfEnabled: _rows.isNotEmpty && !_loading,
      isLoading: _loading,
      filterWidgets: [
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedCategory,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'التصنيف',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                child: Text('كل التصنيفات'),
              ),
              ..._categories.map(
                (category) => DropdownMenuItem<String?>(
                  value: category,
                  child: Text(category, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: _loading
                ? null
                : (value) => setState(() => _selectedCategory = value),
          ),
        ),
      ],
      summaryWidget: _buildSummary(),
      contentWidget: _buildContent(),
    );
  }

  Widget _buildSummary() {
    if (_error != null && _rows.isEmpty) {
      return Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _summaryTile('الأصناف', _summary.itemCount, Colors.blue),
        _summaryTile('تحت الحد', _summary.lowStockCount, Colors.orange),
        _summaryTile('الوارد', _summary.totalIn, Colors.green),
        _summaryTile('الصرف', _summary.totalOut, Colors.red),
        _summaryTile('التسويات', _summary.totalAdjustment, Colors.indigo),
        _summaryTile('الحركات', _summary.movementCount, Colors.teal),
      ],
    );
  }

  Widget _summaryTile(String label, int value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92, maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$label: ${_numberFormat.format(value)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: EmptyState(
          title: 'تعذر تحميل التقرير المخزني',
          subtitle: _error,
          icon: Icons.error_outline,
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: EmptyState(
          title: 'لا توجد بيانات مخزنية',
          subtitle: 'لا توجد أصناف نشطة أو حركات ضمن الفترة المحددة.',
          icon: Icons.inventory_2_outlined,
        ),
      );
    }
    return ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (context, index) => _InventoryReportRowTile(
        row: _rows[index],
        numberFormat: _numberFormat,
      ),
    );
  }
}

class _InventoryReportRow {
  const _InventoryReportRow({
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

  factory _InventoryReportRow.fromData(drift.QueryRow row) {
    final data = row.data;
    int asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _InventoryReportRow(
      name: data['name']?.toString() ?? '',
      unit: data['unit']?.toString() ?? 'قطعة',
      category: data['category']?.toString(),
      quantity: asInt(data['quantity']),
      minimumQuantity: asInt(data['minimum_quantity']),
      totalIn: asInt(data['total_in']),
      totalOut: asInt(data['total_out']),
      totalAdjustment: asInt(data['total_adjustment']),
      movementCount: asInt(data['movement_count']),
    );
  }

  final String name;
  final String unit;
  final String? category;
  final int quantity;
  final int minimumQuantity;
  final int totalIn;
  final int totalOut;
  final int totalAdjustment;
  final int movementCount;

  bool get isLowStock => minimumQuantity > 0 && quantity <= minimumQuantity;
}

class _InventoryReportSummary {
  const _InventoryReportSummary({
    required this.itemCount,
    required this.lowStockCount,
    required this.totalIn,
    required this.totalOut,
    required this.totalAdjustment,
    required this.movementCount,
  });

  const _InventoryReportSummary.empty()
    : itemCount = 0,
      lowStockCount = 0,
      totalIn = 0,
      totalOut = 0,
      totalAdjustment = 0,
      movementCount = 0;

  factory _InventoryReportSummary.fromRows(List<_InventoryReportRow> rows) {
    return _InventoryReportSummary(
      itemCount: rows.length,
      lowStockCount: rows.where((row) => row.isLowStock).length,
      totalIn: rows.fold(0, (sum, row) => sum + row.totalIn),
      totalOut: rows.fold(0, (sum, row) => sum + row.totalOut),
      totalAdjustment: rows.fold(0, (sum, row) => sum + row.totalAdjustment),
      movementCount: rows.fold(0, (sum, row) => sum + row.movementCount),
    );
  }

  final int itemCount;
  final int lowStockCount;
  final int totalIn;
  final int totalOut;
  final int totalAdjustment;
  final int movementCount;
}

class _InventoryReportRowTile extends StatelessWidget {
  const _InventoryReportRowTile({
    required this.row,
    required this.numberFormat,
  });

  final _InventoryReportRow row;
  final NumberFormat numberFormat;

  @override
  Widget build(BuildContext context) {
    final color = row.isLowStock
        ? Colors.orange.shade800
        : Colors.green.shade700;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  row.isLowStock
                      ? Icons.warning_amber_rounded
                      : Icons.inventory_2_outlined,
                  color: color,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '${numberFormat.format(row.quantity)} ${row.unit}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'التصنيف: ${row.category?.isNotEmpty == true ? row.category : 'غير مصنف'}'
              ' • الحد الأدنى: ${row.minimumQuantity} ${row.unit}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 3,
              children: [
                _metric('وارد', row.totalIn, Colors.green),
                _metric('صرف', row.totalOut, Colors.red),
                _metric('تسويات', row.totalAdjustment, Colors.indigo),
                _metric('حركات', row.movementCount, Colors.teal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, int value, Color color) {
    return Text(
      '$label: ${numberFormat.format(value)}',
      style: TextStyle(fontSize: 10, color: color),
    );
  }
}
