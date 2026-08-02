// ignore_for_file: always_put_required_named_parameters_first

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/payment_models.dart';
import '../../../services/local_db.dart' as db;
import '../../../services/stay_balance_calculator.dart';

/// بطاقة ملخص الدفع — widget مستقل مُستخرج من BookingPaymentScreen.
///
/// قبل الإصلاح: كان هذا الـ widget مُضمَّناً كـ method داخل BookingPaymentScreen
/// (279 سطر). الاستخراج يُسهّل الصيانة والاختبار ويُقلل حجم الشاشة الأم.
class PaymentSummaryCard extends StatelessWidget {
  const PaymentSummaryCard({
    super.key,
    required this.summary,
    required this.expectedNights,
    required this.actualNights,
    required this.checkin,
    required this.booking,
    required this.guestPhone,
    required this.currencyFmt,
    required this.debtAmount,
    this.liveBooking,
    this.roomRate,
    this.priceAdjustments,
    this.plannedCheckout,
    this.actualCheckout,
    this.discount = 0,
    this.normalNights = 0,
    this.discountedNights = 0,
    this.surchargeNights = 0,
    this.totalDiscount = 0,
    this.totalSurcharge = 0,
    this.hasNotCheckedOut = false,
    this.nowIsAfterCutoff = false,
    this.actualNightsDynamic = 0,
    this.todayPaidAmount = 0,
    this.onAddBalancePayment,
  });

  final BookingPaymentSummary summary;
  final int expectedNights;
  final int actualNights;
  final DateTime checkin;
  final db.Booking booking;
  final String guestPhone;
  final NumberFormat currencyFmt;
  final double debtAmount;
  final db.Booking? liveBooking;
  final double? roomRate;
  final List<db.BookingPriceAdjustment>? priceAdjustments;
  final DateTime? plannedCheckout;
  final DateTime? actualCheckout;
  final double discount;
  final int normalNights;
  final int discountedNights;
  final int surchargeNights;
  final double totalDiscount;
  final double totalSurcharge;
  final bool hasNotCheckedOut;
  final bool nowIsAfterCutoff;
  final int actualNightsDynamic;
  final double todayPaidAmount;
  final VoidCallback? onAddBalancePayment;

