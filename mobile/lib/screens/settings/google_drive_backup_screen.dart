import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/backup_provider.dart';
import '../../services/google_drive_backup_service.dart';
import '../../services/local_db.dart';
import '../../services/restore_fix_service.dart';
import '../../utils/debug_log.dart';
import '../../utils/theme.dart';
import 'google_drive_logs_screen.dart';

class GoogleDriveBackupScreen extends ConsumerWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupState = ref.watch(backupStatusProvider);

    return AppScaffold(
      title: 'النسخ الاحتياطي - Google Drive',
      actions: [
        IconButton(
          onPressed: () {
            unawaited(Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const GoogleDriveLogsScreen(),
              ),
            ));
          },
          icon: const Icon(Icons.article_outlined),
          tooltip: 'سجلات Google Drive',
        ),
        if (backupState.isSignedIn)
          IconButton(
            onPressed: () =>
                ref.read(backupStatusProvider.notifier).refreshBackupsList(),
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث قائمة النسخ',
          ),
      ],
      body: const GoogleDriveBackupContent(),
    );
  }
}

class GoogleDriveBackupContent extends ConsumerStatefulWidget {
  const GoogleDriveBackupContent({super.key});

  @override
  ConsumerState<GoogleDriveBackupContent> createState() =>
      _GoogleDriveBackupContentState();
}

