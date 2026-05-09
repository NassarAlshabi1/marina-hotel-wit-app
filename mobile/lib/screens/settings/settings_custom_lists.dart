import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/custom_list_providers.dart';

/// شاشة إدارة القوائم المنسدلة المخصصة
class SettingsCustomListsScreen extends ConsumerStatefulWidget {
  const SettingsCustomListsScreen({super.key});

  @override
  ConsumerState<SettingsCustomListsScreen> createState() =>
      _SettingsCustomListsScreenState();
}

class _SettingsCustomListsScreenState
    extends ConsumerState<SettingsCustomListsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    _TabConfig(key: kListKeyExpenseType, label: 'أنواع المصروفات', icon: Icons.category),
    _TabConfig(key: kListKeyIdType, label: 'أنواع الهوية', icon: Icons.badge),
    _TabConfig(key: kListKeyPaymentMethod, label: 'طرق الدفع', icon: Icons.payment),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إدارة القوائم المنسدلة',
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: TabBar(
              controller: _tabController,
              tabs: _tabs
                  .map((t) => Tab(icon: Icon(t.icon, size: 20), text: t.label))
                  .toList(),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((t) => _ListManager(listKey: t.key)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabConfig {
  const _TabConfig({required this.key, required this.label, required this.icon});
  final String key;
  final String label;
  final IconData icon;
}

// ── مدير القائمة الواحدة ────────────────────────────────────────

class _ListManager extends ConsumerStatefulWidget {
  const _ListManager({required this.listKey});
  final String listKey;

  @override
  ConsumerState<_ListManager> createState() => _ListManagerState();
}

class _ListManagerState extends ConsumerState<_ListManager> {
  bool _showInactive = false;

  String get _listKey => widget.listKey;

  String get _listLabel => switch (_listKey) {
        kListKeyExpenseType => 'نوع المصروف',
        kListKeyIdType => 'نوع الهوية',
        kListKeyPaymentMethod => 'طريقة الدفع',
        _ => 'عنصر',
      };

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(customListAllProvider(_listKey));
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (items) {
        final activeItems = items.where((i) => i.isActive).toList();
        final inactiveItems = items.where((i) => !i.isActive).toList();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // زر الإضافة
            FilledButton.icon(
              onPressed: () => _showAddDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: Text('إضافة ${_listLabel} جديد'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
            const SizedBox(height: 12),

            // العناصر النشطة
            if (activeItems.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.list_alt, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'لا توجد عناصر نشطة',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...activeItems.map((item) => _buildItemCard(item)),

            // العناصر المعطلة
            if (inactiveItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _showInactive = !_showInactive),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _showInactive
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'عناصر معطلة (${inactiveItems.length})',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showInactive)
                ...inactiveItems.map((item) => _buildItemCard(item)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildItemCard(CustomListItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: ReorderableDragStartListener(
          index: item.sortOrder,
          child: Icon(
            Icons.drag_handle,
            color: item.isActive ? Colors.grey : Colors.grey.shade300,
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: item.isActive ? null : Colors.grey,
            decoration: item.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: item.isSystem
            ? Text(
                'عنصر نظام — لا يمكن حذفه',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // زر التفعيل/التعطيل
            IconButton(
              icon: Icon(
                item.isActive ? Icons.visibility : Icons.visibility_off,
                size: 20,
                color: item.isActive ? Colors.green : Colors.grey,
              ),
              tooltip: item.isActive ? 'تعطيل' : 'تفعيل',
              onPressed: () => _toggleItem(item),
            ),
            // زر التعديل
            if (!item.isSystem)
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'تعديل',
                onPressed: () => _showEditDialog(item),
              ),
            // زر الحذف
            if (!item.isSystem)
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                tooltip: 'حذف',
                onPressed: () => _confirmDelete(item),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إضافة ${_listLabel}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _listLabel,
            hintText: 'أدخل الاسم الجديد',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty && mounted) {
      await ref.read(addCustomListItemProvider(
        _AddItemArgs(listKey: _listKey, name: controller.text.trim()),
      ).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت الإضافة بنجاح'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _showEditDialog(CustomListItem item) async {
    final controller = TextEditingController(text: item.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل ${_listLabel}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: _listLabel),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, true),
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
    );
    if (ok == true && controller.text.trim().isNotEmpty && mounted) {
      await ref.read(updateCustomListItemProvider(
        _UpdateItemArgs(
          listKey: _listKey,
          id: item.id,
          newName: controller.text.trim(),
        ),
      ).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم التعديل بنجاح'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _toggleItem(CustomListItem item) async {
    await ref.read(toggleCustomListItemProvider(
      _ToggleItemArgs(
        listKey: _listKey,
        id: item.id,
        active: !item.isActive,
      ),
    ).future);
  }

  Future<void> _confirmDelete(CustomListItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف "${item.name}"؟'),
        content: Text(
          'سيتم حذف "${item.name}" من القائمة نهائياً.\n'
          'السجلات السابقة التي تستخدم هذا العنصر لن تتأثر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(deleteCustomListItemProvider(
        _DeleteItemArgs(listKey: _listKey, id: item.id),
      ).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الحذف'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
