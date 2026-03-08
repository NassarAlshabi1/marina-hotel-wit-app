import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../providers/auth_provider.dart';
import '../../utils/currency_formatter.dart';

import '../../services/local_db.dart';
import '../../mixins/sync_on_exit_mixin.dart';

class PaymentsListScreen extends ConsumerStatefulWidget {
  const PaymentsListScreen({super.key});

  @override
  ConsumerState<PaymentsListScreen> createState() => _PaymentsListScreenState();
}

class _PaymentsListScreenState extends ConsumerState<PaymentsListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'payments_list';

  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final canEdit = auth.currentUser?.isAdmin == true ||
        auth.currentUser?.permissions.contains('edit_payments') == true ||
        auth.currentUser?.permissions.contains('all') == true;

    final repo = ref.watch(paymentsRepoProvider);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'المدفوعات',
        actions: [
          IconButton(
            onPressed: () => _showFilterDialog(),
            icon: const Icon(Icons.filter_list),
            tooltip: 'تصفية',
          ),
        ],
        body: StreamBuilder(
          stream: repo.watchAll(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            var list = snapshot.data!;

            // تطبيق التصفية
            if (_fromDate != null || _toDate != null || _filterType != null) {
              list = list.where((p) {
                // تصفية التاريخ
                if (_fromDate != null || _toDate != null) {
                  final paymentDate = _parseDate(p.paymentDate);
                  if (_fromDate != null && paymentDate.isBefore(_fromDate!)) {
                    return false;
                  }
                  if (_toDate != null && paymentDate.isAfter(_toDate!)) {
                    return false;
                  }
                }
                // تصفية النوع
                if (_filterType != null && p.revenueType != _filterType) {
                  return false;
                }
                return true;
              }).toList();
            }

            final totalAmount = list.fold<double>(0, (sum, p) => sum + p.amount);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // بطاقة الملخص
                _buildSummaryCard(totalAmount: totalAmount, count: list.length),
                const SizedBox(height: 12),
                // عرض التصفية النشطة
                if (_fromDate != null || _toDate != null || _filterType != null)
                  _buildActiveFilters(),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: Text('لا توجد مدفوعات ضمن الفترة')),
                  )
                else
                  ...list.map((p) => _buildPaymentCard(p, canEdit)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCard({required double totalAmount, required int count}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryItem(
                label: 'عدد العمليات',
                value: '$count',
                icon: Icons.receipt_long,
                color: Colors.indigo,
              ),
            ),
            Expanded(
              child: _buildSummaryItem(
                label: 'إجمالي المدفوعات',
                value: CurrencyFormatter.formatAmount(totalAmount),
                icon: Icons.payments,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveFilters() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.filter_alt, size: 18, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getFilterDescription(),
                style: const TextStyle(color: Colors.blue),
              ),
            ),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('مسح'),
            ),
          ],
        ),
      ),
    );
  }

  String _getFilterDescription() {
    final parts = <String>[];
    if (_fromDate != null && _toDate != null) {
      parts.add('${_dateFormat.format(_fromDate!)} - ${_dateFormat.format(_toDate!)}');
    } else if (_fromDate != null) {
      parts.add('من ${_dateFormat.format(_fromDate!)}');
    } else if (_toDate != null) {
      parts.add('إلى ${_dateFormat.format(_toDate!)}');
    }
    if (_filterType != null) {
      parts.add(_filterType!);
    }
    return parts.join(' • ');
  }

  void _clearFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _filterType = null;
    });
  }

  Widget _buildPaymentCard(Payment payment, bool canEdit) {
    final date = _parseDate(payment.paymentDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CurrencyFormatter.formatAmount(payment.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${payment.paymentMethod} • ${payment.revenueType}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                // زر التعديل مع التحكم في الصلاحية
                if (canEdit)
                  IconButton(
                    onPressed: () => _editPayment(payment),
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: 'تعديل',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildMetaChip(Icons.calendar_today, _dateFormat.format(date)),
                if (payment.roomNumber != null)
                  _buildMetaChip(Icons.meeting_room, payment.roomNumber!),
                if (payment.bookingLocalId != null)
                  _buildMetaChip(Icons.hotel, 'حجز #${payment.bookingLocalId}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  DateTime _parseDate(String value) {
    final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? DateTime.now();
  }

  Future<void> _showFilterDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصفية المدفوعات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_fromDate != null
                  ? 'من: ${_dateFormat.format(_fromDate!)}'
                  : 'من تاريخ'),
              leading: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _fromDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _fromDate = DateTime(picked.year, picked.month, picked.day));
                }
                Navigator.pop(ctx);
                _showFilterDialog();
              },
            ),
            ListTile(
              title: Text(_toDate != null
                  ? 'إلى: ${_dateFormat.format(_toDate!)}'
                  : 'إلى تاريخ'),
              leading: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _toDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
                }
                Navigator.pop(ctx);
                _showFilterDialog();
              },
            ),
            const Divider(),
            const Text('نوع الإيراد:'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _filterType == null,
                  onSelected: (_) => setState(() => _filterType = null),
                ),
                ChoiceChip(
                  label: const Text('إيجار'),
                  selected: _filterType == 'إيجار',
                  onSelected: (_) => setState(() => _filterType = 'إيجار'),
                ),
                ChoiceChip(
                  label: const Text('مبيعات'),
                  selected: _filterType == 'مبيعات',
                  onSelected: (_) => setState(() => _filterType = 'مبيعات'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _clearFilters();
              Navigator.pop(ctx);
            },
            child: const Text('مسح التصفية'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  Future<void> _editPayment(Payment payment) async {
    final amountCtrl = TextEditingController(
      text: CurrencyFormatter.formatAmount(payment.amount),
    );
    final notesCtrl = TextEditingController(text: payment.notes ?? '');
    String paymentMethod = payment.paymentMethod;
    String revenueType = payment.revenueType;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('تعديل الدفعة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'نقدي', child: Text('نقدي')),
                    DropdownMenuItem(value: 'تحويل', child: Text('تحويل')),
                    DropdownMenuItem(value: 'شبكة', child: Text('شبكة')),
                    DropdownMenuItem(value: 'آجل', child: Text('آجل')),
                  ],
                  onChanged: (v) => setState(() => paymentMethod = v ?? 'نقدي'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: revenueType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الإيراد',
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'إيجار', child: Text('إيجار')),
                    DropdownMenuItem(value: 'مبيعات', child: Text('مبيعات')),
                    DropdownMenuItem(value: 'أخرى', child: Text('أخرى')),
                  ],
                  onChanged: (v) => setState(() => revenueType = v ?? 'إيجار'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
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
      ),
    );

    if (ok != true) return;

    final newAmount = CurrencyFormatter.parseAmount(amountCtrl.text) ?? 0;
    if (newAmount <= 0) return;

    final repo = ref.read(paymentsRepoProvider);
    await repo.update(
      payment.id,
      amount: newAmount,
      paymentMethod: paymentMethod,
      revenueType: revenueType,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    );

    markDataChanged();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث الدفعة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
