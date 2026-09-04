import 'package:flutter/material.dart';
import '../../models/payment_models.dart';
import '../../utils/currency_formatter.dart';

/// Widget لعرض بطاقة ملخص المدفوعات للحجز
class PaymentSummaryWidget extends StatelessWidget {
  const PaymentSummaryWidget({
    required this.summary,
    super.key,
    this.onTap,
    this.compact = false,
  });
  final BookingPaymentSummary summary;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final progressColor = summary.isFullyPaid ? Colors.green : Colors.orange;

    return Card(
      elevation: compact ? 1 : 2,
      margin: EdgeInsets.symmetric(
        vertical: compact ? 4 : 8,
        horizontal: compact ? 8 : 0,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // المعلومات الرئيسية
              Row(
                children: [
                  Icon(
                    summary.isFullyPaid ? Icons.check_circle : Icons.pending,
                    color: progressColor,
                    size: compact ? 20 : 24,
                  ),
                  SizedBox(width: compact ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'حجز #${summary.bookingId.substring(0, 8)}',
                          style: TextStyle(
                            fontSize: compact ? 14 : 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          summary.isFullyPaid ? 'مكتمل الدفع' : 'دفع جزئي',
                          style: TextStyle(
                            fontSize: compact ? 10 : 12,
                            color: progressColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${summary.paidPercentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.bold,
                      color: progressColor,
                    ),
                  ),
                ],
              ),

              if (!compact) ...[
                const SizedBox(height: 12),

                // شريط التقدم
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: summary.paidPercentage / 100,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),

                const SizedBox(height: 12),

                // ملخص المبالغ
                Row(
                  children: [
                    Expanded(
                      child: _buildAmountChip(
                        'الإجمالي',
                        summary.totalAmount,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildAmountChip(
                        'المدفوع',
                        summary.paidAmount,
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildAmountChip(
                        'المتبقي',
                        summary.remainingAmount,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            CurrencyFormatter.formatAmount(amount),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 8, color: color.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Widget لعرض بطاقة دفعة واحدة
class PaymentCard extends StatelessWidget {
  const PaymentCard({
    required this.payment,
    super.key,
    this.onTap,
    this.actions,
    this.showBookingId = true,
  });
  final Payment payment;
  final VoidCallback? onTap;
  final List<Widget>? actions;
  final bool showBookingId;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // معلومات أساسية
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: payment.method.color.withValues(
                      alpha: 0.15,
                    ),
                    child: Icon(
                      payment.method.icon,
                      color: payment.method.color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          CurrencyFormatter.formatAmount(payment.amount),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          payment.method.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        if (showBookingId)
                          Text(
                            'حجز #${payment.bookingId.substring(0, 8)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PaymentStatusBadge(status: payment.status),
                ],
              ),

              const SizedBox(height: 8),

              // تفاصيل إضافية
              Row(
                children: [
                  Expanded(
                    child: _buildDetailItem(
                      'التاريخ',
                      _formatDateTime(payment.paymentDate),
                      Icons.calendar_today,
                    ),
                  ),
                  Expanded(
                    child: _buildDetailItem(
                      'المحاسب',
                      payment.receivedBy,
                      Icons.person,
                    ),
                  ),
                ],
              ),

              if (payment.referenceNumber != null ||
                  payment.cardLastFourDigits != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (payment.referenceNumber != null)
                      Expanded(
                        child: _buildDetailItem(
                          'رقم المرجع',
                          payment.referenceNumber!,
                          Icons.confirmation_number,
                        ),
                      ),
                    if (payment.referenceNumber != null &&
                        payment.cardLastFourDigits != null)
                      const SizedBox(width: 6),
                    if (payment.cardLastFourDigits != null)
                      Expanded(
                        child: _buildDetailItem(
                          'البطاقة',
                          '****${payment.cardLastFourDigits}',
                          Icons.credit_card,
                        ),
                      ),
                  ],
                ),
              ],

              if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ملاحظات:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        payment.notes!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],

              // أزرار العمليات
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: actions!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Widget لعرض شارة حالة الدفعة
class PaymentStatusBadge extends StatelessWidget {
  const PaymentStatusBadge({required this.status, super.key, this.fontSize});
  final PaymentStatus status;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status.color),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: fontSize ?? 12,
          fontWeight: FontWeight.bold,
          color: status.color,
        ),
      ),
    );
  }
}

/// Widget لعرض طريقة الدفع
class PaymentMethodChip extends StatelessWidget {
  const PaymentMethodChip({
    required this.method,
    super.key,
    this.isSelected = false,
    this.onTap,
  });
  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? method.color
              : method.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: method.color, width: isSelected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              method.icon,
              size: 16,
              color: isSelected ? Colors.white : method.color,
            ),
            const SizedBox(width: 6),
            Text(
              method.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : method.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget لعرض إحصائيات المدفوعات
class PaymentStatsWidget extends StatelessWidget {
  const PaymentStatsWidget({
    required this.payments,
    required this.title,
    super.key,
  });
  final List<Payment> payments;
  final String title;

  @override
  Widget build(BuildContext context) {
    final totalAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final completedPayments = payments
        .where((p) => p.status == PaymentStatus.completed)
        .length;
    final pendingPayments = payments
        .where((p) => p.status == PaymentStatus.pending)
        .length;

    final methodStats = <PaymentMethod, int>{};
    for (final payment in payments) {
      methodStats[payment.method] = (methodStats[payment.method] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // إحصائيات عامة
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'إجمالي المدفوعات',
                    payments.length.toString(),
                    Icons.payment,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatItem(
                    'مكتملة',
                    completedPayments.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatItem(
                    'في الانتظار',
                    pendingPayments.toString(),
                    Icons.hourglass_empty,
                    Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // المبلغ الإجمالي
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.attach_money, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'إجمالي المبلغ: ${CurrencyFormatter.formatAmount(totalAmount)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),

            if (methodStats.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'التوزيع حسب طريقة الدفع:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: methodStats.entries.map((entry) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: entry.key.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: entry.key.color.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(entry.key.icon, size: 12, color: entry.key.color),
                        const SizedBox(width: 4),
                        Text(
                          '${entry.key.displayName}: ${entry.value}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: entry.key.color,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Widget لاختيار طريقة الدفع
class PaymentMethodSelector extends StatelessWidget {
  const PaymentMethodSelector({
    required this.onMethodSelected,
    super.key,
    this.selectedMethod,
    this.availableMethods = const [PaymentMethod.cash, PaymentMethod.transfer],
  });
  final PaymentMethod? selectedMethod;
  final void Function(PaymentMethod) onMethodSelected;
  final List<PaymentMethod> availableMethods;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اختر طريقة الدفع:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: availableMethods.length,
          itemBuilder: (context, index) {
            final method = availableMethods[index];
            final isSelected = selectedMethod == method;

            return GestureDetector(
              onTap: () => onMethodSelected(method),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? method.color
                      : method.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: method.color,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      method.icon,
                      color: isSelected ? Colors.white : method.color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        method.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : method.color,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Widget لعرض ملخص الفاتورة
class InvoiceSummaryWidget extends StatelessWidget {
  const InvoiceSummaryWidget({
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.nights,
    required this.roomRate,
    super.key,
  });
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final int nights;
  final double roomRate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ملخص الفاتورة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // تفاصيل الحساب
            _buildInvoiceRow('عدد الليالي', '$nights ليلة'),
            _buildInvoiceRow(
              'سعر الليلة',
              CurrencyFormatter.formatAmount(roomRate),
            ),
            const Divider(),
            _buildInvoiceRow(
              'المبلغ الإجمالي',
              CurrencyFormatter.formatAmount(totalAmount),
              isBold: true,
            ),
            _buildInvoiceRow(
              'المدفوع',
              CurrencyFormatter.formatAmount(paidAmount),
              color: Colors.green,
            ),
            _buildInvoiceRow(
              'المتبقي',
              CurrencyFormatter.formatAmount(remainingAmount),
              color: remainingAmount > 0 ? Colors.red : Colors.green,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceRow(
    String label,
    String value, {
    Color? color,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget لزر العمليات السريعة
class QuickPaymentButton extends StatelessWidget {
  const QuickPaymentButton({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.onPressed,
    super.key,
  });
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            CurrencyFormatter.formatAmount(amount),
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
