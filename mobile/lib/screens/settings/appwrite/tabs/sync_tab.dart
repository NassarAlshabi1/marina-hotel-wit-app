import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/core.dart';
import '../../../../providers/appwrite_providers.dart' as ap;
import '../../../../services/appwrite_config.dart';

/// Appwrite Sync Tab - إدارة المزامنة مع Appwrite
class AppwriteSyncTab extends ConsumerStatefulWidget {
  const AppwriteSyncTab({super.key});

  @override
  ConsumerState<AppwriteSyncTab> createState() => _AppwriteSyncTabState();
}

class _AppwriteSyncTabState extends ConsumerState<AppwriteSyncTab> {
  bool _syncEnabled = true;
  int _syncInterval = 15;
  bool _autoSyncOnConnect = true;
  bool _cacheEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appwrite_sync_enabled', false);
    setState(() {
      _syncEnabled = false;
      _syncInterval = prefs.getInt('appwrite_sync_interval') ?? 15;
      _autoSyncOnConnect =
          prefs.getBool('appwrite_auto_sync_on_connect') ?? true;
      _cacheEnabled = prefs.getBool('appwrite_cache_enabled') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appwrite_sync_enabled', _syncEnabled);
    await prefs.setInt('appwrite_sync_interval', _syncInterval);
    await prefs.setBool('appwrite_auto_sync_on_connect', _autoSyncOnConnect);
    await prefs.setBool('appwrite_cache_enabled', _cacheEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(ap.syncStatsProvider);
    final cacheStats = ref.watch(ap.cacheStatsProvider);

    final stats = statsAsync.maybeWhen(
      data: (data) => data,
      orElse: () => const <String, dynamic>{},
    );

    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        _buildSyncStatusCard(stats),
        const SizedBox(height: UIConstants.spacingLG),
        _buildSyncSettingsCard(),
        const SizedBox(height: UIConstants.spacingLG),
        _buildSyncStatisticsCard(stats),
        const SizedBox(height: UIConstants.spacingLG),
        _buildCacheSettingsCard(cacheStats),
        const SizedBox(height: UIConstants.spacingLG),
        _buildSyncActionsCard(statsAsync.isLoading),
      ],
    );
  }

