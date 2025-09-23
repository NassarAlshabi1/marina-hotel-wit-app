import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import 'package:uuid/uuid.dart';

class ExpensesListScreen extends ConsumerWidget {
  const ExpensesListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(coreProviders.dbProvider);
    return AppScaffold(
      title: 'المصروفات',
      actions: [
        IconButton(onPressed: () => ref.read(coreProviders.syncProvider).runSync(), icon: const Icon(Icons.sync)),
        IconButton(onPressed: () => _edit(context, ref, db), icon: const Icon(Icons.add)),
      ],
      body: StreamBuilder(
        stream: db.select(db.expenses).watch(),
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
                onTap: () => _edit(context, ref, db, existing: e),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AppDatabase db, {ExpensesData? existing}) async {
    final description = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(text: existing?.amount.toString() ?? '');
    final expenseType = TextEditingController(text: existing?.expenseType ?? 'other');
    final date = TextEditingController(text: existing?.date ?? DateTime.now().toString().substring(0, 10));

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

    final uuid = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final comp = ExpensesCompanion(
      localUuid: d.Value(existing?.localUuid ?? uuid),
      serverId: d.Value(existing?.serverId),
      lastModified: d.Value(now),
      deletedAt: const d.Value(null),
      version: const d.Value(1),
      origin: const d.Value('local'),
      expenseId: d.Value(existing?.expenseId),
      expenseType: d.Value(expenseType.text.trim()),
      description: d.Value(description.text.trim()),
      amount: d.Value(double.tryParse(amount.text) ?? 0),
      date: d.Value(date.text.trim()),
    );

    if (existing == null) {
      await db.into(db.expenses).insert(comp);
      await ref.read(coreProviders.syncProvider).queueChange(entity: 'expenses', op: 'create', localUuid: uuid, data: {
        'expense_type': expenseType.text.trim(),
        'description': description.text.trim(),
        'amount': double.tryParse(amount.text) ?? 0,
        'date': date.text.trim(),
      });
    } else {
      await (db.update(db.expenses)..where((t) => t.localUuid.equals(existing.localUuid))).write(comp);
      await ref.read(coreProviders.syncProvider).queueChange(entity: 'expenses', op: 'update', localUuid: existing.localUuid, data: {
        'id': existing.expenseId,
        'expense_type': expenseType.text.trim(),
        'description': description.text.trim(),
        'amount': double.tryParse(amount.text) ?? 0,
        'date': date.text.trim(),
      });
    }
  }
}
