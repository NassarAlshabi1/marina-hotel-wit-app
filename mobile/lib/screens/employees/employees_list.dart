// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/stream_helpers.dart';
import '../../utils/theme.dart';
import '../../utils/english_digits_input_formatter.dart';

class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});

  @override
  ConsumerState<EmployeesListScreen> createState() =>
      _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen>
    with SyncOnExitMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  String get screenId => 'employees_list';
  int _refreshCounter = 0;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ AutomaticKeepAlive
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
              stream: debounceStream(
                repo.watchAll(),
                const Duration(milliseconds: 150),
              ),
              builder: (context, snapshot) {
                // ✅ معالجة حالة الخطأ قبل hasData — بدونها يظهر loading مؤبداً
                // عند انفجار الـ stream بدل رسالة واضحة.
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'حدث خطأ أثناء تحميل الموظفين',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'تحقّق من اتصال الشبكة وحاول مرة أخرى.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        // ✅ زر إعادة محاولة يُشغّل مزامنة فعلية ويُعيد بناء الـ stream
                        ElevatedButton.icon(
                          onPressed: () {
                            ref.read(syncServiceProvider).runSync();
                            setState(() => _refreshCounter++);
                          },
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
                final list = snapshot.data ?? <Employee>[];

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
                          onTerminate: StatusUtils.isEmployeeActive(e.status)
                              ? () => _showTerminateDialog(context, ref, e)
                              : null,
                          onReactivate:
                              StatusUtils.isEmployeeTerminated(e.status)
                              ? () => _reactivateEmployee(context, ref, e)
                              : null,
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

  /// حوار إنهاء خدمة موظف
  void _showTerminateDialog(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) {
    String terminationType = 'مفصول';
    DateTime? terminationDate = DateTime.now();
    final reasonController = TextEditingController();

    showDialog<void>(
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
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_off, color: Colors.red),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('إنهاء خدمة موظف', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الموظف: ${employee.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),

                // نوع الإنهاء
                const Text(
                  'نوع الإنهاء *',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Column(
                      children: [
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text('فصل'),
                            ],
                          ),
                          value: 'مفصول',
                          // ignore: deprecated_member_use
                          groupValue: terminationType,
                          // ignore: deprecated_member_use
                          onChanged: (v) =>
                              setDialogState(() => terminationType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(
                                Icons.logout,
                                color: Colors.orange,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text('استقالة'),
                            ],
                          ),
                          value: 'استقالة',
                          // ignore: deprecated_member_use
                          groupValue: terminationType,
                          // ignore: deprecated_member_use
                          onChanged: (v) =>
                              setDialogState(() => terminationType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(
                                Icons.business_center,
                                color: Colors.grey,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text('استغناء'),
                            ],
                          ),
                          value: 'استغناء',
                          // ignore: deprecated_member_use
                          groupValue: terminationType,
                          // ignore: deprecated_member_use
                          onChanged: (v) =>
                              setDialogState(() => terminationType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // تاريخ الإنهاء
                StatefulBuilder(
                  builder: (context, setDialogState) {
                    return InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: terminationDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => terminationDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'تاريخ الإنهاء',
                          prefixIcon: const Icon(Icons.calendar_today),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          terminationDate != null
                              ? '${terminationDate!.year}/${terminationDate!.month.toString().padLeft(2, '0')}/${terminationDate!.day.toString().padLeft(2, '0')}'
                              : 'اختر التاريخ',
                          style: TextStyle(
                            color: terminationDate != null
                                ? Colors.black
                                : Colors.grey,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // سبب الإنهاء
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'سبب الإنهاء (اختياري)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.info_outline),
                  ),
                  maxLines: 2,
                ),

                const SizedBox(height: 16),

                // تحذير
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سيتم إيقاف صرف السلف والرواتب تلقائياً لهذا الموظف',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final dateStr = terminationDate != null
                    ? '${terminationDate!.year}-${terminationDate!.month.toString().padLeft(2, '0')}-${terminationDate!.day.toString().padLeft(2, '0')}'
                    : DateTime.now().toString().split(' ')[0];

                try {
                  final repo = ref.read(employeesRepoProvider);
                  await repo.terminate(
                    id: employee.id,
                    terminationType: terminationType,
                    terminationDate: dateStr,
                    terminationReason: reasonController.text.trim(),
                  );

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تم إنهاء خدمة ${employee.name} ($terminationType)',
                        ),
                        backgroundColor: Colors.orange,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('فشل إنهاء الخدمة: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.person_off, size: 18),
              label: const Text('إنهاء الخدمة'),
            ),
          ],
        ),
      ),
    ).then((_) {
      reasonController.dispose();
    });
  }

  /// إعادة تفعيل موظف مفصول
  Future<void> _reactivateEmployee(
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
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_add, color: Colors.green),
              ),
              const SizedBox(width: 12),
              const Text('إعادة تفعيل الموظف'),
            ],
          ),
          content: Text(
            'هل تريد إعادة تفعيل الموظف "${employee.name}"؟\n'
            'سيتم تغيير الحالة إلى "نشط" ومسح بيانات إنهاء الخدمة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إعادة التفعيل'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(employeesRepoProvider);
      await repo.reactivate(id: employee.id);
      markDataChanged();
      // ✅ رفع فوري لإعادة تفعيل موظف إلى Appwrite Cloud.
      unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إعادة تفعيل الموظف بنجاح'),
            backgroundColor: AppColors.successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إعادة التفعيل: $e'),
            backgroundColor: AppColors.dangerColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

    if (confirm != true) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(employeesRepoProvider);
      await repo.delete(employee.id);
      markDataChanged();
      // ✅ رفع فوري لحذف موظف إلى Appwrite Cloud.
      unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());
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
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
    final positionCtrl = TextEditingController(
      text: existing?.position ?? 'موظف',
    );
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');

    String status = existing != null
        ? StatusUtils.employeeStatusLabel(existing.status)
        : 'نشط';
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [englishIntegerInputFormatter],
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
                    inputFormatters: const [englishIntegerInputFormatter],
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
                          initialValue: status,
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
                            DropdownMenuItem(
                              value: 'مفصول',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_off,
                                    color: Colors.red,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('مفصول'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'استقالة',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.logout,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('استقالة'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'استغناء',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.business_center,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('استغناء'),
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
                if (formKey.currentState?.validate() ?? false) {
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
    nameCtrl.dispose();
    salaryCtrl.dispose();
    positionCtrl.dispose();
    phoneCtrl.dispose();
    if (ok != true) {
      return;
    }

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
      // ✅ رفع فوري لموظف جديد/محدَّث إلى Appwrite Cloud.
      unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الموظف: $e'),
          backgroundColor: AppColors.dangerColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.onTap,
    required this.onDelete,
    this.onTerminate,
    this.onReactivate,
  });
  final Employee employee;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onTerminate;
  final VoidCallback? onReactivate;

  @override
  Widget build(BuildContext context) {
    final isActive = StatusUtils.isEmployeeActive(employee.status);
    final isTerminated = StatusUtils.isEmployeeTerminated(employee.status);
    final statusLabel = StatusUtils.employeeStatusLabel(employee.status);
    final statusColor = Color(StatusUtils.employeeStatusColor(employee.status));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: statusColor.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            children: [
              // صورة رمزية للموظف
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Icon(
                  isTerminated ? Icons.person_off : Icons.person,
                  color: statusColor,
                  size: 14,
                ),
              ),
              const SizedBox(width: 5),

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
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              decoration: isTerminated
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isActive
                                    ? Icons.check_circle
                                    : isTerminated
                                    ? Icons.person_off
                                    : Icons.cancel,
                                size: 10,
                                color: statusColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        // المنصب
                        if (employee.position.isNotEmpty &&
                            employee.position != 'موظف') ...[
                          const Icon(
                            Icons.badge,
                            size: 9,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              employee.position,
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        // الراتب
                        const Icon(
                          Icons.attach_money,
                          size: 9,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 1),
                        Text(
                          CurrencyFormatter.formatAmount(employee.basicSalary),
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    // رقم الهاتف
                    if (employee.phone.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone,
                            size: 9,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 1),
                          Text(
                            employee.phone,
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // تاريخ وسبب إنهاء الخدمة
                    if (isTerminated &&
                        employee.terminationDate != null &&
                        employee.terminationDate!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          const Icon(
                            Icons.event_busy,
                            size: 9,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 1),
                          Text(
                            'إنهاء: ${employee.terminationDate}',
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // أزرار العمليات — بجانب بعض أفقياً
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onTerminate != null)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        onPressed: onTerminate,
                        icon: const Icon(Icons.person_off, size: 12),
                        color: Colors.red,
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                        ),
                        tooltip: 'إنهاء خدمة',
                      ),
                    ),
                  if (onReactivate != null)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        onPressed: onReactivate,
                        icon: const Icon(Icons.person_add, size: 12),
                        color: Colors.green,
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.green.withValues(alpha: 0.1),
                        ),
                        tooltip: 'إعادة تفعيل',
                      ),
                    ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 12),
                      color: AppColors.dangerColor,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.dangerColor.withValues(
                          alpha: 0.1,
                        ),
                      ),
                      tooltip: 'حذف',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
