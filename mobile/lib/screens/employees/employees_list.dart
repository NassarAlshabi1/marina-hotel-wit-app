import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import 'package:uuid/uuid.dart';

class EmployeesListScreen extends ConsumerWidget {
  const EmployeesListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(coreProviders.dbProvider);
    return AppScaffold(
      title: 'الموظفون',
      actions: [
        IconButton(onPressed: () => ref.read(coreProviders.syncProvider).runSync(), icon: const Icon(Icons.sync)),
        IconButton(onPressed: () => _edit(context, ref, db), icon: const Icon(Icons.add)),
      ],
      body: StreamBuilder(
        stream: db.select(db.employees).watch(),
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
                onTap: () => _edit(context, ref, db, existing: e),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AppDatabase db, {EmployeesData? existing}) async {
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

    final uuid = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final comp = EmployeesCompanion(
      localUuid: d.Value(existing?.localUuid ?? uuid),
      serverId: d.Value(existing?.serverId),
      lastModified: d.Value(now),
      deletedAt: const d.Value(null),
      version: const d.Value(1),
      origin: const d.Value('local'),
      employeeId: d.Value(existing?.employeeId),
      name: d.Value(name.text.trim()),
      basicSalary: d.Value(double.tryParse(salary.text) ?? 0),
      status: d.Value(status),
    );

    if (existing == null) {
      await db.into(db.employees).insert(comp);
      await ref.read(coreProviders.syncProvider).queueChange(entity: 'employees', op: 'create', localUuid: uuid, data: {
        'name': name.text.trim(),
        'basic_salary': double.tryParse(salary.text) ?? 0,
        'status': status,
      });
    } else {
      await (db.update(db.employees)..where((t) => t.localUuid.equals(existing.localUuid))).write(comp);
      await ref.read(coreProviders.syncProvider).queueChange(entity: 'employees', op: 'update', localUuid: existing.localUuid, data: {
        'id': existing.employeeId,
        'name': name.text.trim(),
        'basic_salary': double.tryParse(salary.text) ?? 0,
        'status': status,
      });
    }
  }
}
