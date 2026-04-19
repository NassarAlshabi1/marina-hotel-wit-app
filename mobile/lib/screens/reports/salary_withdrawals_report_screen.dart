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

/// أنواع المصروفات المتعلقة بالرواتب
const _salaryTypes = {
  'salary',
  'salaries',
  'salary_withdrawal',
  'salary-withdrawal',
  'salary_deduction',
  'salary-deduction',
  'رواتب',
  'سحب راتب',
  'سحب من الراتب',
  'خصم راتب',
  'خصم من الراتب',
};

/// أنواع الخصم (كل ما عداها يعتبر سحب)
const _deductionTypes = {'خصم راتب', 'خصم من الراتب', 'salary_deduction', 'salary-deduction'};

bool _isDeduction(String type) => _deductionTypes.contains(type);

/// بيانات معاملة واحدة
class _SalaryTxRow {
  _SalaryTxRow({
    required this.id,
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
    required this.employee,
  });

  final int id;
  final DateTime date;
  final double amount;
  final String type;
  final String description;
  final Employee? employee;
}

/// بيانات مجمعة لموظف واحد
class _EmployeeSalaryGroup {
  _EmployeeSalaryGroup({required this.employee});

  final Employee? employee;
  final List<_SalaryTxRow> transactions = [];
  double totalWithdrawals = 0;
  double totalDeductions = 0;
  int withdrawalCount = 0;
  int deductionCount = 0;

  double get total => totalWithdrawals + totalDeductions;
  int get txCount => transactions.length;
}

class SalaryWithdrawalsReportScreen extends ConsumerStatefulWidget {
  const SalaryWithdrawalsReportScreen({super.key});

  @override
  ConsumerState<SalaryWithdrawalsReportScreen> createState() =>
      _SalaryWithdrawalsReportScreenState();
}

