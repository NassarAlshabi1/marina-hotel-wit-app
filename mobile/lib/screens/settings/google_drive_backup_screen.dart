import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/app_scaffold.dart';
import '../../providers/backup_provider.dart';
import '../../services/google_drive_backup_service.dart';
import '../../utils/theme.dart';

class GoogleDriveBackupScreen extends ConsumerStatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  ConsumerState<GoogleDriveBackupScreen> createState() => _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState extends ConsumerState<GoogleDriveBackupScreen> {
  final _firestore = FirebaseFirestore.instance;
  String? _deviceId;
  
  @override
  void initState() {
    super.initState();
    _loadDeviceId();
    // تحديث حجم قاعدة البيانات عند دخول الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupStatusProvider.notifier).updateDatabaseSize();
    });
  }
  
  Future<void> _loadDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceId = prefs.getString('smart_sync_device_id');
    });
  }

  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);

    return AppScaffold(
      title: 'النسخ الاحتياطي - Google Drive',
      actions: [
        if (backupState.isSignedIn)
          IconButton(
            onPressed: () => ref.read(backupStatusProvider.notifier).refreshBackupsList(),
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث قائمة النسخ',
          ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // رسائل الحالة والأخطاء
            if (backupState.message != null) ...[
              _buildStatusMessage(backupState),
              const SizedBox(height: 16),
            ],

            Expanded(
              child: ListView(
                children: [
                  // قسم حالة Google Drive
                  _buildConnectionStatusCard(backupState),
                  const SizedBox(height: 16),

                  if (backupState.isSignedIn) ...[
                    // قسم معلومات النظام
                    _buildSystemInfoCard(backupState),
                    const SizedBox(height: 16),

                    // قسم النسخ الاحتياطي اليدوي
                    _buildManualBackupCard(backupState),
                    const SizedBox(height: 16),

                    // قسم استعادة النسخ
                    _buildRestoreCard(backupState),
                    const SizedBox(height: 16),

                    // قسم النسخ التلقائي
                    _buildAutoBackupCard(backupState),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage(BackupState state) {
    Color color;
    IconData icon;

    switch (state.status) {
      case BackupStatus.success:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case BackupStatus.error:
        color = Colors.red;
        icon = Icons.error;
        break;
      default:
        color = Colors.blue;
        icon = Icons.info;
    }

    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.message!,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
            if (state.status != BackupStatus.error)
              IconButton(
                onPressed: () => ref.read(backupStatusProvider.notifier).clearMessage(),
                icon: Icon(Icons.close, color: color, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(BackupState state) {
    // استخدام device_id بدلاً من Firebase Auth UID
    final deviceId = _deviceId;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // استخدام StreamBuilder لقراءة حالة الاتصال من Firestore
                if (deviceId != null)
                  StreamBuilder<DocumentSnapshot>(
                    stream: _firestore.collection('devices').doc(deviceId).snapshots(),
                    builder: (context, snapshot) {
                      bool isDriveConnected = state.isSignedIn;
                      if (snapshot.hasData && snapshot.data != null) {
                        final data = snapshot.data!.data() as Map<String, dynamic>?;
                        if (data != null && data.containsKey('is_drive_connected')) {
                          isDriveConnected = data['is_drive_connected'] == true;
                        }
                      }
                      
                      return Icon(
                        Icons.cloud,
                        color: isDriveConnected ? Colors.green : Colors.grey,
                        size: 24,
                      );
                    },
                  )
                else
                  Icon(
                    Icons.cloud,
                    color: state.isSignedIn ? Colors.green : Colors.grey,
                    size: 24,
                  ),
                const SizedBox(width: 12),
                Text(
                  'Google Drive',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // استخدام StreamBuilder للتحكم في عرض المحتوى بناءً على حالة الاتصال من Firestore
            if (deviceId != null)
              StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('devices').doc(deviceId).snapshots(),
                builder: (context, snapshot) {
                  bool isDriveConnected = state.isSignedIn;
                  if (snapshot.hasData && snapshot.data != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null && data.containsKey('is_drive_connected')) {
                      isDriveConnected = data['is_drive_connected'] == true;
                    }
                  }
                  
                  if (isDriveConnected) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'متصل: ${state.signedInAccount?.email ?? 'غير معروف'}',
                                style: const TextStyle(color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).signOut(),
                            icon: const Icon(Icons.logout),
                            label: const Text('قطع الاتصال'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ فشل في تسجيل الدخول أو لم يتم تحديد ملف النسخ الاحتياطي عن بُعد. يُرجى محاولة تسجيل الدخول مرة أخرى.',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).signInToDrive(),
                            icon: state.status == BackupStatus.signIn 
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.login),
                            label: Text(state.status == BackupStatus.signIn ? 'جاري تسجيل الدخول...' : 'تسجيل الدخول'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                },
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.isSignedIn) ...[
                    Row(
                      children: [
                        const Icon(Icons.account_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'متصل: ${state.signedInAccount?.email ?? 'غير معروف'}',
                            style: const TextStyle(color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).signOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text('قطع الاتصال'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'غير متصل - يجب تسجيل الدخول أولاً للوصول إلى ميزات النسخ الاحتياطي',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).signInToDrive(),
                        icon: state.status == BackupStatus.signIn 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(state.status == BackupStatus.signIn ? 'جاري تسجيل الدخول...' : 'تسجيل الدخول'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemInfoCard(BackupState state) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    final sizeInMB = state.databaseSizeBytes != null 
        ? (state.databaseSizeBytes! / (1024 * 1024)).toStringAsFixed(2)
        : '---';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                Text(
                  'معلومات النظام',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            _buildInfoRow('حجم البيانات', '$sizeInMB ميجابايت', Icons.storage),
            const SizedBox(height: 8),
            _buildInfoRow(
              'آخر نسخة احتياطية',
              state.lastBackupTime != null 
                  ? dateFormatter.format(state.lastBackupTime!)
                  : 'لا توجد نسخ سابقة',
              Icons.history,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              'النسخ المتاحة',
              '${state.availableBackups.length} نسخة',
              Icons.backup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildManualBackupCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.backup, color: Colors.green, size: 24),
                const SizedBox(width: 12),
                Text(
                  'إنشاء نسخة احتياطية',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            const Text(
              'إنشاء نسخة احتياطية فورية من جميع بيانات التطبيق ورفعها إلى Google Drive',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'التنسيق الحالي: ${state.autoSettings.backupFormat == BackupFormat.sqlite ? 'SQLite' : 'JSON'}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            if (state.status == BackupStatus.uploading && state.progress != null) ...[
              LinearProgressIndicator(
                value: state.progress,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 8),
              Text(
                '${(state.progress! * 100).round()}% - ${state.message ?? "جاري الرفع..."}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).createBackup(),
                icon: state.status == BackupStatus.uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(state.status == BackupStatus.uploading ? 'جاري الرفع...' : 'إنشاء نسخة احتياطية الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.restore, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Text(
                  'استعادة النسخ الاحتياطية',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (state.status == BackupStatus.downloading || state.status == BackupStatus.restoring) ...[
              LinearProgressIndicator(
                value: state.progress,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
              const SizedBox(height: 8),
              Text(
                state.progress != null 
                    ? '${(state.progress! * 100).round()}% - ${state.message ?? "جاري الاستعادة..."}'
                    : state.message ?? "جاري الاستعادة...",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
            ],

            if (state.availableBackups.isEmpty) ...[
              const Text(
                'لا توجد نسخ احتياطية متاحة',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              const Text(
                'اختر نسخة احتياطية للاستعادة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: state.availableBackups.length,
                  itemBuilder: (context, index) {
                    final backup = state.availableBackups[index];
                    return _buildBackupItem(backup, state.isWorking);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBackupItem(DriveBackupFile backup, bool isWorking) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    final sizeInMB = backup.size != null 
        ? (backup.size! / (1024 * 1024)).toStringAsFixed(2)
        : '---';
    final recordsCount = backup.metadata?.totalRecords ?? int.tryParse(backup.appProperties?['records_count'] ?? '') ?? 0;
    final recordsLabel = recordsCount > 0 ? recordsCount.toString() : '---';
    final formatLabel = backup.format == BackupFormat.sqlite ? 'SQLite' : 'JSON';

    return ListTile(
      leading: const Icon(Icons.backup, color: Colors.blue),
      title: Text(
        dateFormatter.format(backup.createdTime),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        'حجم: $sizeInMB ميجابايت\nالسجلات: $recordsLabel\nالتنسيق: $formatLabel',
      ),
      trailing: IconButton(
        onPressed: isWorking ? null : () => _showRestoreConfirmation(backup),
        icon: const Icon(Icons.restore, color: Colors.orange),
        tooltip: 'استعادة',
      ),
      dense: true,
    );
  }

  void _showRestoreConfirmation(DriveBackupFile backup) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    final recordsCount = backup.metadata?.totalRecords ?? int.tryParse(backup.appProperties?['records_count'] ?? '') ?? 0;
    final recordsLabel = recordsCount > 0 ? recordsCount.toString() : 'غير معروف';
    final formatLabel = backup.format == BackupFormat.sqlite ? 'SQLite' : 'JSON';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ سيتم استبدال جميع البيانات الحالية بالنسخة المختارة:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            const SizedBox(height: 12),
            Text('التاريخ: ${dateFormatter.format(backup.createdTime)}'),
            Text('السجلات: $recordsLabel'),
            Text('التنسيق: ${formatLabel}'),
            const SizedBox(height: 12),
            const Text(
              'هل أنت متأكد من المتابعة؟',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(backupStatusProvider.notifier).restoreFromBackup(backup.fileId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('استعادة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoBackupCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.purple, size: 24),
                const SizedBox(width: 12),
                Text(
                  'النسخ التلقائي',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              title: const Text('تفعيل النسخ التلقائي'),
              subtitle: const Text('إنشاء نسخ احتياطية تلقائية حسب الجدولة المحددة'),
              value: state.autoSettings.isEnabled,
              onChanged: (value) => _updateAutoBackupEnabled(value),
            ),

            if (state.autoSettings.isEnabled) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('التكرار'),
                subtitle: Text(_getFrequencyDisplayName(state.autoSettings.frequency)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showFrequencySelection(state.autoSettings),
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('الوقت'),
                subtitle: Text(state.autoSettings.time),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showTimeSelection(state.autoSettings),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getFrequencyDisplayName(String frequency) {
    switch (frequency) {
      case 'daily': return 'يومياً';
      case 'weekly': return 'أسبوعياً';
      case 'monthly': return 'شهرياً';
      default: return frequency;
    }
  }

  void _updateAutoBackupEnabled(bool enabled) {
    final currentSettings = ref.read(backupStatusProvider).autoSettings;
    ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
      currentSettings.copyWith(isEnabled: enabled),
    );
  }

  void _showFrequencySelection(AutoBackupSettings currentSettings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحديد التكرار'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFrequencyOption('daily', 'يومياً', currentSettings),
            _buildFrequencyOption('weekly', 'أسبوعياً', currentSettings),
            _buildFrequencyOption('monthly', 'شهرياً', currentSettings),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyOption(String value, String label, AutoBackupSettings currentSettings) {
    return RadioListTile<String>(
      title: Text(label),
      value: value,
      groupValue: currentSettings.frequency,
      onChanged: (selectedValue) {
        if (selectedValue != null) {
          Navigator.of(context).pop();
          ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
            currentSettings.copyWith(frequency: selectedValue),
          );
        }
      },
    );
  }

  void _showTimeSelection(AutoBackupSettings currentSettings) {
    final timeParts = currentSettings.time.split(':');
    final currentTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: child!,
        );
      },
    ).then((selectedTime) {
      if (selectedTime != null) {
        final timeString = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
        ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
          currentSettings.copyWith(time: timeString),
        );
      }
    });
  }
}