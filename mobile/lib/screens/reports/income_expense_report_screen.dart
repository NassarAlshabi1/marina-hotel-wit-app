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
import '../../utils/enhanced_pdf_utils.dart';

class IncomeExpenseReportScreen extends ConsumerStatefulWidget {
  const IncomeExpenseReportScreen({super.key});

  @override
  ConsumerState<IncomeExpenseReportScreen> createState() =>
      _IncomeExpenseReportScreenState();
}

class _IncomeExpenseReportScreenState
    extends ConsumerState<IncomeExpenseReportScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
  bool _detailedMode = false;
  bool _loading = false;

  DateTime _toDate = DateTime.now();
  late DateTime _fromDate;

  double _incomeTotal = 0;
  double _expenseTotal = 0;
  double _salaryTotal = 0;
  double get _net => _incomeTotal - _expenseTotal;

  List<_IncomeEntry> _incomeEntries = [];
  List<_ExpenseEntry> _expenseEntries = [];

  @override
  void initState() {
    super.initState();
    _fromDate = DateTime(
      _toDate.year,
      _toDate.month,
      1,
    );
    _toDate = DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
    unawaited(_fetchReport());
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final db = ref.read(coreProviders.dbProvider);

      final payments = await (db.select(db.payments)).get();
      final expenses = await (db.select(db.expenses)).get();

      final incomeEntries = <_IncomeEntry>[];
      double incomeTotal = 0;
      for (final payment in payments) {
        final date = _parseDate(payment.paymentDate);
        if (!_isWithinRange(date)) continue;
        incomeEntries.add(
          _IncomeEntry(
            date: date,
            description: payment.revenueType.isNotEmpty == true
                ? payment.revenueType
                : 'مدفوعات نزيل',
            amount: payment.amount,
          ),
        );
        incomeTotal += payment.amount;
      }
      incomeEntries.sort((a, b) => b.date.compareTo(a.date));

      final expenseEntries = <_ExpenseEntry>[];
      double expenseTotal = 0;
      double salaryTotal = 0;
      for (final expense in expenses) {
        final date = _parseDate(expense.date);
        if (!_isWithinRange(date)) continue;
        final isSalary = _isSalaryExpense(expense.expenseType);
        if (isSalary) {
          salaryTotal += expense.amount;
        }
        expenseEntries.add(
          _ExpenseEntry(
            date: date,
            type: expense.expenseType,
            description: expense.description,
            amount: expense.amount,
            isSalary: isSalary,
          ),
        );
        expenseTotal += expense.amount;
      }
      expenseEntries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _incomeEntries = incomeEntries;
        _expenseEntries = expenseEntries;
        _incomeTotal = incomeTotal;
        _expenseTotal = expenseTotal;
        _salaryTotal = salaryTotal;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  DateTime _parseDate(String value) {
    final normalized =
        value.contains('T') ? value : value.replaceFirst(' ', 'T');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return DateTime.now();
    }
  }

  bool _isWithinRange(DateTime date) {
    final endOfDay = DateTime(
      _toDate.year,
      _toDate.month,
      _toDate.day,
      23,
      59,
      59,
    );
    return !date.isBefore(_fromDate) && !date.isAfter(endOfDay);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        if (_fromDate.isAfter(_toDate)) {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        if (_toDate.isBefore(_fromDate)) {
          _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        }
      }
    });
  }

  bool _isSalaryExpense(String type) {
    final normalized = type.trim();
    return normalized.contains('راتب');
  }

  Future<void> _exportPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();

    pw.Widget buildSummaryBox(String title, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: color, width: 0.6),
        ),
        child: pw.Column(
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
              style: pw.TextStyle(font: fonts.bold, fontSize: 16, color: color),
            ),
          ],
        ),
      );
    }

    pw.Widget buildDetailTable(String title, List<List<String>> rows) {
      if (!_detailedMode || rows.isEmpty) return pw.Container();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
          pw.SizedBox(height: 6),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['التاريخ', 'الوصف', 'المبلغ'],
            data: rows,
            fonts: fonts,
            headerColor: PdfColors.primary,
            alternateRowColor: PdfColors.backgroundLight,
          ),
          pw.SizedBox(height: 12),
        ],
      );
    }

    final incomeRows = _detailedMode
        ? _incomeEntries
            .map(
              (e) => [
                _dateFormat.format(e.date),
                e.description,
                EnhancedPdfUtils.formatNumber(e.amount),
              ],
            )
            .toList()
        : const <List<String>>[];
    final expenseRows = _detailedMode
        ? _expenseEntries
            .map(
              (e) => [
                _dateFormat.format(e.date),
                e.description.isNotEmpty ? e.description : e.type,
                EnhancedPdfUtils.formatNumber(e.amount),
              ],
            )
            .toList()
        : const <List<String>>[];

    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate);

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
          pw.Container(
            width: double.infinity,
            decoration: const pw.BoxDecoration(color: PdfColors.primary),
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              children: [
                pw.Text(
                  'تقرير الدخل والخرج',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 20,
                    color: PdfColors.textWhite,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'الفترة من $fromLabel إلى $toLabel',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 12,
                    color: PdfColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              pw.Expanded(
                child: buildSummaryBox(
                  'إجمالي الدخل',
                  EnhancedPdfUtils.formatNumber(_incomeTotal),
                  PdfColors.success,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: buildSummaryBox(
                  'إجمالي المصروفات',
                  EnhancedPdfUtils.formatNumber(_expenseTotal),
                  PdfColors.danger,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: buildSummaryBox(
                  'مصروفات الرواتب',
                  EnhancedPdfUtils.formatNumber(_salaryTotal),
                  PdfColors.warning,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: buildSummaryBox(
                  'صافي الربح/الخسارة',
                  EnhancedPdfUtils.formatNumber(_net),
                  _net >= 0 ? PdfColors.success : PdfColors.danger,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          buildDetailTable('تفاصيل الدخل', incomeRows),
          buildDetailTable('تفاصيل المصروفات', expenseRows),
        ],
      ),
    );

    final filename =
        'تقرير-الدخل-والخرج-${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    await Printing.sharePdf(bytes: await doc.save(), filename: filename);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تقرير الدخل والخرج',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: (_incomeEntries.isEmpty && _expenseEntries.isEmpty)
              ? null
              : _exportPdf,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: true),
                  icon: const Icon(Icons.calendar_month),
                  label: Text('من: ${DateFormat('yyyy-MM-dd').format(_fromDate)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: false),
                  icon: const Icon(Icons.calendar_month),
                  label: Text('إلى: ${DateFormat('yyyy-MM-dd').format(_toDate)}'),
                ),
                FilterChip(
                  label: const Text('تفصيلي'),
                  selected: _detailedMode,
                  onSelected: (value) => setState(() => _detailedMode = value),
                ),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.refresh),
                  label: _loading
                      ? const Text('جارٍ التحميل...')
                      : const Text('تحديث التقرير'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSummaryCard(),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_incomeEntries.isEmpty && _expenseEntries.isEmpty)
                      ? const EmptyState(
                          title: 'لا توجد بيانات',
                          message: 'لا يوجد دخل أو مصروفات ضمن الفترة المحددة.',
                          icon: Icons.receipt_long,
                        )
                      : _buildDetails(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الفترة: ${DateFormat('yyyy-MM-dd').format(_fromDate)} - ${DateFormat('yyyy-MM-dd').format(_toDate)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _buildSummaryTile('إجمالي الدخل', _incomeTotal),
                _buildSummaryTile('إجمالي المصروفات', _expenseTotal),
                _buildSummaryTile('مصروفات الرواتب', _salaryTotal),
                _buildSummaryTile('صافي الربح/الخسارة', _net),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(String label, double value) {
    final isNet = label.contains('صافي');
    final color = isNet
        ? (value >= 0 ? Colors.green : Colors.red)
        : Theme.of(context).colorScheme.primary;
    return Chip(
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            NumberFormat('#,##0').format(value),
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    return ListView(
      children: [
        if (_detailedMode) ...[
          Text('تفاصيل الدخل', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._incomeEntries.map(
            (e) => ListTile(
              leading: const Icon(Icons.arrow_downward, color: Colors.green),
              title: Text(e.description),
              subtitle: Text(_dateFormat.format(e.date)),
              trailing: Text(NumberFormat('#,##0').format(e.amount)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'تفاصيل المصروفات',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._expenseEntries.map(
            (e) => ListTile(
              leading: Icon(
                Icons.arrow_upward,
                color: e.isSalary ? Colors.orange : Colors.red,
              ),
              title: Text(e.description.isNotEmpty ? e.description : e.type),
              subtitle: Text(_dateFormat.format(e.date)),
              trailing: Text(NumberFormat('#,##0').format(e.amount)),
            ),
          ),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.arrow_downward, color: Colors.green),
            title: const Text('عدد معاملات الدخل'),
            trailing: Text('${_incomeEntries.length}'),
          ),
          ListTile(
            leading: const Icon(Icons.arrow_upward, color: Colors.red),
            title: const Text('عدد معاملات المصروفات'),
            trailing: Text('${_expenseEntries.length}'),
          ),
        ],
      ],
    );
  }
}

class _IncomeEntry {
  _IncomeEntry({
    required this.date,
    required this.description,
    required this.amount,
  });

  final DateTime date;
  final String description;
  final double amount;
}

class _ExpenseEntry {
  _ExpenseEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
    required this.isSalary,
  });

  final DateTime date;
  final String type;
  final String description;
  final double amount;
  final bool isSalary;
}
