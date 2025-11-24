import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';
import '../../utils/currency_formatter.dart';

class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> {
  int? _selectedEmployeeId;
  String? selectedType;
  static const String _salaryType = 'رواتب';
  static const String _salaryWithdrawAction = 'سحب من الراتب';
  static const String _salaryDeductionAction = 'خصم من الراتب';
  static const List<String> _salaryActions = [_salaryWithdrawAction, _salaryDeductionAction];
  static const List<String> availableTypes = ['رواتب', 'ديزل', 'صيانة', 'فواتير كهرباء ومياه', 'مستلزمات', 'مساعدة محتاج', 'اخرى'];

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expensesRepoProvider);
    final employeesAsync = ref.watch(employeesListProvider);

    return AppScaffold(
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
          final employeeNames = {for (final emp in employees) emp.id: emp.name};
          return Column(
            children: [
              _buildEmployeeFilter(employees),
              Expanded(
                child: StreamBuilder<List<Expense>>(
                  stream: repo.watchAll(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('حدث خطأ أثناء تحميل المصروفات.'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var expenses = snapshot.data!;
                    if (_selectedEmployeeId != null) {
                      expenses = expenses.where((expense) => expense.relatedId == _selectedEmployeeId).toList();
                    }
                    if (expenses.isEmpty) {
                      return const Center(child: Text('لا توجد مصروفات مطابقة للعرض.'));
                    }
                    return ListView.builder(
                      itemCount: expenses.length,
                      itemBuilder: (context, index) {
                        final expense = expenses[index];
                        final employeeName = expense.relatedId != null ? employeeNames[expense.relatedId] : null;
                        return ListTile(
                          title: Text(expense.description),
                          subtitle: Text('${expense.expenseType} • ${employeeName ?? 'بدون موظف'} • ${Time.safeIsoToDateString(expense.date)}'),
                          trailing: Text(CurrencyFormatter.formatAmount(expense.amount)),
                          onTap: () => _edit(existing: expense, employees: employees),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('تعذر تحميل الموظفين: $error')),
      ),
    );
  }

  Widget _buildEmployeeFilter(List<Employee> employees) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              value: _selectedEmployeeId,
              decoration: const InputDecoration(
                labelText: 'تصفية حسب الموظف',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('جميع الموظفين')),
                ...employees.map(
                  (employee) => DropdownMenuItem<int?>(
                    value: employee.id,
                    child: Text(employee.name),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedEmployeeId = value;
                });
              },
            ),
          ),
          if (_selectedEmployeeId != null) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedEmployeeId = null;
                });
              },
              child: const Text('إزالة التصفية'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit({Expense? existing, List<Employee>? employees}) async {
    final description = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(text: existing?.amount.toString() ?? '');
    final date = TextEditingController(text: existing?.date ?? Time.nowDateString());

    String dialogSalaryAction = _salaryWithdrawAction;
    selectedType = existing?.expenseType ?? 'اخرى';

    if (existing != null && _isSalaryAction(existing.expenseType)) {
      selectedType = _salaryType;
      dialogSalaryAction = _mapExpenseTypeToSalaryAction(existing.expenseType);
    }

    final availableEmployees = employees ?? await ref.read(employeesRepoProvider).watchAll().first;
    int? selectedEmployeeId = existing?.relatedId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setState) {
            final dropdownTextStyle = Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontSize: 14);
            return AlertDialog(
              title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: description,
                      decoration: const InputDecoration(labelText: 'الوصف'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amount,
                      decoration: const InputDecoration(labelText: 'المبلغ'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: 'نوع المصروف'),
                      style: dropdownTextStyle,
                      items: availableTypes
                          .map((type) => DropdownMenuItem<String>(
                                value: type,
                                child: Text(type, style: dropdownTextStyle),
                              ))
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
                        DropdownButtonFormField<String>(
                          value: dialogSalaryAction,
                          decoration: const InputDecoration(labelText: 'نوع المعاملة'),
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: selectedEmployeeId,
                          decoration: const InputDecoration(labelText: 'الموظف'),
                          items: availableEmployees
                              .map((employee) => DropdownMenuItem<int>(
                                    value: employee.id,
                                    child: Text(employee.name),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => selectedEmployeeId = value),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: date,
                      decoration: const InputDecoration(labelText: 'التاريخ YYYY-MM-DD'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(
                  onPressed: () {
                    // Validate salary expenses must have employee selected
                    if (selectedType == _salaryType && selectedEmployeeId == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: const Text('يجب اختيار موظف عند اختيار نوع المصروف "رواتب"'),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
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
    final parsedAmount = double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
    final trimmedDescription = description.text.trim();
    final trimmedDate = date.text.trim().isEmpty ? Time.nowDateString() : date.text.trim();
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

    if (mounted) {
      setState(() {});
    }
  }

  bool _isSalaryAction(String? type) {
    if (type == null) return false;
    final normalized = type.trim();
    return normalized == _salaryType || normalized == 'سحب راتب' || normalized == _salaryWithdrawAction || normalized == _salaryDeductionAction || normalized == 'خصم راتب';
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
