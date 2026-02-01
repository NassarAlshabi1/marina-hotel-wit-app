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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'استحقاقات الرواتب',
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('لا يوجد موظفين نشطين', style: TextStyle(fontSize: 18)),
          SizedBox(height: 8),
          Text(
            'أضف موظفين من شاشة إدارة الموظفين',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 16),
          const Text(
            'تفاصيل الموظفين',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._entitlements.map((e) => _buildEmployeeCard(e)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'ملخص الاستحقاقات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSummaryRow(
              'عدد الموظفين النشطين',
              '${_summary['employeeCount'] ?? 0}',
              Icons.people,
            ),
            _buildSummaryRow(
              'إجمالي الرواتب الشهرية',
              CurrencyFormatter.formatAmount(_summary['totalBasicSalaries'] ?? 0),
              Icons.payments,
            ),
            _buildSummaryRow(
              'إجمالي الاستحقاقات',
              CurrencyFormatter.formatAmount(_summary['totalEntitlements'] ?? 0),
              Icons.account_balance_wallet,
              color: Colors.green,
            ),
            _buildSummaryRow(
              'إجمالي السحبيات',
              CurrencyFormatter.formatAmount(_summary['totalWithdrawals'] ?? 0),
              Icons.money_off,
              color: Colors.orange,
            ),
            _buildSummaryRow(
              'إجمالي الخصومات',
              CurrencyFormatter.formatAmount(_summary['totalDeductions'] ?? 0),
              Icons.remove_circle,
              color: Colors.red,
            ),
            const Divider(height: 24),
            _buildSummaryRow(
              'صافي المستحقات',
              CurrencyFormatter.formatAmount(_summary['totalNetEntitlements'] ?? 0),
              Icons.account_balance,
              color: Colors.blue.shade700,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    IconData icon, {
    Color? color,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color,
              fontSize: isBold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(SalaryEntitlement entitlement) {
    final isPositive = entitlement.netEntitlement >= 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
          child: Icon(
            Icons.person,
            color: isPositive ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          entitlement.employee.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'صافي المستحق: ${CurrencyFormatter.formatAmount(entitlement.netEntitlement)}',
          style: TextStyle(
            color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailSection('معلومات التوظيف', [
                  _buildDetailRow('تاريخ التوظيف', _formatDate(entitlement.hireDate)),
                  _buildDetailRow('مدة العمل', '${entitlement.totalMonthsWorked} شهر (${entitlement.totalDaysWorked} يوم)'),
                  _buildDetailRow('الراتب الأساسي', CurrencyFormatter.formatAmount(entitlement.basicSalary)),
                ]),
                const Divider(),
                _buildDetailSection('حساب الاستحقاقات', [
                  _buildDetailRow(
                    'إجمالي الاستحقاق',
                    CurrencyFormatter.formatAmount(entitlement.totalEntitlement),
                    color: Colors.green,
                  ),
                  _buildDetailRow(
                    'السحبيات والسلف',
                    '- ${CurrencyFormatter.formatAmount(entitlement.totalWithdrawals)}',
                    color: Colors.orange,
                  ),
                  _buildDetailRow(
                    'الخصومات',
                    '- ${CurrencyFormatter.formatAmount(entitlement.totalDeductions)}',
                    color: Colors.red,
                  ),
                  _buildDetailRow(
                    'خصومات الغياب',
                    '- ${CurrencyFormatter.formatAmount(entitlement.totalAbsenceDeductions)}',
                    color: Colors.red.shade300,
                  ),
                  const Divider(),
                  _buildDetailRow(
                    'صافي المستحق',
                    CurrencyFormatter.formatAmount(entitlement.netEntitlement),
                    color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                    isBold: true,
                  ),
                ]),
                if (entitlement.transactions.isNotEmpty) ...[
                  const Divider(),
                  _buildTransactionsSection(entitlement.transactions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection(List<SalaryTransaction> transactions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'سجل المعاملات',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            Text(
              '${transactions.length} معاملة',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: transactions.length > 10 ? 10 : transactions.length,
            itemBuilder: (context, index) {
              final tx = transactions[index];
              return _buildTransactionItem(tx);
            },
          ),
        ),
        if (transactions.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'و ${transactions.length - 10} معاملات أخرى...',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionItem(SalaryTransaction tx) {
    IconData icon;
    Color color;
    
    switch (tx.type) {
      case 'خصم':
      case 'خصم غياب':
        icon = Icons.remove_circle;
        color = Colors.red;
        break;
      case 'سحب/سلفة':
        icon = Icons.money_off;
        color = Colors.orange;
        break;
      case 'دفعة راتب':
        icon = Icons.payments;
        color = Colors.blue;
        break;
      default:
        icon = Icons.receipt;
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.type,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
                ),
                if (tx.note != null && tx.note!.isNotEmpty)
                  Text(
                    tx.note!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.formatAmount(tx.amount),
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
              ),
              Text(
                tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
