import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../providers/backup_provider.dart';
import '../../../../services/local_backup_service.dart';

/// Local Backups Tab - إدارة النسخ المحلية
///
/// مربوط بالكامل مع BackupStatusNotifier و LocalBackupService
class LocalBackupsTab extends ConsumerStatefulWidget {
  const LocalBackupsTab({super.key});

  @override
  ConsumerState<LocalBackupsTab> createState() => _LocalBackupsTabState();
}

class _LocalBackupsTabState extends ConsumerState<LocalBackupsTab> {
  @override
  void initState() {
    super.initState();
    // التحقق من الأذونات عند فتح التبويب
    Future.microtask(() {
      final notifier = ref.read(backupStatusProvider.notifier);
      notifier.checkStoragePermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);
    final folderInfo = backupState.backupFolderInfo;
    final localBackups = backupState.localBackups;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(UIConstants.spacingMD),
          children: [
            // معلومات التخزين
            _buildStorageInfoCard(folderInfo, backupState),

            const SizedBox(height: UIConstants.spacingLG),

            // أزرار الإجراءات السريعة
            _buildQuickActionsRow(backupState),

            const SizedBox(height: UIConstants.spacingLG),

            // آخر نسخة محلية
            if (backupState.lastLocalBackupTime != null)
              _buildLastBackupCard(backupState.lastLocalBackupTime!),

            if (backupState.lastLocalBackupTime != null)
              const SizedBox(height: UIConstants.spacingLG),

            // قائمة النسخ المحلية
            SectionHeader(
              title: 'النسخ المحلية (${localBackups.length})',
              icon: Icons.phone_android,
              action: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: backupState.isWorking
                    ? null
                    : _refreshLocalBackups,
              ),
            ),

            if (localBackups.isEmpty)
              _buildEmptyState()
            else
              ...localBackups.map(
                (backup) => _buildBackupItem(backup, backupState),
              ),

            const SizedBox(height: 80),
          ],
        ),

