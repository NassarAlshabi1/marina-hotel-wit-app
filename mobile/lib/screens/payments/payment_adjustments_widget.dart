/// Payment adjustments UI widget for booking payment screen.
///
/// Extracted from booking_payment_screen.dart (4,118 LOC)
/// This module handles UI for price adjustments, discounts, and surcharges.

import 'package:flutter/material.dart';

import '../../utils/currency_formatter.dart';
import 'payment_calculations.dart';

/// Payment adjustments widget - displays and manages price adjustments
class PaymentAdjustmentsWidget extends StatefulWidget {
  const PaymentAdjustmentsWidget({
    required this.totalAmount,
    required this.onDiscountChanged,
    required this.onSurchargeChanged,
    this.discountType = 'night',
    this.initialDiscount = 0,
    this.initialSurcharge = 0,
    super.key,
  });

  final double totalAmount;
  final ValueChanged<double> onDiscountChanged;
  final ValueChanged<double> onSurchargeChanged;
  final String discountType;
  final double initialDiscount;
  final double initialSurcharge;

  @override
  State<PaymentAdjustmentsWidget> createState() =>
      _PaymentAdjustmentsWidgetState();
}

class _PaymentAdjustmentsWidgetState extends State<PaymentAdjustmentsWidget> {
  late TextEditingController _discountController;
  late TextEditingController _surchargeController;
  double _currentDiscount = 0;
  double _currentSurcharge = 0;

  @override
  void initState() {
    super.initState();
    _currentDiscount = widget.initialDiscount;
    _currentSurcharge = widget.initialSurcharge;
    _discountController =
        TextEditingController(text: _currentDiscount.toString());
    _surchargeController =
        TextEditingController(text: _currentSurcharge.toString());
  }

  @override
  void dispose() {
    _discountController.dispose();
    _surchargeController.dispose();
    super.dispose();
  }

  void _onDiscountChanged(String value) {
    final discount = double.tryParse(value) ?? 0;
    setState(() => _currentDiscount = discount);
    widget.onDiscountChanged(discount);
  }

  void _onSurchargeChanged(String value) {
    final surcharge = double.tryParse(value) ?? 0;
    setState(() => _currentSurcharge = surcharge);
    widget.onSurchargeChanged(surcharge);
  }

  void _addPresetDiscount(double amount) {
    _discountController.text = amount.toString();
    _onDiscountChanged(amount.toString());
  }

  void _addPresetSurcharge(double amount) {
    _surchargeController.text = amount.toString();
    _onSurchargeChanged(amount.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adjustedTotal = widget.totalAmount - _currentDiscount + _currentSurcharge;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'تعديلات الأسعار',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Discount section
            _buildAdjustmentSection(
              context,
              label: 'خصم',
              controller: _discountController,
              onChanged: _onDiscountChanged,
              onPreset: _addPresetDiscount,
              color: Colors.green,
            ),
            const SizedBox(height: 16),

            // Surcharge section
            _buildAdjustmentSection(
              context,
              label: 'إضافة',
              controller: _surchargeController,
              onChanged: _onSurchargeChanged,
              onPreset: _addPresetSurcharge,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),

            // Breakdown
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBreakdownLine(
                    'المبلغ الأساسي',
                    widget.totalAmount,
                    theme,
                  ),
                  if (_currentDiscount > 0) ...[
                    const SizedBox(height: 8),
                    _buildBreakdownLine(
                      'الخصم',
                      -_currentDiscount,
                      theme,
                      color: Colors.green,
                    ),
                  ],
                  if (_currentSurcharge > 0) ...[
                    const SizedBox(height: 8),
                    _buildBreakdownLine(
                      'الإضافة',
                      _currentSurcharge,
                      theme,
                      color: Colors.orange,
                    ),
                  ],
                  Divider(height: 16),
                  _buildBreakdownLine(
                    'الإجمالي',
                    adjustedTotal,
                    theme,
                    isBold: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustmentSection(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required ValueChanged<double> onPreset,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              'ر.ي',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '0',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            prefixIcon: Icon(Icons.edit, color: color),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _getPresetAmounts().map((amount) {
            return ElevatedButton(
              onPressed: () => onPreset(amount),
              style: ElevatedButton.styleFrom(
                backgroundColor: color.withOpacity(0.2),
                foregroundColor: color,
                elevation: 0,
              ),
              child: Text('${amount.toStringAsFixed(0)} ر.ي'),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBreakdownLine(
    String label,
    double amount,
    ThemeData theme, {
    Color? color,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          PaymentCalculations.formatCurrency(amount.abs()),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  List<double> _getPresetAmounts() {
    final total = widget.totalAmount;
    return [
      50,
      100,
      (total * 0.05).roundToDouble(),
      (total * 0.10).roundToDouble(),
    ].toSet().toList()..sort();
  }
}

/// Adjustment history widget
class AdjustmentHistoryWidget extends StatelessWidget {
  const AdjustmentHistoryWidget({
    required this.adjustments,
    super.key,
  });

  final List<AdjustmentRecord> adjustments;

  @override
  Widget build(BuildContext context) {
    if (adjustments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سجل التعديلات',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: adjustments.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (_, index) {
                final adj = adjustments[index];
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(adj.label),
                        Text(
                          adj.timestamp,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Text(
                      '${adj.isDiscount ? '-' : '+'} ${PaymentCalculations.formatCurrency(adj.amount)}',
                      style: TextStyle(
                        color: adj.isDiscount ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Adjustment record data model
class AdjustmentRecord {
  AdjustmentRecord({
    required this.label,
    required this.amount,
    required this.isDiscount,
    required this.timestamp,
  });

  final String label;
  final double amount;
  final bool isDiscount;
  final String timestamp;
}