  Widget _buildSyncStatusCard(Map<String, dynamic> stats) {
    final lastSyncTime = stats['lastSyncTime'] as String?;
    final outboxCount = stats['outboxCount'] as int? ?? 0;

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
                  Icons.sync,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'حالة المزامنة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'الحالة',
              value: _syncEnabled ? 'مفعّلة' : 'معطّلة',
              icon: Icons.circle,
              iconColor: _syncEnabled ? Colors.green : Colors.grey,
            ),
            InfoRow(
              label: 'آخر مزامنة',
              value: DateTimeFormatter.getRelativeTime(lastSyncTime),
              icon: Icons.schedule,
            ),
            InfoRow(
              label: 'المزامنة التالية',
              value: _nextSyncLabel(lastSyncTime),
              icon: Icons.timer,
            ),
            InfoRow(
              label: 'عناصر معلقة',
              value: '$outboxCount',
              icon: Icons.pending,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncSettingsCard() {
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
                  Icons.tune,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'إعدادات المزامنة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل المزامنة'),
            subtitle: const Text('المزامنة مع Appwrite معطّلة (يدوي فقط)'),
            value: false,
            onChanged: null,
            secondary: const Icon(Icons.sync),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('فترة المزامنة'),
            subtitle: Text('$_syncInterval دقيقة'),
            leading: const Icon(Icons.timer),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: null,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('مزامنة تلقائية عند الاتصال'),
            subtitle: const Text('المزامنة التلقائية معطّلة'),
            value: false,
            onChanged: null,
            secondary: const Icon(Icons.wifi),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatisticsCard(Map<String, dynamic> stats) {
    final totalSyncs = stats['totalSyncs'] as int? ?? 0;
    final successRate = stats['successRate'] as double? ?? 0.0;
    final successfulSyncs = stats['successfulSyncs'] as int? ?? 0;
    final failedSyncs = stats['failedSyncs'] as int? ?? 0;

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
                  Icons.bar_chart,
                  color: Colors.green,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'إحصائيات المزامنة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: UIConstants.spacingMD,
              crossAxisSpacing: UIConstants.spacingMD,
              childAspectRatio: 1.5,
              children: [
                StatCard(
                  title: 'إجمالي المزامنات',
                  value: '$totalSyncs',
                  icon: Icons.sync_alt,
                  color: Colors.blue,
                ),
                StatCard(
                  title: 'معدل النجاح',
                  value: '${successRate.toStringAsFixed(1)}%',
                  icon: Icons.trending_up,
                  color: Colors.green,
                ),
                StatCard(
                  title: 'عمليات ناجحة',
                  value: '$successfulSyncs',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
                StatCard(
                  title: 'عمليات فاشلة',
                  value: '$failedSyncs',
                  icon: Icons.error,
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheSettingsCard(CacheStatistics cacheStats) {
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
                  Icons.storage,
                  color: Colors.purple,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'التخزين المؤقت',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل التخزين المؤقت'),
            subtitle: const Text('تسريع الأداء بالتخزين المحلي'),
            value: _cacheEnabled,
            onChanged: (value) {
              setState(() => _cacheEnabled = value);
              ref.read(ap.appwriteCacheManagerProvider).setEnabled(value);
              _saveSettings();
            },
            secondary: const Icon(Icons.flash_on),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('حجم التخزين المستخدم'),
            subtitle: Text(
              '${FileSizeFormatter.formatBytes(cacheStats.totalSizeBytes)} / ${FileSizeFormatter.formatBytes(cacheStats.maxSizeBytes)}',
            ),
            leading: const Icon(Icons.data_usage),
            trailing: TextButton(
              onPressed: () => _clearCache(),
              child: const Text('مسح'),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('مدة الصلاحية'),
            subtitle: const Text('6 ساعات'),
            leading: const Icon(Icons.timer_outlined),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSyncActionsCard(bool loadingStats) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.sync, color: Colors.blue),
            ),
            title: const Text('مزامنة الآن'),
            subtitle: const Text('إجراء مزامنة فورية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _syncNow(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.refresh, color: Colors.orange),
            ),
            title: const Text('إعادة مزامنة كاملة'),
            subtitle: const Text('مزامنة جميع البيانات من جديد'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showFullSyncDialog(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            title: const Text('مسح سجل المزامنة'),
            subtitle: const Text('مسح سجل المزامنة على السحابة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: loadingStats ? null : () => _showClearHistoryDialog(),
          ),
        ],
      ),
    );
  }

  void _showIntervalDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فترة المزامنة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [5, 10, 15, 30, 60].map((interval) {
            return RadioListTile<int>(
              title: Text('$interval دقيقة'),
              value: interval,
              groupValue: _syncInterval,
              onChanged: (value) {
                setState(() => _syncInterval = value!);
                _saveSettings();
                Navigator.pop(context);
              },
            );
          }).toList(),
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

  Future<void> _clearCache() async {
    ref.read(ap.appwriteCacheManagerProvider).clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم مسح التخزين المؤقت')),
      );
    }
  }

  Future<void> _syncNow() async {
    final manager = ref.read(ap.appwriteSyncManagerProvider);
    final result = await manager.sync();
    ref.invalidate(ap.syncStatsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isSuccess ? 'تمت المزامنة' : 'فشلت المزامنة'),
          backgroundColor: result.isSuccess ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _showFullSyncDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة مزامنة كاملة'),
        content: const Text(
          'هذا سيقوم بمزامنة جميع البيانات من جديد. قد يستغرق بعض الوقت.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _runFullSync();
            },
            child: const Text('بدء المزامنة'),
          ),
        ],
      ),
    );
  }

  Future<void> _runFullSync() async {
    final manager = ref.read(ap.appwriteSyncManagerProvider);
    await manager.resetSyncState();
    final result = await manager.sync(push: true, pull: true);
    ref.invalidate(ap.syncStatsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isSuccess ? 'اكتملت المزامنة' : 'فشلت المزامنة'),
          backgroundColor: result.isSuccess ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح سجل المزامنة (سحابي)'),
        content: const Text('سيتم مسح السجل من Appwrite ومن السجل المحلي.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearCloudSyncLogs();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCloudSyncLogs() async {
    final service = ref.read(ap.appwriteServiceProvider);
    await service.deleteAllDocuments(
      collectionId: AppwriteConfig.syncLogsCollectionId,
    );
    ref.read(ap.appwriteLoggerProvider).clearLogs();
    ref.invalidate(ap.syncStatsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم مسح سجل المزامنة على السحابة')),
      );
    }
  }

  String _nextSyncLabel(String? lastSyncTime) {
    if (!_syncEnabled) return 'معطلة';
    if (lastSyncTime == null || lastSyncTime.isEmpty) return 'غير معروف';

    try {
      final last = DateTime.parse(lastSyncTime);
      final next = last.add(Duration(minutes: _syncInterval));
      return DateTimeFormatter.getRelativeTime(next.toIso8601String());
    } catch (_) {
      return 'غير معروف';
    }
  }
}
