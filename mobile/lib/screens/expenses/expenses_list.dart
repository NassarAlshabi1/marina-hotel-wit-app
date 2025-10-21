import 'dart:ui' as ui;

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
    final description = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(text: existing != null ? existing.amount.toString() : '');
    final date = TextEditingController(text: existing?.date ?? Time.nowDateString());

    final repo = ref.read(expensesRepoProvider);
    final types = await repo.expenseTypes();
    const customKey = '__custom__';

    String? selectedType;
    bool useCustom = false;
    final existingType = existing?.expenseType.trim();
    if (existingType != null && types.contains(existingType)) {
      selectedType = existingType;
    } else if (existingType != null && existingType.isNotEmpty) {
      useCustom = true;
    } else if (types.isNotEmpty) {
      selectedType = types.first;
    }

    final customType = TextEditingController(text: useCustom ? existingType : '');
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'يرجى إدخال الوصف' : null,
                  ),
                  TextFormField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'المبلغ'),
                    keyboardType: TextInputType.number,
                    validator: (value) => (value == null || double.tryParse(value) == null) ? 'يرجى إدخال مبلغ صحيح' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: useCustom ? customKey : (selectedType ?? (types.isNotEmpty ? types.first : customKey)),
                    decoration: const InputDecoration(labelText: 'نوع المصروف'),
                    items: [
                      ...types.map((type) => DropdownMenuItem(value: type, child: Text(type))),
                      const DropdownMenuItem(value: customKey, child: Text('إدخال نوع جديد')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (value == customKey) {
                          useCustom = true;
                          selectedType = null;
                        } else {
                          useCustom = false;
                          selectedType = value;
                        }
                      });
                    },
                  ),
                  if (useCustom)
                    TextFormField(
                      controller: customType,
                      decoration: const InputDecoration(labelText: 'اكتب نوع المصروف'),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'يرجى إدخال نوع المصروف' : null,
                    ),
                  TextFormField(
                    controller: date,
                    decoration: const InputDecoration(labelText: 'التاريخ YYYY-MM-DD'),
                    validator: (value) => (value == null || value.trim().length < 10) ? 'يرجى إدخال تاريخ بصيغة صحيحة' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    final typeValue = useCustom ? customType.text.trim() : (selectedType ?? '');
    final normalizedType = typeValue.isEmpty ? 'other' : typeValue;
    final parsedAmount = double.tryParse(amount.text) ?? 0;

    if (existing == null) {
      await repo.create(
        expenseType: normalizedType,
        description: description.text.trim(),
        amount: parsedAmount,
        date: date.text.trim(),
      );
    } else {
      await repo.update(
        existing.id,
        expenseType: normalizedType,
        description: description.text.trim(),
        amount: parsedAmount,
        date: date.text.trim(),
      );
    }
  }
}
