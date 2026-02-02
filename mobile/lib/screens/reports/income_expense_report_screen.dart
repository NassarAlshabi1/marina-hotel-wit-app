import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/repository_providers.dart';
import '../../services/daos/payments_dao.dart';
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/report_filter_utils.dart';

class IncomeExpenseReportScreen extends ConsumerStatefulWidget {
  const IncomeExpenseReportScreen({super.key});

  @override
  ConsumerState<IncomeExpenseReportScreen> createState() =>
      _IncomeExpenseReportScreenState();
}

class _IncomeExpenseReportScreenState
    extends ConsumerState<IncomeExpenseReportScreen>
    with OptimizedReportFilterMixin {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  DateTime _toDate = DateTime.now();
  late DateTime _fromDate;

  bool _loading = false;
  bool _detailedMode = false;

  List<_IncomeEntry> _incomeEntries = [];
  List<_ExpenseEntry> _expenseEntries = [];

  double _incomeTotal = 0;
  double _expenseTotal = 0;
  double _salaryTotal = 0;
  double _net = 0;

  @override
  void initState() {
    super.initState();
    _fromDate = DateTime(
      _toDate.year,
      _toDate.month,
      1,
    );
    _toDate = DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final paymentsDao = PaymentsDao(db, outboxDao);
      final expensesDao = ExpensesDao(db, outboxDao);

      final fromStr = _dateFormat.format(_fromDate);
      final toStr = _dateFormat.format(_toDate);

      final payments = await paymentsDao.list(from: fromStr, to: toStr);
      final expenses = await expensesDao.list(from: fromStr, to: toStr);

      final result = await compute(_processReportData, _ReportParams(
        payments: payments.map((p) => {
          'date': p.paymentDate,
          'guestName': '',
          'amount': p.amount,
        }).toList(),
        expenses: expenses.map((e) => {
          'date': e.date,
          'type': e.expenseType ?? '',
          'description': e.description ?? '',
          'amount': e.amount,
        }).toList(),
        fromDate: _fromDate,
        toDate: _toDate,
      ));

      if (mounted) {
        setState(() {
          _incomeEntries = result.incomeEntries;
          _expenseEntries = result.expenseEntries;
          _incomeTotal = result.incomeTotal;
          _expenseTotal = result.expenseTotal;
          _salaryTotal = result.salaryTotal;
          _net = result.net;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isSalaryExpense(String type) {
    final normalized = type.trim();
    return normalized.contains('راتب');
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
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
      _fetchReport();
    }
  }

  Future<pw.Document> _buildPdfDocument() async {
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
                  'تقرير الدخل والمصروفات',
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

    return doc;
  }

  String _getFilename() {
    return 'تقرير-الدخل-والمصروفات-${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
  }

  Future<void> _exportPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final doc = await _buildPdfDocument();
    await Printing.sharePdf(bytes: await doc.save(), filename: _getFilename());
  }

  Future<void> _printPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final doc = await _buildPdfDocument();
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  Future<void> _savePdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    try {
      final doc = await _buildPdfDocument();
      final bytes = await doc.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_getFilename()}');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف: ${file.path}'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'إغلاق', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحفظ: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'إغلاق', onPressed: () {}),
          ),
        );
      }
    }
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'تصدير التقرير',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.share, color: Colors.blue),
              ),
              title: const Text('مشاركة PDF'),
              subtitle: const Text('إرسال عبر التطبيقات'),
              onTap: () {
                Navigator.pop(context);
                _exportPdf();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.print, color: Colors.green),
              ),
              title: const Text('طباعة'),
              subtitle: const Text('طباعة مباشرة'),
              onTap: () {
                Navigator.pop(context);
                _printPdf();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.save_alt, color: Colors.orange),
              ),
              title: const Text('حفظ في الجهاز'),
              subtitle: const Text('حفظ كملف PDF'),
              onTap: () {
                Navigator.pop(context);
                _savePdf();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _incomeEntries.isNotEmpty || _expenseEntries.isNotEmpty;
    return AppScaffold(
      title: 'تقرير الدخل والمصروفات',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: !hasData || _loading ? null : _showExportOptions,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'فترة التقرير',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDate(isFrom: true),
                            icon: const Icon(Icons.calendar_today, size: 16),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            ),
                            label: Text(
                              'من: ${_dateFormat.format(_fromDate)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDate(isFrom: false),
                            icon: const Icon(Icons.calendar_today, size: 16),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            ),
                            label: Text(
                              'إلى: ${_dateFormat.format(_toDate)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilterChip(
                          label: const Text('تفصيلي', style: TextStyle(fontSize: 12)),
                          selected: _detailedMode,
                          onSelected: (value) => setState(() => _detailedMode = value),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _fetchReport,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(_loading ? 'جارٍ...' : 'تحديث'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildSummaryCards(),
            const SizedBox(height: 12),
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

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'إجمالي الدخل',
                _incomeTotal,
                Colors.green,
                Icons.arrow_downward,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                'إجمالي المصروفات',
                _expenseTotal,
                Colors.red,
                Icons.arrow_upward,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'مصروفات الرواتب',
                _salaryTotal,
                Colors.orange,
                Icons.people,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                'صافي الربح',
                _net,
                _net >= 0 ? Colors.green : Colors.red,
                _net >= 0 ? Icons.trending_up : Icons.trending_down,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _currencyFormat.format(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails() {
    if (!_detailedMode) {
      return _buildStatsList();
    }
    return _buildCombinedList();
  }

  Widget _buildCombinedList() {
    final List<_CombinedEntry> combined = [];
    for (final e in _incomeEntries) {
      combined.add(_CombinedEntry(
        date: e.date,
        description: e.description,
        amount: e.amount,
        isIncome: true,
        isSalary: false,
        type: '',
      ));
    }
    for (final e in _expenseEntries) {
      combined.add(_CombinedEntry(
        date: e.date,
        description: e.description.isNotEmpty ? e.description : e.type,
        amount: e.amount,
        isIncome: false,
        isSalary: e.isSalary,
        type: e.type,
      ));
    }
    combined.sort((a, b) => b.date.compareTo(a.date));

    if (combined.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    return ListView.builder(
      cacheExtent: 500,
      itemCount: combined.length,
      itemBuilder: (context, index) {
        final entry = combined[index];
        final color = entry.isIncome
            ? Colors.green
            : (entry.isSalary ? Colors.orange : Colors.red);
        final icon = entry.isIncome
            ? Icons.arrow_downward
            : (entry.isSalary ? Icons.people : Icons.arrow_upward);

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 18,
              child: Icon(icon, color: color, size: 18),
            ),
            title: Text(entry.description, style: const TextStyle(fontSize: 12)),
            subtitle: Row(
              children: [
                Text(_dateFormat.format(entry.date), style: const TextStyle(fontSize: 10)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.isIncome ? 'دخل' : (entry.isSalary ? 'راتب' : 'مصروف'),
                    style: TextStyle(fontSize: 8, color: color),
                  ),
                ),
              ],
            ),
            trailing: Text(
              '${entry.isIncome ? '+' : '-'}${_currencyFormat.format(entry.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsList() {
    return Card(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_downward, color: Colors.green),
            title: const Text('عدد معاملات الدخل'),
            trailing: Text('${_incomeEntries.length}'),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward, color: Colors.red),
            title: const Text('عدد معاملات المصروفات'),
            trailing: Text('${_expenseEntries.length}'),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.people, color: Colors.orange),
            title: const Text('عدد معاملات الرواتب'),
            trailing: Text('${_expenseEntries.where((e) => e.isSalary).length}'),
          ),
        ],
      ),
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

class _CombinedEntry {
  _CombinedEntry({
    required this.date,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.isSalary,
    required this.type,
  });

  final DateTime date;
  final String description;
  final double amount;
  final bool isIncome;
  final bool isSalary;
  final String type;
}

class _ReportParams {
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> expenses;
  final DateTime fromDate;
  final DateTime toDate;

  _ReportParams({
    required this.payments,
    required this.expenses,
    required this.fromDate,
    required this.toDate,
  });
}

class _ReportResult {
  final List<_IncomeEntry> incomeEntries;
  final List<_ExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;

  _ReportResult({
    required this.incomeEntries,
    required this.expenseEntries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
    required this.net,
  });
}

_ReportResult _processReportData(_ReportParams params) {
  bool isWithinRange(DateTime date) {
    final endOfDay = DateTime(
      params.toDate.year,
      params.toDate.month,
      params.toDate.day,
      23, 59, 59,
    );
    return !date.isBefore(params.fromDate) && !date.isAfter(endOfDay);
  }

  bool isSalaryExpense(String type) {
    return type.trim().contains('راتب');
  }

  final incomeList = <_IncomeEntry>[];
  for (final p in params.payments) {
    final dateStr = (p['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
        dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr,
      );
    } catch (_) {
      continue;
    }
    if (!isWithinRange(dt)) continue;
    incomeList.add(
      _IncomeEntry(
        date: dt,
        description: 'دفعة حجز - ${p['guestName'] ?? ''}',
        amount: ((p['amount'] ?? 0) as num).toDouble(),
      ),
    );
  }

  final expenseList = <_ExpenseEntry>[];
  for (final e in params.expenses) {
    final dateStr = (e['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
        dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr,
      );
    } catch (_) {
      continue;
    }
    if (!isWithinRange(dt)) continue;
    final type = (e['type'] ?? '').toString();
    expenseList.add(
      _ExpenseEntry(
        date: dt,
        type: type,
        description: (e['description'] ?? '').toString(),
        amount: ((e['amount'] ?? 0) as num).toDouble(),
        isSalary: isSalaryExpense(type),
      ),
    );
  }

  incomeList.sort((a, b) => a.date.compareTo(b.date));
  expenseList.sort((a, b) => a.date.compareTo(b.date));

  final incTotal = incomeList.fold<double>(0, (s, e) => s + e.amount);
  final expTotal = expenseList.fold<double>(0, (s, e) => s + e.amount);
  final salTotal = expenseList
      .where((e) => e.isSalary)
      .fold<double>(0, (s, e) => s + e.amount);

  return _ReportResult(
    incomeEntries: incomeList,
    expenseEntries: expenseList,
    incomeTotal: incTotal,
    expenseTotal: expTotal,
    salaryTotal: salTotal,
    net: incTotal - expTotal,
  );
}
