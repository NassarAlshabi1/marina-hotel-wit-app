import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ditto_cloud_sync_service.dart';
import '../components/widgets/ditto_connection_test_widget.dart';

/// شاشة إدارة Ditto Cloud Sync
/// 
/// تحتوي على:
/// - أداة اختبار الاتصال
/// - إدارة المزامنة
/// - استعلامات DQL مخصصة
/// - عرض البيانات المباشرة
class DittoManagementScreen extends ConsumerStatefulWidget {
  const DittoManagementScreen({super.key});

  @override
  ConsumerState<DittoManagementScreen> createState() => _DittoManagementScreenState();
}

class _DittoManagementScreenState extends ConsumerState<DittoManagementScreen> {
  bool _isInitializing = false;
  final TextEditingController _minAmountController = TextEditingController(text: '500');
  List<Map<String, dynamic>> _highValueBookings = [];
  bool _isLoadingHighValue = false;
  
  // بيانات إضافية للعرض
  Map<String, int> _bookingsStats = {};
  List<Map<String, dynamic>> _roomsStatus = [];
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingStats = true);

    try {
      final dittoService = DittoCloudSyncService();
      
      // تهيئة Ditto إذا لم يكن مهيئاً
      if (!dittoService.isConnected) {
        await dittoService.initialize();
      }

      // جلب البيانات الأولية
      final stats = await dittoService.getBookingsStats();
      final rooms = await dittoService.getRoomsStatus();

      if (mounted) {
        setState(() {
          _bookingsStats = stats;
          _roomsStatus = rooms;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في جلب البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// جلب الحجوزات ذات القيمة العالية
  Future<void> _fetchHighValueBookings() async {
    final minAmountText = _minAmountController.text.trim();
    final minAmount = double.tryParse(minAmountText);
    
    if (minAmount == null || minAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ الرجاء إدخال مبلغ صحيح'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoadingHighValue = true);

    try {
      final dittoService = DittoCloudSyncService();
      final bookings = await dittoService.getHighValueBookings(minAmount: minAmount);
      
      setState(() {
        _highValueBookings = bookings;
        _isLoadingHighValue = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم جلب ${bookings.length} حجوزات بمبلغ أكبر من ${minAmount.toStringAsFixed(2)} ر.س'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoadingHighValue = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في جلب البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'إدارة Ditto Cloud Sync',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.purple.shade600,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            onPressed: _loadInitialData,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
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
              
              // قسم الاستعلام المخصص
              _buildCustomQuerySection(),
              const SizedBox(height: 16),
              
              // الحجوزات في الوقت الفعلي
              SizedBox(
                height: 400,
                child: _buildLiveBookingsSection(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// بطاقة حالة المزامنة
  Widget _buildSyncStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade600, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'إحصائيات المزامنة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_isLoadingStats)
              const Center(child: CircularProgressIndicator())
            else ...[
              // إحصائيات الحجوزات
              if (_bookingsStats.isNotEmpty) ...[
                const Text(
                  'إحصائيات الحجوزات:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: _bookingsStats.entries.map((entry) {
                    return _buildStatChip(
                      _getStatusLabel(entry.key),
                      entry.value.toString(),
                      _getStatusColor(entry.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
              
              // حالة الغرف
              if (_roomsStatus.isNotEmpty) ...[
                const Text(
                  'حالة الغرف (عينة):',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _roomsStatus.length,
                    itemBuilder: (context, index) {
                      final room = _roomsStatus[index];
                      return _buildRoomCard(room);
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.darken(20),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final status = room['status'] ?? '';
    final roomNumber = room['room_number'] ?? '';
    final floor = room['floor'] ?? 1;
    
    final statusColor = _getRoomStatusColor(status);
    
    return Container(
      width: 60,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            roomNumber,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: statusColor.darken(20),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ط$floor',
            style: TextStyle(
              fontSize: 10,
              color: statusColor.darken(10),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  /// أزرار الإدارة
  Widget _buildActionButtons() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Colors.teal.shade600, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'أدوات الإدارة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isInitializing ? null : _initializeDitto,
                    icon: _isInitializing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.power_settings_new),
                    label: const Text('تهيئة النظام'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _forceSync,
                    icon: const Icon(Icons.sync),
                    label: const Text('مزامنة قوية'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// قسم الاستعلام المخصص
  Widget _buildCustomQuerySection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_alt, color: Colors.purple.shade600, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'استعلام مخصص: الحجوزات ذات القيمة العالية',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // حقل الإدخال والزر
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minAmountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الحد الأدنى للمبلغ (ر.س)',
                      hintText: 'مثال: 500',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLoadingHighValue ? null : _fetchHighValueBookings,
                  icon: _isLoadingHighValue
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: const Text('بحث'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // عرض النتائج
            if (_highValueBookings.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'النتائج (${_highValueBookings.length}):',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(
                    _highValueBookings.length > 5 ? 5 : _highValueBookings.length,
                    (index) {
                      final booking = _highValueBookings[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade100,
                            child: Text(
                              booking['room_number']?.toString() ?? '?',
                              style: TextStyle(
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(booking['guest_name'] ?? 'غير محدد'),
                          subtitle: Text('الحالة: ${_getStatusLabel(booking['status'] ?? 'غير محدد')}'),
                          trailing: Text(
                            '${booking['total_amount']?.toStringAsFixed(2) ?? '0'} ر.س',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_highValueBookings.length > 5)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '... و ${_highValueBookings.length - 5} حجز آخر',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// الحجوزات في الوقت الفعلي
  Widget _buildLiveBookingsSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.live_tv, color: Colors.red.shade600, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'الحجوزات المباشرة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'مباشر',
                  style: TextStyle(
                    color: Colors.red.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: DittoCloudSyncService().watchLiveBookings(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_empty, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'لا توجد بيانات مباشرة حالياً',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  final liveBookings = snapshot.data!;
                  return ListView.builder(
                    itemCount: liveBookings.length,
                    itemBuilder: (context, index) {
                      final booking = liveBookings[index];
                      return Card(
                        color: Colors.blue.shade50,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Icon(
                              Icons.new_releases,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            'غرفة ${booking['room_number']} - ${booking['guest_name']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'الحالة: ${_getStatusLabel(booking['status'])}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${booking['total_amount']?.toStringAsFixed(0) ?? '0'} ر.س',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              Text(
                                'الآن',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeDitto() async {
    setState(() => _isInitializing = true);

    try {
      final dittoService = DittoCloudSyncService();
      final initialized = await dittoService.initialize();
      
      if (initialized && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تهيئة Ditto بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadInitialData();
      } else {
        throw Exception('فشل في التهيئة');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في التهيئة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _forceSync() async {
    try {
      final dittoService = DittoCloudSyncService();
      final synced = await dittoService.syncNow();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(synced ? '✅ تمت المزامنة القوية بنجاح' : '❌ فشل في المزامنة'),
            backgroundColor: synced ? Colors.green : Colors.red,
          ),
        );
        
        if (synced) {
          await _loadInitialData();
        }
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

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed': return 'مؤكد';
      case 'checked_in': return 'وصل';
      case 'checked_out': return 'غادر';
      case 'cancelled': return 'ملغي';
      case 'pending': return 'في الانتظار';
      case 'available': return 'متاحة';
      case 'occupied': return 'مشغولة';
      case 'maintenance': return 'صيانة';
      default: return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed': return Colors.blue;
      case 'checked_in': return Colors.green;
      case 'checked_out': return Colors.orange;
      case 'cancelled': return Colors.red;
      case 'pending': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _getRoomStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available': return Colors.green;
      case 'occupied': return Colors.red;
      case 'maintenance': return Colors.orange;
      default: return Colors.grey;
    }
  }
}

// Extension لتعديل الألوان
extension ColorBrightness on Color {
  Color darken([int percent = 10]) {
    assert(1 <= percent && percent <= 100);
    final f = 1 - percent / 100;
    return Color.fromARGB(
      alpha,
      (red * f).round(),
      (green * f).round(),
      (blue * f).round(),
    );
  }
}