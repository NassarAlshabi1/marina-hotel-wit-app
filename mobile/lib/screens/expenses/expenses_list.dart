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
    final amount = TextEditingController(text: existing?.amount.toString() ?? '');
    final expenseType = TextEditingController(text: existing?.expenseType ?? 'other');
    final date = TextEditingController(text: existing?.date ?? Time.nowDateString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: description, decoration: const InputDecoration(labelText: 'الوصف')),
            TextField(controller: amount, decoration: const InputDecoration(labelText: 'المبلغ'), keyboardType: TextInputType.number),
            TextField(controller: expenseType, decoration: const InputDecoration(labelText: 'النوع')),
            TextField(controller: date, decoration: const InputDecoration(labelText: 'التاريخ YYYY-MM-DD')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))],
        ),
      ),
    );
    if (ok != true) return;

    final repo = ref.read(expensesRepoProvider);
    if (existing == null) {
      await repo.create(expenseType: expenseType.text.trim(), description: description.text.trim(), amount: double.tryParse(amount.text) ?? 0, date: date.text.trim());
    } else {
      await repo.update(existing.id, expenseType: expenseType.text.trim(), description: description.text.trim(), amount: double.tryParse(amount.text) ?? 0, date: date.text.trim());
    }
  }
}