  @override
  Widget build(BuildContext context) {
    final progressPercentage = summary.paidPercentage / 100;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'en');
    final checkinText = dateFmt.format(checkin);
    final plannedText = plannedCheckout != null
        ? dateFmt.format(plannedCheckout!)
        : null;
    final actualText = actualCheckout != null
        ? dateFmt.format(actualCheckout!)
        : null;
    final hasPhone = guestPhone.isNotEmpty;
    final identityLine = booking.guestIdNumber.isEmpty
        ? booking.guestIdType
        : '${booking.guestIdType} • ${booking.guestIdNumber}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            if (summary.isFullyPaid)
              Colors.green.shade50
            else
              Colors.blue.shade50,
            if (summary.isFullyPaid)
              Colors.green.shade100
            else
              Colors.blue.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: summary.isFullyPaid
              ? Colors.green.shade200
              : Colors.blue.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGuestInfoRow(
            identityLine,
            hasPhone,
            checkinText,
            plannedText,
            actualText,
          ),
          const SizedBox(height: 8),
          _buildChipsRow(),
          const SizedBox(height: 1),
          _buildProgressBar(progressPercentage),
          const SizedBox(height: 1),
          _buildAmountChipsRow(),
          const SizedBox(height: 2),
          if (onAddBalancePayment != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddBalancePayment,
                icon: const Icon(Icons.account_balance_wallet, size: 12),
                label: const Text(
                  'إضافة دفعة رصيد تراكمي',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGuestInfoRow(
    String identityLine,
    bool hasPhone,
    String checkinText,
    String? plannedText,
    String? actualText,
  ) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.blue,
          child: Text(
            booking.roomNumber,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                booking.guestName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'غرفة ${booking.roomNumber}${hasPhone ? ' • $guestPhone' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              Text(
                identityLine,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                'الجنسية: ${booking.guestNationality}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                'الوصول: $checkinText',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              if (plannedText != null)
                Text(
                  'المغادرة المخطط: $plannedText',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              Builder(
                builder: (context) {
                  final balanceResult = StayBalanceCalculator.calculate(
                    liveBooking ?? booking,
                    roomRate: roomRate,
                    priceAdjustments: priceAdjustments,
                  );
                  if (!balanceResult.hasPayments) {
                    return const SizedBox.shrink();
                  }
                  final autoFmt = DateFormat('dd/MM/yyyy', 'en');
                  final autoStr = autoFmt.format(
                    balanceResult.autoCheckoutDate,
                  );
                  final extra = balanceResult.isAutoExtended
                      ? ' (+${balanceResult.extraNightsBeyondManual})'
                      : '';
                  return Text(
                    'المغادرة التلقائية: $autoStr (${balanceResult.totalPaidNights} ليلة مدفوعة)$extra',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  );
                },
              ),
              if (actualText != null)
                Text(
                  'المغادرة الفعلي: $actualText',
                  style: const TextStyle(fontSize: 11, color: Colors.green),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: summary.isFullyPaid
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: summary.isFullyPaid ? Colors.green : Colors.orange,
            ),
          ),
          child: Text(
            summary.isFullyPaid ? 'مكتمل الدفع' : 'دفع جزئي',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: summary.isFullyPaid ? Colors.green : Colors.orange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChipsRow() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _detailChip(
          icon: Icons.attach_money,
          label: 'سعر الليلة',
          value: currencyFmt.format(roomRate),
        ),
        _detailChip(
          icon: Icons.task_alt,
          label: 'الليالي الفعلية',
          value: actualNights.toString(),
          color: actualNights > expectedNights ? Colors.orange : Colors.green,
        ),
        if (hasNotCheckedOut &&
            nowIsAfterCutoff &&
            actualNightsDynamic > expectedNights)
          _infoBadge(
            icon: Icons.schedule,
            text: '+${actualNightsDynamic - expectedNights} ليلة بعد 14:01',
            bgColor: Colors.orange.shade100,
            borderColor: Colors.orange.shade400,
            textColor: Colors.orange.shade700,
          ),
        if (debtAmount > 0)
          _infoBadge(
            icon: Icons.warning,
            text: 'يوجد دين ${currencyFmt.format(debtAmount)}',
            bgColor: Colors.red.shade100,
            borderColor: Colors.red.shade300,
            textColor: Colors.red.shade700,
          ),
        if (discount > 0)
          _detailChip(
            icon: Icons.discount,
            label: 'التخفيض',
            value: currencyFmt.format(discount),
            color: Colors.purple,
          ),
        if (normalNights > 0)
          _detailChip(
            icon: Icons.nights_stay,
            label: 'ليالي عادية',
            value: normalNights.toString(),
            color: Colors.blueGrey,
          ),
        if (discountedNights > 0)
          _detailChip(
            icon: Icons.trending_down,
            label: 'ليالي مخفضة',
            value: '$discountedNights (-${currencyFmt.format(totalDiscount)})',
            color: Colors.purple,
          ),
        if (surchargeNights > 0)
          _detailChip(
            icon: Icons.trending_up,
            label: 'ليالي مزادة',
            value: '$surchargeNights (+${currencyFmt.format(totalSurcharge)})',
            color: Colors.teal,
          ),
      ],
    );
  }

  Widget _buildProgressBar(double progressPercentage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'تقدم الدفع',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
            ),
            Text(
              '${summary.paidPercentage.toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
            ),
          ],
        ),
        const SizedBox(height: 1),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progressPercentage,
            minHeight: 2,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(
              summary.isFullyPaid ? Colors.green : Colors.blue,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountChipsRow() {
    return Row(
      children: [
        Expanded(
          child: _amountChip('الإجمالي', summary.totalAmount, Colors.blue),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _amountChip('المدفوع', summary.paidAmount, Colors.green),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _amountChip('المتبقي', summary.remainingAmount, Colors.red),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _amountChip('مدفوع اليوم', todayPaidAmount, Colors.indigo),
        ),
      ],
    );
  }

  Widget _detailChip({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final chipColor = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 3),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 9,
              color: chipColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 9,
              color: chipColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBadge({
    required IconData icon,
    required String text,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            currencyFmt.format(amount),
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
