import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';
import 'package:uuid/uuid.dart';

class ExpensesListScreen extends ConsumerWidget {
  const ExpensesListScreen({super.key});

  static const List<String> _expenseTypes = [
    'أخرى',
    'سحب من الراتب',
    'ديزل',
    'مشتريات كهرباء وسباكة',
    'تسديد فواتير كهرباء أو مياة او نت او هاتف',
  ];
  static const String _salaryType = 'سحب من الراتب';
  static const String _defaultType = 'أخرى';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(expensesRepoProvider);
    return AppScaffold(
      title: 'المصروفات',
      actions: [
        IconButton(onPressed: () => ref.read(syncServiceProvider).runSync(), icon: const Icon(Icons.sync)),
        IconButton(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add)),
      ],
      body: StreamBuilder(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final e = list[i];
              return ListTile(
                title: Text(e.description),
                subtitle: Text('${e.expenseType} • ${e.date}'),
                trailing: Text(e.amount.toStringAsFixed(2)),
                onTap: () => _edit(context, ref, existing: e),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, {Expense? existing}) async {
    final employees = await ref.read(employeesRepoProvider).watchAll().first;
    final description = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(text: existing != null ? existing.amount.toString() : '');
    final date = TextEditingController(text: existing?.date ?? Time.nowDateString());

    final availableTypes = List<String>.from(_expenseTypes);
    String selectedType = existing?.expenseType ?? _defaultType;
    if (selectedType.isEmpty) {
      selectedType = availableTypes.first;
    } else if (!availableTypes.contains(selectedType)) {
      availableTypes.add(selectedType);
    }

    int? selectedEmployeeId = existing?.relatedId;
    if (selectedEmployeeId != null && !employees.any((employee) => employee.id == selectedEmployeeId)) {
      selectedEmployeeId = employees.isNotEmpty ? employees.first.id : null;
    }
    if (selectedType == _salaryType && selectedEmployeeId == null && employees.isNotEmpty) {
      selectedEmployeeId = employees.first.id;
    }

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
                            if (employees.isNotEmpty) {
                              selectedEmployeeId ??= employees.first.id;
                            }
                          } else {
                            selectedEmployeeId = null;
                          }
                        });
                      },
                    ),
                    if (selectedType == _salaryType) ...[
                      const SizedBox(height: 12),
                      if (employees.isEmpty)
                        const Text('لا يوجد موظفين مسجلين حالياً.'),
                      if (employees.isNotEmpty)
                        DropdownButtonFormField<int>(
                          value: selectedEmployeeId,
                          decoration: const InputDecoration(labelText: 'الموظف'),
                          items: employees
                              .map((employee) => DropdownMenuItem<int>(
                                    value: employee.id,
                                    child: Text(employee.name),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => selectedEmployeeId = value),
                        ),
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
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
              ],
            );
          },
        ),
      ),
    );
    if (ok != true) return;

    final cleanedAmountText = amount.text.trim().replaceAll(',', '');
    final parsedAmount = double.tryParse(cleanedAmountText);
    if (parsedAmount == null || parsedAmount <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صالح')));
      }
      return;
    }
    if (selectedType == _salaryType && (selectedEmployeeId == null || employees.isEmpty)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن تسجيل سحب من الراتب بدون اختيار موظف')));
      }
      return;
    }

    final repo = ref.read(expensesRepoProvider);
    final sanitizedDate = date.text.trim().isEmpty ? Time.nowDateString() : date.text.trim();

    if (existing == null) {
      await repo.create(
        expenseType: selectedType,
        relatedId: selectedType == _salaryType ? selectedEmployeeId : null,
        description: description.text.trim(),
        amount: parsedAmount,
        date: sanitizedDate,
      );
    } else {
      await repo.update(
        existing.id,
        expenseType: selectedType,
        relatedId: selectedType == _salaryType ? selectedEmployeeId : null,
        description: description.text.trim(),
        amount: parsedAmount,
        date: sanitizedDate,
      );
    }
  }
}

