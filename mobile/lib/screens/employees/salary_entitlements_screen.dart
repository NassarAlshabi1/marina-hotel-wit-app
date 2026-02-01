import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/salary_entitlement_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../mixins/sync_on_exit_mixin.dart';

class SalaryEntitlementsScreen extends ConsumerStatefulWidget {
  const SalaryEntitlementsScreen({super.key});

  @override
  ConsumerState<SalaryEntitlementsScreen> createState() =>
      _SalaryEntitlementsScreenState();
}

class _SalaryEntitlementsScreenState
    extends ConsumerState<SalaryEntitlementsScreen> with SyncOnExitMixin {
  @override
  String get screenId => 'salary_entitlements';
  
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
      debugPrint('Error loading salary entitlements: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'استحقاقات الرواتب',
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _entitlements.isEmpty
                ? _buildEmptyState()
                : _buildContent(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('لا يوجد موظفين نشطين', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text('أضف موظفين من إدارة الموظفين', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 12),
          _buildInfoCard(),
          const SizedBox(height: 12),
          ..._entitlements.map((e) => _buildEmployeeCard(e)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text('ملخص الاستحقاقات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
              ],
            ),
            const SizedBox(height: 12),
            _summaryRow('عدد الموظفين', '${_summary['employeeCount'] ?? 0}'),
            _summaryRow('إجمالي الاستحقاقات', CurrencyFormatter.formatAmount(_summary['totalEntitlements'] ?? 0), color: Colors.green),
            _summaryRow('إجمالي السحبيات', CurrencyFormatter.formatAmount(_summary['totalWithdrawals'] ?? 0), color: Colors.orange),
            _summaryRow('إجمالي الخصومات', CurrencyFormatter.formatAmount(_summary['totalDeductions'] ?? 0), color: Colors.red),
            const Divider(),
            _summaryRow('صافي المستحقات', CurrencyFormatter.formatAmount(_summary['totalNetEntitlements'] ?? 0), color: Colors.blue.shade700, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'يتم تسجيل السحبيات والخصومات والغياب من شاشة المصروفات مع اختيار الموظف',
                style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(SalaryEntitlement ent) {
    final isPositive = ent.netEntitlement >= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
          child: Icon(Icons.person, size: 18, color: isPositive ? Colors.green : Colors.red),
        ),
        title: Text(ent.employee.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          'صافي: ${CurrencyFormatter.formatAmount(ent.netEntitlement)}',
          style: TextStyle(fontSize: 12, color: isPositive ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w500),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _detailRow('تاريخ التوظيف', _formatDate(ent.hireDate)),
                _detailRow('مدة العمل', '${ent.totalMonthsWorked} شهر'),
                _detailRow('الراتب الشهري', CurrencyFormatter.formatAmount(ent.basicSalary)),
                const Divider(),
                _detailRow('إجمالي الاستحقاق', CurrencyFormatter.formatAmount(ent.totalEntitlement), color: Colors.green),
                _detailRow('السحبيات/السلف', '- ${CurrencyFormatter.formatAmount(ent.totalWithdrawals)}', color: Colors.orange),
                _detailRow('الخصومات', '- ${CurrencyFormatter.formatAmount(ent.totalDeductions)}', color: Colors.red),
                _detailRow('خصومات الغياب', '- ${CurrencyFormatter.formatAmount(ent.totalAbsenceDeductions)}', color: Colors.red.shade300),
                const Divider(),
                _detailRow('صافي المستحق', CurrencyFormatter.formatAmount(ent.netEntitlement), color: isPositive ? Colors.green.shade700 : Colors.red.shade700, bold: true),
                if (ent.transactions.isNotEmpty) ...[
                  const Divider(),
                  const Align(alignment: Alignment.centerRight, child: Text('آخر المعاملات:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 4),
                  ...ent.transactions.take(5).map((tx) => _txRow(tx)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _txRow(SalaryTransaction tx) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(_txIcon(tx.type), size: 14, color: _txColor(tx.type)),
          const SizedBox(width: 6),
          Expanded(child: Text(tx.type, style: TextStyle(fontSize: 11, color: _txColor(tx.type)))),
          Text(CurrencyFormatter.formatAmount(tx.amount), style: TextStyle(fontSize: 11, color: _txColor(tx.type))),
          const SizedBox(width: 8),
          Text(tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  IconData _txIcon(String type) {
    switch (type) {
      case 'خصم': case 'خصم غياب': return Icons.remove_circle;
      case 'سحب/سلفة': return Icons.money_off;
      case 'دفعة راتب': return Icons.payments;
      default: return Icons.receipt;
    }
  }

  Color _txColor(String type) {
    switch (type) {
      case 'خصم': case 'خصم غياب': return Colors.red;
      case 'سحب/سلفة': return Colors.orange;
      case 'دفعة راتب': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
