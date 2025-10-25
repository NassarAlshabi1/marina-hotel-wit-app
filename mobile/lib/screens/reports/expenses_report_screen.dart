import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import '../../utils/pdf_utils.dart';

class ExpensesReportScreen extends ConsumerStatefulWidget {
  const ExpensesReportScreen({
    super.key,
    this.allowedTypes,
    this.initialType,
    this.title = 'تقرير المصروفات',
    this.typeLabel = 'نوع المصروف',
    this.showTypeFilter = true,
    this.includeEmployeeDetails = false,
  });

  final Set<String>? allowedTypes;
  final String? initialType;
  final String title;
  final String typeLabel;
  final bool showTypeFilter;
  final bool includeEmployeeDetails;

  @override
  ConsumerState<ExpensesReportScreen> createState() => _ExpensesReportScreenState();
}

class _ExpensesReportScreenState extends ConsumerState<ExpensesReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0.00', 'en_US');

  String _formatNumber(num value) => value.toStringAsFixed(0);
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
    _fromDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (widget.allowedTypes != null && widget.allowedTypes!.isNotEmpty) {
      setState(() {
        _availableTypes
          ..clear()
          ..addAll(widget.allowedTypes!.toList());
        _selectedType = widget.showTypeFilter ? (widget.initialType ?? widget.allowedTypes!.first) : null;
      });
    } else {
      await _loadExpenseTypes();
    }
    await _fetchReport();
  }

  Future<void> _loadExpenseTypes() async {
    final db = ref.read(coreProviders.dbProvider);
    final query = await db.customSelect('SELECT DISTINCT expense_type FROM expenses').get();
    final types = query.map((row) => row.data['expense_type'] as String).toList()..sort();
    setState(() {
      _availableTypes
        ..clear()
        ..addAll(types);
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate = isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
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
    final query = db.select(db.expenses);
    if (widget.allowedTypes != null && widget.allowedTypes!.isNotEmpty) {
      query.where((tbl) => tbl.expenseType.isIn(widget.allowedTypes!.toList()));
    }
    if (widget.showTypeFilter && _selectedType != null && _selectedType!.isNotEmpty) {
      query.where((tbl) => tbl.expenseType.equals(_selectedType!));
    }

    final expenses = await query.get();

    final employeeMap = <int, Employee>{};
    if (widget.includeEmployeeDetails) {
      final employeeIds = expenses.map((e) => e.relatedId).whereType<int>().toSet();
      if (employeeIds.isNotEmpty) {
        final employees = await (db.select(db.employees)..where((tbl) => tbl.id.isIn(employeeIds.toList()))).get();
        for (final employee in employees) {
          employeeMap[employee.id] = employee;
        }
      }
    }

    expenses.sort((a, b) => _parseExpenseDate(b.date).compareTo(_parseExpenseDate(a.date)));

    final rows = <_ExpenseReportRow>[];
    double totalAmount = 0;
    for (final expense in expenses) {
      final employee = expense.relatedId != null ? employeeMap[expense.relatedId!] : null;
      final date = _parseExpenseDate(expense.date);
      if (_fromDate != null && date.isBefore(_fromDate!)) {
        continue;
      }
      if (_toDate != null && date.isAfter(_toDate!)) {
        continue;
      }
      totalAmount += expense.amount;
      rows.add(_ExpenseReportRow(
        date: date,
        amount: expense.amount,
        type: expense.expenseType,
        description: expense.description,
        employee: employee,
      ));
    }

    return _ExpensesReportResult(rows: rows, totalAmount: totalAmount);
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final fonts = await PdfUtils.loadArabicFonts();
    final logo = await PdfUtils.loadLogoImage();
    final doc = pw.Document();
    final fromLabel = _fromDate != null ? DateFormat('yyyy-MM-dd').format(_fromDate!) : 'غير محدد';
    final toLabel = _toDate != null ? DateFormat('yyyy-MM-dd').format(_toDate!) : 'غير محدد';
    final typeLabel = _selectedType?.isNotEmpty == true ? _selectedType! : 'الكل';
    final summaryEntries = [
      MapEntry('إجمالي المصروفات', _formatNumber(_totalAmount)),
      MapEntry('عدد السجلات', _rows.length.toString()),
    ];

    final headers = <String>['التاريخ', 'المبلغ', 'النوع', 'الوصف'];
    if (widget.includeEmployeeDetails) {
      headers.add('الموظف');
    }

    pw.Widget buildSummaryTable() {
      return pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        children: summaryEntries
            .map(
              (entry) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(entry.key, style: pw.TextStyle(font: fonts.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(entry.value, style: pw.TextStyle(font: fonts.base)),
                  ),
                ],
              ),
            )
            .toList(),
      );
    }

    final dataRows = _rows.map((row) {
      final cells = [
        _dateLabelFormat.format(row.date),
        _formatNumber(row.amount),
        row.type,
        row.description,
      ];
      if (widget.includeEmployeeDetails) {
        cells.add(row.employee?.name ?? 'غير محدد');
      }
      return cells;
    }).toList();

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: fonts.base, fontSize: 10),
          ),
        ),
        build: (context) {
          return [
            if (logo != null)
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Image(logo, width: 80),
              ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('فندق مارينا بلازا', style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
                  pw.Text('القاهرة - شارع احمد قاسم • رقم الهاتف 02324457', style: pw.TextStyle(font: fonts.base, fontSize: 8)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(widget.title, style: pw.TextStyle(font: fonts.bold, fontSize: 20)),
            pw.SizedBox(height: 8),
            pw.Text('الفترة: من $fromLabel إلى $toLabel'),
            pw.Text('${widget.typeLabel}: $typeLabel'),
            pw.SizedBox(height: 12),
            buildSummaryTable(),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: headers,
              headerStyle: pw.TextStyle(font: fonts.bold),
              cellStyle: pw.TextStyle(font: fonts.base),
              data: dataRows,
              cellAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(width: 0.5),
            ),
          ];
        },
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'expenses-report.pdf');
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDateSelector(label: 'من تاريخ', value: _fromDate, onPressed: () => _pickDate(isFrom: true)),
                _buildDateSelector(label: 'إلى تاريخ', value: _toDate, onPressed: () => _pickDate(isFrom: false)),
                if (widget.showTypeFilter)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      value: _selectedType,
                      decoration: InputDecoration(labelText: widget.typeLabel),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('الكل'),
                        ),
                        ..._availableTypes.map(
                          (type) => DropdownMenuItem<String?>(
                            value: type,
                            child: Text(type),
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
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search),
                  label: _loading ? const Text('جارٍ التحميل...') : const Text('عرض النتائج'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSummary(),
            const SizedBox(height: 16),
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
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            return Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _dateLabelFormat.format(row.date),
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text('${_currencyFmt.format(row.amount)} ر.س'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('النوع: ${row.type}'),
                                    const SizedBox(height: 4),
                                    Text('الوصف: ${row.description}'),
                                    if (widget.includeEmployeeDetails && row.employee != null) ...[
                                      const SizedBox(height: 4),
                                      Text('الموظف: ${row.employee!.name}'),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: _buildSummaryTile('إجمالي المصروفات', _currencyFmt.format(_totalAmount))),
            Expanded(child: _buildSummaryTile('عدد السجلات', _rows.length.toString())),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }

  Widget _buildDateSelector({required String label, required DateTime? value, required VoidCallback onPressed}) {
    final text = value != null ? DateFormat('yyyy-MM-dd').format(value) : 'غير محدد';
    return SizedBox(
      width: 180,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.date_range),
        label: Text('$label\n$text', textAlign: TextAlign.center),
      ),
    );
  }

  DateTime _parseExpenseDate(String value) {
    final trimmed = value.trim();
    final hasTime = trimmed.length > 10;
    final normalized = hasTime ? trimmed.replaceFirst(' ', 'T') : '${trimmed}T00:00:00';
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
