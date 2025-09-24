import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import 'package:uuid/uuid.dart';

class EmployeesListScreen extends ConsumerWidget {
  const EmployeesListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(employeesRepoProvider);
    return AppScaffold(
      title: 'الموظفون',
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
                title: Text(e.name),
                subtitle: Text('الراتب: ${e.basicSalary.toStringAsFixed(2)} • ${e.status}'),
                onTap: () => _edit(context, ref, existing: e),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, {Employee? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final salary = TextEditingController(text: existing?.basicSalary.toString() ?? '');
    String status = existing?.status ?? 'active';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing == null ? 'إضافة موظف' : 'تعديل موظف'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
            TextField(controller: salary, decoration: const InputDecoration(labelText: 'الراتب'), keyboardType: TextInputType.number),
            DropdownButtonFormField<String>(
              value: status,
              items: const [DropdownMenuItem(value: 'active', child: Text('نشط')), DropdownMenuItem(value: 'inactive', child: Text('غير نشط'))],
              onChanged: (v) => status = v ?? status,
              decoration: const InputDecoration(labelText: 'الحالة'),
            )
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))],
        ),
      ),
    );
    if (ok != true) return;

    final repo = ref.read(employeesRepoProvider);
    if (existing == null) {
      await repo.create(name: name.text.trim(), basicSalary: double.tryParse(salary.text) ?? 0, status: status);
    } else {
      await repo.update(existing.id, name: name.text.trim(), basicSalary: double.tryParse(salary.text) ?? 0, status: status);
    }
  }
}
