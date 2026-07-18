// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/salary_entitlement_service.dart';
import '../../services/sync_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/status_utils.dart';
import '../employees/salary_entitlements_screen.dart';

class SettingsEmployeesScreen extends ConsumerWidget {
  const SettingsEmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeesAsync = ref.watch(employeesListProvider);

    return AppScaffold(
      title: 'إدارة الموظفين',
      actions: [
        IconButton(
          onPressed: () =>
              Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const SalaryEntitlementsScreen())),
          icon: const Icon(Icons.account_balance_wallet),
          tooltip: 'استحقاقات الرواتب',
        ),
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
        IconButton(
          onPressed: () => _showAddEmployeeDialog(context, ref),
          icon: const Icon(Icons.add),
          tooltip: 'إضافة موظف',
        ),
      ],
      body: employeesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('خطأ: $e', textAlign: TextAlign.center),
            ],
          ),
        ),
        data: (employees) {
          if (employees.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('لا يوجد موظفين مسجلين', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEmployeeDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة موظف جديد'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // إحصائيات الموظفين
              _buildEmployeeStats(employees),
              const SizedBox(height: 16),

              // قائمة الموظفين
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(employeesListProvider);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: employees.length,
                    itemBuilder: (context, index) {
                      final employee = employees[index];
                      return RepaintBoundary(child: _buildEmployeeCard(context, ref, employee));
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmployeeStats(List<Employee> employees) {
    final activeEmployees = employees.where((e) => StatusUtils.isEmployeeActive(e.status)).length;
    final terminatedEmployees = employees.where((e) => StatusUtils.isEmployeeTerminated(e.status)).length;
    final otherEmployees = employees.length - activeEmployees - terminatedEmployees;
    final totalSalaries = employees
        .where((e) => StatusUtils.isEmployeeActive(e.status))
        .fold<double>(0.0, (sum, e) => sum + e.salary);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue, size: 24),
              SizedBox(width: 8),
              Text('إحصائيات الموظفين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatChip('إجمالي', employees.length, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('نشط', activeEmployees, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('منهية', terminatedEmployees, Colors.red)),
            ],
          ),
          if (otherEmployees > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildStatChip('أخرى', otherEmployees, Colors.grey)),
                const Expanded(child: SizedBox()),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.attach_money, color: Colors.green, size: 20),
                const SizedBox(width: 4),
                Text(
                  'إجمالي الرواتب: ${CurrencyFormatter.formatAmount(totalSalaries)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(BuildContext context, WidgetRef ref, Employee employee) {
    final isActive = StatusUtils.isEmployeeActive(employee.status);
    final isTerminated = StatusUtils.isEmployeeTerminated(employee.status);
    final statusLabel = StatusUtils.employeeStatusLabel(employee.status);
    final statusColor = Color(StatusUtils.employeeStatusColor(employee.status));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معلومات أساسية
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor,
                  child: Icon(isTerminated ? Icons.person_off : Icons.person, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: isTerminated ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(employee.position, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // تفاصيل إضافية
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow('الراتب', CurrencyFormatter.formatAmount(employee.salary), Icons.attach_money),
                ),
                Expanded(child: _buildDetailRow('الهاتف', employee.phone, Icons.phone)),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(child: _buildDetailRow('تاريخ التوظيف', employee.hireDate, Icons.calendar_today)),
                Expanded(child: _buildDetailRow('رقم الموظف', employee.localUuid, Icons.badge)),
              ],
            ),

            // عرض تاريخ وسبب إنهاء الخدمة إذا كان مفصولاً
            if (isTerminated) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (employee.terminationDate != null && employee.terminationDate!.isNotEmpty)
                      _buildDetailRow('تاريخ الإنهاء', employee.terminationDate!, Icons.event_busy),
                    if (employee.terminationReason != null && employee.terminationReason!.isNotEmpty)
                      _buildDetailRow('السبب', employee.terminationReason!, Icons.info_outline),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // أزرار العمليات — صف أول
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditEmployeeDialog(context, ref, employee),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('تعديل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showEmployeeEntitlement(context, ref, employee),
                    icon: const Icon(Icons.account_balance_wallet, size: 16),
                    label: const Text('الاستحقاق', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showSalaryWithdrawalDialog(context, ref, employee),
                      icon: const Icon(Icons.money_off, size: 16),
                      label: const Text('سحب', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // أزرار العمليات — صف ثاني
            Row(
              children: [
                if (isActive)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showTerminateDialog(context, ref, employee),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('إنهاء'),
                    ),
                  )
                else if (isTerminated)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reactivateEmployee(context, ref, employee),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                      ),
                      child: const Text('إعادة'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _toggleEmployeeStatus(context, ref, employee),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isActive ? Colors.red : Colors.green,
                        side: BorderSide(color: isActive ? Colors.red : Colors.green),
                      ),
                      child: Text(isActive ? 'إيقاف' : 'تفعيل'),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _deleteEmployee(context, ref, employee),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red,
                  style: IconButton.styleFrom(backgroundColor: Colors.red.withValues(alpha: 0.1)),
                  tooltip: 'حذف الموظف',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(
                value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddEmployeeDialog(BuildContext context, WidgetRef ref) {
    _showEmployeeDialog(context, ref, null);
  }

  void _showEditEmployeeDialog(BuildContext context, WidgetRef ref, Employee employee) {
    _showEmployeeDialog(context, ref, employee);
  }

  void _showEmployeeDialog(BuildContext context, WidgetRef ref, Employee? employee) {
    final nameController = TextEditingController(text: employee?.name ?? '');
    final positionController = TextEditingController(text: employee?.position ?? '');
    final salaryController = TextEditingController(text: employee?.salary.toString() ?? '');
    final phoneController = TextEditingController(text: employee?.phone ?? '');
    final hireDateController = TextEditingController(
      // ✅ استخدام اليوم الفندقي كتاريخ افتراضي عند إضافة موظف جديد
      text: employee?.hireDate ?? HotelTimeEngine.getHotelDayKey(),
    );
    String status = employee?.status ?? 'نشط';

    showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(employee == null ? 'إضافة موظف جديد' : 'تعديل بيانات الموظف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'اسم الموظف*', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: positionController,
                  decoration: const InputDecoration(labelText: 'المنصب*', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salaryController,
                  decoration: const InputDecoration(labelText: 'الراتب*', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hireDateController,
                  decoration: const InputDecoration(labelText: 'تاريخ التوظيف', border: OutlineInputBorder()),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      // ✅ استخدام اليوم الفندقي كتاريخ مبدئي
                      initialDate: HotelTimeEngine.getHotelDay(DateTime.now()),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2030),
                    );
                    if (date != null) {
                      hireDateController.text = date.toString().split(' ')[0];
                    }
                  },
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'الحالة', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'نشط', child: Text('نشط')),
                    DropdownMenuItem(value: 'غير نشط', child: Text('غير نشط')),
                    DropdownMenuItem(value: 'مجمد', child: Text('مجمد')),
                    DropdownMenuItem(value: 'مفصول', child: Text('مفصول')),
                    DropdownMenuItem(value: 'استقالة', child: Text('استقالة')),
                    DropdownMenuItem(value: 'استغناء', child: Text('استغناء')),
                  ],
                  onChanged: (value) => status = value ?? status,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty ||
                    positionController.text.trim().isEmpty ||
                    salaryController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('يرجى تعبئة الحقول المطلوبة')));
                  return;
                }

                // ✅ P0 fix: التحقق من صحة الراتب قبل الحفظ
                final salary = double.tryParse(salaryController.text);
                if (salary == null || salary < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('قيمة الراتب غير صحيحة — يرجى إدخال رقم موجب'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final repo = ref.read(employeesRepoProvider);
                try {
                  if (employee == null) {
                    await repo.create(
                      name: nameController.text.trim(),
                      position: positionController.text.trim(),
                      salary: salary,
                      phone: phoneController.text.trim(),
                      hireDate: hireDateController.text,
                      status: status,
                    );
                  } else {
                    await repo.updateByLocalUuid(
                      employee.localUuid,
                      name: nameController.text.trim(),
                      position: positionController.text.trim(),
                      salary: salary,
                      phone: phoneController.text.trim(),
                      hireDate: hireDateController.text,
                      status: status,
                    );
                  }
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(employee == null ? 'تم إضافة الموظف بنجاح' : 'تم تحديث بيانات الموظف')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                }
              },
              child: Text(employee == null ? 'إضافة' : 'تحديث'),
            ),
          ],
        ),
      ),
    ).then((_) {
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكمات بعد إغلاق الحوار
      nameController.dispose();
      positionController.dispose();
      salaryController.dispose();
      phoneController.dispose();
      hireDateController.dispose();
    });
  }

  /// حوار إنهاء خدمة موظف
  void _showTerminateDialog(BuildContext context, WidgetRef ref, Employee employee) {
    String terminationType = 'مفصول';
    // ✅ استخدام اليوم الفندقي كتاريخ افتراضي للإنهاء
    DateTime? terminationDate = HotelTimeEngine.getHotelDay(DateTime.now());
    final reasonController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              const Expanded(child: Text('إنهاء خدمة موظف', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الموظف: ${employee.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),

                // نوع الإنهاء
                const Text('نوع الإنهاء *', style: TextStyle(fontWeight: FontWeight.w500)),
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
                          onChanged: (v) => setDialogState(() => terminationType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.logout, color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Text('استقالة'),
                            ],
                          ),
                          value: 'استقالة',
                          // ignore: deprecated_member_use
                          groupValue: terminationType,
                          // ignore: deprecated_member_use
                          onChanged: (v) => setDialogState(() => terminationType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.business_center, color: Colors.grey, size: 20),
                              SizedBox(width: 8),
                              Text('استغناء'),
                            ],
                          ),
                          value: 'استغناء',
                          // ignore: deprecated_member_use
                          groupValue: terminationType,
                          // ignore: deprecated_member_use
                          onChanged: (v) => setDialogState(() => terminationType = v!),
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
                          // ✅ استخدام اليوم الفندقي كتاريخ مبدئي
                          initialDate: terminationDate ?? HotelTimeEngine.getHotelDay(DateTime.now()),
                          firstDate: DateTime(2000),
                          lastDate: HotelTimeEngine.getHotelDay(DateTime.now()).add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => terminationDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'تاريخ الإنهاء',
                          prefixIcon: const Icon(Icons.calendar_today),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          terminationDate != null
                              ? '${terminationDate!.year}/${terminationDate!.month.toString().padLeft(2, '0')}/${terminationDate!.day.toString().padLeft(2, '0')}'
                              : 'اختر التاريخ',
                          style: TextStyle(color: terminationDate != null ? Colors.black : Colors.grey),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                // ✅ استخدام اليوم الفندقي في تاريخ الإنهاء
                final dateStr = terminationDate != null
                    ? '${terminationDate!.year}-${terminationDate!.month.toString().padLeft(2, '0')}-${terminationDate!.day.toString().padLeft(2, '0')}'
                    : HotelTimeEngine.getHotelDayKey();

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
                        content: Text('تم إنهاء خدمة ${employee.name} ($terminationType)'),
                        backgroundColor: Colors.orange,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('فشل إنهاء الخدمة: $e'), backgroundColor: Colors.red));
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
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكم بعد إغلاق الحوار
      reasonController.dispose();
    });
  }

  /// إعادة تفعيل موظف مفصول
  Future<void> _reactivateEmployee(BuildContext context, WidgetRef ref, Employee employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
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

    try {
      final repo = ref.read(employeesRepoProvider);
      await repo.reactivate(id: employee.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إعادة تفعيل الموظف بنجاح'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل إعادة التفعيل: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showEmployeeEntitlement(BuildContext context, WidgetRef ref, Employee employee) async {
    final service = SalaryEntitlementService(ref.read(databaseProvider));

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final entitlement = await service.calculateEmployeeEntitlement(employee);
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (!context.mounted) {
        return;
      }

      final isPositive = entitlement.netEntitlement >= 0;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('استحقاق ${employee.name}', style: const TextStyle(fontSize: 14)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _entitlementRow(
                    'تاريخ التعيين',
                    '${entitlement.hireDate.year}-${entitlement.hireDate.month}-${entitlement.hireDate.day}',
                  ),
                  _entitlementRow('مدة العمل', '${entitlement.totalMonthsWorked} شهر'),
                  _entitlementRow('الراتب الشهري', CurrencyFormatter.formatAmount(entitlement.basicSalary)),
                  const Divider(),
                  _entitlementRow(
                    'إجمالي الاستحقاق',
                    CurrencyFormatter.formatAmount(entitlement.totalEntitlement),
                    Colors.green,
                  ),
                  _entitlementRow(
                    'السحبيات',
                    '- ${CurrencyFormatter.formatAmount(entitlement.totalWithdrawals)}',
                    Colors.orange,
                  ),
                  _entitlementRow(
                    'السلف',
                    '- ${CurrencyFormatter.formatAmount(entitlement.totalAdvances)}',
                    Colors.indigo,
                  ),
                  if (entitlement.totalAdvances > 0)
                    _entitlementRow(
                      'رصيد السلف المتبقي',
                      CurrencyFormatter.formatAmount(entitlement.advanceBalance),
                      entitlement.advanceBalance > 0 ? Colors.indigo.shade300 : Colors.grey,
                    ),
                  _entitlementRow(
                    'الخصومات',
                    '- ${CurrencyFormatter.formatAmount(entitlement.totalDeductions)}',
                    Colors.red,
                  ),
                  const Divider(),
                  _entitlementRow(
                    'المتبقي',
                    CurrencyFormatter.formatAmount(entitlement.netEntitlement),
                    isPositive ? Colors.green : Colors.red,
                    true,
                  ),
                ],
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  Widget _entitlementRow(String label, String value, [Color? color, bool bold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          ),
        ],
      ),
    );
  }

  void _showSalaryWithdrawalDialog(BuildContext context, WidgetRef ref, Employee employee) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String withdrawalType = 'سلفة';
    // ✅ إصلاح: استخدام اليوم الفندقي بدلاً من اليوم التقويمي
    // إذا كانت الساعة 2 صباحاً من 4 يونيو → اليوم الفندقي = 3 يونيو
    DateTime selectedDate = HotelTimeEngine.getHotelDay(DateTime.now());

    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.money_off, color: Colors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('سحب راتب - ${employee.name}', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_money, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'الراتب الأساسي: ${CurrencyFormatter.formatAmount(employee.salary)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // نوع السحب
                const Text('نوع السحب *', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Column(
                      children: [
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.trending_up, color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Text('سلفة'),
                            ],
                          ),
                          value: 'سلفة',
                          // ignore: deprecated_member_use
                          groupValue: withdrawalType,
                          // ignore: deprecated_member_use
                          onChanged: (v) => setDialogState(() => withdrawalType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: Colors.purple, size: 20),
                              SizedBox(width: 8),
                              Text('سحب راتب'),
                            ],
                          ),
                          value: 'سحب راتب',
                          // ignore: deprecated_member_use
                          groupValue: withdrawalType,
                          // ignore: deprecated_member_use
                          onChanged: (v) => setDialogState(() => withdrawalType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.build, color: Colors.grey, size: 20),
                              SizedBox(width: 8),
                              Text('أخرى'),
                            ],
                          ),
                          value: 'أخرى',
                          // ignore: deprecated_member_use
                          groupValue: withdrawalType,
                          // ignore: deprecated_member_use
                          onChanged: (v) => setDialogState(() => withdrawalType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'المبلغ المسحوب *',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.attach_money),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),

                // ✅ إصلاح: إضافة منتقي تاريخ مع اليوم الفندقي كافتراضي
                StatefulBuilder(
                  builder: (context, setDialogState) {
                    return GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'التاريخ', suffixIcon: Icon(Icons.calendar_today)),
                        child: Text(
                          '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final amountText = amountController.text.trim();
                if (amountText.isEmpty) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(const SnackBar(content: Text('يرجى إدخال المبلغ'), backgroundColor: Colors.red));
                  return;
                }

                final amount = double.tryParse(amountText);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('يرجى إدخال مبلغ صحيح أكبر من صفر'), backgroundColor: Colors.red),
                  );
                  return;
                }

                try {
                  final repo = ref.read(salaryWithdrawalsRepoProvider);
                  // ✅ إصلاح: استخدام selectedDate (اليوم الفندقي) بدلاً من DateTime.now()
                  final dateStr =
                      '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                  // حساب hotelDayKey من التاريخ المختار باستخدام 14:01
                  // لضمان أن التاريخ التقويمي يُطابق نفس اليوم الفندقي
                  final hotelDayKey = HotelTimeEngine.getHotelDayKey(
                    dateTime: DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 14, 1),
                  );

                  await repo.createFromExpense(
                    expenseId: 0, // لا يوجد مصروف مرتبط — سحب مباشر
                    employeeId: employee.id,
                    reason: 'direct_withdrawal_${employee.localUuid}',
                    amount: amount,
                    date: dateStr,
                    hotelDayKey: hotelDayKey,
                    withdrawalType: withdrawalType,
                    description: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                  );

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تسجيل سحب ${CurrencyFormatter.formatAmount(amount)} $withdrawalType بنجاح'),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('فشل تسجيل السحب: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('تسجيل السحب'),
            ),
          ],
        ),
      ),
    ).then((_) {
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكمات بعد إغلاق الحوار
      amountController.dispose();
      noteController.dispose();
    });
  }

  Future<void> _deleteEmployee(BuildContext context, WidgetRef ref, Employee employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_forever, color: Colors.red),
              ),
              const SizedBox(width: 12),
              const Text('حذف الموظف'),
            ],
          ),
          content: Text(
            'هل أنت متأكد من حذف الموظف "${employee.name}"؟\n'
            'سيتم حذف الموظف نهائياً ومزامنة الحذف مع السحابة.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    try {
      final repo = ref.read(employeesRepoProvider);
      await repo.delete(employee.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الموظف بنجاح'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حذف الموظف: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleEmployeeStatus(BuildContext context, WidgetRef ref, Employee employee) async {
    final newStatus = StatusUtils.isEmployeeActive(employee.status) ? 'غير نشط' : 'نشط';

    try {
      final repo = ref.read(employeesRepoProvider);
      await repo.updateByLocalUuid(
        employee.localUuid,
        name: employee.name,
        position: employee.position,
        salary: employee.salary,
        phone: employee.phone,
        hireDate: employee.hireDate,
        status: newStatus,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم ${newStatus == 'نشط' ? 'تفعيل' : 'إيقاف'} الموظف')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }
}
