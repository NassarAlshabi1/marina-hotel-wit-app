import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ditto_providers.dart';
import '../services/ditto_cloud_sync_service.dart';
import '../widgets/ditto_connection_test.dart';

/// شاشة إدارة Ditto Cloud Sync
class DittoManagementScreen extends ConsumerStatefulWidget {
  const DittoManagementScreen({super.key});

  @override
  ConsumerState<DittoManagementScreen> createState() => _DittoManagementScreenState();
}

class _DittoManagementScreenState extends ConsumerState<DittoManagementScreen> {
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _initializeDitto();
  }

  /// تهيئة Ditto عند بدء التطبيق
  Future<void> _initializeDitto() async {
    if (_isInitializing) return;
    
    setState(() => _isInitializing = true);
    
    try {
      final dittoService = ref.read(dittoCloudSyncProvider);
      await dittoService.initialize();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تهيئة Ditto Cloud Sync بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في تهيئة Ditto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🌐 Ditto Cloud Sync'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isInitializing ? null : _forceSyncNow,
            icon: const Icon(Icons.sync),
            tooltip: 'مزامنة فورية',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // أداة اختبار الاتصال
            const DittoConnectionTestWidget(),
            const SizedBox(height: 16),
            
            // بطاقة حالة المزامنة
            _buildSyncStatusCard(),
            const SizedBox(height: 16),
            
            // أزرار الإدارة
            _buildActionButtons(),
            const SizedBox(height: 16),
            
            // الحجوزات في الوقت الفعلي
            Expanded(
              child: _buildLiveBookingsSection(),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة حالة المزامنة
  Widget _buildSyncStatusCard() {
    return Consumer(
      builder: (context, ref, child) {
        final syncStatusAsync = ref.watch(dittoSyncStatusProvider);
        
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud,
                      color: Colors.blue.shade600,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'حالة المزامنة السحابية',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                syncStatusAsync.when(
                  data: (status) => _buildStatusDetails(status),
                  loading: () => const CircularProgressIndicator(),
                  error: (error, _) => Text(
                    'خطأ في جلب الحالة: $error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// تفاصيل حالة المزامنة
  Widget _buildStatusDetails(Map<String, dynamic> status) {
    return Column(
      children: [
        _buildStatusRow('مُهيّأ', status['initialized'] ? '✅ نعم' : '❌ لا'),
        _buildStatusRow('يعمل حالياً', status['syncing'] ? '🔄 نعم' : '⏸️ لا'),
        _buildStatusRow('معرف الجهاز', status['device_id'] ?? 'غير محدد'),
        _buildStatusRow('آخر مزامنة', _formatLastSync(status['last_sync'])),
        _buildStatusRow('WebSocket', status['websocket_url'] ?? 'غير محدد'),
        _buildStatusRow('P2P محلي', status['p2p_enabled'] ? 'مُفعّل' : '🚫 معطل'),
      ],
    );
  }

  /// صف حالة فردي
  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// أزرار الإدارة
  Widget _buildActionButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ElevatedButton.icon(
          onPressed: _isInitializing ? null : _testCreateBooking,
          icon: const Icon(Icons.add_business),
          label: const Text('إنشاء حجز تجريبي'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isInitializing ? null : _testCreatePayment,
          icon: const Icon(Icons.payment),
          label: const Text('إنشاء دفعة تجريبية'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade600,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isInitializing ? null : _forceSyncNow,
          icon: const Icon(Icons.sync),
          label: const Text('مزامنة فورية'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  /// قسم الحجوزات المباشرة
  Widget _buildLiveBookingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📋 الحجوزات (مزامنة حية)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        Expanded(
          child: Consumer(
            builder: (context, ref, child) {
              final bookingsAsync = ref.watch(dittoLiveBookingsProvider);
              
              return bookingsAsync.when(
                data: (bookings) {
                  if (bookings.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('لا توجد حجوزات حالياً'),
                        ],
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      final booking = bookings[index];
                      return _buildBookingCard(booking);
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Center(
                  child: Text('خطأ في جلب الحجوزات: $error'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// بطاقة حجز
  Widget _buildBookingCard(Map<String, dynamic> booking) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(booking['status']),
          child: Text(
            booking['room_number']?.toString() ?? '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(booking['guest_name'] ?? 'غير محدد'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الحالة: ${booking['status'] ?? 'غير محدد'}'),
            Text('تاريخ الدخول: ${_formatDate(booking['checkin_date'])}'),
          ],
        ),
        trailing: Text(
          '${booking['total_amount']?.toStringAsFixed(2) ?? '0'} ر.س',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      ),
    );
  }

  /// لون حالة الحجز
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'محجوزة':
        return Colors.blue;
      case 'تم الدخول':
        return Colors.green;
      case 'تم الخروج':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  /// تنسيق التاريخ
  String _formatDate(String? dateString) {
    if (dateString == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  /// تنسيق آخر مزامنة
  String _formatLastSync(String? lastSyncString) {
    if (lastSyncString == null) return 'لم تتم مزامنة بعد';
    try {
      final lastSync = DateTime.parse(lastSyncString);
      final now = DateTime.now();
      final diff = now.difference(lastSync);
      
      if (diff.inMinutes < 1) {
        return 'الآن';
      } else if (diff.inHours < 1) {
        return 'منذ ${diff.inMinutes} دقيقة';
      } else if (diff.inDays < 1) {
        return 'منذ ${diff.inHours} ساعة';
      } else {
        return 'منذ ${diff.inDays} أيام';
      }
    } catch (e) {
      return lastSyncString;
    }
  }

  /// إنشاء حجز تجريبي
  Future<void> _testCreateBooking() async {
    try {
      final dittoService = ref.read(dittoCloudSyncProvider);
      
      final bookingId = await dittoService.createBooking(
        guestName: 'نزيل تجريبي ${DateTime.now().millisecondsSinceEpoch}',
        roomNumber: '${101 + (DateTime.now().millisecondsSinceEpoch % 10)}',
        checkinDate: DateTime.now().toIso8601String(),
        checkoutDate: DateTime.now().add(Duration(days: 3)).toIso8601String(),
        totalAmount: 450.0,
        notes: 'حجز تجريبي من Ditto Cloud',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم إنشاء حجز تجريبي: $bookingId'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في إنشاء الحجز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// إنشاء دفعة تجريبية  
  Future<void> _testCreatePayment() async {
    try {
      final dittoService = ref.read(dittoCloudSyncProvider);
      
      final paymentId = await dittoService.createPayment(
        bookingId: 'test_booking_id',
        amount: 150.0,
        paymentMethod: 'نقدي',
        notes: 'دفعة تجريبية من Ditto Cloud',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم إنشاء دفعة تجريبية: $paymentId'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في إنشاء الدفعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// مزامنة فورية
  Future<void> _forceSyncNow() async {
    try {
      final dittoService = ref.read(dittoCloudSyncProvider);
      await dittoService.forceSyncNow();
      
      // تحديث البيانات
      ref.invalidate(dittoSyncStatusProvider);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت المزامنة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}