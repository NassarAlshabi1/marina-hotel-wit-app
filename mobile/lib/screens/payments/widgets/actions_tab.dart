// ignore_for_file: always_put_required_named_parameters_first

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/payment_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/local_db.dart' as db;

/// تبويب الإجراءات — widget مستقل مُستخرج من BookingPaymentScreen.
/// يعرض: الفاتورة، سجل المدفوعات، تسجيل المغادرة، مردود، إلغاء يوم، كشف حساب.
class ActionsTab extends ConsumerWidget {
  const ActionsTab({
    super.key,
    required this.summary,
    required this.booking,
    required this.nights,
    required this.currencyFmt,
    required this.debtAmount,
    required this.unsettledDebts,
    required this.onGenerateInvoice,
    required this.onShowPaymentHistory,
    required this.onShowCheckoutConfirmation,
    required this.onShowEarlyCheckout,
    required this.onShowCancelTodayPayment,
    required this.onSendAccountStatement,
    required this.onCreateDebtFromRemaining,
    required this.onShowDiscountDialog,
  });

  final BookingPaymentSummary summary;
  final db.Booking booking;
  final List<db.BookingNight> nights;
  final NumberFormat currencyFmt;
  final double debtAmount;
  final List<dynamic> unsettledDebts;
  final VoidCallback onGenerateInvoice;
  final VoidCallback onShowPaymentHistory;
  final void Function(BookingPaymentSummary, db.Booking, List<db.BookingNight>) onShowCheckoutConfirmation;
  final void Function(BookingPaymentSummary) onShowEarlyCheckout;
  final void Function(BookingPaymentSummary) onShowCancelTodayPayment;
  final void Function(BookingPaymentSummary) onSendAccountStatement;
  final void Function(BookingPaymentSummary, db.Booking) onCreateDebtFromRemaining;
  final void Function(BookingPaymentSummary, db.Booking) onShowDiscountDialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = <Widget>[
      _buildActionCard(
        'عرض الفاتورة الشاملة',
        'عرض وطباعة الفاتورة التفصيلية',
        Icons.receipt_long,
        Colors.teal,
        onGenerateInvoice,
      ),
      _buildActionCard('سجل المدفوعات', 'عرض تاريخ جميع المدفوعات', Icons.history, Colors.purple, onShowPaymentHistory),
      _buildActionCard(
        'تسجيل المغادرة',
        summary.isFullyPaid ? 'تسجيل مغادرة العميل' : 'تحذير: يوجد مبلغ متبقي!',
        Icons.logout,
        summary.isFullyPaid ? Colors.green : Colors.red,
        () => onShowCheckoutConfirmation(summary, booking, nights),
      ),
      _buildActionCard(
        'مغادرة مبكرة / مردود',
        'حساب المردود عند مغادرة قبل الموعد',
        Icons.currency_exchange,
        Colors.amber.shade700,
        () => onShowEarlyCheckout(summary),
      ),
      _buildActionCard(
        'إلغاء يوم إضافي',
        'إلغاء دفعة اليوم الفندقي المحتسبة بالخطأ',
        Icons.remove_circle_outline,
        Colors.red.shade700,
        () => onShowCancelTodayPayment(summary),
      ),
      _buildActionCard(
        'إرسال كشف حساب',
        'إرسال ملخص المدفوعات للعميل',
        Icons.send,
        Colors.orange,
        () => onSendAccountStatement(summary),
      ),
    ];

    final hasRemainingBalance = summary.remainingAmount > 0;
    final hasUnsettledDebt = debtAmount > 0 && unsettledDebts.isNotEmpty;
    final isAdmin = ref.watch(authProvider).currentUser?.isAdmin ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRemainingBalance || hasUnsettledDebt) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: hasUnsettledDebt ? Colors.red.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: hasUnsettledDebt ? Colors.red.shade300 : Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    hasUnsettledDebt ? Icons.error_outline : Icons.warning_amber_rounded,
                    color: hasUnsettledDebt ? Colors.red.shade700 : Colors.orange.shade700,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hasUnsettledDebt
                          ? 'دين سابق: ${currencyFmt.format(debtAmount)} • متبقي: ${currencyFmt.format(summary.remainingAmount)}'
                          : 'متبقي: ${currencyFmt.format(summary.remainingAmount)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: hasUnsettledDebt ? Colors.red.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                if (hasRemainingBalance)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ElevatedButton.icon(
                        onPressed: () => onCreateDebtFromRemaining(summary, booking),
                        icon: const Icon(Icons.add_circle, size: 14),
                        label: const Text('إنشاء دين', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                if (isAdmin) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ElevatedButton.icon(
                        onPressed: () => onShowDiscountDialog(summary, booking),
                        icon: const Icon(Icons.discount, size: 14),
                        label: const Text('خصم مبلغ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ صلاحية الخصم متاحة للمدير فقط'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.lock_outline, size: 14),
                        label: const Text('خصم (مقيد)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: actions,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('معلومات الحجز', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildInfoRow('رقم الحجز', booking.localUuid),
                  _buildInfoRow('تاريخ الوصول', booking.checkinDate.split(' ')[0]),
                  if (booking.checkoutDate != null)
                    _buildInfoRow('تاريخ المغادرة', booking.checkoutDate!.split(' ')[0]),
                  _buildInfoRow('الحالة', booking.status),
                  if (booking.notes != null && booking.notes!.isNotEmpty) _buildInfoRow('ملاحظات', booking.notes!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Internal UI helpers — مُدمجة داخل ActionsTab (لا coupling خارجي)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 8, color: Colors.grey),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
