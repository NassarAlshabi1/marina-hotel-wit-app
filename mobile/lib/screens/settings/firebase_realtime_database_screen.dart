import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/firebase_realtime_provider.dart';
import '../../services/firebase_realtime_database_service.dart';
import '../../widgets/primary_button.dart';
import '../../utils/time.dart';

class FirebaseRealtimeDatabaseScreen extends ConsumerStatefulWidget {
  const FirebaseRealtimeDatabaseScreen({super.key});

  @override
  ConsumerState<FirebaseRealtimeDatabaseScreen> createState() => _FirebaseRealtimeDatabaseScreenState();
}

class _FirebaseRealtimeDatabaseScreenState extends ConsumerState<FirebaseRealtimeDatabaseScreen> {
  bool _isRealtimeMonitoringEnabled = false;

  @override
  Widget build(BuildContext context) {
    final firebaseState = ref.watch(firebaseRealtimeStateProvider);
    final firebaseNotifier = ref.read(firebaseRealtimeStateProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Realtime Database'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // حالة الاتصال
              _buildConnectionStatus(firebaseState),
              const SizedBox(height: 20),

              // الإحصائيات المباشرة
              _buildRealtimeStatistics(),
              const SizedBox(height: 20),

              // أزرار التحكم
              _buildControlButtons(firebaseNotifier, firebaseState),
              const SizedBox(height: 20),

              // إعدادات المراقبة المباشرة
              _buildRealtimeMonitoringSettings(firebaseNotifier),
              const SizedBox(height: 20),

              // معلومات الخدمة
              _buildServiceInfo(),
              const SizedBox(height: 20),

              // قواعد الأمان (للمرجع)
              _buildSecurityRules(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(FirebaseRealtimeState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.isInitialized ? Icons.cloud_done : Icons.cloud_off,
                  color: state.isInitialized ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  state.isInitialized ? 'متصل' : 'غير متصل',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: state.isInitialized ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.errorMessage != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            if (state.lastSyncTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'آخر مزامنة: ${state.lastSyncTime}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
            if (state.isSyncing) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('جاري المزامنة...'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeStatistics() {
    final statisticsAsync = ref.watch(firebaseStatisticsStreamProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الإحصائيات المباشرة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            statisticsAsync.when(
              data: (stats) => _buildStatisticsGrid(stats),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('غير متاح (وضع Offline)'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsGrid(Map<String, int> stats) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.5,
      children: [
        _buildStatCard('الغرف', stats['total_rooms'] ?? 0, Icons.hotel, Colors.blue),
        _buildStatCard('الحجوزات', stats['total_bookings'] ?? 0, Icons.book, Colors.green),
        _buildStatCard('المدفوعات', stats['total_payments'] ?? 0, Icons.payment, Colors.orange),
        _buildStatCard('المصروفات', stats['total_expenses'] ?? 0, Icons.receipt, Colors.red),
      ],
    );
  }

  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(FirebaseRealtimeNotifier notifier, FirebaseRealtimeState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'التحكم في المزامنة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                text: state.isSyncing ? 'جاري المزامنة...' : 'مزامنة جميع البيانات',
                onPressed: state.isSyncing ? null : () => notifier.syncAllData(),
                icon: state.isSyncing ? Icons.sync : Icons.cloud_sync,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeMonitoringSettings(FirebaseRealtimeNotifier notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المراقبة المباشرة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'تلقي تحديثات فورية عند حدوث تغييرات في البيانات',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('تفعيل المراقبة المباشرة'),
              subtitle: Text(
                _isRealtimeMonitoringEnabled 
                  ? 'سيتم إشعارك فور حدوث تغييرات'
                  : 'المراقبة المباشرة معطلة',
              ),
              value: _isRealtimeMonitoringEnabled,
              onChanged: (value) {
                setState(() {
                  _isRealtimeMonitoringEnabled = value;
                });
                notifier.toggleRealtimeMonitoring(value);
              },
              activeColor: Colors.blue[700],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات الخدمة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Firebase URL', 'aden-flutter-default-rtdb.firebaseio.com'),
            _buildInfoRow('Project ID', 'aden-flutter'),
            _buildInfoRow('مسار البيانات', 'marina_hotel_data'),
            _buildInfoRow('Cache Size', '10 MB'),  // قيمة ثابتة
            _buildInfoRow('Offline Support', 'مُفعل'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildSecurityRules() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'قواعد الأمان المقترحة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'نسخ هذه القواعد إلى Firebase Console → Realtime Database → Rules',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                FirebaseRealtimeDatabaseService.securityRulesExample,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.security, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'يتطلب مصادقة للقراءة والكتابة',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// شاشة مراقبة البيانات المباشرة
class FirebaseRealtimeMonitorScreen extends ConsumerWidget {
  const FirebaseRealtimeMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المراقبة المباشرة'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // إحصائيات سريعة
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.green[50],
              child: Consumer(
                builder: (context, ref, child) {
                  final statsAsync = ref.watch(firebaseStatisticsStreamProvider);
                  return statsAsync.when(
                    data: (stats) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildQuickStat('الغرف', stats['total_rooms'] ?? 0, Icons.hotel),
                        _buildQuickStat('الحجوزات', stats['total_bookings'] ?? 0, Icons.book),
                        _buildQuickStat('المدفوعات', stats['total_payments'] ?? 0, Icons.payment),
                      ],
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Text('خطأ في جلب الإحصائيات: $error'),
                  );
                },
              ),
            ),

            // قائمة الحجوزات النشطة
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final activeBookingsAsync = ref.watch(firebaseActiveBookingsStreamProvider);
                  return activeBookingsAsync.when(
                    data: (bookings) => ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: bookings.length,
                      itemBuilder: (context, index) {
                        final booking = bookings[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getStatusColor(booking.status),
                              child: Text(
                                booking.roomNumber,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(booking.guestName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('الغرفة: ${booking.roomNumber}'),
                                Text('الدخول: ${booking.checkinDate}'),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(booking.status).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatusText(booking.status),
                                style: TextStyle(
                                  color: _getStatusColor(booking.status),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, stack) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.error, color: Colors.red[400], size: 48),
                            const SizedBox(height: 8),
                            Text(
                              'خطأ في جلب الحجوزات المباشرة',
                              style: TextStyle(color: Colors.red[700]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              error.toString(),
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.green[700]),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.green[700],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.green[600],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'confirmed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'checked_in':
        return Colors.blue;
      case 'checked_out':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'confirmed':
        return 'مؤكد';
      case 'pending':
        return 'معلق';
      case 'checked_in':
        return 'دخل';
      case 'checked_out':
        return 'خرج';
      default:
        return status;
    }
  }
}