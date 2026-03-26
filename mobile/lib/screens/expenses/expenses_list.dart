import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
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
  @override
  String get screenId => 'expenses_list';
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
  DateTime? _fromDate;
  DateTime? _toDate;
  String? selectedType;
  late Stream<List<Expense>> _expensesStream;

  // ✅ أنواع المصروفات الأساسية
  static const String _salaryType = 'رواتب';
  static const List<String> availableTypes = [
    'رواتب',
    'ديزل',
    'صيانة',
    'فواتير كهرباء ومياه',
    'مستلزمات',
    'مساعدة محتاج',
    'اخرى',
  ];

  // ✅ قائمة إجراءات الرواتب الافتراضية (قابلة للتوسعة)
  // Default salary actions list - can be extended dynamically
  static const List<String> defaultSalaryActions = [
    'سحب من الراتب',
    'خصم من الراتب',
    'سلفة',
    'مكافأة',
    'خصم تأخير',
    'خصم غياب',
    'مصروفات طبية',
    'سداد دين',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _expensesStream = _buildExpensesStream();
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeesListProvider);
    final salaryWithdrawalsAsync = ref.watch(salaryWithdrawalsListProvider);

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
            
            // Build a map of expenseId -> employeeId from salary_withdrawals
            final salaryExpenseToEmployee = <int, int>{};
            if (salaryWithdrawalsAsync.hasValue && salaryWithdrawalsAsync.value != null) {
              for (final sw in salaryWithdrawalsAsync.value!) {
                if (sw.expenseId != null) {
                  salaryExpenseToEmployee[sw.expenseId!] = sw.employeeId;
                }
              }
            }
            
            return StreamBuilder<List<Expense>>(
              stream: _expensesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('حدث خطأ أثناء تحميل المصروفات.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final filteredExpenses = snapshot.data!;
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
                        child: Center(
                          child: Text('لا توجد مصروفات ضمن الفترة'),
                        ),
                      )
                    else
                      ...filteredExpenses.map(
                        (expense) {
                          // Get employee name: first from relatedId, then from salary_withdrawals
                          final employeeName = _getEmployeeNameForExpense(
                            expense,
                            employeeNames,
                            salaryExpenseToEmployee,
                          );
                          return _buildExpenseCard(
                            expense,
                            employeeName,
                            employees,
                          );
                        },
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

  /// الحصول على اسم الموظف للمصروف
  /// Get employee name for expense (from relatedId or salary_withdrawals)
  String? _getEmployeeNameForExpense(
    Expense expense,
    Map<int, String> employeeNames,
    Map<int, int> salaryExpenseToEmployee,
  ) {
    // First try from relatedId
    if (expense.relatedId != null && employeeNames.containsKey(expense.relatedId)) {
      return employeeNames[expense.relatedId];
    }
    
    // For salary expenses, check salary_withdrawals table
    if (expense.expenseType == _salaryType) {
      final employeeId = salaryExpenseToEmployee[expense.id];
      if (employeeId != null && employeeNames.containsKey(employeeId)) {
        return employeeNames[employeeId];
      }
    }
    
    return null;
  }

  Stream<List<Expense>> _buildExpensesStream() {
    final repo = ref.read(expensesRepoProvider);
    final fromStr = _fromDate != null ? Time.dateToString(_fromDate!) : null;
    final toStr = _toDate != null ? Time.dateToString(_toDate!) : null;
    return Stream.fromFuture(repo.listFiltered(from: fromStr, to: toStr));
  }

  void _refreshExpensesStream() {
    setState(() {
      _expensesStream = _buildExpensesStream();
    });
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
      _expensesStream = _buildExpensesStream();
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
            const Row(
              children: [
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
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
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
                    Icons.calendar_today,
                    _dateFormat.format(date),
                  ),
                  _buildMetaChip(Icons.person, employeeName ?? 'بدون موظف'),
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

    // ✅ الإجراء المحدد للموظف - حر بدون قيود
    String selectedSalaryAction = defaultSalaryActions.first;
    selectedType = existing?.expenseType ?? 'اخرى';

    // Load salary withdrawal data for existing salary expenses
    SalaryWithdrawal? existingSalaryWithdrawal;
    if (existing != null && existing.expenseType == _salaryType) {
      // Try to load from salary_withdrawals table
      final salaryRepo = ref.read(salaryWithdrawalsRepoProvider);
      final allWithdrawals = await salaryRepo.listAll();
      try {
        existingSalaryWithdrawal = allWithdrawals.firstWhere(
          (sw) => sw.expenseId == existing.id,
        );
        // ✅ استخدم الإجراء كما هو بدون تحويل
        selectedSalaryAction = existingSalaryWithdrawal.action;
      } catch (_) {
        // Not found, use defaults
      }
    }

    final availableEmployees =
        employees ?? await ref.read(employeesRepoProvider).watchAll().first;
    
    // Get employee ID: first from relatedId, then from salary_withdrawals
    int? selectedEmployeeId = existing?.relatedId;
    if (selectedEmployeeId == null && existingSalaryWithdrawal != null) {
      selectedEmployeeId = existingSalaryWithdrawal.employeeId;
    }

    // ✅ قائمة الإجراءات المتاحة (قابلة للتوسعة)
    List<String> salaryActions = List.from(defaultSalaryActions);
    
    // إضافة الإجراء الحالي إذا لم يكن في القائمة
    if (!salaryActions.contains(selectedSalaryAction)) {
      salaryActions.insert(0, selectedSalaryAction);
    }

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
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'نوع المصروف'),
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
                        initialValue: selectedEmployeeId,
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
                      // ✅ حقل الإجراء - حر مع إمكانية الكتابة
                      DropdownButtonFormField<String>(
                        initialValue: selectedSalaryAction,
                        decoration: const InputDecoration(
                          labelText: 'نوع المعاملة',
                          hintText: 'اختر أو اكتب نوع المعاملة',
                        ),
                        items: salaryActions
                            .map(
                              (action) => DropdownMenuItem<String>(
                                value: action,
                                child: Text(action, style: dropdownTextStyle),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => selectedSalaryAction = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      // ✅ حقل نصي لإضافة إجراء جديد مخصص
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'أو اكتب إجراء مخصص جديد',
                          hintText: 'مثال: سلفة طارئة',
                        ),
                        onChanged: (value) {
                          if (value.trim().isNotEmpty) {
                            setState(() {
                              selectedSalaryAction = value.trim();
                            });
                          }
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
    
    // ✅ استخدام النوع والإجراء كما هما بدون تحويل
    final savedType = selectedType ?? 'اخرى';

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
        // ✅ تمرير الإجراء كما هو بدون تحويل
        await salaryRepo.saveFromExpense(
          expenseId: newId,
          employeeId: selectedEmployeeId!,
          action: selectedSalaryAction, // ✅ مباشرة بدون تحويل
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
        // ✅ تمرير الإجراء كما هو بدون تحويل
        await salaryRepo.saveFromExpense(
          expenseId: existing.id,
          employeeId: selectedEmployeeId!,
          action: selectedSalaryAction, // ✅ مباشرة بدون تحويل
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

    // ✅ تحديث قائمة سحوبات الرواتب
    ref.invalidate(salaryWithdrawalsListProvider);
    
    markDataChanged();
    if (mounted) {
      _refreshExpensesStream();
    }
  }
}
