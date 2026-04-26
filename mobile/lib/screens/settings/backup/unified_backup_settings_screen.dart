import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/core.dart';
import '../../../components/app_scaffold.dart';
import '../../../providers/backup_provider.dart';

/// Unified Backup Settings Screen
///
/// شاشة موحدة لجميع إعدادات النسخ الاحتياطي
/// مربطة بالكامل مع BackupStatusNotifier والخدمات الحقيقية
class UnifiedBackupSettingsScreen extends ConsumerStatefulWidget {
  const UnifiedBackupSettingsScreen({super.key});

  @override
  ConsumerState<UnifiedBackupSettingsScreen> createState() =>
      _UnifiedBackupSettingsScreenState();
}

class _UnifiedBackupSettingsScreenState
    extends ConsumerState<UnifiedBackupSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);

    return AppScaffold(
      title: 'إعدادات النسخ الاحتياطي',
      body: ListView(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        children: [
          // نظرة عامة
          _buildOverviewSection(backupState),

          const SizedBox(height: UIConstants.spacingLG),

          // النسخ الاحتياطي التلقائي
          _buildAutoBackupSection(backupState),

          const SizedBox(height: UIConstants.spacingLG),

          // Google Drive
          _buildGoogleDriveSection(backupState),

          const SizedBox(height: UIConstants.spacingLG),

          // النسخ الاحتياطي المحلي
          _buildLocalBackupSection(backupState),

          const SizedBox(height: UIConstants.spacingLG),

          // إعدادات متقدمة
          _buildAdvancedSection(backupState),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(BackupState state) {
    final lastBackup = state.lastBackupTime ?? state.lastLocalBackupTime;
    final dbSize = state.databaseSizeBytes;
    final totalBackups =
        state.availableBackups.length + state.localBackups.length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.backup,
                  color: UIConstants.backupColor,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'حالة النسخ الاحتياطي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'آخر نسخة (Drive)',
              value: state.lastBackupTime != null
                  ? DateTimeFormatter.getRelativeTime(
                      state.lastBackupTime!.toIso8601String())
                  : 'لم يتم بعد',
              icon: Icons.cloud,
            ),
            InfoRow(
              label: 'آخر نسخة (محلي)',
              value: state.lastLocalBackupTime != null
                  ? DateTimeFormatter.getRelativeTime(
                      state.lastLocalBackupTime!.toIso8601String())
                  : 'لم يتم بعد',
              icon: Icons.phone_android,
            ),
            InfoRow(
              label: 'حجم قاعدة البيانات',
              value: dbSize != null
                  ? FileSizeFormatter.formatBytes(dbSize)
                  : 'جاري التحميل...',
              icon: Icons.storage,
            ),
            InfoRow(
              label: 'إجمالي النسخ',
              value: '$totalBackups نسخة (Drive: ${state.availableBackups.length}, محلي: ${state.localBackups.length})',
              icon: Icons.layers,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoBackupSection(BackupState state) {
    final autoSettings = state.autoSettings;

    String frequencyLabel;
    switch (autoSettings.frequency) {
      case 'weekly':
        frequencyLabel = 'أسبوعياً';
        break;
      case 'monthly':
        frequencyLabel = 'شهرياً';
        break;
      default:
        frequencyLabel = 'يومياً';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: UIConstants.backupColor,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'النسخ الاحتياطي التلقائي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل النسخ التلقائي'),
            subtitle: Text(
              autoSettings.isEnabled
                  ? 'مفعّل - $frequencyLabel في ${autoSettings.time}'
                  : 'معطّل',
            ),
            value: autoSettings.isEnabled,
            onChanged: state.isWorking
                ? null
                : (value) => _updateAutoSettings(
                      autoSettings.copyWith(isEnabled: value),
                    ),
            secondary: const Icon(Icons.auto_awesome),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('تكرار النسخ'),
            subtitle: Text(frequencyLabel),
            leading: const Icon(Icons.repeat),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: state.isWorking
                ? null
                : () => _showBackupFrequencyDialog(autoSettings),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('نسخ محلي تلقائي'),
            subtitle: const Text('حفظ نسخة على الجهاز تلقائياً'),
            value: autoSettings.enableLocalBackup,
            onChanged: state.isWorking
                ? null
                : (value) => _updateAutoSettings(
                      autoSettings.copyWith(enableLocalBackup: value),
                    ),
            secondary: const Icon(Icons.phone_android),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('نسخ إلى Google Drive تلقائي'),
            subtitle: const Text('رفع نسخة إلى السحابة تلقائياً'),
            value: autoSettings.enableGoogleDriveBackup,
            onChanged: state.isWorking || !state.isSignedIn
                ? null
                : (value) => _updateAutoSettings(
                      autoSettings.copyWith(
                          enableGoogleDriveBackup: value),
                    ),
            secondary: const Icon(Icons.cloud_upload),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleDriveSection(BackupState state) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.cloud,
                  color:
                      state.isSignedIn ? Colors.blue : Colors.grey.shade500,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'Google Drive',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: state.isSignedIn
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.isSignedIn ? 'متصل' : 'غير متصل',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          state.isSignedIn ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (state.isSignedIn) ...[
            ListTile(
              title: const Text('الحساب المتصل'),
              subtitle: Text(state.signedInAccount?.email ?? ''),
              leading: const Icon(Icons.account_circle),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('النسخ المتاحة على Drive'),
              subtitle: Text('${state.availableBackups.length} نسخة'),
              leading: const Icon(Icons.cloud_done),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.pushNamed(
                context,
                '/settings/google-drive-backup',
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('مزامنة Google Drive'),
              subtitle: const Text('مزامنة تلقائية مع السحابة'),
              value: state.googleDriveSyncEnabled,
              onChanged: state.isWorking
                  ? null
                  : (value) => ref
                      .read(backupStatusProvider.notifier)
                      .setGoogleDriveSyncEnabled(value),
              secondary: const Icon(Icons.sync),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('تسجيل الخروج'),
              leading: const Icon(Icons.logout, color: Colors.red),
              onTap: state.isWorking
                  ? null
                  : () => _confirmSignOut(),
            ),
          ] else
            ListTile(
              title: const Text('تسجيل الدخول'),
              subtitle: const Text('ربط حساب Google Drive للنسخ السحابي'),
              leading: const Icon(Icons.login, color: Colors.blue),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: state.isWorking
                  ? null
                  : () => ref
                      .read(backupStatusProvider.notifier)
                      .signInToDrive(),
            ),
        ],
      ),
    );
  }

  Widget _buildLocalBackupSection(BackupState state) {
    final folderInfo = state.backupFolderInfo;
    final localCount = state.localBackups.length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.phone_android,
                  color: state.hasStoragePermission
                      ? Colors.green
                      : Colors.orange,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'النسخ المحلي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (!state.hasStoragePermission)
                  TextButton(
                    onPressed: () => ref
                        .read(backupStatusProvider.notifier)
                        .checkStoragePermissions(),
                    child: const Text('منح الأذونات'),
                  )
                else
                  TextButton(
                    onPressed: state.isWorking
                        ? null
                        : () => ref
                            .read(backupStatusProvider.notifier)
                            .checkStoragePermissions(),
                    child: const Text('تحديث'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('موقع التخزين'),
            subtitle: Text(
              folderInfo?['path'] as String? ?? 'غير متاح',
            ),
            leading: const Icon(Icons.folder),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('عدد النسخ المحلية'),
            subtitle: Text('$localCount نسخة'),
            leading: const Icon(Icons.inventory_2),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('المساحة المستخدمة'),
            subtitle: Text(
              '${folderInfo?['total_size_mb'] ?? 0} ميجابايت',
            ),
            leading: const Icon(Icons.sd_storage),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('عرض النسخ المحلية'),
            subtitle: const Text('استعراض وإدارة النسخ'),
            leading: const Icon(Icons.list),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // التنقل إلى التبويب المحلي
              Navigator.pushNamed(context, '/settings/backup');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSection(BackupState state) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.settings_suggest,
                  color: Colors.grey.shade700,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'إعدادات متقدمة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('نسخ احتياطي الآن (محلي)'),
            subtitle: const Text('إنشاء نسخة محلية فورية'),
            leading: Icon(Icons.backup, color: UIConstants.backupColor),
            trailing: state.isWorking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: state.isWorking
                ? null
                : () => _createBackupNow(),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('استيراد نسخة من ملف'),
            subtitle: const Text('اختيار ملف نسخة احتياطية من الجهاز'),
            leading: const Icon(Icons.file_download, color: Colors.orange),
            trailing: state.isWorking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: state.isWorking
                ? null
                : () => _importBackup(),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('تنظيف النسخ القديمة'),
            subtitle: const Text('الاحتفاظ بآخر 10 نسخ فقط'),
            leading:
                const Icon(Icons.cleaning_services, color: Colors.teal),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: state.isWorking
                ? null
                : () => _cleanOldBackups(),
          ),
        ],
      ),
    );
  }

  // ─── الأفعال ───

  void _updateAutoSettings(AutoBackupSettings settings) {
    ref
        .read(backupStatusProvider.notifier)
        .updateAutoBackupSettings(settings);
  }

  void _showBackupFrequencyDialog(AutoBackupSettings current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تكرار النسخ الاحتياطي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _frequencyOption('يومياً', 'daily', current.frequency, context),
            _frequencyOption('أسبوعياً', 'weekly', current.frequency, context),
            _frequencyOption('شهرياً', 'monthly', current.frequency, context),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Widget _frequencyOption(
    String label,
    String value,
    String current,
    BuildContext context,
  ) {
    return ListTile(
      title: Text(label),
      leading: Radio(
        value: value,
        groupValue: current,
        onChanged: (v) {
          Navigator.pop(context);
          final settings = ref.read(backupStatusProvider).autoSettings;
          _updateAutoSettings(settings.copyWith(frequency: value));
        },
      ),
      onTap: () {
        Navigator.pop(context);
        final settings = ref.read(backupStatusProvider).autoSettings;
        _updateAutoSettings(settings.copyWith(frequency: value));
      },
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج من Google Drive'),
        content: const Text(
          'سيتم إيقاف جميع المزامنات مع Google Drive.\nالنسخ المحلية لن تتأثر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(backupStatusProvider.notifier).signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تسجيل الخروج',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _createBackupNow() async {
    await ref.read(backupStatusProvider.notifier).createLocalBackup();
    if (mounted) {
      final state = ref.read(backupStatusProvider);
      final color = state.status == BackupStatus.success
          ? Colors.green
          : state.status == BackupStatus.error
              ? Colors.red
              : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.message ?? 'تم'),
          backgroundColor: color,
        ),
      );
    }
  }

  void _importBackup() async {
    await ref.read(backupStatusProvider.notifier).importBackupFromFile();
    if (mounted) {
      final state = ref.read(backupStatusProvider);
      final color = state.status == BackupStatus.success
          ? Colors.green
          : state.status == BackupStatus.error
              ? Colors.red
              : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.message ?? 'تم'),
          backgroundColor: color,
        ),
      );
    }
  }

  void _cleanOldBackups() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تنظيف النسخ القديمة'),
        content: const Text(
          'سيتم حذف النسخ القديمة مع الاحتفاظ بآخر 10 نسخ فقط.\nهل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تنظيف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(backupStatusProvider.notifier).cleanOldLocalBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تنظيف النسخ القديمة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}
