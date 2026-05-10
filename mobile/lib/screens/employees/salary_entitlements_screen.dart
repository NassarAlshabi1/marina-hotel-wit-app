import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../services/local_db.dart';
import '../../services/salary_entitlement_service.dart';
import '../../utils/currency_formatter.dart';

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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'استحقاقات الرواتب',
      actions: [
        IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
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
        ..._entitlements.map(_buildEmployeeCard),
      ],
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
            const Text(
              'ملخص الاستحقاقات',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _row('عدد الموظفين', '${_summary['count'] ?? 0}'),
            _row(
              'إجمالي الاستحقاقات',
              CurrencyFormatter.formatAmount(
                (_summary['totalEntitlements'] as num?)?.toDouble() ?? 0.0,
              ),
              Colors.green,
            ),
            _row(
              'إجمالي السحبيات',
              CurrencyFormatter.formatAmount((_summary['totalWithdrawals'] as num?)?.toDouble() ?? 0.0),
              Colors.orange,
            ),
            _row(
              'إجمالي الخصومات',
              CurrencyFormatter.formatAmount((_summary['totalDeductions'] as num?)?.toDouble() ?? 0.0),
              Colors.red,
            ),
            const Divider(),
            _row(
              'صافي المستحقات',
              CurrencyFormatter.formatAmount((_summary['totalNet'] as num?)?.toDouble() ?? 0.0),
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
                _row(
                  'السحبيات',
                  '- ${CurrencyFormatter.formatAmount(ent.totalWithdrawals)}',
                  Colors.orange,
                ),
                _row(
                  'الخصومات',
                  '- ${CurrencyFormatter.formatAmount(ent.totalDeductions)}',
                  Colors.red,
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
                  ...ent.transactions
                      .take(5)
                      .map(
                        (tx) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Text(
                                tx.type,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tx.type == 'سحب'
                                      ? Colors.orange
                                      : Colors.red,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                CurrencyFormatter.formatAmount(tx.amount),
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tx.date.length > 10
                                    ? tx.date.substring(0, 10)
                                    : tx.date,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
