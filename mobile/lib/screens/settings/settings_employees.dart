import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';

class SettingsEmployeesScreen extends ConsumerWidget {
  const SettingsEmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeesAsync = ref.watch(employeesListProvider);

    return AppScaffold(
      title: 'إدارة الموظفين',
      actions: [
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
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    return _buildEmployeeCard(context, ref, employee);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmployeeStats(List<Employee> employees) {
    final activeEmployees = employees.where((e) => e.status == 'نشط').length;
    final inactiveEmployees = employees.length - activeEmployees;
    final totalSalaries = employees
        .where((e) => e.status == 'نشط')
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
              Text(
                'إحصائيات الموظفين',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatChip('إجمالي', employees.length, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('نشط', activeEmployees, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('غير نشط', inactiveEmployees, Colors.red)),
            ],
          ),
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
                  'إجمالي الرواتب: ${totalSalaries.toStringAsFixed(0)} ر.س',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(BuildContext context, WidgetRef ref, Employee employee) {
    final isActive = employee.status == 'نشط';
    
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
                  backgroundColor: isActive ? Colors.green : Colors.red,
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        employee.position,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? Colors.green : Colors.red,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    employee.status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // تفاصيل إضافية
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow('الراتب', '${employee.salary.toStringAsFixed(0)} ر.س', Icons.attach_money),
                ),
                Expanded(
                  child: _buildDetailRow('الهاتف', employee.phone, Icons.phone),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow('تاريخ التوظيف', employee.hireDate, Icons.calendar_today),
                ),
                Expanded(
                  child: _buildDetailRow('رقم الموظف', employee.localUuid, Icons.badge),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // أزرار العمليات
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
                    onPressed: () => _showSalaryWithdrawalDialog(context, ref, employee),
                    icon: const Icon(Icons.money_off, size: 16),
                    label: const Text('سحب راتب'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _toggleEmployeeStatus(context, ref, employee),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isActive ? Colors.red : Colors.green,
                    side: BorderSide(color: isActive ? Colors.red : Colors.green),
                  ),
                  child: Text(isActive ? 'إيقاف' : 'تفعيل'),
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
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
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
    final hireDateController = TextEditingController(text: employee?.hireDate ?? DateTime.now().toString().split(' ')[0]);
    String status = employee?.status ?? 'نشط';

    showDialog(
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
                  decoration: const InputDecoration(
                    labelText: 'اسم الموظف*',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: positionController,
                  decoration: const InputDecoration(
                    labelText: 'المنصب*',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salaryController,
                  decoration: const InputDecoration(
                    labelText: 'الراتب*',
                    border: OutlineInputBorder(),
                    suffixText: 'ر.س',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hireDateController,
                  decoration: const InputDecoration(
                    labelText: 'تاريخ التوظيف',
                    border: OutlineInputBorder(),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
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
                  value: status,
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'نشط', child: Text('نشط')),
                    DropdownMenuItem(value: 'غير نشط', child: Text('غير نشط')),
                    DropdownMenuItem(value: 'مجمد', child: Text('مجمد')),
                  ],
                  onChanged: (value) => status = value ?? status,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty || 
                    positionController.text.trim().isEmpty || 
                    salaryController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى تعبئة الحقول المطلوبة')),
                  );
                  return;
                }

                final repo = ref.read(employeesRepoProvider);
                try {
                  if (employee == null) {
                    await repo.create(
                      name: nameController.text.trim(),
                      position: positionController.text.trim(),
                      salary: double.parse(salaryController.text),
                      phone: phoneController.text.trim(),
                      hireDate: hireDateController.text,
                      status: status,
                    );
                  } else {
                    await repo.update(
                      employee.localUuid,
                      name: nameController.text.trim(),
                      position: positionController.text.trim(),
                      salary: double.parse(salaryController.text),
                      phone: phoneController.text.trim(),
                      hireDate: hireDateController.text,
                      status: status,
                    );
                  }
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(employee == null ? 'تم إضافة الموظف بنجاح' : 'تم تحديث بيانات الموظف'),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e')),
                  );
                }
              },
              child: Text(employee == null ? 'إضافة' : 'تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSalaryWithdrawalDialog(BuildContext context, WidgetRef ref, Employee employee) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('سحب راتب - ${employee.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الراتب الأساسي: ${employee.salary.toStringAsFixed(0)} ر.س'),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'المبلغ المسحوب*',
                  border: OutlineInputBorder(),
                  suffixText: 'ر.س',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                // TODO: تنفيذ عملية سحب الراتب
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تسجيل سحب الراتب (قيد التطوير)')),
                );
              },
              child: const Text('تسجيل السحب'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleEmployeeStatus(BuildContext context, WidgetRef ref, Employee employee) async {
    final newStatus = employee.status == 'نشط' ? 'غير نشط' : 'نشط';
    
    try {
      final repo = ref.read(employeesRepoProvider);
      await repo.update(
        employee.localUuid,
        name: employee.name,
        position: employee.position,
        salary: employee.salary,
        phone: employee.phone,
        hireDate: employee.hireDate,
        status: newStatus,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ${newStatus == 'نشط' ? 'تفعيل' : 'إيقاف'} الموظف')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    }
  }
}