import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/local_db.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../widgets/report_date_filter.dart';

/// أيقونات وألوان لأنواع المصروفات
const _typeConfig = <String, _ExpenseTypeConfig>{
  'رواتب': _ExpenseTypeConfig(Icons.account_balance_wallet, Colors.purple),
  'سحب راتب': _ExpenseTypeConfig(Icons.account_balance_wallet, Colors.purple),
  'سحب من الراتب': _ExpenseTypeConfig(Icons.account_balance_wallet, Colors.purple),
  'خصم راتب': _ExpenseTypeConfig(Icons.remove_circle_outline, Colors.purple),
  'خصم من الراتب': _ExpenseTypeConfig(Icons.remove_circle_outline, Colors.purple),
  'ديزل': _ExpenseTypeConfig(Icons.local_gas_station, Colors.amber),
  'صيانة': _ExpenseTypeConfig(Icons.build, Colors.orange),
  'فواتير كهرباء ومياه': _ExpenseTypeConfig(Icons.electrical_services, Colors.teal),
  'مستلزمات': _ExpenseTypeConfig(Icons.inventory_2, Colors.indigo),
  'مساعدة محتاج': _ExpenseTypeConfig(Icons.volunteer_activism, Colors.pink),
  'اخرى': _ExpenseTypeConfig(Icons.more_horiz, Colors.grey),
};

_ExpenseTypeConfig _configForType(String type) {
  for (final key in _typeConfig.keys) {
    if (type.contains(key)) return _typeConfig[key]!;
  }
  return const _ExpenseTypeConfig(Icons.receipt, Colors.grey);
}

class ExpensesReportScreen extends ConsumerStatefulWidget {
  const ExpensesReportScreen({
    super.key,
    this.allowedTypes,
    this.initialType,
    this.title = 'تقرير المصروفات',
    this.typeLabel = 'نوع المصروف',
    this.showTypeFilter = true,
    this.includeEmployeeDetails = false,
    this.totalSummaryLabel = 'إجمالي المصروفات',
    this.totalRowLabel = 'الإجمالي',
  });

  final Set<String>? allowedTypes;
  final String? initialType;
  final String title;
  final String typeLabel;
  final bool showTypeFilter;
  final bool includeEmployeeDetails;
  final String totalSummaryLabel;
  final String totalRowLabel;

  @override
  ConsumerState<ExpensesReportScreen> createState() =>
      _ExpensesReportScreenState();
}