class _SalaryWithdrawalsReportScreenState
    extends ConsumerState<SalaryWithdrawalsReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final _filterController = DateFilterController();
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');
  final DateFormat _timeFormat = DateFormat('HH:mm');
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;
  bool _initialized = false;

  final List<_SalaryTxRow> _allRows = [];
  final Map<int, _EmployeeSalaryGroup> _employeeGroups = {};

  double _grandTotal = 0;
  double _grandWithdrawals = 0;
  double _grandDeductions = 0;
  int _totalTxCount = 0;
  int _totalEmployees = 0;

  String _sortBy = 'employee'; // 'employee', 'amount', 'date'

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
    await _fetchReport();
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final db = ref.read(coreProviders.dbProvider);
      final result = await _loadSalaryData(db);
      setState(() {
        _allRows
          ..clear()
          ..addAll(result.rows);
        _employeeGroups
          ..clear()
          ..addAll(result.groups);
        _grandTotal = result.grandTotal;
        _grandWithdrawals = result.grandWithdrawals;
        _grandDeductions = result.grandDeductions;
        _totalTxCount = result.rows.length;
        _totalEmployees = result.groups.length;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_SalaryReportData> _loadSalaryData(AppDatabase db) async {
    final outboxDao = OutboxDao(db);
    final expensesDao = ExpensesDao(db, outboxDao);

    final fromStr = _fromDate != null
        ? '${DateFormat('yyyy-MM-dd HH:mm:ss').format(_fromDate!)}'
        : null;
    final toStr = _toDate != null
        ? '${DateFormat('yyyy-MM-dd HH:mm:ss').format(_toDate!)}'
        : null;

    var expenses = await expensesDao.listFiltered(from: fromStr, to: toStr);
    expenses = expenses.where((e) => _salaryTypes.contains(e.expenseType)).toList();

    // جلب بيانات الموظفين
    final employeeMap = <int, Employee>{};
    final employeeIds = expenses.map((e) => e.relatedId).whereType<int>().toSet();
    if (employeeIds.isNotEmpty) {
      final employees = await (db.select(db.employees)
            ..where((tbl) => tbl.id.isIn(employeeIds.toList())))
          .get();
      for (final emp in employees) {
        employeeMap[emp.id] = emp;
      }
    }

    // بناء الصفوف
    final rows = <_SalaryTxRow>[];
    for (final expense in expenses) {
      final employee = expense.relatedId != null ? employeeMap[expense.relatedId!] : null;
      final date = _parseDate(expense.date);
      rows.add(_SalaryTxRow(
        id: expense.id,
        date: date,
        amount: expense.amount,
        type: expense.expenseType,
        description: expense.description,
        employee: employee,
      ));
    }

    // تجميع حسب الموظف
    final groups = <int, _EmployeeSalaryGroup>{};
    double grandW = 0, grandD = 0;

    // أولوية: ترتيب حسب التاريخ الأحدث
    rows.sort((a, b) => b.date.compareTo(a.date));

    for (final row in rows) {
      final empId = row.employee?.id ?? 0;
      groups.putIfAbsent(empId, () => _EmployeeSalaryGroup(employee: row.employee));
      final group = groups[empId]!;
      group.transactions.add(row);

      if (_isDeduction(row.type)) {
        group.totalDeductions += row.amount;
        group.deductionCount++;
        grandD += row.amount;
      } else {
        group.totalWithdrawals += row.amount;
        group.withdrawalCount++;
        grandW += row.amount;
      }
    }

    // ترتيب المجموعات حسب المبلغ الأعلى
    final sortedEntries = groups.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final orderedGroups = <int, _EmployeeSalaryGroup>{
      for (final entry in sortedEntries) entry.key: entry.value,
    };

    return _SalaryReportData(
      rows: rows,
      groups: orderedGroups,
      grandTotal: grandW + grandD,
      grandWithdrawals: grandW,
      grandDeductions: grandD,
    );
  }

  // ─── PDF: بدون تغيير ───
  Future<void> _exportPdf() async {
    if (_allRows.isEmpty) return;
    final fromLabel = _fromDate != null
        ? DateFormat('yyyy-MM-dd').format(_fromDate!)
        : 'غير محدد';
    final toLabel = _toDate != null
        ? DateFormat('yyyy-MM-dd').format(_toDate!)
        : 'غير محدد';

    final headers = <String>['التاريخ', 'المبلغ', 'النوع', 'الوصف', 'الموظف'];

    final dataRows = <List<String>>[];
    for (final row in _allRows) {
      dataRows.add([
        _dateLabelFormat.format(row.date),
        EnhancedPdfUtils.formatNumber(row.amount),
        row.type,
        row.description.isNotEmpty ? row.description : '-',
        row.employee?.name ?? 'غير محدد',
      ]);
    }

    dataRows.add([
      'إجمالي سحبيات الرواتب',
      EnhancedPdfUtils.formatNumber(_grandTotal),
      '',
      '',
      '',
    ]);

    await ReportPdfBuilder.buildAndShare(ReportPdfConfig(
      title: 'تقرير سحبيات الرواتب',
      fromDate: _fromDate,
      toDate: _toDate,
      buildContent: (fonts) {
        pw.Widget metaRow(String label, String value) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(label,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                pw.Text(value,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 11)),
              ],
            ),
          );
        }

        final metaInfoCard = EnhancedPdfUtils.buildInfoCard(
          title: 'تقرير سحبيات الرواتب',
          fonts: fonts,
          content: [
            metaRow('الفترة', 'من $fromLabel إلى $toLabel'),
            metaRow('عدد السجلات', '${_allRows.length}'),
          ],
        );

        pw.Widget buildSummaryItem(
            String title, String value, PdfColor accent) {
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
                pw.Text(title,
                    style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 11,
                        color: PdfColors.textDark)),
                pw.SizedBox(height: 4),
                pw.Text(value,
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 16, color: accent)),
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
                    'إجمالي سحبيات الرواتب',
                    EnhancedPdfUtils.formatNumber(_grandTotal),
                    PdfColors.secondary,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: buildSummaryItem(
                    'عدد السجلات',
                    _allRows.length.toString(),
                    PdfColors.info,
                  ),
                ),
              ],
            ),
          ),
        ];
      },
      fileName: ReportPdfBuilder.generateFileName('تقرير سحبيات الرواتب'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'تقرير سحبيات الرواتب',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort, size: 20),
          tooltip: 'ترتيب',
          onSelected: (value) {
            setState(() => _sortBy = value);
            _reorderGroups();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'employee',
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 16),
                  SizedBox(width: 8),
                  Text('ترتيب حسب الموظف'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'amount',
              child: Row(
                children: [
                  Icon(Icons.payments_outlined, size: 16),
                  SizedBox(width: 8),
                  Text('ترتيب حسب المبلغ'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'date',
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 16),
                  SizedBox(width: 8),
                  Text('ترتيب حسب التاريخ'),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: _allRows.isEmpty ? null : _exportPdf,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // فلتر التاريخ
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
            const SizedBox(height: 8),
            // زر البحث
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(_loading ? 'جارٍ...' : 'بحث'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // الملخص التفصيلي
            _buildOverallSummary(theme),
            const SizedBox(height: 8),
            // قائمة الموظفين مع تفاصيل المعاملات
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _allRows.isEmpty
                      ? const EmptyState(
                          title: 'لا توجد بيانات',
                          message: 'لم يتم العثور على سحبيات رواتب ضمن النطاق المحدد.',
                          icon: Icons.account_balance_wallet,
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 8),
                          children: _buildEmployeeList(theme),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _reorderGroups() {
    final entries = _employeeGroups.entries.toList();

    switch (_sortBy) {
      case 'amount':
        entries.sort((a, b) => b.value.total.compareTo(a.value.total));
        break;
      case 'date':
        entries.sort((a, b) {
          final aDate = a.value.transactions.isNotEmpty
              ? a.value.transactions.first.date
              : DateTime(2000);
          final bDate = b.value.transactions.isNotEmpty
              ? b.value.transactions.first.date
              : DateTime(2000);
          return bDate.compareTo(aDate);
        });
        break;
      case 'employee':
      default:
        entries.sort((a, b) {
          final aName = a.value.employee?.name ?? '';
          final bName = b.value.employee?.name ?? '';
          return aName.compareTo(bName);
        });
    }

    setState(() {
      _employeeGroups.clear();
      for (final entry in entries) {
        _employeeGroups[entry.key] = entry.value;
      }
    });
  }

  /// الملخص العام في الأعلى
  Widget _buildOverallSummary(ThemeData theme) {
    if (_allRows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.purple.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        children: [
          // الصف الأول: الإجمالي العام
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.purple,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currencyFmt.format(_grandTotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: Colors.purple,
                      ),
                    ),
                    const Text(
                      'إجمالي سحبيات الرواتب',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey, height: 1.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // الصف الثاني: السحوبات والخصومات والموظفين
          Row(
            children: [
              _buildSummaryStatCard(
                icon: Icons.call_made,
                label: 'السحوبات',
                value: _currencyFmt.format(_grandWithdrawals),
                count: '${_employeeGroups.values.fold<int>(0, (sum, g) => sum + g.withdrawalCount)} عملية',
                color: Colors.orange,
                bgColor: Colors.orange.shade50,
              ),
              const SizedBox(width: 8),
              _buildSummaryStatCard(
                icon: Icons.call_received,
                label: 'الخصومات',
                value: _currencyFmt.format(_grandDeductions),
                count: '${_employeeGroups.values.fold<int>(0, (sum, g) => sum + g.deductionCount)} عملية',
                color: Colors.red,
                bgColor: Colors.red.shade50,
              ),
              const SizedBox(width: 8),
              _buildSummaryStatCard(
                icon: Icons.people_outline,
                label: 'الموظفين',
                value: '$_totalEmployees',
                count: '$_totalTxCount عملية',
                color: Colors.blue,
                bgColor: Colors.blue.shade50,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String count,
    required Color color,
    required Color bgColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              count,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء قائمة الموظفين مع تفاصيل المعاملات
  List<Widget> _buildEmployeeList(ThemeData theme) {
    final widgets = <Widget>[];
    final entries = _employeeGroups.entries.toList();

    for (int i = 0; i < entries.length; i++) {
      final group = entries[i].value;
      widgets.add(_buildEmployeeCard(group, rank: i + 1));
      if (i < entries.length - 1) const SizedBox(height: 8);
    }

    return widgets;
  }

  /// بطاقة الموظف مع التفاصيل القابلة للتوسيع
  Widget _buildEmployeeCard(_EmployeeSalaryGroup group, {required int rank}) {
    final emp = group.employee;
    final empName = emp?.name ?? 'موظف غير محدد';

    final hasWithdrawals = group.withdrawalCount > 0;
    final hasDeductions = group.deductionCount > 0;

    // حساب النسبة من الإجمالي
    final pct = _grandTotal > 0 ? (group.total / _grandTotal * 100) : 0;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
          initiallyExpanded: rank <= 3, // توسيع أول 3 موظفين تلقائياً
          shape: const Border(),
          collapsedShape: const Border(),

          // ─── الرأس (عند الطي) ───
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.purple.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currencyFmt.format(group.total),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  Text(
                    '${group.txCount} عملية',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              children: [
                // شريط التقدم
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0, 1),
                          backgroundColor: Colors.grey.shade100,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.purple.shade300),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                // ملخص سريع: سحوبات وخصومات
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (hasWithdrawals) ...[
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.call_made,
                                size: 11, color: Colors.orange.shade700),
                            const SizedBox(width: 3),
                            Text(
                              'سحب ${_currencyFmt.format(group.totalWithdrawals)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (hasWithdrawals && hasDeductions)
                      const SizedBox(width: 6),
                    if (hasDeductions) ...[
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.call_received,
                                size: 11, color: Colors.red.shade700),
                            const SizedBox(width: 3),
                            Text(
                              'خصم ${_currencyFmt.format(group.totalDeductions)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                  ],
                ),
              ],
            ),
          ),

          // ─── المحتوى عند التوسيع ───
          children: [
            // ملخص تفصيلي للموظف
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildDetailRow('إجمالي السحوبات', _currencyFmt.format(group.totalWithdrawals),
                      '${group.withdrawalCount} عملية', Colors.orange),
                  const SizedBox(height: 4),
                  _buildDetailRow('إجمالي الخصومات', _currencyFmt.format(group.totalDeductions),
                      '${group.deductionCount} عملية', Colors.red),
                  const Divider(height: 16),
                  _buildDetailRow('الإجمالي الكلي', _currencyFmt.format(group.total),
                      '${group.txCount} عملية', Colors.purple, bold: true),
                ],
              ),
            ),
            // عنوان المعاملات
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'تفاصيل المعاملات:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // قائمة المعاملات
            ...group.transactions.map((tx) => _buildTransactionRow(tx)),
          ],
        ),
      ),
    );
  }

  /// صف تفصيلي داخل ملخص الموظف
  Widget _buildDetailRow(
    String label,
    String value,
    String sub,
    Color color, {
    bool bold = false,
  }) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          sub,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  /// صف معاملة واحد
  Widget _buildTransactionRow(_SalaryTxRow tx) {
    final isDed = _isDeduction(tx.type);
    final accentColor = isDed ? Colors.red : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الصف الرئيسي: النوع + التاريخ + المبلغ
          Row(
            children: [
              // شارة النوع
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDed ? Icons.remove_circle_outline : Icons.account_balance_wallet,
                      size: 12,
                      color: accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDed ? 'خصم راتب' : 'سحب راتب',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // التاريخ والوقت
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(
                      _dateLabelFormat.format(tx.date),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.access_time, size: 11, color: Colors.grey.shade300),
                    const SizedBox(width: 3),
                    Text(
                      _timeFormat.format(tx.date),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              // المبلغ
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _currencyFmt.format(tx.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          // الوصف
          if (tx.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tx.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  DateTime _parseDate(String value) {
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

/// نتيجة تحميل بيانات التقرير
class _SalaryReportData {
  _SalaryReportData({
    required this.rows,
    required this.groups,
    required this.grandTotal,
    required this.grandWithdrawals,
    required this.grandDeductions,
  });

  final List<_SalaryTxRow> rows;
  final Map<int, _EmployeeSalaryGroup> groups;
  final double grandTotal;
  final double grandWithdrawals;
  final double grandDeductions;
}
