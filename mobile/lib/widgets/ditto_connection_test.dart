import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ditto_cloud_sync_service.dart';
import '../utils/ditto_config.dart';

/// أداة اختبار اتصال Ditto Cloud
class DittoConnectionTestWidget extends ConsumerStatefulWidget {
  const DittoConnectionTestWidget({super.key});

  @override
  ConsumerState<DittoConnectionTestWidget> createState() => _DittoConnectionTestState();
}

class _DittoConnectionTestState extends ConsumerState<DittoConnectionTestWidget> {
  bool _isTesting = false;
  String _testResult = '';
  Color _resultColor = Colors.blue;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان
            Row(
              children: [
                const Icon(Icons.network_check, size: 28, color: Colors.blue),
                const SizedBox(width: 12),
                const Text(
                  'اختبار اتصال Ditto Cloud',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // معلومات الإعدادات
            _buildConfigInfo(),
            const SizedBox(height: 16),
            
            // زر الاختبار
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isTesting ? null : _runConnectionTest,
                icon: _isTesting 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
                label: Text(_isTesting ? 'جاري الاختبار...' : 'تشغيل اختبار الاتصال'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            
            // نتائج الاختبار
            if (_testResult.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _resultColor.withOpacity(0.1),
                  border: Border.all(color: _resultColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _testResult,
                  style: TextStyle(
                    color: _resultColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// معلومات الإعدادات
  Widget _buildConfigInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📋 الإعدادات الحالية:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _configRow('App ID', DittoConfig.appId),
          _configRow('Playground Token', '${DittoConfig.playgroundToken.substring(0, 8)}***'),
          _configRow('API Token', '${DittoConfig.apiToken.substring(0, 8)}***'),
          _configRow('WebSocket URL', DittoConfig.webSocketUrl),
          _configRow('Cloud Webhook', DittoConfig.cloudWebhookUrl),
          _configRow('Cloud Sync', DittoConfig.enableCloudSync ? '✅ مُفعّل' : '❌ معطل'),
          _configRow('P2P Sync', DittoConfig.enableP2PSync ? '❌ مُفعّل' : '✅ معطل'),
        ],
      ),
    );
  }

  /// صف إعداد واحد
  Widget _configRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// تشغيل اختبار الاتصال
  Future<void> _runConnectionTest() async {
    if (_isTesting) return;
    
    setState(() {
      _isTesting = true;
      _testResult = '';
    });

    try {
      // الخطوة 1: التحقق من الإعدادات
      _updateTestResult('🔧 فحص الإعدادات...', Colors.blue);
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!DittoConfig.isConfigured) {
        _updateTestResult(
          '❌ الإعدادات غير مكتملة!\n${DittoConfig.configErrorMessage}', 
          Colors.red
        );
        return;
      }
      
      _updateTestResult('✅ الإعدادات صحيحة', Colors.green);
      await Future.delayed(const Duration(milliseconds: 500));

      // الخطوة 2: محاولة تهيئة Ditto
      _updateTestResult('🚀 بدء تهيئة Ditto...', Colors.blue);
      await Future.delayed(const Duration(milliseconds: 500));
      
      final dittoService = DittoCloudSyncService.instance;
      await dittoService.initialize();
      
      _updateTestResult('✅ تم تهيئة Ditto بنجاح', Colors.green);
      await Future.delayed(const Duration(milliseconds: 500));

      // الخطوة 3: اختبار حالة المزامنة
      _updateTestResult('📊 فحص حالة المزامنة...', Colors.blue);
      await Future.delayed(const Duration(milliseconds: 500));
      
      final status = await dittoService.getSyncStatus();
      
      if (status['initialized'] == true) {
        _updateTestResult('✅ Ditto مُهيّأ ومتصل بالسحابة!', Colors.green);
      } else {
        _updateTestResult('⚠️ Ditto مُهيّأ لكن غير متصل', Colors.orange);
      }
      
      await Future.delayed(const Duration(milliseconds: 500));

      // الخطوة 4: اختبار العمليات
      _updateTestResult('🧪 اختبار إنشاء وثيقة تجريبية...', Colors.blue);
      await Future.delayed(const Duration(milliseconds: 500));
      
      final testBookingId = await dittoService.createBooking(
        guestName: 'اختبار الاتصال',
        roomNumber: 'TEST',
        checkinDate: DateTime.now().toIso8601String(),
        totalAmount: 1.0,
        notes: 'اختبار اتصال Ditto Cloud',
      );
      
      _updateTestResult('✅ نجح اختبار الاتصال!\n🎯 معرف الحجز: $testBookingId', Colors.green);

    } catch (e) {
      _updateTestResult('❌ فشل في الاختبار:\n$e', Colors.red);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  /// تحديث نتيجة الاختبار
  void _updateTestResult(String result, Color color) {
    setState(() {
      _testResult = result;
      _resultColor = color;
    });
  }
}