import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/auth_provider.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(inventoryItemsProvider);
    return AppScaffold(
      title: 'المخزون',
      actions: [
        IconButton(
          tooltip: 'إضافة صنف',
          onPressed: () => _showAddItemDialog(context, ref),
          icon: const Icon(Icons.add, size: 20),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => _showAddItemDialog(context, ref),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('إضافة صنف'),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'تعذر تحميل المخزون: $error',
            textAlign: TextAlign.center,
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text('لا توجد أصناف. أضف أول صنف للمخزون.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _InventoryItemCard(item: items[index]),
          );
        },
      ),
    );
  }

  static Future<void> _showAddItemDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final unitController = TextEditingController(text: 'قطعة');
    final categoryController = TextEditingController();
    final initialController = TextEditingController(text: '0');
    final minimumController = TextEditingController(text: '0');

    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('إضافة صنف للمخزون'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'اسم الصنف'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'اسم الصنف مطلوب'
                        : null,
                  ),
                  TextFormField(
                    controller: unitController,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                  ),
                  TextFormField(
                    controller: categoryController,
                    decoration: const InputDecoration(
                      labelText: 'التصنيف (اختياري)',
                    ),
                  ),
                  TextFormField(
                    controller: initialController,
                    decoration: const InputDecoration(
                      labelText: 'الرصيد الافتتاحي',
                    ),
                    keyboardType: TextInputType.number,
                    validator: _validateNonNegativeInteger,
                  ),
                  TextFormField(
                    controller: minimumController,
                    decoration: const InputDecoration(
                      labelText: 'حد التنبيه الأدنى',
                    ),
                    keyboardType: TextInputType.number,
                    validator: _validateNonNegativeInteger,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'name': nameController.text,
                  'unit': unitController.text,
                  'category': categoryController.text,
                  'initial': initialController.text,
                  'minimum': minimumController.text,
                });
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (values == null) return;

      await ref
          .read(inventoryRepoProvider)
          .createItem(
            name: values['name']!,
            unit: values['unit']!,
            category: values['category'],
            initialQuantity: int.parse(values['initial']!),
            minimumQuantity: int.parse(values['minimum']!),
          );
      if (context.mounted) {
        _showMessage(context, 'تمت إضافة الصنف');
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, 'تعذر إضافة الصنف: $error');
    } finally {
      nameController.dispose();
      unitController.dispose();
      categoryController.dispose();
      initialController.dispose();
      minimumController.dispose();
    }
  }

  static String? _validateNonNegativeInteger(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 ? 'أدخل رقماً صحيحاً غير سالب' : null;
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InventoryItemCard extends ConsumerWidget {
  const _InventoryItemCard({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLow =
        item.minimumQuantity > 0 && item.quantity <= item.minimumQuantity;
    final balanceColor = isLow ? Colors.orange.shade800 : Colors.green.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isLow
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  child: Icon(
                    isLow ? Icons.warning_amber_rounded : Icons.inventory_2,
                    size: 20,
                    color: balanceColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        [
                          if (item.category?.isNotEmpty == true) item.category!,
                          'الوحدة: ${item.unit}',
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${item.quantity}',
                      style: TextStyle(
                        color: balanceColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(item.unit, style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showMovementDialog(context, ref, item, 'in'),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('وارد'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showMovementDialog(context, ref, item, 'out'),
                    icon: const Icon(Icons.remove, size: 16),
                    label: const Text('صرف'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showStockDialog(context, ref, item),
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('جرد'),
                  ),
                ),
              ],
            ),
            if (isLow)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'تنبيه: الرصيد وصل إلى الحد الأدنى (${item.minimumQuantity})',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMovementDialog(
    BuildContext context,
    WidgetRef ref,
    InventoryItem item,
    String movementType,
  ) async {
    final quantityController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(movementType == 'in' ? 'إضافة وارد' : 'تسجيل صرف'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('الصنف: ${item.name} (${item.quantity} ${item.unit})'),
                TextFormField(
                  controller: quantityController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'الكمية (${item.unit})',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    return parsed == null || parsed <= 0
                        ? 'أدخل كمية أكبر من صفر'
                        : null;
                  },
                ),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, {
                    'quantity': quantityController.text,
                    'note': noteController.text,
                  });
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (values == null) return;
      final user = ref.read(authProvider).currentUser;
      await ref
          .read(inventoryRepoProvider)
          .recordMovement(
            itemId: item.id,
            movementType: movementType,
            quantity: int.parse(values['quantity']!),
            note: values['note'],
            userId: user?.id,
            userName: user?.name,
          );
      if (context.mounted) {
        _showMessage(
          context,
          movementType == 'in' ? 'تم تسجيل الوارد' : 'تم تسجيل الصرف',
        );
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, 'تعذر تسجيل الحركة: $error');
    } finally {
      quantityController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _showStockDialog(
    BuildContext context,
    WidgetRef ref,
    InventoryItem item,
  ) async {
    final quantityController = TextEditingController(text: '${item.quantity}');
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('جرد المخزون'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('الرصيد الحالي: ${item.quantity} ${item.unit}'),
                TextFormField(
                  controller: quantityController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'الرصيد الفعلي (${item.unit})',
                  ),
                  keyboardType: TextInputType.number,
                  validator: InventoryScreen._validateNonNegativeInteger,
                ),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, {
                    'quantity': quantityController.text,
                    'note': noteController.text,
                  });
                }
              },
              child: const Text('اعتماد الجرد'),
            ),
          ],
        ),
      );
      if (values == null) return;
      final user = ref.read(authProvider).currentUser;
      await ref
          .read(inventoryRepoProvider)
          .setStock(
            itemId: item.id,
            actualQuantity: int.parse(values['quantity']!),
            note: values['note'],
            userId: user?.id,
            userName: user?.name,
          );
      if (context.mounted) _showMessage(context, 'تم اعتماد الجرد');
    } catch (error) {
      if (context.mounted) _showMessage(context, 'تعذر اعتماد الجرد: $error');
    } finally {
      quantityController.dispose();
      noteController.dispose();
    }
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
