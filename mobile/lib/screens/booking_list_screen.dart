import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking.dart';
import '../data/mock_bookings.dart';
import 'payment_checkout_screen.dart';

class BookingListScreen extends StatelessWidget {
  const BookingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'ar_SA', symbol: 'ر.س', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الحجوزات'),
      ),
      body: ListView.separated(
        itemCount: mockBookings.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final booking = mockBookings[index];
          final nights = booking.nightsForDisplay();
          final remaining = booking.remaining();

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              foregroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.person),
            ),
            title: Text(
              booking.guestName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Row(
              children: [
                const Icon(Icons.meeting_room, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('غرفة ${booking.roomNumber}', style: const TextStyle(color: Colors.black87)),
                const SizedBox(width: 12),
                const Icon(Icons.night_shelter, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('$nights ليلة', style: const TextStyle(color: Colors.black87)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  currency.format(remaining),
                  style: TextStyle(
                    color: remaining > 0 ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining > 0 ? 'متبقي' : 'مسدد',
                  style: TextStyle(color: remaining > 0 ? Colors.red : Colors.green, fontSize: 12),
                ),
              ],
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaymentCheckoutScreen(booking: booking),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