class _ExpensesReportScreenState extends ConsumerState<ExpensesReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final _filterController = DateFilterController();

  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;

  final List<_ExpenseReportRow> _rows = [];
  final List<String> _availableTypes = [];

  String? _selectedType;
  double _totalAmount = 0;

  /// النتائج مجمعة حسب النوع
  Map<String, List<_ExpenseReportRow>> _grouped = {};
  Map<String, double> _typeSubtotals = {};

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initializeDefaults();
    }
  }

  Future<void> _initializeDefaults() async {
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from;
    _toDate = range.to;

    if (widget.allowedTypes != null && widget.allowedTypes!.isNotEmpty) {
      setState(() {
        _availableTypes
          ..clear()
          ..addAll(widget.allowedTypes!.toList());
        _selectedType = widget.showTypeFilter
            ? (widget.initialType ?? widget.allowedTypes!.first)
            : null;
      });
    } else {
      await _loadExpenseTypes();
    }
    await _fetchReport();
  }

  Future<void> _loadExpenseTypes() async {
    final db = ref.read(coreProviders.dbProvider);
    final query = await db
        .customSelect('SELECT DISTINCT expense_type FROM expenses')
        .get();
    final types =
        query.map((row) => row.data['expense_type'] as String).toList()..sort();
    setState(() {
      _availableTypes
        ..clear()
        ..addAll(types);
    });
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final db = ref.read(coreProviders.dbProvider);
      final result = await _loadExpensesReport(db);
      setState(() {
        _rows
          ..clear()
          ..addAll(result.rows);
        _totalAmount = result.totalAmount;
        _buildGroups();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _buildGroups() {
    _grouped = {};
    _typeSubtotals = {};
    for (final row in _rows) {
      _grouped.putIfAbsent(row.type, () => []).add(row);
      _typeSubtotals[row.type] = (_typeSubtotals[row.type] ?? 0) + row.amount;
    }
    // ترتيب حسب المبلغ الأعلى
    final sortedKeys = _typeSubtotals.keys.toList()
      ..sort((a, b) => _typeSubtotals[b]!.compareTo(_typeSubtotals[a]!));
    final ordered = <String, List<_ExpenseReportRow>>{};
    for (final key in sortedKeys) {
      ordered[key] = _grouped[key]!;
    }
    _grouped = ordered;
  }

  Future<_ExpensesReportResult> _loadExpensesReport(AppDatabase db) async {
    final outboxDao = OutboxDao(db);
    final expensesDao = ExpensesDao(db, outboxDao);
    final fromStr = _fromDate != null
        ? '${DateFormat('yyyy-MM-dd').format(_fromDate!)}'
        : null;
    final toStr = _toDate != null
        ? '${DateFormat('yyyy-MM-dd').format(_toDate!)}'
        : null;
    final selectedType =
        widget.showTypeFilter &&
            _selectedType != null &&
            _selectedType!.isNotEmpty
        ? _selectedType
        : null;

    var expenses = await expensesDao.listFiltered(
      from: fromStr,
      to: toStr,
      expenseType: selectedType,
    );

    if (widget.allowedTypes != null && widget.allowedTypes!.isNotEmpty) {
      expenses = expenses
          .where(
            (expense) => widget.allowedTypes!.contains(expense.expenseType),
          )
          .toList();
    }

    // سحب أسماء الموظفين دائماً
    final employeeMap = <int, Employee>{};
    final employeeIds = expenses
        .map((e) => e.relatedId)
        .whereType<int>()
        .toSet();
    if (employeeIds.isNotEmpty) {
      final employees = await (db.select(
        db.employees,
      )..where((tbl) => tbl.id.isIn(employeeIds.toList()))).get();
      for (final employee in employees) {
        employeeMap[employee.id] = employee;
      }
    }

    final rows = <_ExpenseReportRow>[];
    double totalAmount = 0;
    for (final expense in expenses) {
      final employee = expense.relatedId != null
          ? employeeMap[expense.relatedId!]
          : null;
      final date = _parseExpenseDate(expense.date);
      totalAmount += expense.amount;
      rows.add(
        _ExpenseReportRow(
          date: date,
          amount: expense.amount,
          type: expense.expenseType,
          description: expense.description,
          employee: employee,
        ),
      );
    }

    return _ExpensesReportResult(rows: rows, totalAmount: totalAmount);
  }

  // ─── PDF: بدون تغيير ───
  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final fromLabel = _fromDate != null
        ? DateFormat('yyyy-MM-dd').format(_fromDate!)
        : 'غير محدد';
    final toLabel = _toDate != null
        ? DateFormat('yyyy-MM-dd').format(_toDate!)
        : 'غير محدد';
    final selectedTypeLabel = _selectedType?.isNotEmpty == true
        ? _selectedType!
        : 'الكل';

    final headers = <String>['التاريخ', 'المبلغ', 'النوع', 'الوصف'];
    if (widget.includeEmployeeDetails) {
      headers.add('الموظف');
    }

    final dataRows = <List<String>>[];
    for (final row in _rows) {
      final cells = [
        _dateLabelFormat.format(row.date),
        EnhancedPdfUtils.formatNumber(row.amount),
        row.type,
        row.description.isNotEmpty ? row.description : '-',
      ];
      if (widget.includeEmployeeDetails) {
        cells.add(row.employee?.name ?? 'غير محدد');
      }
      dataRows.add(cells);
    }

    final totalRow = [
      widget.totalRowLabel,
      EnhancedPdfUtils.formatNumber(_totalAmount),
      '',
      '',
    ];
    if (widget.includeEmployeeDetails) {
      totalRow.add('');
    }
    dataRows.add(totalRow);

    await ReportPdfBuilder.buildAndShare(ReportPdfConfig(
      title: widget.title,
      fromDate: _fromDate,
      toDate: _toDate,
      buildContent: (fonts) {
        pw.Widget metaRow(String label, String value) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(label, style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                pw.Text(
                  value,
                  style: pw.TextStyle(font: fonts.regular, fontSize: 11),
                ),
              ],
            ),
          );
        }

        final metaInfoCard = EnhancedPdfUtils.buildInfoCard(
          title: widget.title,
          fonts: fonts,
          content: [
            metaRow('الفترة', 'من $fromLabel إلى $toLabel'),
            metaRow(widget.typeLabel, selectedTypeLabel),
            metaRow('عدد السجلات', _rows.length.toString()),
          ],
        );

        pw.Widget buildSummaryItem(String title, String value, PdfColor accent) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.backgroundCard,
              border: pw.Border.all(color: accent, width: 0.7),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 11,
                    color: PdfColors.textDark,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  value,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 16,
                    color: accent,
                  ),
                ),
              ],
            ),
          );
        }

        return [
          pw.SizedBox(height: 16),
          metaInfoCard,
          pw.SizedBox(height: 12),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: headers,
            data: dataRows,
            fonts: fonts,
            headerColor: PdfColors.primary,
            alternateRowColor: PdfColors.backgroundLight,
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.backgroundLight,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.primary, width: 0.4),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryItem(
                    widget.totalSummaryLabel,
                    EnhancedPdfUtils.formatNumber(_totalAmount),
                    PdfColors.secondary,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: buildSummaryItem(
                    'عدد السجلات',
                    _rows.length.toString(),
                    PdfColors.info,
                  ),
                ),
              ],
            ),
          ),
        ];
      },
      fileName: ReportPdfBuilder.generateFileName(widget.title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.title,
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: _rows.isEmpty ? null : _exportPdf,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // فلتر التاريخ المشترك
            ReportDateFilterWidget(
              controller: _filterController,
              onDateRangeChanged: (range) {
                setState(() {
                  _fromDate = range.from;
                  _toDate = range.to;
                });
                _fetchReport();
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.showTypeFilter)
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String?>(
                      value: _selectedType,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: widget.typeLabel,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('الكل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color)),
                        ),
                        ..._availableTypes.map(
                          (type) => DropdownMenuItem<String?>(
                            value: type,
                            child: Text(type, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color)),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedType = value;
                        });
                      },
                    ),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(_loading ? 'جارٍ...' : 'بحث'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailedSummary(),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const EmptyState(
                      title: 'لا توجد بيانات',
                      message: 'لم يتم العثور على مصروفات ضمن النطاق المحدد.',
                      icon: Icons.receipt_long,
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: _buildGroupedList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء القائمة مجمعة حسب نوع المصروف
  List<Widget> _buildGroupedList() {
    final widgets = <Widget>[];
    final sortedTypes = _grouped.keys.toList();

    for (int t = 0; t < sortedTypes.length; t++) {
      final type = sortedTypes[t];
      final items = _grouped[type]!;
      final subtotal = _typeSubtotals[type] ?? 0.0;
      final cfg = _configForType(type);
      final pct = _totalAmount > 0 ? (subtotal / _totalAmount * 100) : 0.0;

      // رأس المجموعة
      widgets.add(
        _buildGroupHeader(
          type: type,
          icon: cfg.icon,
          color: cfg.color,
          count: items.length,
          subtotal: subtotal,
          percentage: pct,
        ),
      );
      const SizedBox(height: 4);

      // بنود المجموعة
      for (int i = 0; i < items.length; i++) {
        widgets.add(_buildDetailedExpenseCard(items[i], rowIndex: i + 1));
        if (i < items.length - 1) const SizedBox(height: 4);
      }

      // فاصل بين المجموعات
      if (t < sortedTypes.length - 1) const SizedBox(height: 12);
    }

    return widgets;
  }

  /// رأس مجموعة النوع مع المبلغ الإجمالي والنسبة المئوية
  Widget _buildGroupHeader({
    required String type,
    required IconData icon,
    required Color color,
    required int count,
    required double subtotal,
    required double percentage,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  '$count عملية',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currencyFmt.format(subtotal),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 80,
                    height: 5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (percentage / 100).clamp(0, 1),
                        backgroundColor: color.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// بطاقة المصروف المفصلة
  Widget _buildDetailedExpenseCard(_ExpenseReportRow row, {required int rowIndex}) {
    final cfg = _configForType(row.type);
    final pct = _totalAmount > 0 ? (row.amount / _totalAmount * 100) : 0.0;
    final hasDesc = row.description.isNotEmpty;
    final hasEmployee = row.employee != null;

    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade100, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصف الأول: رقم + التاريخ والوقت + المبلغ
            Row(
              children: [
                // رقم البند
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: cfg.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rowIndex',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cfg.color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // التاريخ والوقت
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text(
                        _dateLabelFormat.format(row.date),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Text(
                        _timeFormat.format(row.date),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // المبلغ + النسبة
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currencyFmt.format(row.amount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: cfg.color,
                      ),
                    ),
                    if (_grouped.length > 1)
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // الصف الثاني: الوصف
            if (hasDesc) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes, size: 13, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      row.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // الصف الثالث: الموظف
            if (hasEmployee) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 13, color: Colors.blue.shade400),
                  const SizedBox(width: 4),
                  Text(
                    row.employee!.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  if (row.employee!.phone.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.phone, size: 11, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(
                      row.employee!.phone,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // شريط النسبة المصغرة (إذا كان هناك أكثر من نوع)
            if (_grouped.length > 1) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0, 1),
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(cfg.color.withOpacity(0.6)),
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ملخص تفصيلي مع توزيع الأنواع
  Widget _buildDetailedSummary() {
    if (_rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الإجمالي الرئيسي
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currencyFmt.format(_totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.orange,
                      ),
                    ),
                    Text(
                      widget.totalSummaryLabel,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${_rows.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue,
                      ),
                    ),
                    Text(
                      'عملية',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // توزيع الأنواع
          if (_typeSubtotals.length > 1) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'التوزيع حسب النوع',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _typeSubtotals.entries.map((entry) {
                final cfg = _configForType(entry.key);
                final pct = _totalAmount > 0 ? (entry.value / _totalAmount * 100) : 0.0;
                final count = _grouped[entry.key]?.length ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: cfg.color.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cfg.color.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cfg.icon, size: 13, color: cfg.color),
                      const SizedBox(width: 4),
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cfg.color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_currencyFmt.format(entry.value)} ($count)',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // متوسط المصروف لكل عملية
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'متوسط المبلغ لكل عملية: ${_currencyFmt.format(_totalAmount / _rows.length)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  DateTime _parseExpenseDate(String value) {
    final trimmed = value.trim();
    final hasTime = trimmed.length > 10;
    final normalized = hasTime
        ? trimmed.replaceFirst(' ', 'T')
        : '${trimmed}T00:00:00';
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return DateTime.now();
    }
  }
}

class _ExpenseReportRow {
  _ExpenseReportRow({
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
    required this.employee,
  });

  final DateTime date;
  final double amount;
  final String type;
  final String description;
  final Employee? employee;
}

class _ExpensesReportResult {
  _ExpensesReportResult({required this.rows, required this.totalAmount});

  final List<_ExpenseReportRow> rows;
  final double totalAmount;
}

class _ExpenseTypeConfig {
  const _ExpenseTypeConfig(this.icon, this.color);
  final IconData icon;
  final Color color;
}
