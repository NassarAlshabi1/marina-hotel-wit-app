import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/custom_list_providers.dart';

/// شاشة إدارة أنواع المصروفات — إضافة / تعديل / حذف / ترتيب / تفعيل
class SettingsExpenseTypesScreen extends ConsumerStatefulWidget {
  const SettingsExpenseTypesScreen({super.key});

  @override
  ConsumerState<SettingsExpenseTypesScreen> createState() =>
      _SettingsExpenseTypesScreenState();
}

class _SettingsExpenseTypesScreenState
    extends ConsumerState<SettingsExpenseTypesScreen> {
  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(allExpenseTypesProvider);

    return AppScaffold(
      title: 'أنواع المصروفات',
      actions: [
        IconButton(
          onPressed: _showAddDialog,
          icon: const Icon(Icons.add),
          tooltip: 'إضافة نوع',
        ),
      ],
      body: typesAsync.when(
        data: (types) {
          if (types.isEmpty) {
            return const Center(
              child: Text('لا توجد أنواع مصروفات'),
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: types.length,
            onReorder: (oldIndex, newIndex) async {
              // تصحيح الفهرس عند النقل للأسفل
              if (newIndex > oldIndex) newIndex--;
              final orderedIds = types.map((t) => t.id).toList();
              final item = orderedIds.removeAt(oldIndex);
              orderedIds.insert(newIndex, item);
              await reorderExpenseTypes(ref, orderedIds);
            },
            itemBuilder: (context, index) {
              final type = types[index];
              return _ExpenseTypeCard(
                key: ValueKey('expense_type_${type.id}'),
                type: type,
                onEdit: () => _showEditDialog(type),
                onDelete: type.isSystem ? null : () => _confirmDelete(type),
                onToggle: type.isSystem
                    ? null
                    : (value) => toggleExpenseTypeActive(ref, type.id, value),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('خطأ في تحميل أنواع المصروفات'),
              const SizedBox(height: 12),
              Text(error.toString(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => refreshExpenseTypes(ref),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة نوع مصروف جديد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم النوع',
            hintText: 'مثال: نقل',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _doAdd(ctx, controller),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => _doAdd(ctx, controller),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  Future<void> _doAdd(BuildContext ctx, TextEditingController controller) async {
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final ok = await addExpenseType(ref, name);
    if (ctx.mounted) {
      Navigator.pop(ctx);
      if (!ok) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('فشل الإضافة — ربما الاسم موجود مسبقاً'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditDialog(ExpenseTypeInfo type) {
    final controller = TextEditingController(text: type.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل نوع المصروف'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم النوع'),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _doEdit(ctx, type, controller),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => _doEdit(ctx, type, controller),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _doEdit(
    BuildContext ctx,
    ExpenseTypeInfo type,
    TextEditingController controller,
  ) async {
    final name = controller.text.trim();
    if (name.isEmpty || name == type.name) {
      Navigator.pop(ctx);
      return;
    }
    final ok = await updateExpenseType(ref, type.id, name);
    if (ctx.mounted) {
      Navigator.pop(ctx);
      if (!ok) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('فشل التعديل — ربما الاسم موجود مسبقاً'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmDelete(ExpenseTypeInfo type) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف "${type.name}"؟\n'
            'المصروفات المسجلة بهذا النوع لن تُحذف.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final ok = await deleteExpenseType(ref, type.id);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (!ok) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('لا يمكن حذف هذا النوع'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTypeCard extends StatelessWidget {
  const _ExpenseTypeCard({
    super.key,
    required this.type,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final ExpenseTypeInfo type;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // مقبض السحب
            ReorderableDragStartListener(
              index: 0, // سيتم تجاوزه بواسطة ReorderableListView
              child: Icon(
                Icons.drag_handle,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 12),

            // اسم النوع
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: type.isActive
                          ? null
                          : Colors.grey,
                      decoration: type.isActive
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                  if (type.isSystem)
                    Text(
                      'نوع نظامي',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                      ),
                    ),
                ],
              ),
            ),

            // مفتاح التفعيل
            if (onToggle != null)
              Switch(
                value: type.isActive,
                onChanged: onToggle,
                activeColor: Colors.green,
              ),

            // زر التعديل
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, size: 20),
              tooltip: 'تعديل',
              color: Colors.blue,
            ),

            // زر الحذف
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'حذف',
                color: Colors.red,
              ),
          ],
        ),
      ),
    );
  }
}