class _GoogleDriveBackupContentState
    extends ConsumerState<GoogleDriveBackupContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(backupStatusProvider.notifier).updateDatabaseSize());
    });
  }

  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (backupState.message != null) ...[
            _buildStatusMessage(backupState),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: ListView(
              children: [
                _buildConnectionStatusCard(backupState),
                const SizedBox(height: 16),
                if (backupState.isSignedIn) ...[
                  _buildSyncControlCard(backupState),
                  const SizedBox(height: 16),
                  _buildSystemInfoCard(backupState),
                  const SizedBox(height: 16),
                  _buildManualBackupCard(backupState),
                  const SizedBox(height: 16),
                  _buildRestoreCard(backupState),
                  const SizedBox(height: 16),
                  _buildAutoBackupCard(backupState),
                ],
              ],
            ),
          ),
        ],
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
      case BackupStatus.error:
        color = Colors.red;
        icon = Icons.error;
      default:
        color = Colors.blue;
        icon = Icons.info;
    }

    return Card(
      color: color.withValues(alpha: 0.1),
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
                onPressed: () =>
                    ref.read(backupStatusProvider.notifier).clearMessage(),
                icon: Icon(Icons.close, color: color, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud,
                  color: state.isSignedIn ? Colors.green : Colors.grey,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Google Drive',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.isSignedIn) ...[
              Row(
                children: [
                  const Icon(
                    Icons.account_circle,
                    color: Colors.green,
                    size: 20,
                  ),
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
                  onPressed: state.isWorking
                      ? null
                      : () => ref.read(backupStatusProvider.notifier).signOut(),
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
                  onPressed: state.isWorking
                      ? null
                      : () => ref
                            .read(backupStatusProvider.notifier)
                            .signInToDrive(),
                  icon: state.status == BackupStatus.signIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(
                    state.status == BackupStatus.signIn
                        ? 'جاري تسجيل الدخول...'
                        : 'تسجيل الدخول',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(value, style: const TextStyle(color: Colors.grey)),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'إنشاء نسخة احتياطية فورية من جميع بيانات التطبيق ورفعها إلى Google Drive',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // اختيار نوع النسخة
            Row(
              children: [
                Expanded(
                  child: _buildBackupTypeButton(
                    context,
                    ref,
                    'JSON',
                    Icons.data_object,
                    Colors.blue,
                    () => _createJsonBackup(ref),
                    state,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildBackupTypeButton(
                    context,
                    ref,
                    '.db',
                    Icons.storage,
                    Colors.purple,
                    () => _createDbBackup(ref),
                    state,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupTypeButton(
    BuildContext context,
    WidgetRef ref,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
    BackupState state,
  ) {
    return OutlinedButton.icon(
      onPressed: state.isWorking ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text('نسخ $label'),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Future<void> _createJsonBackup(WidgetRef ref) async {
    await ref.read(backupStatusProvider.notifier).createBackup();
  }

  Future<void> _createDbBackup(WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage, color: Colors.purple),
            SizedBox(width: 8),
            Text('نسخة .db'),
          ],
        ),
        content: const Text(
          'سيتم إنشاء نسخة احتياطية بصيغة .db (ملف قاعدة البيانات الأصلي).\n\n'
          '✅ المميزات:\n'
          '• نسخة كاملة من قاعدة البيانات\n'
          '• استعادة سريعة جداً\n'
          '• جميع البيانات محفوظة\n\n'
          '⚠️ ملاحظة: حجم الملف قد يكون كبيراً',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('إنشاء نسخة .db'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        final service = ref.read(googleDriveBackupServiceProvider);
        await service.uploadDbBackup();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم إنشاء نسخة .db ورفعها بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          // تجاهل الفيوتشر لأن الـ Provider يُدير دورة حياته داخلياً
          // (refreshBackupsList يطلق تحديث الحالة بدون الحاجة لـ await هنا).
          unawaited(
            ref.read(backupStatusProvider.notifier).refreshBackupsList(),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.status == BackupStatus.downloading ||
                state.status == BackupStatus.restoring) ...[
              LinearProgressIndicator(
                value: state.progress,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
              const SizedBox(height: 8),
              Text(
                state.progress != null
                    ? '${(state.progress! * 100).round()}% - ${state.message ?? 'جاري الاستعادة...'}'
                    : state.message ?? 'جاري الاستعادة...',
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
    final recordsCount =
        (backup.metadata?['total_records'] as int?) ??
        int.tryParse(backup.appProperties['records_count'] ?? '') ??
        0;
    final recordsLabel = recordsCount > 0 ? recordsCount.toString() : '---';
    final formatLabel = backup.format == BackupFormat.sqlite
        ? 'SQLite'
        : 'JSON';

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
    final recordsCount =
        (backup.metadata?['total_records'] as int?) ??
        int.tryParse(backup.appProperties['records_count'] ?? '') ??
        0;
    final recordsLabel = recordsCount > 0
        ? recordsCount.toString()
        : 'غير معروف';
    final formatLabel = backup.format == BackupFormat.sqlite
        ? 'SQLite (.db)'
        : 'JSON';

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ سيتم استبدال جميع البيانات الحالية بالنسخة المختارة:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
            Text('التاريخ: ${dateFormatter.format(backup.createdTime)}'),
            Text('السجلات: $recordsLabel'),
            Text('التنسيق: $formatLabel'),
            if (backup.format == BackupFormat.sqlite) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.purple, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'نسخة .db: استعادة سريعة - قاعدة البيانات ستُغلق مؤقتاً',
                        style: TextStyle(fontSize: 12, color: Colors.purple),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
              // التحقق من نوع النسخة
              if (backup.format == BackupFormat.sqlite) {
                unawaited(_restoreDbBackup(backup.fileId));
              } else {
                unawaited(ref
                    .read(backupStatusProvider.notifier)
                    .restoreFromBackup(backup.fileId));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('استعادة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ));
  }

  Future<void> _restoreDbBackup(String fileId) async {
    final notifier = ref.read(backupStatusProvider.notifier);
    try {
      notifier.setStatus(BackupStatus.downloading, 'جاري تنزيل نسخة .db...');

      final service = ref.read(googleDriveBackupServiceProvider);
      await service.restoreDbBackup(fileId);

      if (!mounted) return;
      notifier.setStatus(
        BackupStatus.restoring,
        'جاري فحص وإصلاح البيانات بعد الاستعادة...',
      );

      // مسار SQLite يستبدل ملف القاعدة مباشرة، لذلك يحتاج إلى نفس
      // post-restore fix الموجود في مسار JSON لإعادة ربط العلاقات وتحديث
      // القيم المشتقة بعد إعادة فتح DatabaseManager.
      final fixReport = await RestoreFixService(
        DatabaseManager.instance,
      ).runAutoFixAfterRestore();
      if (!fixReport.success) {
        dlog(
          () => '⚠️ فشل الإصلاح التلقائي بعد استعادة .db: ${fixReport.error}',
        );
      }

      await notifier.updateDatabaseSize();
      if (!mounted) return;
      notifier.setStatus(
        BackupStatus.success,
        fixReport.success
            ? 'تمت استعادة قاعدة البيانات وإصلاحها بنجاح'
            : 'تمت الاستعادة، لكن يلزم فحص الإصلاحات يدوياً',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fixReport.success
                ? '✅ تمت استعادة نسخة .db وإصلاح البيانات بنجاح'
                : '⚠️ تمت الاستعادة مع وجود ملاحظات في الإصلاح التلقائي',
          ),
          backgroundColor: fixReport.success ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
      );
      notifier.setStatus(BackupStatus.error, 'فشل الاستعادة: $e');
    }
  }

  Widget _buildSyncControlCard(BackupState state) {
    final syncEnabled = state.googleDriveSyncEnabled;
    final activeColor = syncEnabled ? Colors.teal : Colors.grey;
    final statusText = syncEnabled ? 'نشطة' : 'معطّلة';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync, color: activeColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'المزامنة التلقائية',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: syncEnabled
                        ? Colors.teal.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: activeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'مزامنة تلقائية للتغييرات بين التطبيق و Google Drive. عند التفعيل، يتم رفع التغييرات وسحب التحديثات تلقائياً.',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'تفعيل المزامنة التلقائية',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                syncEnabled
                    ? 'يتم مزامنة البيانات تلقائياً مع Google Drive'
                    : 'المزامنة التلقائية معطّلة - لن يتم رفع أو سحب التغييرات تلقائياً',
              ),
              value: syncEnabled,
              onChanged: (value) => ref
                  .read(backupStatusProvider.notifier)
                  .setGoogleDriveSyncEnabled(value),
              activeThumbColor: Colors.teal,
            ),
            if (!syncEnabled) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'التغييرات المحلية لن تُرفع تلقائياً. يمكنك استخدام النسخ الاحتياطي اليدوي لرفع البيانات.',
                        style: TextStyle(
                          color: Colors.orange.shade700,
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('تفعيل النسخ التلقائي'),
              subtitle: const Text(
                'إنشاء نسخ احتياطية تلقائية حسب الجدولة المحددة',
              ),
              value: state.autoSettings.isEnabled,
              onChanged: _updateAutoBackupEnabled,
            ),
            if (state.autoSettings.isEnabled) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('التكرار'),
                subtitle: Text(
                  _getFrequencyDisplayName(state.autoSettings.frequency),
                ),
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
      case 'daily':
        return 'يومياً';
      case 'weekly':
        return 'أسبوعياً';
      case 'monthly':
        return 'شهرياً';
      default:
        return frequency;
    }
  }

  void _updateAutoBackupEnabled(bool enabled) {
    final currentSettings = ref.read(backupStatusProvider).autoSettings;
    unawaited(ref
        .read(backupStatusProvider.notifier)
        .updateAutoBackupSettings(currentSettings.copyWith(isEnabled: enabled)));
  }

  void _showFrequencySelection(AutoBackupSettings currentSettings) {
    unawaited(showDialog<void>(
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
    ));
  }

  Widget _buildFrequencyOption(
    String value,
    String label,
    AutoBackupSettings currentSettings,
  ) {
    return RadioListTile<String>(
      title: Text(label),
      value: value,
      // ignore: deprecated_member_use
      groupValue: currentSettings.frequency,
      // ignore: deprecated_member_use
      onChanged: (selectedValue) {
        if (selectedValue != null) {
          Navigator.of(context).pop();
          unawaited(ref
              .read(backupStatusProvider.notifier)
              .updateAutoBackupSettings(
                currentSettings.copyWith(frequency: selectedValue),
              ));
        }
      },
    );
  }

  void _showTimeSelection(AutoBackupSettings currentSettings) {
    final timeParts = currentSettings.time.split(':');
    final currentTime = TimeOfDay(
      hour: int.tryParse(timeParts[0]) ?? 0,
      minute: int.tryParse(timeParts[1]) ?? 0,
    );

    unawaited(showTimePicker(
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
        final timeString =
            '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
        unawaited(ref
            .read(backupStatusProvider.notifier)
            .updateAutoBackupSettings(
              currentSettings.copyWith(time: timeString),
            ));
      }
    }));
  }
}
