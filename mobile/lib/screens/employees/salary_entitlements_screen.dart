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
    extends ConsumerState<SalaryEntitlementsScreen>
    with WidgetsBindingObserver {
  late SalaryEntitlementService _service;
  List<SalaryEntitlement> _entitlements = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = SalaryEntitlementService(DatabaseManager.instance);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ تحديث تلقائي عند العودة للتطبيق
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
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
              CurrencyFormatter.formatAmount(
                (_summary['totalWithdrawals'] as num?)?.toDouble() ?? 0.0,
              ),
              Colors.orange,
            ),
            // ✅ إضافة: إجمالي السلف
            _row(
              'إجمالي السلف',
              CurrencyFormatter.formatAmount(
                (_summary['totalAdvances'] as num?)?.toDouble() ?? 0.0,
              ),
              Colors.indigo,
            ),
            _row(
              'إجمالي الخصومات',
              CurrencyFormatter.formatAmount(
                (_summary['totalDeductions'] as num?)?.toDouble() ?? 0.0,
              ),
              Colors.red,
            ),
            const Divider(),
            _row(
              'صافي المستحقات',
              CurrencyFormatter.formatAmount(
                (_summary['totalNet'] as num?)?.toDouble() ?? 0.0,
              ),
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
                // ✅ إضافة: السلف مع رصيد متبقي
                _row(
                  'السلف',
                  '- ${CurrencyFormatter.formatAmount(ent.totalAdvances)}',
                  Colors.indigo,
                ),
                if (ent.totalAdvances > 0)
                  _row(
                    'رصيد السلف المتبقي',
                    CurrencyFormatter.formatAmount(ent.advanceBalance),
                    ent.advanceBalance > 0 ? Colors.indigo.shade300 : Colors.grey,
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...ent.transactions.take(8).map(_buildTransactionRow),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ تحسين: عرض المعاملة بالفئة والوصف واللون المناسب
  Widget _buildTransactionRow(SalaryTransaction tx) {
    final Color typeColor;
    final IconData typeIcon;
    switch (tx.type) {
      case 'سلفة':
        typeColor = Colors.indigo;
        typeIcon = Icons.account_balance_wallet;
      case 'سحب':
        typeColor = Colors.orange;
        typeIcon = Icons.payments;
      case 'خصم':
        typeColor = Colors.red;
        typeIcon = Icons.remove_circle_outline;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.circle;
    }

    final dateStr = tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // أيقونة النوع
          Icon(typeIcon, size: 12, color: typeColor),
          const SizedBox(width: 4),
          // الفئة (سحب راتب / سلفة / خصم / غياب)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tx.category ?? tx.type,
              style: TextStyle(fontSize: 9, color: typeColor, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          // الوصف
          Expanded(
            child: Text(
              tx.note ?? '',
              style: const TextStyle(fontSize: 10, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          // المبلغ
          Text(
            CurrencyFormatter.formatAmount(tx.amount),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: typeColor,
            ),
          ),
          const SizedBox(width: 6),
          // التاريخ
          Text(
            dateStr,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
