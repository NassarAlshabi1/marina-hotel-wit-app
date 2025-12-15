import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/app_scaffold.dart';
import '../../services/smart_sync_manager.dart';
import '../../services/sync_guardian.dart';
import '../../services/appwrite_sync_manager.dart';
import '../../services/google_drive_backup_service.dart';
import '../../providers/smart_sync_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/backup_provider.dart';

class AutoSyncDiagnosticScreen extends ConsumerStatefulWidget {
  const AutoSyncDiagnosticScreen({super.key});

  @override
  ConsumerState<AutoSyncDiagnosticScreen> createState() => _AutoSyncDiagnosticScreenState();
}

class _AutoSyncDiagnosticScreenState extends ConsumerState<AutoSyncDiagnosticScreen> {
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final smartSyncStatus = ref.watch(smartSyncStatusProvider);
    final syncHealth = ref.watch(syncHealthProvider);
    final backupState = ref.watch(backupStatusProvider);

    return AppScaffold(
      title: 'تشخيص المزامنة التلقائية',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refreshAll,
        ),
      ],
      body: _isRefreshing
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildOverallStatus(smartSyncStatus, syncHealth, backupState),
                  const SizedBox(height: 16),
                  _buildSmartSyncCard(smartSyncStatus),
                  const SizedBox(height: 16),
                  _buildSyncGuardianCard(syncHealth),
                  const SizedBox(height: 16),
                  _buildGoogleDriveCard(backupState),
                  const SizedBox(height: 16),
                  _buildAppwriteCard(),
                  const SizedBox(height: 16),
                  _buildQuickActionsCard(),
                  const SizedBox(height: 16),
                  _buildSystemInfoCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildOverallStatus(
    AsyncValue<Map<String, dynamic>> smartSyncStatus,
    AsyncValue<SyncHealthSnapshot> syncHealth,
    BackupState backupState,
  ) {
    bool allSystemsGo = false;
    String statusText = 'جاري التحميل...';
    Color statusColor = Colors.orange;
    IconData statusIcon = Icons.hourglass_empty;

    smartSyncStatus.when(
      data: (status) {
        final isEnabled = status['enabled'] as bool? ?? false;
        final isSignedIn = backupState.signedInAccount != null;
        
        syncHealth.when(
          data: (health) {
            allSystemsGo = isEnabled && isSignedIn && health.isInitialized;
            
            if (allSystemsGo) {
              statusText = 'المزامنة التلقائية تعمل بشكل طبيعي';
              statusColor = Colors.green;
              statusIcon = Icons.check_circle;
            } else if (!isSignedIn) {
              statusText = 'يجب تسجيل الدخول إلى Google Drive';
              statusColor = Colors.red;
              statusIcon = Icons.cloud_off;
            } else if (!isEnabled) {
              statusText = 'المزامنة التلقائية معطّلة';
              statusColor = Colors.orange;
              statusIcon = Icons.pause_circle;
            } else {
              statusText = 'المزامنة قيد التهيئة...';
              statusColor = Colors.blue;
              statusIcon = Icons.sync;
            }
          },
          loading: () {
            statusText = 'جاري فحص حالة الحارس...';
          },
          error: (err, _) {
            statusText = 'خطأ في فحص الحالة';
            statusColor = Colors.red;
            statusIcon = Icons.error;
          },
        );
      },
      loading: () {},
      error: (err, _) {
        statusText = 'خطأ في تحميل حالة المزامنة';
        statusColor = Colors.red;
        statusIcon = Icons.error;
      },
    );

    return Card(
      color: statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(statusIcon, size: 64, color: statusColor),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (allSystemsGo) ...[
              const SizedBox(height: 8),
              const Text(
                'جميع الأنظمة تعمل بشكل صحيح',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSmartSyncCard(AsyncValue<Map<String, dynamic>> smartSyncStatus) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_alt, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Smart Sync Manager',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            smartSyncStatus.when(
              data: (status) {
                final isEnabled = status['enabled'] as bool? ?? false;
                final interval = status['interval'] as int? ?? 2;
                final lastSync = status['last_sync'] as String? ?? 'لم يتم بعد';
                final deviceId = status['device_id'] as String? ?? 'غير معروف';

                return Column(
                  children: [
                    _buildStatusRow('الحالة', isEnabled ? 'مُفعّل ✅' : 'معطّل ⏸️',
                        isEnabled ? Colors.green : Colors.orange),
                    _buildStatusRow('الفترة الزمنية', '$interval دقائق', Colors.blue),
                    _buildStatusRow('آخر مزامنة', lastSync, Colors.grey),
                    _buildStatusRow('معرف الجهاز', deviceId.substring(0, 16) + '...', Colors.grey),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('خطأ: $err', style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncGuardianCard(AsyncValue<SyncHealthSnapshot> syncHealth) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.security, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'Sync Guardian',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            syncHealth.when(
              data: (health) {
                final lastSyncText = health.lastSyncAt != null
                    ? DateFormat('dd/MM/yyyy HH:mm').format(health.lastSyncAt!)
                    : 'لم يتم بعد';

                return Column(
                  children: [
                    _buildStatusRow(
                      'الحالة',
                      health.isInitialized ? 'مُهيَّأ ✅' : 'غير مُهيَّأ ⚠️',
                      health.isInitialized ? Colors.green : Colors.red,
                    ),
                    _buildStatusRow(
                      'المراقبة',
                      health.monitoringActive ? 'نشطة ✅' : 'معطّلة ⏸️',
                      health.monitoringActive ? Colors.green : Colors.orange,
                    ),
                    _buildStatusRow('آخر مزامنة', lastSyncText, Colors.grey),
                    _buildStatusRow('محاولات فاشلة', '${health.failedAttempts}',
                        health.failedAttempts > 0 ? Colors.red : Colors.green),
                    _buildStatusRow(
                      'أحداث معلقة',
                      health.pendingEvents ? 'نعم ⏳' : 'لا ✅',
                      health.pendingEvents ? Colors.orange : Colors.green,
                    ),
                    if (health.lastError != null)
                      _buildStatusRow('آخر خطأ', health.lastError!, Colors.red),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('خطأ: $err', style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleDriveCard(BackupState backupState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Google Drive',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildStatusRow(
              'تسجيل الدخول',
              backupState.signedInAccount != null ? 'مسجل ✅' : 'غير مسجل ❌',
              backupState.signedInAccount != null ? Colors.green : Colors.red,
            ),
            if (backupState.signedInAccount != null)
              _buildStatusRow('الحساب', backupState.signedInAccount!.email, Colors.blue),
            _buildStatusRow(
              'حالة الاتصال',
              backupState.isConnected ? 'متصل ✅' : 'غير متصل ⚠️',
              backupState.isConnected ? Colors.green : Colors.orange,
            ),
            if (backupState.lastBackupTime != null)
              _buildStatusRow(
                'آخر نسخة',
                DateFormat('dd/MM/yyyy HH:mm').format(backupState.lastBackupTime!),
                Colors.grey,
              ),
            if (backupState.lastError != null)
              _buildStatusRow('آخر خطأ', backupState.lastError!, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildAppwriteCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_queue, color: Colors.purple),
                const SizedBox(width: 8),
                const Text(
                  'Appwrite Sync',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            FutureBuilder<bool>(
              future: _checkAppwriteStatus(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final isEnabled = snapshot.data ?? false;
                return Column(
                  children: [
                    _buildStatusRow(
                      'الحالة',
                      isEnabled ? 'مُفعّل ✅' : 'معطّل ⏸️',
                      isEnabled ? Colors.green : Colors.orange,
                    ),
                    if (!isEnabled)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'ℹ️ المزامنة عبر Appwrite معطّلة افتراضياً. يمكن تفعيلها من شاشة إعدادات Appwrite.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'إجراءات سريعة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _forceSyncNow,
              icon: const Icon(Icons.sync),
              label: const Text('مزامنة فورية'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _forceGuardianSync,
              icon: const Icon(Icons.security),
              label: const Text('مزامنة حارس المزامنة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _testGoogleDriveConnection,
              icon: const Icon(Icons.cloud_done),
              label: const Text('اختبار اتصال Google Drive'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'معلومات النظام',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            _buildInfoRow('أنظمة المزامنة النشطة', '3'),
            _buildInfoRow('Smart Sync', 'Google Drive - كل دقيقتين'),
            _buildInfoRow('Sync Guardian', 'WorkManager - كل 15 دقيقة'),
            _buildInfoRow('Auto Backup', 'على التغييرات - Debounce 5 ثواني'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ℹ️ ملاحظة مهمة:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'التطبيق يستخدم main.dart الذي يُفعّل SmartSyncManager و SyncGuardian فقط.\n\n'
                    'AutoSyncEngine متوفر في main_with_auto_sync_engine.dart لكنه غير مُستخدم حالياً.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshAll() async {
    setState(() => _isRefreshing = true);
    
    ref.invalidate(smartSyncStatusProvider);
    ref.invalidate(syncHealthProvider);
    ref.invalidate(backupStatusProvider);
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() => _isRefreshing = false);
  }

  Future<void> _forceSyncNow() async {
    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.forceSyncNow();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تمت المزامنة الفورية بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
      
      await _refreshAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشلت المزامنة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _forceGuardianSync() async {
    try {
      final guardian = ref.read(syncGuardianProvider);
      await guardian.forceSync();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تمت مزامنة الحارس بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
      
      await _refreshAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشلت مزامنة الحارس: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _testGoogleDriveConnection() async {
    try {
      final backupService = ref.read(googleDriveBackupServiceProvider);
      
      if (!backupService.isSignedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ يجب تسجيل الدخول أولاً'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final files = await backupService.listBackupFiles();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ الاتصال ناجح! تم العثور على ${files.length} نسخة احتياطية'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل الاتصال: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _checkAppwriteStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('appwrite_sync_enabled') ?? false;
    } catch (e) {
      return false;
    }
  }
}
