import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../widgets/report_date_filter.dart';

/// بيانات معاملة واحدة من جدول salary_withdrawals
class _SalaryTxRow {
  _SalaryTxRow({
    required this.id,
    required this.date,
    required this.amount,
    required this.withdrawalType,
    required this.reason,
    required this.description,
    required this.employee,
  });

  final int id;
  final DateTime date;
  final double amount;
  final String withdrawalType;
  final String reason;
  final String description;
  final Employee? employee;
}

/// بيانات مجمعة لموظف واحد
class _EmployeeSalaryGroup {
  _EmployeeSalaryGroup({required this.employee});

  final Employee? employee;
  final List<_SalaryTxRow> transactions = [];
  double totalAmount = 0;
  int txCount = 0;
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
  final List<Employee> _allEmployees = [];

  String _sortBy = 'date';
  int? _selectedEmployeeId; // null = الكل

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initializeDefaults();
    }
  }

  Future<void> _initializeDefaults() async {
    // افتراضي: بداية الشهر الحالي
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    await _fetchReport();
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final result = await _loadSalaryData(db);
      setState(() {
        _allEmployees
          ..clear()
          ..addAll(result.allEmployees);
        _allRows
          ..clear()
          ..addAll(result.rows);
        _employeeGroups
          ..clear()
          ..addAll(result.groups);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_SalaryReportData> _loadSalaryData(AppDatabase db) async {
    // جلب كل الموظفين للقائمة المنسدلة
    final allEmployees = await (db.select(db.employees)
          ..where((tbl) => tbl.deletedAt.isNull()))
        .get();
    allEmployees.sort((a, b) => a.name.compareTo(b.name));

    // جلب سجلات salary_withdrawals مع فلترة التاريخ
    var query = db.select(db.salaryWithdrawals)
      ..where((tbl) => tbl.deletedAt.isNull());

    final fromStr = _fromDate != null
        ? '${DateFormat('yyyy-MM-dd').format(_fromDate!)}'
        : null;
    final toStr = _toDate != null
        ? '${DateFormat('yyyy-MM-dd').format(_toDate!)}'
        : null;

    if (fromStr != null) {
      query = query..where((tbl) => tbl.withdrawDate.isBiggerOrEqualValue(fromStr));
    }
    if (toStr != null) {
      query = query..where((tbl) => tbl.withdrawDate.isSmallerOrEqualValue('${toStr}T23:59:59'));
    }

    // فلترة حسب الموظف المحدد
    if (_selectedEmployeeId != null) {
      query = query..where((tbl) => tbl.employeeId.equals(_selectedEmployeeId!));
    }

    var withdrawals = await query.get();

    // بناء خريطة الموظفين
    final employeeMap = <int, Employee>{};
    for (final emp in allEmployees) {
      employeeMap[emp.id] = emp;
    }

    // بناء الصفوف
    final rows = <_SalaryTxRow>[];
    for (final sw in withdrawals) {
      final employee = employeeMap[sw.employeeId];
      final date = _parseDate(sw.withdrawDate);
      rows.add(_SalaryTxRow(
        id: sw.id,
        date: date,
        amount: sw.amount,
        withdrawalType: sw.withdrawalType ?? '',
        reason: sw.reason ?? '',
        description: sw.description ?? '',
        employee: employee,
      ));
    }

    // ترتيب حسب التاريخ الأحدث
    rows.sort((a, b) => b.date.compareTo(a.date));

    // تجميع حسب الموظف
    final groups = <int, _EmployeeSalaryGroup>{};
    for (final row in rows) {
      final empId = row.employee?.id ?? 0;
      groups.putIfAbsent(empId, () => _EmployeeSalaryGroup(employee: row.employee));
      final group = groups[empId]!;
      group.transactions.add(row);
      group.totalAmount += row.amount;
      group.txCount++;
    }

    return _SalaryReportData(
      rows: rows,
      groups: groups,
      allEmployees: allEmployees,
    );
  }

  // ─── PDF ───
  Future<void> _exportPdf() async {
    // استخدام البيانات المفلترة (حسب الموظف المحدد أو الكل)
    final rows = _filteredRows;
    if (rows.isEmpty) return;

    final selectedEmpName = _selectedEmployeeId != null
        ? _allEmployees.where((e) => e.id == _selectedEmployeeId).firstOrNull?.name
        : null;

    final headers = _selectedEmployeeId != null
        ? <String>['التاريخ', 'المبلغ', 'النوع', 'السبب', 'الملاحظات']
        : <String>['التاريخ', 'المبلغ', 'النوع', 'السبب', 'الملاحظات', 'الموظف'];

    final dataRows = <List<String>>[];
    for (final row in rows) {
      // تنظيف حقل السبب: إذا كان يبدأ بـ "exp_" يُعتبر ربط داخلي، لا يُعرض
      String displayReason = '-';
      if (row.reason.isNotEmpty && !row.reason.startsWith('exp_')) {
        displayReason = row.reason;
      }

      final cells = <String>[
        _dateLabelFormat.format(row.date),
        EnhancedPdfUtils.formatNumber(row.amount),
        row.withdrawalType.isNotEmpty ? row.withdrawalType : 'سحب',
        displayReason,
        row.description.isNotEmpty ? row.description : '-',
      ];
      if (_selectedEmployeeId == null) {
        cells.add(row.employee?.name ?? 'غير محدد');
      }
      dataRows.add(cells);
    }

    final totalAmount = rows.fold<double>(0, (sum, r) => sum + r.amount);
    final emptyCells = List.filled(headers.length, '');
    dataRows.add([
      'الإجمالي',
      EnhancedPdfUtils.formatNumber(totalAmount),
      ...emptyCells.sublist(2),
    ]);

    await ReportPdfBuilder.buildAndShare(ReportPdfConfig(
      title: 'تقرير سحبيات الرواتب',
      fromDate: _fromDate,
      toDate: _toDate,
      buildContent: (fonts) {
        final fromLabel = _fromDate != null
            ? DateFormat('yyyy-MM-dd').format(_fromDate!)
            : 'غير محدد';
        final toLabel = _toDate != null
            ? DateFormat('yyyy-MM-dd').format(_toDate!)
            : 'غير محدد';

        return [
          pw.SizedBox(height: 16),
          EnhancedPdfUtils.buildInfoCard(
            title: 'تقرير سحبيات الرواتب',
            fonts: fonts,
            content: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الفترة',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                    pw.Text('من $fromLabel إلى $toLabel',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 11)),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الموظف',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                    pw.Text(selectedEmpName ?? 'الكل',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 11)),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('عدد السجلات',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                    pw.Text('${rows.length}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: headers,
            data: dataRows,
            fonts: fonts,
            headerColor: PdfColors.primary,
            alternateRowColor: PdfColors.backgroundLight,
          ),
        ];
      },
      fileName: ReportPdfBuilder.generateFileName(
        selectedEmpName != null
            ? 'سحبيات راتب $selectedEmpName'
            : 'تقرير سحبيات الرواتب',
      ),
    ));
  }

  List<_SalaryTxRow> get _filteredRows {
    if (_selectedEmployeeId == null) return _allRows;
    return _allRows.where((r) => r.employee?.id == _selectedEmployeeId).toList();
  }

  Map<int, _EmployeeSalaryGroup> get _filteredGroups {
    if (_selectedEmployeeId == null) return _employeeGroups;
    final filtered = <int, _EmployeeSalaryGroup>{};
    final g = _employeeGroups[_selectedEmployeeId];
    if (g != null) filtered[_selectedEmployeeId!] = g;
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredRows = _filteredRows;
    final filteredGroups = _filteredGroups;
    final totalFiltered = filteredRows.fold<double>(0, (sum, r) => sum + r.amount);

    return AppScaffold(
      title: 'تقرير سحبيات الرواتب',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: filteredRows.isEmpty ? null : _exportPdf,
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

            // القائمة المنسدلة للموظف + زر البحث
            Row(
              children: [
                // القائمة المنسدلة
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedEmployeeId,
                        isExpanded: true,
                        hint: const Text(
                          'عرض بحسب الموظف',
                          style: TextStyle(fontSize: 13),
                        ),
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Row(
                              children: [
                                Icon(Icons.people, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('الكل', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          ..._allEmployees.map((emp) {
                            return DropdownMenuItem<int?>(
                              value: emp.id,
                              child: Row(
                                children: [
                                  const Icon(Icons.person, size: 18, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      emp.name,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedEmployeeId = value);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // زر البحث
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

            // شريط إجمالي مبسط
            if (filteredRows.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedEmployeeId != null
                            ? 'سحبيات: ${_allEmployees.where((e) => e.id == _selectedEmployeeId).firstOrNull?.name ?? ""} — ${filteredRows.length} عملية'
                            : 'جميع الموظفين — ${filteredRows.length} عملية',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                    Text(
                      '${_currencyFmt.format(totalFiltered)} ريال',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // قائمة المعاملات
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredRows.isEmpty
                      ? const EmptyState(
                          title: 'لا توجد بيانات',
                          message: 'لم يتم العثور على سحبيات رواتب ضمن النطاق المحدد.',
                          icon: Icons.account_balance_wallet,
                        )
                      : _selectedEmployeeId == null
                          ? ListView(
                              padding: const EdgeInsets.only(bottom: 8),
                              children: _buildGroupedList(filteredGroups),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: filteredRows.length,
                              itemBuilder: (context, index) =>
                                  _buildTransactionRow(filteredRows[index]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء القائمة مجمععة حسب الموظف (عند اختيار "الكل")
  List<Widget> _buildGroupedList(Map<int, _EmployeeSalaryGroup> groups) {
    final widgets = <Widget>[];
    final entries = groups.entries.toList();

    // ترتيب
    switch (_sortBy) {
      case 'amount':
        entries.sort((a, b) => b.value.totalAmount.compareTo(a.value.totalAmount));
        break;
      case 'employee':
        entries.sort((a, b) {
          final aName = a.value.employee?.name ?? '';
          final bName = b.value.employee?.name ?? '';
          return aName.compareTo(bName);
        });
        break;
      case 'date':
      default:
        // ترتيب حسب أحدث معاملة
        entries.sort((a, b) {
          final aDate = a.value.transactions.isNotEmpty
              ? a.value.transactions.first.date
              : DateTime(2000);
          final bDate = b.value.transactions.isNotEmpty
              ? b.value.transactions.first.date
              : DateTime(2000);
          return bDate.compareTo(aDate);
        });
    }

    for (int i = 0; i < entries.length; i++) {
      final group = entries[i].value;
      widgets.add(_buildEmployeeCard(group, rank: i + 1));
      if (i < entries.length - 1) const SizedBox(height: 8);
    }

    return widgets;
  }

  /// بطاقة الموظف مع التفاصيل القابلة للتوسيع
  Widget _buildEmployeeCard(_EmployeeSalaryGroup group, {required int rank}) {
    final empName = group.employee?.name ?? 'موظف غير محدد';

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
          initiallyExpanded: rank <= 3,
          shape: const Border(),
          collapsedShape: const Border(),

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
                child: Text(
                  empName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currencyFmt.format(group.totalAmount),
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
          children: [
            ...group.transactions.map((tx) => _buildTransactionRow(tx)),
          ],
        ),
      ),
    );
  }

  /// صف معاملة واحد
  Widget _buildTransactionRow(_SalaryTxRow tx) {
    final isDeduction = tx.withdrawalType.contains('deduction') ||
        tx.withdrawalType.contains('خصم');
    final accentColor = isDeduction ? Colors.red : Colors.orange;
    final typeLabel = isDeduction ? 'خصم' : 'سحب';
    final typeIcon = isDeduction ? Icons.remove_circle_outline : Icons.account_balance_wallet;

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
                    Icon(typeIcon, size: 12, color: accentColor),
                    const SizedBox(width: 4),
                    Text(
                      typeLabel,
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
          // السبب
          if (tx.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.label_outline, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tx.reason,
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
          // الوصف
          if (tx.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tx.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      height: 1.4,
                    ),
                    maxLines: 2,
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
    required this.allEmployees,
  });

  final List<_SalaryTxRow> rows;
  final Map<int, _EmployeeSalaryGroup> groups;
  final List<Employee> allEmployees;
}
