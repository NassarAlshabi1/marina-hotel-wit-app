import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/backup_provider.dart';
import '../../services/google_drive_backup_service.dart';
import '../../services/local_backup_service.dart';
import '../../services/file_management_service.dart';
import '../../utils/theme.dart';

class ComprehensiveBackupScreen extends ConsumerStatefulWidget {
  const ComprehensiveBackupScreen({super.key});

  @override
  ConsumerState<ComprehensiveBackupScreen> createState() => _ComprehensiveBackupScreenState();
}

class _ComprehensiveBackupScreenState extends ConsumerState<ComprehensiveBackupScreen> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // زيادة عدد التبويبات
    
    // تحديث البيانات عند دخول الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupStatusProvider.notifier).updateDatabaseSize();
      ref.read(backupStatusProvider.notifier).checkStoragePermissions();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);

    return AppScaffold(
      title: 'النسخ الاحتياطي',
      actions: [
        IconButton(
          onPressed: () => _refreshAll(),
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث جميع البيانات',
        ),
      ],
      body: Column(
        children: [
          // رسائل الحالة والأخطاء
          if (backupState.message != null) ...[
            _buildStatusMessage(backupState),
          ],

          // Tab Bar
          Container(
            color: Colors.grey[100],
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primaryColor,
              tabs: const [
                Tab(
                  icon: Icon(Icons.dashboard),
                  text: 'الرئيسية',
                ),
                Tab(
                  icon: Icon(Icons.cloud),
                  text: 'Google Drive',
                ),
                Tab(
                  icon: Icon(Icons.phone_android),
                  text: 'النسخ المحلية',
                ),
                Tab(
                  icon: Icon(Icons.import_export),
                  text: 'إدارة الملفات',
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMainTab(backupState),
                _buildGoogleDriveTab(backupState),
                _buildLocalTab(backupState),
                _buildFileManagementTab(backupState),
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
        break;
      case BackupStatus.error:
        color = Colors.red;
        icon = Icons.error;
        break;
      default:
        color = Colors.blue;
        icon = Icons.info;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
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
    );
  }

  Widget _buildMainTab(BackupState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقة معلومات النظام
        _buildSystemOverviewCard(state),
        const SizedBox(height: 16),

        // بطاقة الأعمال السريعة
        _buildQuickActionsCard(state),
        const SizedBox(height: 16),

        // إعدادات النسخ التلقائي
        _buildAutoBackupSettingsCard(state),
      ],
    );
  }

  Widget _buildSystemOverviewCard(BackupState state) {
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
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'حجم البيانات',
                    '$sizeInMB ميجابايت',
                    Icons.storage,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'نسخ Google Drive',
                    '${state.availableBackups.length}',
                    Icons.cloud,
                    state.isSignedIn ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'النسخ المحلية',
                    '${state.localBackups.length}',
                    Icons.phone_android,
                    state.hasStoragePermission ? Colors.orange : Colors.grey,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'آخر نسخة',
                    _getLastBackupDisplay(state),
                    Icons.history,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getLastBackupDisplay(BackupState state) {
    final driveTime = state.lastBackupTime;
    final localTime = state.lastLocalBackupTime;
    
    if (driveTime == null && localTime == null) {
      return 'لا توجد';
    }
    
    DateTime? latest;
    if (driveTime != null && localTime != null) {
      latest = driveTime.isAfter(localTime) ? driveTime : localTime;
    } else {
      latest = driveTime ?? localTime;
    }
    
    final diff = DateTime.now().difference(latest!);
    if (diff.inDays > 0) {
      return '${diff.inDays} أيام';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} ساعات';
    } else {
      return '${diff.inMinutes} دقائق';
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
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
            title,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Text(
                  'الأعمال السريعة',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // شريط التقدم للعمليات الجارية
            if (state.isWorking && state.progress != null) ...[
              LinearProgressIndicator(
                value: state.progress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                '${(state.progress! * 100).round()}% - ${state.message ?? "جاري التنفيذ..."}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).createComprehensiveBackup(),
                    icon: const Icon(Icons.backup),
                    label: const Text('نسخة شاملة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).exportToDownloads(),
                    icon: const Icon(Icons.download),
                    label: const Text('تصدير'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).importBackupFromFile(),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('استيراد ملف'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).cleanOldLocalBackups(),
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('تنظيف'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
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

  Widget _buildAutoBackupSettingsCard(BackupState state) {
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
              subtitle: Text('التكرار: ${_getFrequencyDisplayName(state.autoSettings.frequency)} في ${state.autoSettings.time}'),
              value: state.autoSettings.isEnabled,
              onChanged: (value) => _updateAutoBackupEnabled(value),
            ),

            if (state.autoSettings.isEnabled) ...[
              const Divider(),
              
              CheckboxListTile(
                title: const Text('Google Drive'),
                subtitle: state.isSignedIn ? Text('متصل: ${state.signedInAccount?.email}') : const Text('غير متصل'),
                value: state.autoSettings.enableGoogleDriveBackup,
                onChanged: state.isSignedIn ? (value) => _updateAutoBackupType(
                  enableDrive: value ?? false,
                  enableLocal: state.autoSettings.enableLocalBackup,
                ) : null,
              ),
              
              CheckboxListTile(
                title: const Text('التخزين المحلي'),
                subtitle: state.hasStoragePermission ? const Text('مُتاح') : const Text('يتطلب أذونات'),
                value: state.autoSettings.enableLocalBackup,
                onChanged: state.hasStoragePermission ? (value) => _updateAutoBackupType(
                  enableDrive: state.autoSettings.enableGoogleDriveBackup,
                  enableLocal: value ?? false,
                ) : null,
              ),
              
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showFrequencySelection(state.autoSettings),
                      icon: const Icon(Icons.repeat),
                      label: Text(_getFrequencyDisplayName(state.autoSettings.frequency)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showTimeSelection(state.autoSettings),
                      icon: const Icon(Icons.access_time),
                      label: Text(state.autoSettings.time),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleDriveTab(BackupState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConnectionStatusCard(state),
        const SizedBox(height: 16),
        if (state.isSignedIn) ...[
          _buildManualBackupCard(state),
          const SizedBox(height: 16),
          _buildDriveRestoreCard(state),
        ],
      ],
    );
  }

  Widget _buildLocalTab(BackupState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLocalStorageCard(state),
        const SizedBox(height: 16),
        if (state.hasStoragePermission) ...[
          _buildLocalBackupCard(state),
          const SizedBox(height: 16),
          _buildLocalRestoreCard(state),
          const SizedBox(height: 16),
          _buildFileManagementCard(state),
        ],
      ],
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
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
                'غير متصل - يجب تسجيل الدخول للوصول لميزات Google Drive',
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
      ),
    );
  }

  Widget _buildLocalStorageCard(BackupState state) {
    final folderInfo = state.backupFolderInfo;
    final totalSizeMB = folderInfo?['total_size_mb'] ?? '0.00';
    final path = folderInfo?['path']?.toString() ?? '';
    final visiblePathSegments = path.isEmpty ? <String>[] : path.split('/').where((segment) => segment.isNotEmpty).toList();
    final displayPath = visiblePathSegments.isEmpty
        ? 'غير معروف'
        : (visiblePathSegments.length > 3
            ? visiblePathSegments.sublist(visiblePathSegments.length - 3).join('/')
            : visiblePathSegments.join('/'));
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.phone_android,
                  color: state.hasStoragePermission ? Colors.orange : Colors.grey,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'التخزين المحلي',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (state.hasStoragePermission) ...[
              Row(
                children: [
                  const Icon(Icons.folder, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المسار: $displayPath',
                      style: const TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.storage, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Text('الحجم الإجمالي: $totalSizeMB ميجابايت'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).checkStoragePermissions(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث المعلومات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'لا توجد أذونات للوصول للتخزين المحلي',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).checkStoragePermissions(),
                  icon: state.status == BackupStatus.checkingPermissions
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.security),
                  label: Text(state.status == BackupStatus.checkingPermissions ? 'جاري التحقق...' : 'طلب الأذونات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
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

  Widget _buildManualBackupCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload, color: Colors.green, size: 24),
                const SizedBox(width: 12),
                Text(
                  'النسخ السحابي',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            const Text(
              'إنشاء نسخة احتياطية ورفعها إلى Google Drive',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).createBackup(),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('رفع إلى Google Drive'),
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

  Widget _buildLocalBackupCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.save, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                Text(
                  'النسخ المحلي',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            const Text(
              'حفظ نسخة احتياطية في ذاكرة الجهاز',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).createLocalBackup(),
                icon: const Icon(Icons.save),
                label: const Text('حفظ محلياً'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveRestoreCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_download, color: Colors.indigo, size: 24),
                const SizedBox(width: 12),
                Text(
                  'استعادة من Google Drive',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (state.availableBackups.isEmpty) ...[
              const Text(
                'لا توجد نسخ احتياطية في Google Drive',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
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
                    return _buildDriveBackupItem(backup, state.isWorking);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalRestoreCard(BackupState state) {
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
                  'استعادة من النسخ المحلية',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (state.localBackups.isEmpty) ...[
              const Text(
                'لا توجد نسخ احتياطية محلية',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: state.localBackups.length,
                  itemBuilder: (context, index) {
                    final backup = state.localBackups[index];
                    return _buildLocalBackupItem(backup, state.isWorking);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileManagementCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open, color: Colors.teal, size: 24),
                const SizedBox(width: 12),
                Text(
                  'إدارة الملفات',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).importBackupFromFile(),
                    icon: const Icon(Icons.file_upload),
                    label: const Text('استيراد ملف'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).exportToDownloads(),
                    icon: const Icon(Icons.file_download),
                    label: const Text('تصدير'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.localBackups.isEmpty ? null : () => ref.read(backupStatusProvider.notifier).cleanOldLocalBackups(keepCount: 5),
                icon: const Icon(Icons.cleaning_services),
                label: Text('تنظيف النسخ القديمة (الاحتفاظ بـ 5)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveBackupItem(DriveBackupFile backup, bool isWorking) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    final sizeInMB = backup.size != null 
        ? (backup.size! / (1024 * 1024)).toStringAsFixed(2)
        : '---';

    return ListTile(
      leading: const Icon(Icons.cloud, color: Colors.blue),
      title: Text(
        dateFormatter.format(backup.createdTime),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        'حجم: $sizeInMB ميجابايت\nسجلات: ${backup.metadata?['records_count'] ?? '---'}',
      ),
      trailing: IconButton(
        onPressed: isWorking ? null : () => _showRestoreConfirmation(backup.fileId, BackupType.googleDrive),
        icon: const Icon(Icons.cloud_download, color: Colors.indigo),
        tooltip: 'استعادة',
      ),
      dense: true,
    );
  }

  Widget _buildLocalBackupItem(LocalBackupFile backup, bool isWorking) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    final sizeInMB = (backup.sizeBytes / (1024 * 1024)).toStringAsFixed(2);

    return ListTile(
      leading: const Icon(Icons.phone_android, color: Colors.orange),
      title: Text(
        dateFormatter.format(backup.createdTime),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        'حجم: $sizeInMB ميجابايت\nسجلات: ${backup.metadata?.totalRecords ?? '---'}',
      ),
      trailing: PopupMenuButton<String>(
        enabled: !isWorking,
        onSelected: (action) => _handleLocalBackupAction(action, backup),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'restore',
            child: Row(
              children: [
                Icon(Icons.restore, color: Colors.orange),
                SizedBox(width: 8),
                Text('استعادة'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'share',
            child: Row(
              children: [
                Icon(Icons.share, color: Colors.blue),
                SizedBox(width: 8),
                Text('مشاركة'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('حذف'),
              ],
            ),
          ),
        ],
        child: const Icon(Icons.more_vert),
      ),
      dense: true,
    );
  }

  void _handleLocalBackupAction(String action, LocalBackupFile backup) {
    switch (action) {
      case 'restore':
        _showRestoreConfirmation(backup.filePath, BackupType.local);
        break;
      case 'share':
        ref.read(backupStatusProvider.notifier).shareLocalBackup(backup.filePath);
        break;
      case 'delete':
        _showDeleteConfirmation(backup);
        break;
    }
  }

  void _showDeleteConfirmation(LocalBackupFile backup) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('هل أنت متأكد من حذف هذه النسخة الاحتياطية؟'),
            const SizedBox(height: 8),
            Text('التاريخ: ${dateFormatter.format(backup.createdTime)}'),
            const Text('⚠️ لا يمكن التراجع عن هذا الإجراء', 
                style: TextStyle(color: Colors.red)),
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
              ref.read(backupStatusProvider.notifier).deleteLocalBackup(backup.filePath);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRestoreConfirmation(String identifier, BackupType type) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    
    String title, description, location;
    DateTime createdTime;
    int? recordsCount;

    if (type == BackupType.googleDrive) {
      final backup = ref.read(availableBackupsProvider).firstWhere((b) => b.fileId == identifier);
      title = 'استعادة من Google Drive';
      description = 'سيتم تنزيل النسخة من Google Drive واستعادة البيانات';
      location = 'Google Drive';
      createdTime = backup.createdTime;
      recordsCount = int.tryParse(backup.metadata?['records_count'] ?? '0');
    } else {
      final backup = ref.read(localBackupsProvider).firstWhere((b) => b.filePath == identifier);
      title = 'استعادة من النسخة المحلية';
      description = 'سيتم استعادة البيانات من النسخة المحفوظة محلياً';
      location = 'التخزين المحلي';
      createdTime = backup.createdTime;
      recordsCount = backup.metadata?.totalRecords;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ سيتم استبدال جميع البيانات الحالية بالنسخة المختارة:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            const SizedBox(height: 12),
            Text('المصدر: $location'),
            Text('التاريخ: ${dateFormatter.format(createdTime)}'),
            if (recordsCount != null) Text('السجلات: $recordsCount'),
            const SizedBox(height: 12),
            Text(description),
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
              if (type == BackupType.googleDrive) {
                ref.read(backupStatusProvider.notifier).restoreFromBackup(identifier);
              } else {
                ref.read(backupStatusProvider.notifier).restoreFromLocalBackup(identifier);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('استعادة', style: TextStyle(color: Colors.white)),
          ),
        ],
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

  void _updateAutoBackupType({required bool enableDrive, required bool enableLocal}) {
    final currentSettings = ref.read(backupStatusProvider).autoSettings;
    
    BackupType type = BackupType.both;
    if (enableDrive && !enableLocal) {
      type = BackupType.googleDrive;
    } else if (!enableDrive && enableLocal) {
      type = BackupType.local;
    }

    ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
      currentSettings.copyWith(
        enableGoogleDriveBackup: enableDrive,
        enableLocalBackup: enableLocal,
        backupType: type,
      ),
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
          textDirection: TextDirection.rtl,
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

  void _refreshAll() {
    ref.read(backupStatusProvider.notifier).refreshBackupsList();
    ref.read(backupStatusProvider.notifier).refreshLocalBackups();
    ref.read(backupStatusProvider.notifier).updateDatabaseSize();
  }

  Widget _buildFileManagementTab(BackupState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقة التصدير المتقدم
        _buildAdvancedExportCard(state),
        const SizedBox(height: 16),

        // بطاقة الاستيراد والدمج
        _buildImportAndMergeCard(state),
        const SizedBox(height: 16),

        // بطاقة إدارة الملفات
        _buildAdvancedFileManagementCard(state),
        const SizedBox(height: 16),

        // بطاقة إحصائيات وتحليل
        _buildAnalyticsCard(state),
      ],
    );
  }

  Widget _buildAdvancedExportCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.file_download, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                Text(
                  'التصدير المتقدم',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            const Text(
              'تصدير البيانات بتنسيقات مختلفة للتحليل والمشاركة',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).exportToCSV(),
                    icon: const Icon(Icons.table_chart),
                    label: const Text('تصدير CSV'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).createReadableReport(),
                    icon: const Icon(Icons.description),
                    label: const Text('تقرير شامل'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).exportToDownloads(),
                icon: const Icon(Icons.download),
                label: const Text('تصدير إلى مجلد Downloads'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportAndMergeCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.file_upload, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Text(
                  'الاستيراد والدمج',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            const Text(
              'استيراد ملفات نسخ احتياطية من مصادر خارجية ودمج نسخ متعددة',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).importBackupFromFile(),
                    icon: const Icon(Icons.file_upload),
                    label: const Text('استيراد ملف'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.localBackups.length < 2 ? null : () => _showMergeDialog(state),
                    icon: const Icon(Icons.merge),
                    label: const Text('دمج نسخ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedFileManagementCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open, color: Colors.teal, size: 24),
                const SizedBox(width: 12),
                Text(
                  'إدارة الملفات المتقدمة',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (state.backupFolderInfo != null) ...[
              Text(
                'مجلد النسخ: ${state.backupFolderInfo!['backups_count']} ملف (${state.backupFolderInfo!['total_size_mb']} ميجابايت)',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isWorking || state.localBackups.isEmpty ? null : () => _showShareMultipleDialog(state),
                    icon: const Icon(Icons.share),
                    label: const Text('مشاركة متعددة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).cleanupTempFiles(),
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('تنظيف مؤقت'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.isWorking || state.localBackups.length < 6 ? null : () => ref.read(backupStatusProvider.notifier).cleanOldLocalBackups(keepCount: 5),
                icon: const Icon(Icons.auto_delete),
                label: const Text('حذف النسخ القديمة (الاحتفاظ بـ 5)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsCard(BackupState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.purple, size: 24),
                const SizedBox(width: 12),
                Text(
                  'إحصائيات وتحليل',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildAnalyticItem(
                    'إجمالي النسخ',
                    '${state.availableBackups.length + state.localBackups.length}',
                    Icons.backup,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildAnalyticItem(
                    'النسخ السحابية',
                    '${state.availableBackups.length}',
                    Icons.cloud,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildAnalyticItem(
                    'النسخ المحلية',
                    '${state.localBackups.length}',
                    Icons.phone_android,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildAnalyticItem(
                    'المساحة المستخدمة',
                    '${state.backupFolderInfo?['total_size_mb'] ?? '0'} ميجابايت',
                    Icons.storage,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.isWorking ? null : () => ref.read(backupStatusProvider.notifier).analyzeBackupFiles(),
                icon: const Icon(Icons.analytics),
                label: const Text('تحليل مفصل للملفات'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticItem(String title, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 8, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showMergeDialog(BackupState state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('دمج النسخ الاحتياطية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('سيتم دمج جميع النسخ المحلية في ملف واحد'),
            const SizedBox(height: 12),
            Text('عدد الملفات: ${state.localBackups.length}'),
            const Text('سيتم إزالة التكرارات تلقائياً'),
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
              final paths = state.localBackups.map((b) => b.filePath).toList();
              final mergedName = 'merged_backup_${DateTime.now().millisecondsSinceEpoch}.json';
              ref.read(backupStatusProvider.notifier).mergeBackups(paths, mergedName);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('دمج', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showShareMultipleDialog(BackupState state) {
    final selectedBackups = <String>{};
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('مشاركة نسخ متعددة'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: Column(
              children: [
                const Text('اختر النسخ الاحتياطية للمشاركة:'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: state.localBackups.length,
                    itemBuilder: (context, index) {
                      final backup = state.localBackups[index];
                      final isSelected = selectedBackups.contains(backup.filePath);
                      
                      return CheckboxListTile(
                        title: Text(backup.fileName),
                        subtitle: Text('${(backup.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} ميجابايت'),
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedBackups.add(backup.filePath);
                            } else {
                              selectedBackups.remove(backup.filePath);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: selectedBackups.isEmpty ? null : () {
                Navigator.of(context).pop();
                ref.read(backupStatusProvider.notifier).shareMultipleBackups(selectedBackups.toList());
              },
              child: Text('مشاركة (${selectedBackups.length})'),
            ),
          ],
        ),
      ),
    );
  }
}