import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/theme.dart';
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
  int _refreshCounter = 0;
  bool _isLoading = false;

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
            tooltip: 'مزامنة',
          ),
          IconButton(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add),
            tooltip: 'إضافة موظف',
          ),
        ],
        body: Stack(
          children: [
            StreamBuilder(
              stream: repo.watchAll(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data!;

                if (list.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _refreshCounter++);
                  },
                  child: ListView.builder(
                    key: ValueKey(_refreshCounter),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final e = list[i];
                      return RepaintBoundary(
                        child: _EmployeeCard(
                          employee: e,
                          onTap: () => _edit(context, ref, existing: e),
                          onDelete: () => _deleteEmployee(context, ref, e),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            if (_isLoading)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              Icons.people_outline,
              size: 50,
              color: AppColors.primaryColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'لا يوجد موظفون',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'ابدأ بإضافة موظف جديد',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('إضافة موظف'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmployee(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.dangerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete_forever,
                  color: AppColors.dangerColor,
                ),
              ),
              const SizedBox(width: 12),
              const Text('حذف الموظف'),
            ],
          ),
          content: Text('هل أنت متأكد من حذف الموظف "${employee.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerColor,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(employeesRepoProvider);
      await repo.delete(employee.id);
      markDataChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الموظف بنجاح'),
            backgroundColor: AppColors.successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حذف الموظف: $e'),
            backgroundColor: AppColors.dangerColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    Employee? existing,
  }) async {
    final formKey = GlobalKey<FormState>();

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final salaryCtrl = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.basicSalary)
          : '',
    );
    final positionCtrl =
        TextEditingController(text: existing?.position ?? 'موظف');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');

    String status = existing?.status ?? 'نشط';
    DateTime? hireDate;
    if (existing != null && existing.hireDate.isNotEmpty) {
      hireDate = DateTime.tryParse(existing.hireDate);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  existing == null ? Icons.person_add : Icons.edit,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  existing == null ? 'إضافة موظف جديد' : 'تعديل بيانات الموظف',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // اسم الموظف
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم الموظف *',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'أدخل اسم الموظف';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // المنصب / الوظيفة
                  TextFormField(
                    controller: positionCtrl,
                    decoration: InputDecoration(
                      labelText: 'المنصب / الوظيفة',
                      prefixIcon: const Icon(Icons.badge),
                      hintText: 'مثال: موظف استقبال، نادل، مدير',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // الراتب الأساسي
                  TextFormField(
                    controller: salaryCtrl,
                    decoration: InputDecoration(
                      labelText: 'الراتب الأساسي *',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'أدخل الراتب';
                      }
                      final salary = CurrencyFormatter.parseAmount(v);
                      if (salary == null || salary < 0) {
                        return 'أدخل راتباً صحيحاً';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // رقم الهاتف
                  TextFormField(
                    controller: phoneCtrl,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف',
                      prefixIcon: const Icon(Icons.phone),
                      hintText: 'مثال: 0912345678',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),

                  // تاريخ التعيين
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      return InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: hireDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            locale: const Locale('ar'),
                          );
                          if (picked != null) {
                            setLocalState(() => hireDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'تاريخ التعيين',
                            prefixIcon: const Icon(Icons.calendar_today),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            hireDate != null
                                ? '${hireDate!.year}/${hireDate!.month.toString().padLeft(2, '0')}/${hireDate!.day.toString().padLeft(2, '0')}'
                                : 'اختر تاريخ التعيين',
                            style: TextStyle(
                              color: hireDate != null
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // الحالة
                  StatefulBuilder(
                    builder: (context, setLocalState) =>
                        DropdownButtonFormField<String>(
                          value: status,
                          decoration: InputDecoration(
                            labelText: 'الحالة',
                            prefixIcon: const Icon(Icons.toggle_on),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'نشط',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: AppColors.successColor,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('نشط'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'غير نشط',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cancel,
                                    color: AppColors.dangerColor,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('غير نشط'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setLocalState(() => status = v ?? status),
                        ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(ctx, true);
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _isLoading = true);
    final repo = ref.read(employeesRepoProvider);

    try {
      // تحضير تاريخ التعيين كنص
      final hireDateStr = hireDate != null
          ? '${hireDate!.year}-${hireDate!.month.toString().padLeft(2, '0')}-${hireDate!.day.toString().padLeft(2, '0')}'
          : '';

      if (existing == null) {
        await repo.create(
          name: nameCtrl.text.trim(),
          basicSalary: CurrencyFormatter.parseAmount(salaryCtrl.text) ?? 0,
          position: positionCtrl.text.trim().isEmpty
              ? 'موظف'
              : positionCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          hireDate: hireDateStr,
          status: status,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تمت إضافة الموظف بنجاح'),
              backgroundColor: AppColors.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await repo.update(
          existing.id,
          name: nameCtrl.text.trim(),
          basicSalary: CurrencyFormatter.parseAmount(salaryCtrl.text) ?? 0,
          position: positionCtrl.text.trim().isEmpty
              ? 'موظف'
              : positionCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          hireDate: hireDateStr,
          status: status,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تعديل بيانات الموظف بنجاح'),
              backgroundColor: AppColors.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      markDataChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الموظف: $e'),
          backgroundColor: AppColors.dangerColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EmployeeCard({
    required this.employee,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = employee.status == 'نشط';
    final statusColor = isActive ? AppColors.successColor : AppColors.dangerColor;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.2), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // صورة رمزية للموظف
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  isActive ? Icons.person : Icons.person_off,
                  color: AppColors.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // بيانات الموظف
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            employee.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isActive
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 12,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isActive ? 'نشط' : 'غير نشط',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // المنصب
                        if (employee.position.isNotEmpty &&
                            employee.position != 'موظف') ...[
                          Icon(
                            Icons.badge,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            employee.position,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 10),
                        ],
                        // الراتب
                        Icon(
                          Icons.attach_money,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          CurrencyFormatter.formatAmount(employee.basicSalary),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // رقم الهاتف
                    if (employee.phone.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            employee.phone,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // زر الحذف
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.dangerColor,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.dangerColor.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
