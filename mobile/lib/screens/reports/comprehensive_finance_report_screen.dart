import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';

const List<String> _arabicMonths = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

class ComprehensiveFinanceReportScreen extends ConsumerStatefulWidget {
  const ComprehensiveFinanceReportScreen({super.key});

  @override
  ConsumerState<ComprehensiveFinanceReportScreen> createState() =>
      _ComprehensiveFinanceReportScreenState();
}

class _ComprehensiveFinanceReportScreenState
    extends ConsumerState<ComprehensiveFinanceReportScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  List<int> _availableYears = [];
  int _selectedYear = DateTime.now().year;
  DateTime? _fromDate;
  DateTime? _toDate;

  bool _loading = true;
  String? _error;

  double _totalRevenue = 0;
  double _totalExpenses = 0;
  List<_MonthlyFinanceRow> _monthlyRows = const [];
  List<_YearlyFinanceRow> _yearlyRows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
    });
    final db = ref.read(coreProviders.dbProvider);
    try {
      final years = await _collectAvailableYears(db);
      final defaultYear = years.isNotEmpty ? years.last : DateTime.now().year;
      final from = DateTime(defaultYear, 1, 1);
      final to = DateTime(defaultYear, 12, 31, 23, 59, 59);
      final report = await _loadReportData(
        db: db,
        selectedYear: defaultYear,
        from: from,
        to: to,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _availableYears = years.isNotEmpty ? years : [defaultYear];
        if (!_availableYears.contains(defaultYear)) {
          _availableYears.add(defaultYear);
          _availableYears.sort();
        }
        _selectedYear = defaultYear;
        _fromDate = from;
        _toDate = to;
        _applyReport(report);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل البيانات';
      });
    }
  }

  void _applyReport(_FinanceReportData data) {
    _totalRevenue = data.totalRevenue;
    _totalExpenses = data.totalExpenses;
    _monthlyRows = data.monthlyRows;
    _yearlyRows = data.yearlyRows;
  }

  Future<void> _fetchReport() async {
    final from = _fromDate;
    final to = _toDate;
    if (from == null || to == null) {
      return;
    }
    if (from.isAfter(to)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('يرجى التأكد من أن تاريخ البداية قبل تاريخ النهاية')),
        );
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final db = ref.read(coreProviders.dbProvider);
    try {
      final report = await _loadReportData(
        db: db,
        selectedYear: _selectedYear,
        from: from,
        to: to,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyReport(report);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل البيانات';
      });
    }
  }

  Future<_FinanceReportData> _loadReportData({
    required AppDatabase db,
    required int selectedYear,
    required DateTime from,
    required DateTime to,
  }) async {
    final rangeCollections =
        await _fetchCollections(db: db, from: from, to: to);
    final yearStart = DateTime(selectedYear, 1, 1);
    final yearEnd = DateTime(selectedYear, 12, 31, 23, 59, 59);
    final selectedYearCollections =
        await _fetchCollections(db: db, from: yearStart, to: yearEnd);

    final previousYear = selectedYear - 1;
    _FinanceCollections? previousYearCollections;
    if (previousYear > 0) {
      final prevStart = DateTime(previousYear, 1, 1);
      final prevEnd = DateTime(previousYear, 12, 31, 23, 59, 59);
      previousYearCollections =
          await _fetchCollections(db: db, from: prevStart, to: prevEnd);
    }

    final aggregatedRange = _aggregateRange(rangeCollections);
    final yearlyRows = <_YearlyFinanceRow>[
      _buildYearlyRow(selectedYear, selectedYearCollections)
    ];
    if (previousYearCollections != null) {
      yearlyRows.add(_buildYearlyRow(previousYear, previousYearCollections));
    }

    yearlyRows.sort((a, b) => b.year.compareTo(a.year));

    return _FinanceReportData(
      totalRevenue: aggregatedRange.totalRevenue,
      totalExpenses: aggregatedRange.totalExpense,
      monthlyRows: aggregatedRange.monthlyRows,
      yearlyRows: yearlyRows,
    );
  }

  Future<_FinanceCollections> _fetchCollections({
    required AppDatabase db,
    required DateTime from,
    required DateTime to,
  }) async {
    final fromIso = from.toIso8601String();
    final toIso = to.toIso8601String();

    final paymentsQuery = db.select(db.payments)
      ..where((tbl) => tbl.deletedAt.isNull())
      ..where((tbl) => tbl.paymentDate.isBiggerOrEqualValue(fromIso))
      ..where((tbl) => tbl.paymentDate.isSmallerOrEqualValue(toIso));
    final payments = await paymentsQuery.get();

    final cashQuery = db.select(db.cashTransactions)
      ..where((tbl) => tbl.deletedAt.isNull())
      ..where((tbl) => tbl.transactionTime.isBiggerOrEqualValue(fromIso))
      ..where((tbl) => tbl.transactionTime.isSmallerOrEqualValue(toIso));
    final cashTransactions = await cashQuery.get();

    final fromDateString = _dateFormat.format(from);
    final toDateString = _dateFormat.format(to);
    final expensesQuery = db.select(db.expenses)
      ..where((tbl) => tbl.deletedAt.isNull())
      ..where((tbl) => tbl.date.isBiggerOrEqualValue(fromDateString))
      ..where((tbl) => tbl.date.isSmallerOrEqualValue(toDateString));
    final expenses = await expensesQuery.get();

    return _FinanceCollections(
      payments: payments,
      cashTransactions: cashTransactions,
      expenses: expenses,
    );
  }

  _AggregatedRangeResult _aggregateRange(_FinanceCollections collections) {
    final monthlyMap = <DateTime, _FinanceAggregate>{};
    double totalRevenue = 0;
    double totalExpense = 0;

    void addAmount(DateTime date, double revenue, double expense) {
      final key = DateTime(date.year, date.month);
      final aggregate = monthlyMap.putIfAbsent(key, () => _FinanceAggregate());
      aggregate.revenue += revenue;
      aggregate.expense += expense;
      totalRevenue += revenue;
      totalExpense += expense;
    }

    for (final payment in collections.payments) {
      final date = _parseIsoDate(payment.paymentDate);
      if (date == null) continue;
      addAmount(date, payment.amount, 0);
    }

    for (final transaction in collections.cashTransactions) {
      final date = _parseIsoDate(transaction.transactionTime);
      if (date == null) continue;
      final contribution = _classifyCashTransaction(transaction);
      addAmount(date, contribution.revenue, contribution.expense);
    }

    for (final expense in collections.expenses) {
      final date = _parseDateOnly(expense.date);
      if (date == null) continue;
      addAmount(date, 0, expense.amount);
    }

    final monthlyRows = monthlyMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return _AggregatedRangeResult(
      totalRevenue: totalRevenue,
      totalExpense: totalExpense,
      monthlyRows: monthlyRows
          .map(
            (entry) => _MonthlyFinanceRow(
              year: entry.key.year,
              month: entry.key.month,
              revenue: entry.value.revenue,
              expense: entry.value.expense,
            ),
          )
          .toList(),
    );
  }

  _YearlyFinanceRow _buildYearlyRow(int year, _FinanceCollections collections) {
    final totals = _aggregateRange(collections);
    return _YearlyFinanceRow(
      year: year,
      revenue: totals.totalRevenue,
      expense: totals.totalExpense,
    );
  }

  Future<List<int>> _collectAvailableYears(AppDatabase db) async {
    final years = <int>{};

    Future<void> collect(String table, String column,
        {bool dateOnly = false}) async {
      final result = await db
          .customSelect(
              'SELECT MIN($column) AS min_value, MAX($column) AS max_value FROM $table WHERE deleted_at IS NULL')
          .get();
      if (result.isEmpty) {
        return;
      }
      final data = result.first.data;
      final minStr = data['min_value'] as String?;
      final maxStr = data['max_value'] as String?;
      final minDate = _parseForMode(minStr, dateOnly: dateOnly);
      final maxDate = _parseForMode(maxStr, dateOnly: dateOnly);
      if (minDate == null || maxDate == null) {
        return;
      }
      for (var year = minDate.year; year <= maxDate.year; year++) {
        years.add(year);
      }
    }

    await collect('payments', 'payment_date');
    await collect('cash_transactions', 'transaction_time');
    await collect('expenses', 'date', dateOnly: true);

    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }

    final sorted = years.toList()..sort();
    return sorted;
  }

  DateTime? _parseIsoDate(String value) {
    final normalized =
        value.contains('T') ? value : value.replaceFirst(' ', 'T');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDateOnly(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized = '${trimmed}T00:00:00';
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseForMode(String? value, {required bool dateOnly}) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final trimmed = value.trim();
    final normalized = dateOnly
        ? '${trimmed}T00:00:00'
        : (trimmed.contains('T') ? trimmed : trimmed.replaceFirst(' ', 'T'));
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  _CashContribution _classifyCashTransaction(CashTransaction transaction) {
    final type = transaction.transactionType.toLowerCase();
    final amount = transaction.amount;

    const revenueTypes = {'income', 'revenue', 'deposit', 'credit', 'in'};
    const expenseTypes = {'expense', 'withdrawal', 'debit', 'out', 'outcome'};

    if (revenueTypes.contains(type)) {
      if (amount >= 0) {
        return _CashContribution(revenue: amount, expense: 0);
      }
      return _CashContribution(revenue: 0, expense: amount.abs());
    }

    if (expenseTypes.contains(type)) {
      return _CashContribution(revenue: 0, expense: amount.abs());
    }

    if (amount >= 0) {
      return _CashContribution(revenue: amount, expense: 0);
    }
    return _CashContribution(revenue: 0, expense: amount.abs());
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate =
        (isFrom ? _fromDate : _toDate) ?? DateTime(_selectedYear, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isFrom) {
        _fromDate = DateTime(picked.year, picked.month, picked.day);
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  void _onYearChanged(int? year) {
    if (year == null) {
      return;
    }
    final from = DateTime(year, 1, 1);
    final to = DateTime(year, 12, 31, 23, 59, 59);
    setState(() {
      _selectedYear = year;
      _fromDate = from;
      _toDate = to;
    });
    _fetchReport();
  }

  String _formatCurrency(double value) =>
      '${_currencyFormat.format(value)} ر.س';

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'غير محدد';
    }
    return _dateFormat.format(date);
  }

  String _formatMonthLabel(_MonthlyFinanceRow row) {
    final monthName = _arabicMonths[row.month - 1];
    return '$monthName ${row.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'التقرير المالي الشامل',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFilters(),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<int>(
            value: _selectedYear,
            decoration: const InputDecoration(labelText: 'السنة الأساسية'),
            items: _availableYears
                .map(
                  (year) => DropdownMenuItem<int>(
                    value: year,
                    child: Text(year.toString()),
                  ),
                )
                .toList(),
            onChanged: _loading ? null : _onYearChanged,
          ),
        ),
        _buildDateSelector(
            label: 'من تاريخ',
            value: _fromDate,
            onPressed: () => _pickDate(isFrom: true)),
        _buildDateSelector(
            label: 'إلى تاريخ',
            value: _toDate,
            onPressed: () => _pickDate(isFrom: false)),
        ElevatedButton.icon(
          onPressed: _loading ? null : _fetchReport,
          icon: const Icon(Icons.refresh),
          label: const Text('عرض النتائج'),
        ),
      ],
    );
  }

  Widget _buildDateSelector(
      {required String label,
      required DateTime? value,
      required VoidCallback onPressed}) {
    return SizedBox(
      width: 200,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.date_range),
        label:
            Text('$label\n${_formatDate(value)}', textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final hasData =
        _monthlyRows.isNotEmpty || _totalRevenue > 0 || _totalExpenses > 0;
    if (!hasData) {
      return const EmptyState(
        title: 'لا توجد بيانات',
        message: 'لم يتم العثور على حركات مالية ضمن النطاق المحدد.',
        icon: Icons.analytics_outlined,
      );
    }

    return ListView(
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 16),
        _buildMonthlyCard(),
        const SizedBox(height: 16),
        _buildYearlyCard(),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final net = _totalRevenue - _totalExpenses;
    final netColor = net >= 0 ? Colors.green : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الملخص العام',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _buildSummaryTile(
                        label: 'إجمالي الإيرادات',
                        amount: _totalRevenue,
                        color: Colors.blue)),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildSummaryTile(
                        label: 'إجمالي المصروفات',
                        amount: _totalExpenses,
                        color: Colors.orange)),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildSummaryTile(
                        label: 'صافي الربح', amount: net, color: netColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(
      {required String label, required double amount, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 8),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الملخص الشهري',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _monthlyRows.isEmpty
                ? const Text('لا توجد بيانات شهرية ضمن النطاق المحدد.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('الشهر')),
                        DataColumn(label: Text('الإيرادات')),
                        DataColumn(label: Text('المصروفات')),
                        DataColumn(label: Text('صافي الربح')),
                      ],
                      rows: _monthlyRows
                          .map(
                            (row) => DataRow(
                              cells: [
                                DataCell(Text(_formatMonthLabel(row))),
                                DataCell(Text(_formatCurrency(row.revenue))),
                                DataCell(Text(_formatCurrency(row.expense))),
                                DataCell(
                                  Text(
                                    _formatCurrency(row.net),
                                    style: TextStyle(
                                        color: row.net >= 0
                                            ? Colors.green
                                            : Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearlyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الملخص السنوي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _yearlyRows.isEmpty
                ? const Text('لا توجد بيانات سنوية للعرض.')
                : DataTable(
                    columns: const [
                      DataColumn(label: Text('السنة')),
                      DataColumn(label: Text('الإيرادات')),
                      DataColumn(label: Text('المصروفات')),
                      DataColumn(label: Text('صافي الربح')),
                    ],
                    rows: _yearlyRows
                        .map(
                          (row) => DataRow(
                            cells: [
                              DataCell(Text(row.year.toString())),
                              DataCell(Text(_formatCurrency(row.revenue))),
                              DataCell(Text(_formatCurrency(row.expense))),
                              DataCell(
                                Text(
                                  _formatCurrency(row.net),
                                  style: TextStyle(
                                      color: row.net >= 0
                                          ? Colors.green
                                          : Colors.red),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyFinanceRow {
  _MonthlyFinanceRow({
    required this.year,
    required this.month,
    required this.revenue,
    required this.expense,
  });

  final int year;
  final int month;
  final double revenue;
  final double expense;

  double get net => revenue - expense;
}

class _YearlyFinanceRow {
  _YearlyFinanceRow({
    required this.year,
    required this.revenue,
    required this.expense,
  });

  final int year;
  final double revenue;
  final double expense;

  double get net => revenue - expense;
}

class _FinanceCollections {
  _FinanceCollections({
    required this.payments,
    required this.cashTransactions,
    required this.expenses,
  });

  final List<Payment> payments;
  final List<CashTransaction> cashTransactions;
  final List<Expense> expenses;
}

class _AggregatedRangeResult {
  _AggregatedRangeResult({
    required this.totalRevenue,
    required this.totalExpense,
    required this.monthlyRows,
  });

  final double totalRevenue;
  final double totalExpense;
  final List<_MonthlyFinanceRow> monthlyRows;
}

class _FinanceAggregate {
  double revenue = 0;
  double expense = 0;
}

class _CashContribution {
  _CashContribution({required this.revenue, required this.expense});

  final double revenue;
  final double expense;
}

class _FinanceReportData {
  _FinanceReportData({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.monthlyRows,
    required this.yearlyRows,
  });

  final double totalRevenue;
  final double totalExpenses;
  final List<_MonthlyFinanceRow> monthlyRows;
  final List<_YearlyFinanceRow> yearlyRows;
}