        // شريط التقدم
        if (backupState.isWorking && backupState.progress != null)
          _buildProgressOverlay(backupState),
      ],
    );
  }

  Widget _buildStorageInfoCard(
    Map<String, dynamic>? folderInfo,
    BackupState backupState,
  ) {
    final path = folderInfo?['path'] as String? ?? 'جاري التحميل...';
    final totalSizeMb =
        folderInfo?['total_size_mb'] as String? ?? '0';
    final count = folderInfo?['backups_count'] as int? ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.sd_storage,
                  color: backupState.hasStoragePermission
                      ? Colors.green
                      : Colors.red,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'تخزين الجهاز',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (!backupState.hasStoragePermission)
                  TextButton.icon(
                    onPressed: () => ref
                        .read(backupStatusProvider.notifier)
                        .checkStoragePermissions(),
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: const Text('منح الأذونات'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'المسار',
              value: path,
              icon: Icons.folder,
              isExpandable: true,
            ),
            InfoRow(
              label: 'عدد النسخ',
              value: '$count نسخة',
              icon: Icons.layers,
            ),
            InfoRow(
              label: 'المساحة المستخدمة',
              value: '$totalSizeMb ميجابايت',
              icon: Icons.data_usage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow(BackupState backupState) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: backupState.isWorking
                ? null
                : _createLocalBackup,
            icon: backupState.isWorking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.backup),
            label: const Text('نسخ الآن'),
            style: ElevatedButton.styleFrom(
              backgroundColor: UIConstants.backupColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(UIConstants.spacingMD),
            ),
          ),
        ),
        const SizedBox(width: UIConstants.spacingMD),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: backupState.isWorking
                ? null
                : _importBackup,
            icon: const Icon(Icons.file_download),
            label: const Text('استيراد نسخة'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(UIConstants.spacingMD),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLastBackupCard(DateTime lastBackupTime) {
    final now = DateTime.now();
    final diff = now.difference(lastBackupTime);
    String relativeTime;
    if (diff.inMinutes < 1) {
      relativeTime = 'الآن';
    } else if (diff.inMinutes < 60) {
      relativeTime = 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      relativeTime = 'منذ ${diff.inHours} ساعة';
    } else {
      relativeTime = 'منذ ${diff.inDays} يوم';
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Row(
          children: [
            Icon(
              Icons.history,
              color: Colors.blue.shade400,
              size: UIConstants.iconSizeMD,
            ),
            const SizedBox(width: UIConstants.spacingSM),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'آخر نسخة محلية',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$relativeTime - ${DateTimeFormatter.formatDateTime(lastBackupTime.toIso8601String())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.backup_outlined,
                size: 48, color: Colors.grey.shade400,),
            const SizedBox(height: UIConstants.spacingMD),
            Text(
              'لا توجد نسخ احتياطية محلية',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              'اضغط "نسخ الآن" لإنشاء أول نسخة احتياطية',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupItem(
    LocalBackupFile backup,
    BackupState backupState,
  ) {
    final metadata = backup.metadata;
    final formatLabel =
        backup.format == BackupFormat.sqlite ? 'SQLite' : 'JSON';

    return Card(
      margin: const EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: const Icon(Icons.file_present, color: Colors.green),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                metadata?.deviceInfo ?? 'نسخة محلية',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                formatLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              DateTimeFormatter.formatDateTime(
                  backup.createdTime.toIso8601String(),),
              style: const TextStyle(fontSize: 12),
            ),
            Row(
              children: [
                Text(
                  FileSizeFormatter.formatBytes(backup.sizeBytes),
                  style: const TextStyle(fontSize: 11),
                ),
                if (metadata != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${metadata.totalRecords} سجل',
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'v${metadata.databaseVersion}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore, size: 20),
                  SizedBox(width: 8),
                  Text('استعادة'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 8),
                  Text('مشاركة'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('حذف', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) => _handleBackupAction(value, backup),
        ),
      ),
    );
  }

  Widget _buildProgressOverlay(BackupState backupState) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    backupState.message ?? 'جاري المعالجة...',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: backupState.progress,
              backgroundColor: Colors.grey.shade200,
              color: UIConstants.backupColor,
            ),
          ],
        ),
      ),
    );
  }

  // ─── الأفعال ───

  Future<void> _createLocalBackup() async {
    await ref.read(backupStatusProvider.notifier).createLocalBackup();
    if (mounted) {
      final state = ref.read(backupStatusProvider);
      if (state.status == BackupStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message ?? 'تم إنشاء النسخة'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (state.status == BackupStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message ?? 'حدث خطأ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    await ref.read(backupStatusProvider.notifier).importBackupFromFile();
    if (mounted) {
      final state = ref.read(backupStatusProvider);
      if (state.status == BackupStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message ?? 'تم الاستيراد'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (state.status == BackupStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message ?? 'حدث خطأ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleBackupAction(String action, LocalBackupFile backup) async {
    switch (action) {
      case 'restore':
        _confirmRestore(backup);
      case 'share':
        await ref
            .read(backupStatusProvider.notifier)
            .shareLocalBackup(backup.filePath);
      case 'delete':
        _confirmDelete(backup);
    }
  }

  void _confirmRestore(LocalBackupFile backup) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Text(
          'سيتم استبدال جميع البيانات الحالية ببيانات النسخة الاحتياطية.\n\n'
          'الملف: ${backup.fileName}\n'
          'التاريخ: ${DateTimeFormatter.formatDateTime(backup.createdTime.toIso8601String())}\n'
          'الحجم: ${FileSizeFormatter.formatBytes(backup.sizeBytes)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<void>(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop<void>(context);
              _restoreBackup(backup);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup(LocalBackupFile backup) async {
    await ref
        .read(backupStatusProvider.notifier)
        .restoreFromLocalBackup(backup.filePath);

    if (mounted) {
      final state = ref.read(backupStatusProvider);
      if (state.status == BackupStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت الاستعادة بنجاح - سيتم تحديث البيانات'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (state.status == BackupStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message ?? 'فشلت الاستعادة'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmDelete(LocalBackupFile backup) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نسخة احتياطية'),
        content: Text(
          'هل أنت متأكد من حذف:\n${backup.fileName}؟\n\n'
          'لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<void>(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop<void>(context);
              _deleteBackup(backup);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBackup(LocalBackupFile backup) async {
    await ref
        .read(backupStatusProvider.notifier)
        .deleteLocalBackup(backup.filePath);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف النسخة الاحتياطية'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _refreshLocalBackups() {
    ref.read(backupStatusProvider.notifier).checkStoragePermissions();
  }
}
