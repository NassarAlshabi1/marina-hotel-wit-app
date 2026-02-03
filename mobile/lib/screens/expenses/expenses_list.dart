import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import '../../services/logging_service.dart';
import '../../utils/time.dart';
import '../../utils/currency_formatter.dart';
import '../../mixins/sync_on_exit_mixin.dart';

class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen>
    with SyncOnExitMixin {
  final _logger = LoggingService();

  Future<void> _onRefresh() async {
    ref.invalidate(expensesRepoProvider);
    ref.invalidate(employeesListProvider);
    _logger.logTransaction(
      type: TransactionType.sync,
      entity: 'Expenses',
      details: 'تحديث قائمة المصروفات',
    );
  }

  @override
  String get screenId => 'expenses_list';
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
  DateTime? _fromDate;
  DateTime? _toDate;
  String? selectedType;
  static const String _salaryType = 'رواتب';
  static const String _salaryWithdrawAction = 'سحب من الراتب';
  static const String _salaryDeductionAction = 'خصم من الراتب';
  static const List<String> _salaryActions = [
    _salaryWithdrawAction,
    _salaryDeductionAction,
  ];
  static const List<String> availableTypes = [
    'رواتب',
    'ديزل',
    'صيانة',
    'فواتير كهرباء ومياه',
    'مستلزمات',
    'مساعدة محتاج',
    'اخرى',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expensesRepoProvider);
    final employeesAsync = ref.watch(employeesListProvider);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'المصروفات',
        actions: [
          IconButton(
            onPressed: () => ref.read(syncServiceProvider).runSync(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: () => _edit(employees: employeesAsync.value),
            icon: const Icon(Icons.add),
          ),
        ],
        body: employeesAsync.when(
          data: (employees) {
            final employeeNames = {
              for (final emp in employees) emp.id: emp.name,
            };
            return StreamBuilder<List<Expense>>(
              stream: repo.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('حدث خطأ أثناء تحميل المصروفات.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allExpenses = snapshot.data!;
                final filteredExpenses = _filterByDate(allExpenses);
                final totalAmount = filteredExpenses.fold<double>(
                  0,
                  (sum, e) => sum + e.amount,
                );

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildFiltersCard(),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      totalAmount: totalAmount,
                      count: filteredExpenses.length,
                    ),
                    const SizedBox(height: 12),
                    if (filteredExpenses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child:
                            Center(child: Text('لا توجد مصروفات ضمن الفترة')),
                      )
                    else
                      ...filteredExpenses.map(
                        (expense) => _buildExpenseCard(
                          expense,
                          employeeNames[expense.relatedId],
                          employees,
                        ),
                      ),
                  ],
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('تعذر تحميل الموظفين: $error')),
        ),
      ),
    );
  }

  List<Expense> _filterByDate(List<Expense> expenses) {
    final from = _fromDate;
    final to = _toDate;
    final filtered = expenses.where((expense) {
      final date = _parseExpenseDate(expense.date);
      if (from != null && date.isBefore(from)) return false;
      if (to != null && date.isAfter(to)) return false;
      return true;
    }).toList();
    filtered.sort(
      (a, b) => _parseExpenseDate(b.date).compareTo(_parseExpenseDate(a.date)),
    );
    return filtered;
  }

  DateTime _parseExpenseDate(String value) {
    final normalized =
        value.contains('T') ? value : value.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? DateTime.now();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial =
        isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
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
        if (_toDate != null && _fromDate!.isAfter(_toDate!)) {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        if (_fromDate != null && _toDate!.isBefore(_fromDate!)) {
          _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        }
      }
    });
  }

  Widget _buildFiltersCard() {
    final fromLabel =
        _fromDate != null ? _dateFormat.format(_fromDate!) : 'غير محدد';
    final toLabel = _toDate != null ? _dateFormat.format(_toDate!) : 'غير محدد';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.date_range, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'الفترة الزمنية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: true),
                    icon: const Icon(Icons.calendar_month),
                    label: Text('من: $fromLabel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: false),
                    icon: const Icon(Icons.calendar_month),
                    label: Text('إلى: $toLabel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({required double totalAmount, required int count}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryItem(
                label: 'عدد العمليات',
                value: '$count',
                icon: Icons.receipt_long,
                color: Colors.indigo,
              ),
            ),
            Expanded(
              child: _buildSummaryItem(
                label: 'إجمالي المصروفات',
                value: CurrencyFormatter.formatAmount(totalAmount),
                icon: Icons.payments,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseCard(
    Expense expense,
    String? employeeName,
    List<Employee> employees,
  ) {
    final date = _parseExpenseDate(expense.date);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _edit(existing: expense, employees: employees),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      expense.description.isNotEmpty
                          ? expense.description
                          : 'مصروف بدون وصف',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatAmount(expense.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildMetaChip(Icons.category, expense.expenseType),
                  _buildMetaChip(
                      Icons.calendar_today, _dateFormat.format(date)),
                  _buildMetaChip(
                    Icons.person,
                    employeeName ?? 'بدون موظف',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _edit({Expense? existing, List<Employee>? employees}) async {
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final amount = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.amount)
          : '',
    );
    final date = TextEditingController(
      text: existing?.date ?? Time.hotelDayKey(),
    );

    String dialogSalaryAction = _salaryWithdrawAction;
    selectedType = existing?.expenseType ?? 'اخرى';

    if (existing != null && _isSalaryAction(existing.expenseType)) {
      selectedType = _salaryType;
      dialogSalaryAction = _mapExpenseTypeToSalaryAction(existing.expenseType);
    }

    final availableEmployees =
        employees ?? await ref.read(employeesRepoProvider).watchAll().first;
    int? selectedEmployeeId = existing?.relatedId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final dropdownTextStyle = Theme.of(
            ctx,
          ).textTheme.bodyMedium?.copyWith(fontSize: 14);
          return AlertDialog(
            title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'نوع المصروف',
                    ),
                    style: dropdownTextStyle,
                    items: availableTypes
                        .map(
                          (type) => DropdownMenuItem<String>(
                            value: type,
                            child: Text(type, style: dropdownTextStyle),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedType = value;
                        if (selectedType == _salaryType) {
                          if (availableEmployees.isNotEmpty) {
                            selectedEmployeeId ??= availableEmployees.first.id;
                          }
                        } else {
                          selectedEmployeeId = null;
                          dialogSalaryAction = _salaryWithdrawAction;
                        }
                      });
                    },
                  ),
                  if (selectedType == _salaryType) ...[
                    const SizedBox(height: 12),
                    if (availableEmployees.isEmpty)
                      const Text('لا يوجد موظفين مسجلين حالياً.'),
                    if (availableEmployees.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: selectedEmployeeId,
                        decoration: const InputDecoration(
                          labelText: 'اسم الموظف',
                        ),
                        items: availableEmployees
                            .map(
                              (employee) => DropdownMenuItem<int>(
                                value: employee.id,
                                child: Text(employee.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => selectedEmployeeId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: dialogSalaryAction,
                        decoration: const InputDecoration(
                          labelText: 'نوع المعاملة',
                        ),
                        items: _salaryActions
                            .map(
                              (action) => DropdownMenuItem<String>(
                                value: action,
                                child: Text(action, style: dropdownTextStyle),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => dialogSalaryAction = value);
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'المبلغ'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'التاريخ YYYY-MM-DD',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  // Validate salary expenses must have employee selected
                  if (selectedType == _salaryType &&
                      selectedEmployeeId == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'يجب اختيار موظف عند اختيار نوع المصروف "رواتب"',
                        ),
                        backgroundColor: Theme.of(ctx).colorScheme.error,
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: 'إغلاق',
                          textColor: Colors.white,
                          onPressed: () =>
                              ScaffoldMessenger.of(ctx).hideCurrentSnackBar(),
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) {
      description.dispose();
      amount.dispose();
      date.dispose();
      return;
    }

    final repo = ref.read(expensesRepoProvider);
    final salaryRepo = ref.read(salaryWithdrawalsRepoProvider);
    final parsedAmount = CurrencyFormatter.parseAmount(amount.text) ?? 0;
    final trimmedDescription = description.text.trim();
    final trimmedDate =
        date.text.trim().isEmpty ? Time.hotelDayKey() : date.text.trim();
    final isSalaryExpense = selectedType == _salaryType;
    final savedType = isSalaryExpense
        ? _deriveSalaryExpenseType(dialogSalaryAction)
        : (selectedType ?? 'اخرى');

    if (parsedAmount <= 0) {
      description.dispose();
      amount.dispose();
      date.dispose();
      return;
    }

    if (existing == null) {
      final newId = await repo.create(
        expenseType: savedType,
        relatedId: isSalaryExpense ? selectedEmployeeId : null,
        description: trimmedDescription,
        amount: parsedAmount,
        date: trimmedDate,
      );

      if (isSalaryExpense && selectedEmployeeId != null) {
        await salaryRepo.saveFromExpense(
          expenseId: newId,
          employeeId: selectedEmployeeId!,
          action: savedType,
          amount: parsedAmount,
          date: trimmedDate,
          note: trimmedDescription,
        );
      }
    } else {
      await repo.update(
        existing.id,
        expenseType: savedType,
        relatedId: isSalaryExpense ? selectedEmployeeId : null,
        description: trimmedDescription,
        amount: parsedAmount,
        date: trimmedDate,
      );

      if (isSalaryExpense && selectedEmployeeId != null) {
        await salaryRepo.saveFromExpense(
          expenseId: existing.id,
          employeeId: selectedEmployeeId!,
          action: savedType,
          amount: parsedAmount,
          date: trimmedDate,
          note: trimmedDescription,
        );
      } else {
        await salaryRepo.deleteByExpenseId(existing.id);
      }
    }

    description.dispose();
    amount.dispose();
    date.dispose();

    markDataChanged();
    if (mounted) {
      setState(() {});
    }
  }

  bool _isSalaryAction(String? type) {
    if (type == null) return false;
    final normalized = type.trim();
    return normalized == _salaryType ||
        normalized == 'سحب راتب' ||
        normalized == _salaryWithdrawAction ||
        normalized == _salaryDeductionAction ||
        normalized == 'خصم راتب';
  }

  String _mapExpenseTypeToSalaryAction(String type) {
    final normalized = type.trim();
    if (normalized == _salaryDeductionAction || normalized == 'خصم راتب') {
      return _salaryDeductionAction;
    }
    return _salaryWithdrawAction;
  }

  String _deriveSalaryExpenseType(String action) {
    if (action == _salaryDeductionAction) {
      return _salaryDeductionAction;
    }
    return 'سحب راتب';
  }
}
