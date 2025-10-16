import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking.dart';

class PaymentCheckoutScreen extends StatelessWidget {
  final Booking booking;
  const PaymentCheckoutScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'ar_SA', symbol: 'ر.س', decimalDigits: 0);

    final totalDue = booking.totalDue();
    final paid = booking.paidTotal;
    final remaining = booking.remaining();

    return Scaffold(
      appBar: AppBar(title: const Text('الدفع والمغادرة')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('معلومات الحجز', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    _infoRow(Icons.person, 'النزيل', booking.guestName),
                    _infoRow(Icons.bed, 'الغرفة', booking.roomNumber),
                    _infoRow(
                      Icons.night_shelter,
                      'عدد الليالي',
                      '${booking.nightsForBilling()} ليلة',
                    ),
                    _infoRow(
                      Icons.price_change,
                      'سعر الليلة',
                      currency.format(booking.nightlyRate),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _totalRow('الإجمالي', currency.format(totalDue), Colors.blue),
                    const SizedBox(height: 6),
                    _totalRow('المدفوع', currency.format(paid), Colors.green),
                    const Divider(),
                    _totalRow(
                      'المتبقي',
                      currency.format(remaining),
                      remaining > 0 ? Colors.red : Colors.green,
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('سجل المدفوعات', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (booking.payments.isEmpty)
                        const Expanded(
                          child: Center(child: Text('لا توجد مدفوعات مسجلة')),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: booking.payments.length,
                            itemBuilder: (context, index) {
                              final p = booking.payments[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.receipt_long, color: Colors.green),
                                title: Text(
                                  currency.format(p.amount),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(DateFormat('yyyy-MM-dd HH:mm', 'ar_SA').format(p.paymentDate)),
                                trailing: Chip(
                                  label: Text(p.method),
                                  backgroundColor: Colors.green.shade50,
                                  side: BorderSide.none,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: remaining > 0
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم إتمام تسجيل المغادرة بنجاح'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('تسجيل المغادرة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.w800 : FontWeight.w600)),
        Text(value, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.w800 : FontWeight.w700)),
      ],
    );
  }
}
