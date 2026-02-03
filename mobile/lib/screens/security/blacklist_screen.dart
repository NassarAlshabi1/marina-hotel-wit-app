import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/repositories/blacklist_repository.dart';
import '../../services/logging_service.dart';

class BlacklistScreen extends ConsumerWidget {
  const BlacklistScreen({super.key});
  static final _logger = LoggingService();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(blacklistRepoProvider);
    return AppScaffold(
      title: 'القائمة السوداء',
      body: StreamBuilder<List<BlacklistEntry>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return _EmptyState(onAdd: () => _openAddDialog(context, repo));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final e = entries[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        e.active ? Colors.red.shade100 : Colors.grey.shade300,
                    child: Icon(
                      Icons.gavel,
                      color: e.active ? Colors.red : Colors.grey,
                    ),
                  ),
                  title: Text(
                    '${e.name}${e.nationality != null && e.nationality!.isNotEmpty ? ' • ${e.nationality}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.nationality != null && e.nationality!.isNotEmpty)
                        Text('الجنسية: ${e.nationality!}'),
                      if (e.reason != null && e.reason!.isNotEmpty)
                        Text('سبب: ${e.reason!}'),
                      if (e.nationalId != null && e.nationalId!.isNotEmpty)
                        Text('الهوية: ${e.nationalId!}'),
                      if (e.phone != null && e.phone!.isNotEmpty)
                        Text('الهاتف: ${e.phone!}'),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      switch (value) {
                        case 'toggle':
                          await repo.updateActive(e.id, !e.active);
                          _logger.logTransaction(type: TransactionType.update, entity: 'Blacklist', entityId: e.id.toString(), details: e.active ? 'تعطيل' : 'تفعيل');
                          break;
                        case 'delete':
                          await repo.delete(e.id);
                          _logger.logTransaction(type: TransactionType.delete, entity: 'Blacklist', entityId: e.id.toString(), details: 'حذف من القائمة السوداء');
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(e.active ? 'تعطيل' : 'تفعيل'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      fab: FloatingActionButton(
        onPressed: () => _openAddDialog(context, repo),
        child: const Icon(Icons.person_add_disabled),
      ),
    );
  }

  void _openAddDialog(BuildContext context, BlacklistRepository repo) {
    final name = TextEditingController();
    final nationality = TextEditingController(text: 'يمني');
    final nationalId = TextEditingController();
    final phone = TextEditingController();
    final reason = TextEditingController();
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة إلى القائمة السوداء'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل *',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: nationality,
                  decoration: const InputDecoration(labelText: 'الجنسية'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: nationalId,
                  decoration: const InputDecoration(labelText: 'رقم الهوية'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'السبب'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              // من الأفضل تخزين الـ navigator قبل الفجوة غير المتزامنة
              final navigator = Navigator.of(context);
              await repo.addEntry(
                name: name.text,
                nationality: nationality.text,
                nationalId: nationalId.text,
                phone: phone.text,
                reason: reason.text,
                notes: notes.text,
              );
              _logger.logTransaction(type: TransactionType.create, entity: 'Blacklist', details: 'إضافة: ${name.text}');
              navigator.pop();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_off, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('لا توجد أسماء في القائمة السوداء'),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('إضافة اسم'),
          ),
        ],
      ),
    );
  }
}
