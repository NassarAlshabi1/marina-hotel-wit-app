import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import '../../components/widgets/empty_state.dart';
import 'booking_edit.dart';
import '../payments/booking_payment_screen.dart';
import '../payments/booking_checkout_screen.dart';
import '../payments/payments_main_screen.dart';

class BookingsListScreen extends ConsumerWidget {
  const BookingsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingsListProvider);
    
    return AppScaffold(
      title: 'الحجوزات',
      actions: [
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PaymentsMainScreen())
            );
          },
          icon: const Icon(Icons.payments),
          tooltip: 'إدارة المدفوعات',
        ),
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة البيانات',
        ),
        IconButton(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingEditScreen()));
          },
          icon: const Icon(Icons.add),
          tooltip: 'حجز جديد',
        )
      ],
      body: bookings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('خطأ: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              title: 'لا توجد حجوزات',
              message: 'اضغط على + لإضافة حجز جديد',
              icon: Icons.hotel_outlined,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (c, i) {
              final booking = list[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // معلومات الحجز الرئيسية
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  booking.guestName,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'غرفة ${booking.roomNumber}',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildStatusChip(context, booking.status),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // تواريخ الإقامة
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.login, size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Text('الوصول: ${booking.checkinDate}'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.logout, size: 16, color: Colors.red),
                                const SizedBox(width: 8),
                                Text('المغادرة: ${booking.checkoutDate ?? 'لم يحدد'}'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // أزرار العمليات
                      Row(
                        children: [
                          // زر تعديل
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BookingEditScreen(existing: booking)
                                  )
                                );
                              },
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('تعديل'),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // زر المدفوعات
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BookingPaymentScreen(booking: booking)
                                  )
                                );
                              },
                              icon: const Icon(Icons.payment, size: 18),
                              label: const Text('دفع'),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // زر تسجيل المغادرة (فقط للحجوزات النشطة)
                          if (booking.status == 'active' || booking.status == 'نشط') ...[
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BookingCheckoutScreen(booking: booking)
                                    )
                                  );
                                },
                                icon: const Icon(Icons.exit_to_app, size: 18),
                                label: const Text('خروج'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ] else ...[
                            const Expanded(child: SizedBox()),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, String status) {
    Color backgroundColor;
    Color textColor;
    String displayText;

    switch (status.toLowerCase()) {
      case 'active':
      case 'نشط':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        displayText = 'نشط';
        break;
      case 'completed':
      case 'مكتمل':
        backgroundColor = Colors.blue.shade100;
        textColor = Colors.blue.shade800;
        displayText = 'مكتمل';
        break;
      case 'cancelled':
      case 'ملغي':
        backgroundColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
        displayText = 'ملغي';
        break;
      default:
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
        displayText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
