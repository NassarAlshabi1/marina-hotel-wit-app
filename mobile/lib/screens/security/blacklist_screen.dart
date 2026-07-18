import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/repositories/blacklist_repository.dart';
import '../../services/sync_service.dart';

class BlacklistScreen extends ConsumerStatefulWidget {
  const BlacklistScreen({super.key});

  @override
  ConsumerState<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends ConsumerState<BlacklistScreen> {
  bool _isSyncing = false;
  String _filterText = '';

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(blacklistRepoProvider);
    final syncService = ref.watch(syncServiceProvider);

    return AppScaffold(
      title: 'القائمة السوداء',
      actions: [
        IconButton(icon: const Icon(Icons.search), onPressed: () => _showSearchDialog(context), tooltip: 'بحث'),
        IconButton(
          icon: _isSyncing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          onPressed: _isSyncing ? null : () => _performSync(syncService),
          tooltip: 'مزامنة',
        ),
      ],
      body: RepaintBoundary(
        child: StreamBuilder<List<BlacklistEntry>>(
          stream: repo.watchAll(),
          builder: (context, snapshot) {
            // ✅ P0 fix: معالجة أخطاء الـ stream
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('خطأ في تحميل البيانات: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            var entries = snapshot.data!;
            if (_filterText.isNotEmpty) {
              final query = _filterText.trim().toLowerCase();
              entries = entries
                  .where(
                    (e) =>
                        e.name.toLowerCase().contains(query) ||
                        (e.nationalId?.toLowerCase().contains(query) ?? false) ||
                        (e.phone?.toLowerCase().contains(query) ?? false) ||
                        (e.nationality?.toLowerCase().contains(query) ?? false),
                  )
                  .toList();
            }
            if (entries.isEmpty) {
              return _EmptyState(onAdd: () => _openEntryDialog(context, repo), isFiltered: _filterText.isNotEmpty);
            }
            return Column(
              children: [
                if (_filterText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'نتائج البحث: ${entries.length}',
                          style: const TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _filterText = ''),
                          child: const Text(
                            'مسح الفلتر',
                            style: TextStyle(fontSize: 13, color: Colors.blue, decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _performSync(ref.read(syncServiceProvider)),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: e.active ? Colors.red.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openEntryDialog(context, repo, entry: e),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: e.active ? Colors.red.shade100 : Colors.grey.shade300,
                                  child: Icon(Icons.gavel, color: e.active ? Colors.red : Colors.grey),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          decoration: e.active ? TextDecoration.none : TextDecoration.lineThrough,
                                          color: e.active ? null : Colors.grey,
                                        ),
                                      ),
                                    ),
                                    if (e.active)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'نشط',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text('معطّل', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (e.nationality != null && e.nationality!.isNotEmpty)
                                      Text('الجنسية: ${e.nationality!}', style: const TextStyle(fontSize: 13)),
                                    if (e.nationalId != null && e.nationalId!.isNotEmpty)
                                      Text('الهوية: ${e.nationalId!}', style: const TextStyle(fontSize: 13)),
                                    if (e.phone != null && e.phone!.isNotEmpty)
                                      Text('الهاتف: ${e.phone!}', style: const TextStyle(fontSize: 13)),
                                    if (e.reason != null && e.reason!.isNotEmpty)
                                      Text('السبب: ${e.reason!}', style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'edit':
                                        _openEntryDialog(context, repo, entry: e);
                                      case 'toggle':
                                        try {
                                          await repo.updateActive(e.id, !e.active);
                                          if (!mounted) {
                                            return;
                                          }
                                          // ignore: use_build_context_synchronously
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(e.active ? 'تم تعطيل: ${e.name}' : 'تم تفعيل: ${e.name}'),
                                              backgroundColor: e.active ? Colors.orange : Colors.green,
                                            ),
                                          );
                                        } catch (err) {
                                          if (!mounted) {
                                            return;
                                          }
                                          // ignore: use_build_context_synchronously
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('فشل تحديث الحالة: $err'),
                                              backgroundColor: Colors.red.shade900,
                                            ),
                                          );
                                        }
                                      case 'delete':
                                        final confirmed = await _showDeleteConfirmDialog(context, e.name);
                                        if (confirmed ?? false) {
                                          try {
                                            await repo.delete(e.id);
                                            if (!mounted) {
                                              return;
                                            }
                                            // ignore: use_build_context_synchronously
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('تم حذف: ${e.name}'), backgroundColor: Colors.red),
                                            );
                                          } catch (err) {
                                            if (!mounted) {
                                              return;
                                            }
                                            // ignore: use_build_context_synchronously
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('فشل الحذف: $err'),
                                                backgroundColor: Colors.red.shade900,
                                              ),
                                            );
                                          }
                                        }
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, size: 18, color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text('تعديل'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Row(
                                        children: [
                                          Icon(
                                            e.active ? Icons.visibility_off : Icons.visibility,
                                            size: 18,
                                            color: e.active ? Colors.orange : Colors.green,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(e.active ? 'تعطيل' : 'تفعيل'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, size: 18, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('حذف', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ), // RepaintBoundary
      fab: FloatingActionButton(
        onPressed: () => _openEntryDialog(context, repo),
        tooltip: 'إضافة شخص للقائمة السوداء',
        child: const Icon(Icons.person_add_disabled),
      ),
    );
  }

  Future<void> _performSync(SyncService syncService) async {
    setState(() => _isSyncing = true);
    try {
      await syncService.runSync();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت المزامنة بنجاح'), backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشلت المزامنة: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _showSearchDialog(BuildContext context) {
    final controller = TextEditingController(text: _filterText);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بحث في القائمة السوداء'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم، هوية، هاتف، أو جنسية', prefixIcon: Icon(Icons.search)),
          onSubmitted: (value) {
            setState(() => _filterText = value);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          if (_filterText.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _filterText = '');
                Navigator.pop(ctx);
              },
              child: const Text('مسح البحث'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              setState(() => _filterText = controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('بحث'),
          ),
        ],
      ),
    ).then((_) {
      controller.dispose();
    });
  }

  Future<bool?> _showDeleteConfirmDialog(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber, color: Colors.red, size: 48),
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف "$name" من القائمة السوداء؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openEntryDialog(BuildContext context, BlacklistRepository repo, {BlacklistEntry? entry}) {
    final isEdit = entry != null;
    final nameCtrl = TextEditingController(text: isEdit ? entry.name : '');
    final nationalityCtrl = TextEditingController(text: isEdit ? (entry.nationality ?? '') : '');
    final nationalIdCtrl = TextEditingController(text: isEdit ? (entry.nationalId ?? '') : '');
    final phoneCtrl = TextEditingController(text: isEdit ? (entry.phone ?? '') : '');
    final reasonCtrl = TextEditingController(text: isEdit ? (entry.reason ?? '') : '');
    final notesCtrl = TextEditingController(text: isEdit ? (entry.notes ?? '') : '');
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'تعديل بيانات الشخص' : 'إضافة إلى القائمة السوداء'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nationalityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الجنسية',
                    prefixIcon: Icon(Icons.flag),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nationalIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهوية',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'السبب',
                    prefixIcon: Icon(Icons.warning),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton.icon(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }
              final navigator = Navigator.of(ctx);
              try {
                if (isEdit) {
                  await repo.updateEntry(
                    id: entry.id,
                    name: nameCtrl.text,
                    nationality: nationalityCtrl.text,
                    nationalId: nationalIdCtrl.text,
                    phone: phoneCtrl.text,
                    reason: reasonCtrl.text,
                    notes: notesCtrl.text,
                  );
                } else {
                  await repo.addEntry(
                    name: nameCtrl.text,
                    nationality: nationalityCtrl.text,
                    nationalId: nationalIdCtrl.text,
                    phone: phoneCtrl.text,
                    reason: reasonCtrl.text,
                    notes: notesCtrl.text,
                  );
                }
                navigator.pop();
                if (!mounted) {
                  return;
                }
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEdit ? 'تم تعديل: ${nameCtrl.text}' : 'تمت الإضافة: ${nameCtrl.text}'),
                    backgroundColor: isEdit ? Colors.blue : Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
              }
            },
            icon: Icon(isEdit ? Icons.save : Icons.person_add),
            label: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      nationalityCtrl.dispose();
      nationalIdCtrl.dispose();
      phoneCtrl.dispose();
      reasonCtrl.dispose();
      notesCtrl.dispose();
    });
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, this.isFiltered = false});
  final VoidCallback onAdd;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isFiltered ? Icons.search_off : Icons.person_off, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            isFiltered ? 'لا توجد نتائج مطابقة للبحث' : 'لا توجد أسماء في القائمة السوداء',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (!isFiltered)
            ElevatedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('إضافة اسم')),
        ],
      ),
    );
  }
}
