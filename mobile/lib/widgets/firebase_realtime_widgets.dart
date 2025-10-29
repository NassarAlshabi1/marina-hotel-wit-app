/// دمج Firebase Realtime Database مع Dashboard
/// إضافة هذا الكود إلى dashboard_screen.dart

// أضف هذا Import في dashboard_screen.dart
import '../../providers/firebase_realtime_provider.dart';

// أضف هذا Widget للإحصائيات المباشرة من Firebase
class FirebaseRealtimeStatsCard extends ConsumerWidget {
  const FirebaseRealtimeStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseState = ref.watch(firebaseRealtimeStateProvider);
    final statisticsAsync = ref.watch(firebaseStatisticsStreamProvider);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  firebaseState.isInitialized ? Icons.cloud_done : Icons.cloud_off,
                  color: firebaseState.isInitialized ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'الإحصائيات المباشرة (Firebase)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: firebaseState.isInitialized ? Colors.green : Colors.red,
                  ),
                ),
                const Spacer(),
                if (firebaseState.isSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            statisticsAsync.when(
              data: (stats) => GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 3,
                children: [
                  _buildStatItem('الغرف الكلية', stats['total_rooms'] ?? 0, Icons.hotel, Colors.blue),
                  _buildStatItem('الحجوزات النشطة', stats['total_bookings'] ?? 0, Icons.book, Colors.green),
                  _buildStatItem('المدفوعات', stats['total_payments'] ?? 0, Icons.payment, Colors.orange),
                  _buildStatItem('المصروفات', stats['total_expenses'] ?? 0, Icons.receipt, Colors.red),
                ],
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    const Text('وضع Offline - البيانات المحلية فقط'),
                  ],
                ),
              ),
            ),
            
            if (firebaseState.lastSyncTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'آخر تحديث: ${_formatTime(firebaseState.lastSyncTime!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String isoTime) {
    final time = DateTime.parse(isoTime);
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'منذ لحظات';
    } else if (difference.inHours < 1) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inDays < 1) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }
}

// Widget للعرض السريع للحجوزات المباشرة
class RealtimeActiveBookingsWidget extends ConsumerWidget {
  const RealtimeActiveBookingsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBookingsAsync = ref.watch(firebaseActiveBookingsStreamProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.real_estate_agent, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'الحجوزات النشطة (مباشر)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            activeBookingsAsync.when(
              data: (bookings) {
                if (bookings.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('لا توجد حجوزات نشطة'),
                    ),
                  );
                }
                
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: bookings.length > 3 ? 3 : bookings.length, // عرض 3 فقط
                  itemBuilder: (context, index) {
                    final booking = bookings[index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          booking.roomId.toString(),
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(booking.guestName, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        'غرفة ${booking.roomId} • ${booking.status}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Container(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    const Text('غير متاح (وضع Offline)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            
            if (activeBookingsAsync.hasValue && activeBookingsAsync.value!.length > 3)
              TextButton(
                onPressed: () {
                  // انتقل إلى صفحة الحجوزات الكاملة
                  Navigator.pushNamed(context, '/bookings');
                },
                child: Text('عرض جميع الحجوزات (${activeBookingsAsync.value!.length})'),
              ),
          ],
        ),
      ),
    );
  }
}