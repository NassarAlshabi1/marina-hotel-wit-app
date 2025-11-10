import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/ditto_cloud_sync_service.dart';
import '../../services/ditto_local_sync_service.dart';
import '../../services/providers.dart';
import 'dart:async';

/// شاشة حالة المزامنة والاتصال مع Ditto Cloud
/// 
/// تعرض معلومات تفصيلية عن:
/// - حالة الاتصال مع Ditto Cloud
/// - إحصائيات المزامنة
/// - عدد السجلات في كل مجموعة
/// - معلومات الجهاز الحالي
/// - سجل المزامنة
class DittoSyncStatusScreen extends ConsumerStatefulWidget {
  const DittoSyncStatusScreen({super.key});

  @override
  ConsumerState<DittoSyncStatusScreen> createState() => _DittoSyncStatusScreenState();
}

class _DittoSyncStatusScreenState extends ConsumerState<DittoSyncStatusScreen> {
  final _dittoService = DittoCloudSyncService();
  final _syncService = DittoLocalSyncService();
  
  bool _isLoading = false;
  Map<String, dynamic>? _connectionStatus;
  Map<String, dynamic>? _deviceInfo;
  Map<String, dynamic>? _syncStats;
  List<String> _syncLog = [];
  
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    
    // تحديث تلقائي كل 5 ثوانٍ
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadConnectionStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    await Future.wait([
      _loadConnectionStatus(),
      _loadDeviceInfo(),
      _loadSyncStats(),
    ]);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadConnectionStatus() async {
    try {
      final status = await _dittoService.checkConnectionStatus();
      if (mounted) {
        setState(() => _connectionStatus = status);
      }
    } catch (e) {
      _addToLog('❌ خطأ في جلب حالة الاتصال: $e');
    }
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final info = await _dittoService.getDeviceInfo();
      if (mounted) {
        setState(() => _deviceInfo = info);
      }
    } catch (e) {
      _addToLog('❌ خطأ في جلب معلومات الجهاز: $e');
    }
  }

  Future<void> _loadSyncStats() async {
    try {
      final stats = await _syncService.getSyncStats();
      if (mounted) {
        setState(() => _syncStats = stats);
      }
    } catch (e) {
      _addToLog('❌ خطأ في جلب إحصائيات المزامنة: $e');
    }
  }

  void _addToLog(String message) {
    final timestamp = DateTime.now();
    final logEntry = '[${timestamp.hour}:${timestamp.minute}:${timestamp.second}] $message';
    
    setState(() {
      _syncLog.insert(0, logEntry);
      if (_syncLog.length > 50) {
        _syncLog.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'حالة Ditto Cloud Sync',
      actions: [
        IconButton(
          onPressed: _isLoading ? null : _loadAllData,
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
        ),
      ],
      body: _isLoading && _connectionStatus == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // حالة الاتصال الرئيسية
                  _buildConnectionStatusCard(),
                  const SizedBox(height: 16),
                  
                  // إحصائيات البيانات
                  _buildDataStatsCard(),
                  const SizedBox(height: 16),
                  
                  // معلومات الجهاز
                  _buildDeviceInfoCard(),
                  const SizedBox(height: 16),
                  
                  // أدوات التحكم
                  _buildControlPanel(),
                  const SizedBox(height: 16),
                  
                  // سجل المزامنة
                  _buildSyncLogCard(),
                ],
              ),
            ),
    );
  }

  /// بطاقة حالة الاتصال
  Widget _buildConnectionStatusCard() {
    final isConnected = _connectionStatus?['isConnected'] as bool? ?? false;
    final peersCount = _connectionStatus?['peersCount'] as int? ?? 0;
    final syncEnabled = _connectionStatus?['syncEnabled'] as bool? ?? false;
    final error = _connectionStatus?['error'] as String?;

    return Card(
      elevation: 4,
      color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // أيقونة الحالة الرئيسية
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isConnected ? Colors.green.shade100 : Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isConnected ? Icons.cloud_done : Icons.cloud_off,
                size: 48,
                color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 16),
            
            // حالة الاتصال
            Text(
              isConnected ? 'متصل بـ Ditto Cloud' : 'غير متصل',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isConnected ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
            const SizedBox(height: 8),
            
            Text(
              isConnected 
                  ? 'المزامنة عبر الإنترنت نشطة' 
                  : 'لا يوجد اتصال بالإنترنت',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // مؤشرات الحالة
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatusIndicator(
                  'الأجهزة المتصلة',
                  peersCount.toString(),
                  Icons.devices,
                  peersCount > 0 ? Colors.blue : Colors.grey,
                ),
                _buildStatusIndicator(
                  'حالة المزامنة',
                  syncEnabled ? 'مفعلة' : 'معطلة',
                  syncEnabled ? Icons.sync : Icons.sync_disabled,
                  syncEnabled ? Colors.green : Colors.orange,
                ),
                _buildStatusIndicator(
                  'الوضع',
                  'Cloud Only',
                  Icons.cloud,
                  Colors.purple,
                ),
              ],
            ),
            
            if (error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
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
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// بطاقة إحصائيات البيانات
  Widget _buildDataStatsCard() {
    final roomsCount = _syncStats?['rooms_in_ditto'] ?? 0;
    final bookingsCount = _syncStats?['bookings_in_ditto'] ?? 0;
    final isSyncing = _syncStats?['is_syncing'] as bool? ?? false;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'إحصائيات البيانات في Ditto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // المجموعات
            _buildDataRow('الغرف', roomsCount, Icons.hotel, Colors.blue),
            const Divider(height: 24),
            _buildDataRow('الحجوزات', bookingsCount, Icons.calendar_today, Colors.green),
            const Divider(height: 24),
            _buildDataRow('الموظفين', 0, Icons.people, Colors.purple),
            const Divider(height: 24),
            _buildDataRow('المدفوعات', 0, Icons.payments, Colors.orange),
            
            const SizedBox(height: 16),
            
            // حالة المزامنة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSyncing ? Colors.blue.shade50 : Colors.grey.shade50,
                border: Border.all(
                  color: isSyncing ? Colors.blue.shade200 : Colors.grey.shade200,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (isSyncing)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                      ),
                    )
                  else
                    Icon(Icons.check_circle, color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    isSyncing ? 'جاري المزامنة...' : 'المزامنة متوقفة',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSyncing ? Colors.blue.shade700 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, int count, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// بطاقة معلومات الجهاز
  Widget _buildDeviceInfoCard() {
    final deviceId = _deviceInfo?['deviceId']?.toString() ?? 'غير محدد';
    final appId = _deviceInfo?['appId']?.toString() ?? 'غير محدد';
    final mode = _deviceInfo?['mode']?.toString() ?? 'غير محدد';

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_android, color: Colors.teal.shade700, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'معلومات الجهاز والاتصال',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildInfoRow('معرف الجهاز', deviceId, Icons.fingerprint),
            const SizedBox(height: 12),
            _buildInfoRow('App ID', appId, Icons.apps),
            const SizedBox(height: 12),
            _buildInfoRow('وضع التشغيل', mode, Icons.settings),
            const SizedBox(height: 12),
            _buildInfoRow('وسيلة المزامنة', 'الإنترنت فقط (Cloud)', Icons.cloud),
            
            const SizedBox(height: 16),
            
            // معلومات Cloud Webhook
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                border: Border.all(color: Colors.purple.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.webhook, color: Colors.purple.shade700, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Cloud Webhook:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'i83inp.cloud.dittolive.app',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.purple.shade900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// لوحة التحكم
  Widget _buildControlPanel() {
    final isConnected = _connectionStatus?['isConnected'] as bool? ?? false;
    final syncEnabled = _connectionStatus?['syncEnabled'] as bool? ?? false;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.control_camera, color: Colors.orange.shade700, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'لوحة التحكم',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // أزرار التحكم
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected ? null : _initializeDitto,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('تهيئة Ditto'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !isConnected || syncEnabled ? null : _startSync,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('بدء المزامنة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !syncEnabled ? null : _stopSync,
                    icon: const Icon(Icons.stop),
                    label: const Text('إيقاف المزامنة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !isConnected ? null : _fullSync,
                    icon: const Icon(Icons.sync),
                    label: const Text('مزامنة كاملة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      disabledBackgroundColor: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // معلومات إضافية
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المزامنة عبر الإنترنت فقط - توفير الطاقة والبطارية',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة سجل المزامنة
  Widget _buildSyncLogCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.indigo.shade700, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'سجل المزامنة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_syncLog.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _syncLog.clear()),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('مسح السجل', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (_syncLog.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(Icons.history_toggle_off, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'لا توجد أحداث بعد',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _syncLog.length,
                  itemBuilder: (context, index) {
                    final log = _syncLog[index];
                    final isError = log.contains('❌');
                    final isSuccess = log.contains('✅');
                    final isWarning = log.contains('⚠️');
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isError
                              ? Colors.red.shade700
                              : isSuccess
                                  ? Colors.green.shade700
                                  : isWarning
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade800,
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

  // ========================================
  // دوال التحكم
  // ========================================

  Future<void> _initializeDitto() async {
    _addToLog('🔄 جاري تهيئة Ditto...');
    setState(() => _isLoading = true);

    try {
      final initialized = await _dittoService.initialize();
      
      if (initialized) {
        _addToLog('✅ تم تهيئة Ditto بنجاح');
        await _loadAllData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم تهيئة Ditto بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _addToLog('❌ فشل في تهيئة Ditto');
        throw Exception('فشل في التهيئة');
      }
    } catch (e) {
      _addToLog('❌ خطأ: $e');
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
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startSync() async {
    _addToLog('🔄 جاري بدء المزامنة...');
    setState(() => _isLoading = true);

    try {
      final started = await _dittoService.startSync();
      
      if (started) {
        _addToLog('✅ تم بدء المزامنة بنجاح');
        await _loadConnectionStatus();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم بدء المزامنة عبر الإنترنت'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _addToLog('❌ فشل في بدء المزامنة');
        throw Exception('فشل في البدء');
      }
    } catch (e) {
      _addToLog('❌ خطأ: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _stopSync() async {
    _addToLog('🔄 جاري إيقاف المزامنة...');
    setState(() => _isLoading = true);

    try {
      await _dittoService.stopSync();
      _addToLog('✅ تم إيقاف المزامنة');
      await _loadConnectionStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم إيقاف المزامنة'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      _addToLog('❌ خطأ: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fullSync() async {
    _addToLog('🔄 جاري تنفيذ مزامنة كاملة...');
    setState(() => _isLoading = true);

    try {
      // تهيئة خدمة المزامنة الثنائية
      final database = ref.read(databaseProvider);
      await _syncService.initialize(database);
      
      // تنفيذ المزامنة الكاملة
      final synced = await _syncService.fullSync();
      
      if (synced) {
        _addToLog('✅ اكتملت المزامنة الكاملة بنجاح');
        await _loadSyncStats();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تمت المزامنة الكاملة - تم رفع وتنزيل جميع البيانات'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        _addToLog('❌ فشل في المزامنة الكاملة');
        throw Exception('فشل في المزامنة');
      }
    } catch (e) {
      _addToLog('❌ خطأ في المزامنة الكاملة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
