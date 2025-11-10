import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ditto_cloud_sync_service.dart';

/// Widget لاختبار الاتصال مع Ditto Cloud
class DittoConnectionTestWidget extends ConsumerStatefulWidget {
  const DittoConnectionTestWidget({super.key});

  @override
  ConsumerState<DittoConnectionTestWidget> createState() => _DittoConnectionTestWidgetState();
}

class _DittoConnectionTestWidgetState extends ConsumerState<DittoConnectionTestWidget> {
  bool _isLoading = false;
  Map<String, dynamic>? _connectionStatus;

  @override
  void initState() {
    super.initState();
    // فحص الحالة عند تحميل Widget
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() => _isLoading = true);

    try {
      final dittoService = DittoCloudSyncService();
      final status = await dittoService.checkConnectionStatus();
      
      if (mounted) {
        setState(() {
          _connectionStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionStatus = {
            'isConnected': false,
            'peersCount': 0,
            'error': 'خطأ في الاتصال: $e',
          };
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_tethering,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'اختبار الاتصال مع Ditto Cloud',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _isLoading ? null : _checkConnection,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  tooltip: 'تحديث حالة الاتصال',
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_connectionStatus != null)
              _buildConnectionDetails(_connectionStatus!)
            else
              const Text(
                'لا توجد معلومات عن حالة الاتصال',
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionDetails(Map<String, dynamic> status) {
    final isConnected = status['isConnected'] as bool? ?? false;
    final peersCount = status['peersCount'] as int? ?? 0;
    final lastSyncTime = status['lastSyncTime'] as String?;
    final syncEnabled = status['syncEnabled'] as bool? ?? false;
    final error = status['error'] as String?;

    return Column(
      children: [
        // حالة الاتصال
        _buildStatusRow(
          'حالة الاتصال',
          isConnected ? 'متصل' : 'غير متصل',
          isConnected ? Colors.green : Colors.red,
          isConnected ? Icons.check_circle : Icons.error,
        ),
        const SizedBox(height: 8),
        
        // عدد الأجهزة المتصلة
        _buildStatusRow(
          'الأجهزة المتصلة',
          '$peersCount أجهزة',
          peersCount > 0 ? Colors.blue : Colors.grey,
          Icons.devices,
        ),
        const SizedBox(height: 8),
        
        // حالة المزامنة
        _buildStatusRow(
          'حالة المزامنة',
          syncEnabled ? 'مفعلة' : 'معطلة',
          syncEnabled ? Colors.green : Colors.orange,
          syncEnabled ? Icons.sync : Icons.sync_disabled,
        ),
        
        if (lastSyncTime != null) ...[
          const SizedBox(height: 8),
          _buildStatusRow(
            'آخر مزامنة',
            _formatDateTime(lastSyncTime),
            Colors.blue,
            Icons.access_time,
          ),
        ],
        
        if (error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.red.shade600, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 12),
        
        // أزرار التحكم
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _testConnection(),
                icon: const Icon(Icons.power_settings_new, size: 16),
                label: const Text('تهيئة Ditto', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _syncNow(),
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('مزامنة فورية', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inMinutes < 60) {
        return 'منذ ${difference.inMinutes} دقيقة';
      } else if (difference.inHours < 24) {
        return 'منذ ${difference.inHours} ساعة';
      } else {
        return 'منذ ${difference.inDays} يوم';
      }
    } catch (e) {
      return 'غير محدد';
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);

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
      }
      
      await _checkConnection(); // تحديث الحالة
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل في تهيئة Ditto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isLoading = true);

    try {
      final dittoService = DittoCloudSyncService();
      final synced = await dittoService.syncNow();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(synced ? '✅ تمت المزامنة بنجاح' : '❌ فشل في المزامنة'),
            backgroundColor: synced ? Colors.green : Colors.red,
          ),
        );
      }
      
      await _checkConnection(); // تحديث الحالة
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