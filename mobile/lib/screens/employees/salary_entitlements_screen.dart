import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../providers/auth_provider.dart';
import '../../services/salary_entitlement_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/enhanced_pdf_utils.dart';

/// شاشة التقرير التفصيلي للموظف
class EmployeeDetailReportScreen extends StatelessWidget {
  const EmployeeDetailReportScreen({
    super.key,
    required this.entitlement,
  });

  final SalaryEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    // حساب السحب والخصم
    final totalWithdrawals = entitlement.totalSalaryWithdrawals + entitlement.totalAdvances;
    final totalDeductions = entitlement.totalSalaryDeductions + entitlement.totalAbsences;
    final totalDeductionsAll = totalWithdrawals + totalDeductions;

    return AppScaffold(
      title: 'تقرير ${entitlement.employee.name}',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // معلومات الموظف
          _buildInfoCard(totalWithdrawals, totalDeductions),
          const SizedBox(height: 12),
          
          // جدول المعاملات
          const Text(
            'سجل المعاملات:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          
          // عنوان الجدول
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('النوع', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('المبلغ', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('ملاحظات', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          
          // صفوف المعاملات
          if (entitlement.transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('لا توجد معاملات', style: TextStyle(fontSize: 12))),
            )
          else
            ...entitlement.transactions.map((tx) => _buildTransactionRow(tx)),
          
          const Divider(),
          
          // الإجمالي
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _summaryRow('إجمالي الاستحقاق', CurrencyFormatter.formatAmount(entitlement.totalEntitlement), Colors.green),
                _summaryRow('إجمالي السحب والخصم', '- ${CurrencyFormatter.formatAmount(totalDeductionsAll)}', Colors.red),
                const Divider(),
                _summaryRow(
                  'المتبقي',
                  CurrencyFormatter.formatAmount(entitlement.netEntitlement),
                  entitlement.netEntitlement >= 0 ? Colors.green : Colors.red,
                  bold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(double totalWithdrawals, double totalDeductions) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الموظف: ${entitlement.employee.name}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _infoRow('المنصب', entitlement.employee.position),
            _infoRow('تاريخ التعيين', entitlement.employee.hireDate),
            _infoRow('الراتب الشهري', CurrencyFormatter.formatAmount(entitlement.basicSalary)),
            _infoRow('مدة العمل', '${entitlement.totalMonthsWorked} شهر'),
            const Divider(),
            _infoRow('سحب من راتب', CurrencyFormatter.formatAmount(totalWithdrawals), Colors.orange),
            _infoRow('خصم من راتب', CurrencyFormatter.formatAmount(totalDeductions), Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(SalaryTransaction tx) {
    Color txColor;
    String txType;
    
    switch (tx.type) {
      case 'سحب راتب':
      case 'رواتب':
        txColor = Colors.orange;
        txType = 'سحب';
        break;
      case 'سلفة':
        txColor = Colors.orange.shade700;
        txType = 'سلفة';
        break;
      case 'خصم راتب':
      case 'خصم':
        txColor = Colors.red;
        txType = 'خصم';
        break;
      case 'غياب':
        txColor = Colors.red.shade700;
        txType = 'غياب';
        break;
      default:
        txColor = Colors.grey;
        txType = tx.type;
    }
    
    final dateStr = tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(dateStr, style: const TextStyle(fontSize: 11))),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: txColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(txType, style: TextStyle(fontSize: 10, color: txColor), textAlign: TextAlign.center),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              CurrencyFormatter.formatAmount(tx.amount),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: txColor),
            ),
          ),
          Expanded(flex: 3, child: Text(tx.note ?? '-', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class SalaryEntitlementsScreen extends ConsumerStatefulWidget {
  const SalaryEntitlementsScreen({super.key});

  @override
  ConsumerState<SalaryEntitlementsScreen> createState() =>
      _SalaryEntitlementsScreenState();
}

class _SalaryEntitlementsScreenState
    extends ConsumerState<SalaryEntitlementsScreen> {
  late SalaryEntitlementService _service;
  List<SalaryEntitlement> _entitlements = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _service = SalaryEntitlementService(DatabaseManager.instance);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _summary = await _service.getSummary();
      _entitlements = _summary['entitlements'] as List<SalaryEntitlement>;
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل تحميل البيانات: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _canEdit() {
    final auth = ref.watch(authProvider);
    return auth.currentUser?.isAdmin == true ||
        auth.currentUser?.permissions.contains('edit_salaries') == true ||
        auth.currentUser?.permissions.contains('all') == true;
  }

  void _openDetailReport(SalaryEntitlement ent) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeDetailReportScreen(entitlement: ent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'استحقاقات الرواتب',
      actions: [
        IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        if (_entitlements.isNotEmpty)
          IconButton(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير PDF',
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entitlements.isEmpty
              ? const Center(
                  child: Text(
                    'لا يوجد موظفين نشطين',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              : RefreshIndicator(onRefresh: _loadData, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 8),
        const Text(
          'تفاصيل الموظفين:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._entitlements.map((e) => _buildEmployeeCard(e)),
      ],
    );
  }

  Widget _buildSummaryCard() {
    // الحساب المبسط: سحب + خصم = المتبقي
    final totalWithdrawals = (_summary['totalSalaryWithdrawals'] ?? 0.0) + 
                             (_summary['totalAdvances'] ?? 0.0);
    final totalDeductions = (_summary['totalSalaryDeductions'] ?? 0.0) + 
                            (_summary['totalAbsences'] ?? 0.0);
    
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ملخص الاستحقاقات',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _row('عدد الموظفين', '${_summary['count'] ?? 0}'),
            _row(
              'إجمالي الاستحقاقات',
              CurrencyFormatter.formatAmount(
                _summary['totalEntitlements'] ?? 0,
              ),
              Colors.green,
            ),
            const Divider(height: 16),
            // سحب من راتب (سحب + رواتب + سلفة)
            _row(
              'سحب من راتب',
              '- ${CurrencyFormatter.formatAmount(totalWithdrawals)}',
              Colors.orange,
            ),
            // خصم من راتب (خصم + غياب)
            _row(
              'خصم من راتب',
              '- ${CurrencyFormatter.formatAmount(totalDeductions)}',
              Colors.red,
            ),
            const Divider(),
            _row(
              'المتبقي',
              CurrencyFormatter.formatAmount(_summary['totalNet'] ?? 0),
              Colors.blue.shade700,
              true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, [Color? color, bool bold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(SalaryEntitlement ent) {
    final isPositive = ent.netEntitlement >= 0;
    final canEdit = _canEdit();
    
    // الحساب المبسط: سحب + خصم
    final totalWithdrawals = ent.totalSalaryWithdrawals + ent.totalAdvances;
    final totalDeductions = ent.totalSalaryDeductions + ent.totalAbsences;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          ent.employee.name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'المتبقي: ${CurrencyFormatter.formatAmount(ent.netEntitlement)}',
          style: TextStyle(
            fontSize: 12,
            color: isPositive ? Colors.green : Colors.red,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // زر التقرير التفصيلي
            IconButton(
              icon: const Icon(Icons.receipt_long, color: Colors.green, size: 20),
              onPressed: () => _openDetailReport(ent),
              tooltip: 'تقرير تفصيلي',
            ),
            // زر التعديل
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                onPressed: () => _showEditDialog(ent),
                tooltip: 'تعديل',
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _row('تاريخ التعيين', _formatDate(ent.hireDate)),
                _row('مدة العمل', '${ent.totalMonthsWorked} شهر'),
                _row(
                  'الراتب الشهري',
                  CurrencyFormatter.formatAmount(ent.basicSalary),
                ),
                const Divider(),
                _row(
                  'إجمالي الاستحقاق',
                  CurrencyFormatter.formatAmount(ent.totalEntitlement),
                  Colors.green,
                ),
                const SizedBox(height: 4),
                // سحب من راتب
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _row(
                    'سحب من راتب',
                    '- ${CurrencyFormatter.formatAmount(totalWithdrawals)}',
                    Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                // خصم من راتب
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _row(
                    'خصم من راتب',
                    '- ${CurrencyFormatter.formatAmount(totalDeductions)}',
                    Colors.red,
                  ),
                ),
                const Divider(),
                _row(
                  'المتبقي',
                  CurrencyFormatter.formatAmount(ent.netEntitlement),
                  isPositive ? Colors.green : Colors.red,
                  true,
                ),
                if (ent.transactions.isNotEmpty) ...[
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'آخر المعاملات:',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  ...ent.transactions.take(5).map(_buildTransactionRow),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(SalaryTransaction tx) {
    Color txColor;
    IconData txIcon;
    
    switch (tx.type) {
      case 'سحب راتب':
      case 'رواتب':
        txColor = Colors.orange;
        txIcon = Icons.money_off;
        break;
      case 'سلفة':
        txColor = Colors.orange.shade700;
        txIcon = Icons.account_balance_wallet;
        break;
      case 'خصم راتب':
      case 'خصم':
        txColor = Colors.red;
        txIcon = Icons.remove_circle;
        break;
      case 'غياب':
        txColor = Colors.red.shade700;
        txIcon = Icons.event_busy;
        break;
      default:
        txColor = Colors.grey;
        txIcon = Icons.swap_horiz;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(txIcon, size: 14, color: txColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              tx.type,
              style: TextStyle(fontSize: 11, color: txColor),
            ),
          ),
          Text(
            '- ${CurrencyFormatter.formatAmount(tx.amount)}',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(width: 8),
          Text(
            tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(SalaryEntitlement ent) async {
    final salaryCtrl = TextEditingController(
      text: ent.basicSalary.toString(),
    );
    final nameCtrl = TextEditingController(text: ent.employee.name);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل بيانات ${ent.employee.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الموظف',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: salaryCtrl,
              decoration: const InputDecoration(
                labelText: 'الراتب الشهري',
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final newSalary = double.tryParse(salaryCtrl.text) ?? 0;
    if (newSalary <= 0) return;

    // تحديث الراتب في قاعدة البيانات
    final db = DatabaseManager.instance;
    await (db.update(db.employees)..where((t) => t.id.equals(ent.employee.id)))
        .write(
      EmployeesCompanion(
        basicSalary: Value(newSalary),
        name: Value(nameCtrl.text.trim()),
      ),
    );

    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث بيانات الموظف'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
