import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';

class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> {
  int? _selectedEmployeeId;

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
                          trailing: Text('${expense.amount.toStringAsFixed(2)} ر.س'),
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
    final expenseType = TextEditingController(text: existing?.expenseType ?? 'other');
    final date = TextEditingController(text: existing?.date ?? Time.nowDateString());

    final employeesList = employees ?? await ref.read(employeesRepoProvider).watchAll().first;
    int? selectedEmployeeId = existing?.relatedId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  TextField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'المبلغ'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: expenseType,
                    decoration: const InputDecoration(labelText: 'النوع'),
                  ),
                  TextField(
                    controller: date,
                    decoration: const InputDecoration(labelText: 'التاريخ YYYY-MM-DD'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedEmployeeId,
                    decoration: const InputDecoration(
                      labelText: 'الموظف',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('بدون موظف')),
                      ...employeesList.map(
                        (employee) => DropdownMenuItem<int?>(
                          value: employee.id,
                          child: Text(employee.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedEmployeeId = value;
                      });
                    },
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
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) {
      description.dispose();
      amount.dispose();
      expenseType.dispose();
      date.dispose();
      return;
    }

    final repo = ref.read(expensesRepoProvider);
    final parsedAmount = double.tryParse(amount.text.trim()) ?? 0;
    final trimmedDescription = description.text.trim();
    final trimmedType = expenseType.text.trim();
    final trimmedDate = date.text.trim();

    if (existing == null) {
      await repo.create(
        expenseType: trimmedType,
        relatedId: selectedEmployeeId,
        description: trimmedDescription,
        amount: parsedAmount,
        date: trimmedDate,
      );
    } else {
      await repo.update(
        existing.id,
        expenseType: trimmedType,
        relatedId: selectedEmployeeId,
        description: trimmedDescription,
        amount: parsedAmount,
        date: trimmedDate,
      );
    }

    description.dispose();
    amount.dispose();
    expenseType.dispose();
    date.dispose();
  }
}
