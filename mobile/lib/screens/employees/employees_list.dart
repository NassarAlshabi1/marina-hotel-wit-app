import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../mixins/sync_on_exit_mixin.dart';

class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});

  @override
  ConsumerState<EmployeesListScreen> createState() =>
      _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'employees_list';

  Future<void> _onRefresh() async {
    final logger = ref.read(loggingServiceProvider);
    logger.logTransaction(type: TransactionType.sync, entity: 'Employees', details: 'تحديث قائمة الموظفين');
    await ref.read(syncServiceProvider).runSync();
    ref.invalidate(employeesListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(employeesRepoProvider);
    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'الموظفون',
        actions: [
          IconButton(
            onPressed: () => ref.read(syncServiceProvider).runSync(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          child: StreamBuilder(
          stream: repo.watchAll(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snapshot.data!;
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (c, i) {
                final e = list[i];
                return ListTile(
                  title: Text(e.name),
                  subtitle: Text(
                    'الراتب: ${CurrencyFormatter.formatAmount(e.basicSalary)} • ${e.status}',
                  ),
                  onTap: () => _edit(context, ref, existing: e),
                );
              },
            );
          },
        ),
      ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    Employee? existing,
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final salary = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.basicSalary)
          : '',
    );
    String status = existing?.status ?? 'active';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing == null ? 'إضافة موظف' : 'تعديل موظف'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              TextField(
                controller: salary,
                decoration: const InputDecoration(labelText: 'الراتب'),
                keyboardType: TextInputType.number,
              ),
              DropdownButtonFormField<String>(
                value: status,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('نشط')),
                  DropdownMenuItem(value: 'inactive', child: Text('غير نشط')),
                ],
                onChanged: (v) => status = v ?? status,
                decoration: const InputDecoration(labelText: 'الحالة'),
              ),
            ],
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
    );
    if (ok != true) return;

    final repo = ref.read(employeesRepoProvider);
    final logger = ref.read(loggingServiceProvider);
    if (existing == null) {
      await repo.create(
        name: name.text.trim(),
        basicSalary: CurrencyFormatter.parseAmount(salary.text) ?? 0,
        status: status,
      );
      logger.logTransaction(type: TransactionType.create, entity: 'Employee', details: 'إضافة موظف: ${name.text.trim()}');
    } else {
      await repo.update(
        existing.id,
        name: name.text.trim(),
        basicSalary: CurrencyFormatter.parseAmount(salary.text) ?? 0,
        status: status,
      );
      logger.logTransaction(type: TransactionType.update, entity: 'Employee', entityId: existing.id.toString(), details: 'تعديل موظف: ${name.text.trim()}');
    }

    markDataChanged();
  }
}
