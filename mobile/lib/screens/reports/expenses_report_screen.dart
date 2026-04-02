import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/local_db.dart';
import '../../utils/enhanced_pdf_utils.dart';

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

  // ignore: unused_element
  String _formatNumber(num value) => _currencyFmt.format(value);
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;

  final List<_ExpenseReportRow> _rows = [];
  final List<String> _availableTypes = [];

  String? _selectedType;
  double _totalAmount = 0;

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
    final now = DateTime.now();
    _fromDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

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

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        } else {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
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
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<_ExpensesReportResult> _loadExpensesReport(AppDatabase db) async {
    final outboxDao = OutboxDao(db);
    final expensesDao = ExpensesDao(db, outboxDao);
    final fromStr = _fromDate != null
        ? DateFormat('yyyy-MM-dd').format(_fromDate!)
        : null;
    final toStr = _toDate != null
        ? DateFormat('yyyy-MM-dd').format(_toDate!)
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

    final employeeMap = <int, Employee>{};
    if (widget.includeEmployeeDetails) {
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

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final fromLabel = _fromDate != null
        ? DateFormat('yyyy-MM-dd').format(_fromDate!)
        : 'غير محدد';
    final toLabel = _toDate != null
        ? DateFormat('yyyy-MM-dd').format(_toDate!)
        : 'غير محدد';
    final selectedTypeLabel = _selectedType?.isNotEmpty == true
        ? _selectedType!
        : 'الكل';

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

    pw.Widget buildReportHeader() {
      final periodText = 'الفترة من تاريخ $fromLabel إلى تاريخ $toLabel';
      return pw.Container(
        width: double.infinity,
        decoration: const pw.BoxDecoration(color: PdfColors.primary),
        padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'فندق مارينا بلازا',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 22,
                color: PdfColors.textWhite,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              widget.title,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 20,
                color: PdfColors.textWhite,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              periodText,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 12,
                color: PdfColors.textWhite,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );
    }

    pw.Widget buildTotalsSummary() {
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

      return pw.Container(
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
      );
    }

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

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: fonts.regular, fontSize: 10),
          ),
        ),
        build: (context) => [
          buildReportHeader(),
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
          buildTotalsSummary(),
        ],
      ),
    );

    String generateFileName(String title) {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final sanitizedTitle = title.replaceAll(RegExp(r'\s+'), '-');
      return '$sanitizedTitle-$timestamp.pdf';
    }

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: generateFileName(widget.title),
    );
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildDateSelector(
                  label: 'من',
                  value: _fromDate,
                  onPressed: () => _pickDate(isFrom: true),
                ),
                _buildDateSelector(
                  label: 'إلى',
                  value: _toDate,
                  onPressed: () => _pickDate(isFrom: false),
                ),
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
                      style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('الكل', style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color)),
                        ),
                        ..._availableTypes.map(
                          (type) => DropdownMenuItem<String?>(
                            value: type,
                            child: Text(type, style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color)),
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
            _buildSummary(),
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
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return _buildExpenseCard(row);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCard(_ExpenseReportRow row) {
    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dateLabelFormat.format(row.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  _currencyFmt.format(row.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.label, size: 13, color: Colors.orange),
                const SizedBox(width: 3),
                Text(
                  row.type,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (row.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.notes, size: 13, color: Colors.grey),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      row.description,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (widget.includeEmployeeDetails && row.employee != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person, size: 13, color: Colors.blue),
                  const SizedBox(width: 3),
                  Text(
                    row.employee!.name,
                    style: const TextStyle(fontSize: 10, color: Colors.blue),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    _currencyFmt.format(_totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.totalSummaryLabel,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 28, color: Colors.grey.shade200),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _rows.length.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'عدد السجلات',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
  }) {
    final text = value != null
        ? DateFormat('yyyy-MM-dd').format(value)
        : '—';
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text('$label: $text'),
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
