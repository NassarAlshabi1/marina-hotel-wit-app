import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/core.dart';
import '../../../../providers/appwrite_providers.dart' as ap;
import '../../../../providers/repository_providers.dart';
import '../../../../services/appwrite_config.dart';
import '../../../../services/appwrite_cache_manager.dart';
import '../../../../services/appwrite_delta_sync.dart';
import '../../sync_history_screen.dart';

/// Appwrite Sync Tab - إدارة المزامنة مع Appwrite
class AppwriteSyncTab extends ConsumerStatefulWidget {
  const AppwriteSyncTab({super.key});

  @override
  ConsumerState<AppwriteSyncTab> createState() => _AppwriteSyncTabState();
}

class _AppwriteSyncTabState extends ConsumerState<AppwriteSyncTab> {
  bool _syncEnabled = false;
  int _syncInterval = 15;
  bool _autoSyncOnConnect = true;
  bool _cacheEnabled = true;

  // ✅ أخطاء Field-Level Sync
  List<FieldSyncError> _fieldErrors = [];
  bool _isLoadingErrors = false;
  String? _errorFilterType;
  String? _errorFilterEntity;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadFieldErrors();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _syncEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;
      _syncInterval = prefs.getInt('appwrite_sync_interval') ?? 15;
      _autoSyncOnConnect =
          prefs.getBool('appwrite_auto_sync_on_connect') ?? true;
      _cacheEnabled = prefs.getBool('appwrite_cache_enabled') ?? true;
    });

    // تفعيل المزامنة التلقائية إذا كانت مفعلة
    if (_syncEnabled) {
      final manager = ref.read(ap.appwriteSyncManagerProvider);
      manager.startAutoSync(interval: Duration(minutes: _syncInterval));
    }
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
        const SizedBox(height: UIConstants.spacingLG),
        _buildFieldSyncErrorsCard(),
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
            const Row(
              children: [
                Icon(
                  Icons.sync,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'حالة المزامنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
          const Padding(
            padding: EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'إعدادات المزامنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل المزامنة التلقائية'),
            subtitle: Text(
              _syncEnabled
                  ? 'المزامنة التلقائية مفعّلة'
                  : 'المزامنة مع Appwrite معطّلة (يدوي فقط)',
            ),
            value: _syncEnabled,
            onChanged: (value) async {
              setState(() => _syncEnabled = value);
              await _saveSettings(); // حفظ الإعداد أولاً
              _onSyncEnabledChanged(value); // ثم تفعيل/إيقاف المزامنة
            },
            secondary: Icon(
              _syncEnabled ? Icons.sync : Icons.sync_disabled,
              color: _syncEnabled ? Colors.green : Colors.grey,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('فترة المزامنة'),
            subtitle: Text('$_syncInterval دقيقة'),
            leading: const Icon(Icons.timer),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            enabled: _syncEnabled,
            onTap: _syncEnabled ? _showIntervalDialog : null,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('مزامنة تلقائية عند الاتصال'),
            subtitle: Text(
              _autoSyncOnConnect
                  ? 'ستتم المزامنة تلقائياً عند الاتصال بالإنترنت'
                  : 'المزامنة عند الاتصال معطّلة',
            ),
            value: _autoSyncOnConnect,
            onChanged: _syncEnabled
                ? (value) async {
                    setState(() => _autoSyncOnConnect = value);
                    await _saveSettings();
                  }
                : null,
            secondary: Icon(
              Icons.wifi,
              color: _autoSyncOnConnect && _syncEnabled
                  ? Colors.blue
                  : Colors.grey,
            ),
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
            const Row(
              children: [
                Icon(
                  Icons.bar_chart,
                  color: Colors.green,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'إحصائيات المزامنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            Builder(
              builder: (context) {
                final width = MediaQuery.sizeOf(context).width;
                final crossAxisCount = width < 360
                    ? 1
                    : width < 600
                    ? 2
                    : 3;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
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
                );
              },
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
          const Padding(
            padding: EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.storage,
                  color: Colors.purple,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'التخزين المؤقت',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              onPressed: _clearCache,
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
            onTap: _syncNow,
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
            onTap: _showFullSyncDialog,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.bug_report, color: Colors.teal),
            ),
            title: const Text('اختبار تشخيصي'),
            subtitle: const Text('فحص الاتصال والبيانات المحلية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _runDiagnosticTest,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.cloud_upload, color: Colors.purple),
            ),
            title: const Text('رفع شامل إلى Appwrite'),
            subtitle: const Text('رفع جميع البيانات المحلية مباشرة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showFullPushDialog,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.history, color: Colors.indigo),
            ),
            title: const Text('سجل المزامنة'),
            subtitle: const Text('عرض سجلات المزامنة الناجحة والفاشلة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SyncHistoryScreen()),
            ),
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
            onTap: loadingStats ? null : _showClearHistoryDialog,
          ),
        ],
      ),
    );
  }

  void _onSyncEnabledChanged(bool enabled) {
    final manager = ref.read(ap.appwriteSyncManagerProvider);
    if (enabled) {
      manager.startAutoSync(interval: Duration(minutes: _syncInterval));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تفعيل المزامنة التلقائية كل $_syncInterval دقيقة'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      manager.stopAutoSync();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إيقاف المزامنة التلقائية'),
          backgroundColor: Colors.orange,
        ),
      );
    }
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
                if (_syncEnabled) {
                  _onSyncEnabledChanged(true);
                }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم مسح التخزين المؤقت')));
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

  void _showFullPushDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رفع شامل إلى Appwrite'),
        content: const Text(
          'سيتم رفع جميع البيانات المحلية مباشرة إلى Appwrite.\n\n'
          '⚠️ هذا سيستبدل البيانات الموجودة على السحابة.\n\n'
          'استخدم هذا الخيار عند:\n'
          '• التثبيت الأول للتطبيق\n'
          '• بعد استعادة نسخة احتياطية محلية\n'
          '• عندما لا تعمل المزامنة العادية',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _runFullPush();
            },
            child: const Text('رفع شامل'),
          ),
        ],
      ),
    );
  }

  Future<void> _runFullPush() async {
    if (!mounted) return;

    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري الرفع الشامل إلى Appwrite...'),
            SizedBox(height: 8),
            Text(
              'قد تستغرق هذه العملية عدة دقائق',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      final manager = ref.read(ap.appwriteSyncManagerProvider);
      final stats = await manager.pushAllLocalDataToAppwrite();

      ref.invalidate(ap.syncStatsProvider);

      if (!mounted) return;

      // إغلاق مؤشر التحميل
      Navigator.pop(context);

      final totalRecords = stats.entries
          .where((e) => e.key != 'errors')
          .fold<int>(0, (sum, e) => sum + (e.value));
      final errors = stats['errors'] ?? 0;

      // طباعة النتائج في console
      debugPrint('📊 نتيجة الرفع الشامل:');
      debugPrint('   إجمالي السجلات: $totalRecords');
      debugPrint('   الأخطاء: $errors');
      for (final e in stats.entries) {
        debugPrint('   ${e.key}: ${e.value}');
      }

      // إظهار النتائج
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                errors == 0 ? Icons.check_circle : Icons.warning,
                color: errors == 0 ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              const Text('نتيجة الرفع الشامل'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تم رفع $totalRecords سجل بنجاح',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (totalRecords == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '⚠️ لا توجد بيانات في قاعدة البيانات المحلية للرفع',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (errors > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'أخطاء: $errors',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'التفاصيل:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...stats.entries
                    .where((e) => e.key != 'errors')
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('• ${_translateEntity(e.key)}'),
                            Text(
                              '${e.value}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      if (!mounted) return;

      // إغلاق مؤشر التحميل في حالة الخطأ
      Navigator.pop(context);

      // طباعة الخطأ في console
      debugPrint('❌ خطأ في الرفع الشامل: $e');
      debugPrint('Stack trace: $stackTrace');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الرفع الشامل:\n$e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  String _translateEntity(String entity) {
    const translations = {
      'rooms': 'الغرف',
      'bookings': 'الحجوزات',
      'booking_notes': 'ملاحظات الحجز',
      'booking_nights': 'ليالي الحجز',
      'employees': 'الموظفين',
      'expenses': 'المصروفات',
      'cash_transactions': 'المعاملات النقدية',
      'payments': 'المدفوعات',
      'debts': 'الديون',
      'salary_cycles': 'دورات الرواتب',
      'salary_payments': 'دفعات الرواتب',
      'salary_withdrawals': 'سحوبات الرواتب',
      'shift_notes': 'ملاحظات الشيفت',
      'booking_price_adjustments': 'تعديلات الأسعار',
    };
    return translations[entity] ?? entity;
  }

  Future<void> _runDiagnosticTest() async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري إجراء الاختبار التشخيصي...'),
          ],
        ),
      ),
    );

    try {
      final database = ref.read(databaseProvider);
      final appwriteService = ref.read(ap.appwriteServiceProvider);

      // فحص البيانات المحلية
      final roomsCount = await database
          .select(database.rooms)
          .get()
          .then((l) => l.length);
      final bookingsCount = await database
          .select(database.bookings)
          .get()
          .then((l) => l.length);
      final paymentsCount = await database
          .select(database.payments)
          .get()
          .then((l) => l.length);

      debugPrint('📊 البيانات المحلية:');
      debugPrint('   الغرف: $roomsCount');
      debugPrint('   الحجوزات: $bookingsCount');
      debugPrint('   المدفوعات: $paymentsCount');

      // فحص Appwrite
      await appwriteService.initialize();
      final isInitialized = appwriteService.isInitialized;
      final projectInfo = appwriteService.getProjectInfo();

      debugPrint('🔌 حالة Appwrite:');
      debugPrint('   مُهيأ: $isInitialized');
      debugPrint('   Project ID: ${projectInfo['projectId']}');
      debugPrint('   Database ID: ${projectInfo['databaseId']}');

      // اختبار رفع غرفة واحدة
      String? testResult;
      if (roomsCount > 0) {
        try {
          final room = await database
              .select(database.rooms)
              .get()
              .then((l) => l.first);

          final payload = <String, dynamic>{
            'roomNumber': room.roomNumber,
            'type': room.type,
            'price': room.price,
            'status': room.status,
            'localUuid': room.localUuid,
            'createdAt': room.createdAt,
            'updatedAt': room.updatedAt,
            'lastModified': room.lastModified,
            'version': room.version,
            'origin': room.origin,
          };

          if (room.serverId != null) payload['serverId'] = room.serverId;
          if (room.deletedAt != null) payload['deletedAt'] = room.deletedAt;

          debugPrint('📤 اختبار رفع غرفة ${room.roomNumber}...');

          final doc = await appwriteService.upsertRoom(room.localUuid, payload);
          testResult =
              '✅ نجح رفع غرفة ${room.roomNumber}\nDocument ID: ${doc.$id}';

          debugPrint('✅ نجح الاختبار!');
        } catch (e) {
          testResult = '❌ فشل رفع الغرفة:\n$e';
          debugPrint('❌ خطأ في رفع الغرفة: $e');
        }
      }

      if (!mounted) return;
      Navigator.pop(context);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.bug_report, color: Colors.teal),
              SizedBox(width: 8),
              Text('نتيجة الاختبار التشخيصي'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '📊 البيانات المحلية:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('• الغرف: $roomsCount'),
                Text('• الحجوزات: $bookingsCount'),
                Text('• المدفوعات: $paymentsCount'),
                const SizedBox(height: 16),
                const Text(
                  '🔌 حالة Appwrite:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('• مُهيأ: ${isInitialized ? "✅ نعم" : "❌ لا"}'),
                Text('• Project ID: ${projectInfo['projectId']}'),
                Text('• Database ID: ${projectInfo['databaseId']}'),
                if (testResult != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '🧪 اختبار الرفع:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(testResult),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      if (!mounted) return;
      Navigator.pop(context);

      debugPrint('❌ خطأ في الاختبار التشخيصي: $e');
      debugPrint('Stack trace: $stackTrace');

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('فشل الاختبار'),
            ],
          ),
          content: Text('حدث خطأ:\n$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
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

  // ==========================================================================\n  // Field-Level Sync Errors - أخطاء مزامنة الحقول\n  // ==========================================================================\n\n  /// تحميل أخطاء مزامنة الحقول من SharedPreferences\n  Future<void> _loadFieldErrors() async {\n    setState(() => _isLoadingErrors = true);\n    try {\n      final errors = await AppwriteDeltaSync.getFieldSyncErrors();\n      if (mounted) {\n        setState(() {\n          _fieldErrors = errors;\n          _isLoadingErrors = false;\n        });\n      }\n    } catch (_) {\n      if (mounted) {\n        setState(() => _isLoadingErrors = false);\n      }\n    }\n  }\n\n  /// بناء بطاقة أخطاء مزامنة الحقول\n  Widget _buildFieldSyncErrorsCard() {\n    // تطبيق الفلاتر\n    final filteredErrors = _fieldErrors.where((e) {\n      if (_errorFilterType != null && e.errorType != _errorFilterType) {\n        return false;\n      }\n      if (_errorFilterEntity != null && e.entityName != _errorFilterEntity) {\n        return false;\n      }\n      return true;\n    }).toList();\n\n    // تجميع الأخطاء حسب الجدول\n    final errorsByEntity = <String, int>{};\n    for (final e in _fieldErrors) {\n      errorsByEntity[e.entityName] =\n          (errorsByEntity[e.entityName] ?? 0) + 1;\n    }\n\n    // تجميع الأخطاء حسب النوع\n    final errorsByType = <String, int>{};\n    for (final e in _fieldErrors) {\n      errorsByType[e.errorType] = (errorsByType[e.errorType] ?? 0) + 1;\n    }\n\n    // ألوان أنواع الأخطاء\n    final errorTypeColors = {\n      'network': Colors.orange,\n      'validation': Colors.red,\n      'not_found': Colors.amber,\n      'permission': Colors.purple,\n      'timeout': Colors.deepOrange,\n      'data_mismatch': Colors.redAccent,\n      'unknown': Colors.grey,\n    };\n\n    return Card(\n      elevation: 2,\n      shape: RoundedRectangleBorder(\n        borderRadius: BorderRadius.circular(UIConstants.radiusLG),\n        side: BorderSide(\n          color: _fieldErrors.isEmpty\n              ? Colors.green.withOpacity(0.3)\n              : Colors.red.withOpacity(0.5),\n          width: 1.5,\n        ),\n      ),\n      child: Column(\n        crossAxisAlignment: CrossAxisAlignment.start,\n        children: [\n          // Header مع عداد وزر تحديث ومسح\n          Padding(\n            padding: const EdgeInsets.all(UIConstants.spacingMD),\n            child: Row(\n              children: [\n                Icon(\n                  _fieldErrors.isEmpty\n                      ? Icons.check_circle_outline\n                      : Icons.error_outline,\n                  color: _fieldErrors.isEmpty ? Colors.green : Colors.red,\n                  size: UIConstants.iconSizeMD,\n                ),\n                const SizedBox(width: UIConstants.spacingSM),\n                Expanded(\n                  child: Text(\n                    'أخطاء مزامنة الحقول',\n                    style: const TextStyle(\n                      fontSize: 18,\n                      fontWeight: FontWeight.bold,\n                    ),\n                  ),\n                ),\n                // زر تحديث\n                if (!_isLoadingErrors)\n                  IconButton(\n                    onPressed: _loadFieldErrors,\n                    icon: const Icon(Icons.refresh, size: 20),\n                    tooltip: 'تحديث',\n                    padding: EdgeInsets.zero,\n                    constraints: const BoxConstraints(\n                      minWidth: 32,\n                      minHeight: 32,\n                    ),\n                  ),\n                if (_fieldErrors.isNotEmpty)\n                  IconButton(\n                    onPressed: _showClearErrorsDialog,\n                    icon: const Icon(Icons.delete_sweep, size: 20),\n                    tooltip: 'مسح الأخطاء',\n                    padding: EdgeInsets.zero,\n                    constraints: const BoxConstraints(\n                      minWidth: 32,\n                      minHeight: 32,\n                    ),\n                  ),\n              ],\n            ),\n          ),\n\n          // حالة التحميل\n          if (_isLoadingErrors)\n            const Padding(\n              padding: EdgeInsets.all(UIConstants.spacingLG),\n              child: Center(\n                child: CircularProgressIndicator(strokeWidth: 2),\n              ),\n            )\n          // لا توجد أخطاء\n          else if (_fieldErrors.isEmpty)\n            Padding(\n              padding: const EdgeInsets.symmetric(\n                horizontal: UIConstants.spacingMD,\n                vertical: UIConstants.spacingSM,\n              ),\n              child: Container(\n                padding: const EdgeInsets.all(12),\n                decoration: BoxDecoration(\n                  color: Colors.green.withOpacity(0.08),\n                  borderRadius: BorderRadius.circular(12),\n                ),\n                child: const Row(\n                  children: [\n                    Icon(Icons.check_circle, color: Colors.green, size: 20),\n                    SizedBox(width: 10),\n                    Expanded(\n                      child: Text(\n                        'لا توجد أخطاء في مزامنة الحقول',\n                        style: TextStyle(\n                          color: Colors.green,\n                          fontWeight: FontWeight.w500,\n                        ),\n                      ),\n                    ),\n                  ],\n                ),\n              ),\n            )\n          else ...[\n            // ملخص سريع\n            Padding(\n              padding: const EdgeInsets.symmetric(\n                horizontal: UIConstants.spacingMD,\n              ),\n              child: Text(\n                '${_fieldErrors.length} خطأ مسجل - عرض ${filteredErrors.length}',\n                style: TextStyle(\n                  fontSize: 12,\n                  color: Colors.grey.shade600,\n                ),\n              ),\n            ),\n            const SizedBox(height: 8),\n\n            // أشرطة الفلترة حسب نوع الخطأ\n            SizedBox(\n              height: 36,\n              child: ListView(\n                scrollDirection: Axis.horizontal,\n                padding: const EdgeInsets.symmetric(\n                  horizontal: UIConstants.spacingSM,\n                ),\n                children: [\n                  // زر \"الكل\"\n                  _buildFilterChip(\n                    label: 'الكل',\n                    count: _fieldErrors.length,\n                    isSelected: _errorFilterType == null,\n                    selectedColor: Colors.blue,\n                    onTap: () {\n                      setState(() => _errorFilterType = null);\n                    },\n                  ),\n                  // أشرطة حسب النوع\n                  ...errorsByType.entries.map((entry) {\n                    final color = errorTypeColors[entry.key] ?? Colors.grey;\n                    return _buildFilterChip(\n                      label: _translateErrorType(entry.key),\n                      count: entry.value,\n                      isSelected: _errorFilterType == entry.key,\n                      selectedColor: color,\n                      onTap: () {\n                        setState(() {\n                          _errorFilterType = _errorFilterType == entry.key\n                              ? null\n                              : entry.key;\n                        });\n                      },\n                    );\n                  }),\n                ],\n              ),\n            ),\n\n            // أشرطة الفلترة حسب الجدول\n            if (errorsByEntity.length > 1) ...[\n              const SizedBox(height: 6),\n              SizedBox(\n                height: 36,\n                child: ListView(\n                  scrollDirection: Axis.horizontal,\n                  padding: const EdgeInsets.symmetric(\n                    horizontal: UIConstants.spacingSM,\n                  ),\n                  children: [\n                    _buildFilterChip(\n                      label: 'كل الجداول',\n                      count: _fieldErrors.length,\n                      isSelected: _errorFilterEntity == null,\n                      selectedColor: Colors.teal,\n                      onTap: () {\n                        setState(() => _errorFilterEntity = null);\n                      },\n                    ),\n                    ...errorsByEntity.entries.map((entry) {\n                      return _buildFilterChip(\n                        label: _translateEntity(entry.key),\n                        count: entry.value,\n                        isSelected: _errorFilterEntity == entry.key,\n                        selectedColor: Colors.teal,\n                        onTap: () {\n                          setState(() {\n                            _errorFilterEntity =\n                                _errorFilterEntity == entry.key\n                                    ? null\n                                    : entry.key;\n                          });\n                        },\n                      );\n                    }),\n                  ],\n                ),\n              ),\n            ],\n\n            const Divider(height: 1),\n\n            // قائمة الأخطاء\n            if (filteredErrors.isEmpty)\n              Padding(\n                padding: const EdgeInsets.all(UIConstants.spacingLG),\n                child: Center(\n                  child: Text(\n                    'لا توجد أخطاء تطابق الفلتر المحدد',\n                    style: TextStyle(\n                      fontSize: 13,\n                      color: Colors.grey.shade500,\n                    ),\n                  ),\n                ),\n              )\n          else\n            ...filteredErrors.take(20).map((error) {\n              final errorColor =\n                  errorTypeColors[error.errorType] ?? Colors.grey;\n              return _buildErrorItem(error, errorColor);\n            }),\n\n          // عرض \"عرض المزيد\" إذا كان هناك أكثر من 20 خطأ\n          if (filteredErrors.length > 20)\n            Padding(\n              padding: const EdgeInsets.all(UIConstants.spacingSM),\n              child: Center(\n                child: Text(\n                  'وأكثر... (إجمالي ${filteredErrors.length} خطأ)',\n                  style: TextStyle(\n                    fontSize: 12,\n                    color: Colors.grey.shade500,\n                  ),\n                ),\n              ),\n            ),\n          ],\n\n          const SizedBox(height: 8),\n        ],\n      ),\n    );\n  }\n\n  /// بناء شريحة فلتر\n  Widget _buildFilterChip({\n    required String label,\n    required int count,\n    required bool isSelected,\n    required Color selectedColor,\n    required VoidCallback onTap,\n  }) {\n    return Padding(\n      padding: const EdgeInsets.only(left: 6),\n      child: ActionChip(\n        label: Row(\n          mainAxisSize: MainAxisSize.min,\n          children: [\n            Text(label, style: const TextStyle(fontSize: 11)),\n            const SizedBox(width: 4),\n            Container(\n              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),\n              decoration: BoxDecoration(\n                color: isSelected\n                    ? selectedColor.withOpacity(0.2)\n                    : Colors.grey.shade200,\n                borderRadius: BorderRadius.circular(8),\n              ),\n              child: Text(\n                '$count',\n                style: TextStyle(\n                  fontSize: 10,\n                  fontWeight: FontWeight.bold,\n                  color: isSelected ? selectedColor : Colors.grey.shade600,\n                ),\n              ),\n            ),\n          ],\n        ),\n        onPressed: onTap,\n        backgroundColor: isSelected\n            ? selectedColor.withOpacity(0.12)\n            : Colors.grey.shade100,\n        side: BorderSide(\n          color: isSelected ? selectedColor : Colors.grey.shade300,\n          width: 1,\n        ),\n        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),\n        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,\n      ),\n    );\n  }\n\n  /// بناء عنصر خطأ واحد\n  Widget _buildErrorItem(FieldSyncError error, Color errorColor) {\n    final timeStr = error.timestamp > 0\n        ? DateTime.fromMillisecondsSinceEpoch(error.timestamp * 1000)\n        : null;\n    final timeLabel = timeStr != null\n        ? '${timeStr.hour.toString().padLeft(2, '0')}:${timeStr.minute.toString().padLeft(2, '0')}'\n        : '';\n\n    return InkWell(\n      onTap: () => _showErrorDetailDialog(error),\n      child: Padding(\n        padding: const EdgeInsets.symmetric(\n          horizontal: UIConstants.spacingMD,\n          vertical: 6,\n        ),\n        child: Row(\n          crossAxisAlignment: CrossAxisAlignment.start,\n          children: [\n            // أيقونة نوع الخطأ\n            Container(\n              margin: const EdgeInsets.only(top: 2),\n              padding: const EdgeInsets.all(4),\n              decoration: BoxDecoration(\n                color: errorColor.withOpacity(0.12),\n                borderRadius: BorderRadius.circular(6),\n              ),\n              child: Icon(\n                _getErrorIcon(error.errorType),\n                size: 14,\n                color: errorColor,\n              ),\n            ),\n            const SizedBox(width: 10),\n\n            // محتوى الخطأ\n            Expanded(\n              child: Column(\n                crossAxisAlignment: CrossAxisAlignment.start,\n                children: [\n                  // السطر الأول: الجدول والحقل\n                  Row(\n                    children: [\n                      Container(\n                        padding: const EdgeInsets.symmetric(\n                          horizontal: 6,\n                          vertical: 2,\n                        ),\n                        decoration: BoxDecoration(\n                          color: Colors.blue.shade50,\n                          borderRadius: BorderRadius.circular(4),\n                        ),\n                        child: Text(\n                          _translateEntity(error.entityName),\n                          style: TextStyle(\n                            fontSize: 11,\n                            fontWeight: FontWeight.w600,\n                            color: Colors.blue.shade800,\n                          ),\n                        ),\n                      ),\n                      const SizedBox(width: 6),\n                      if (error.fieldName.isNotEmpty &&\n                          error.fieldName != 'general')\n                        Container(\n                          padding: const EdgeInsets.symmetric(\n                            horizontal: 6,\n                            vertical: 2,\n                          ),\n                          decoration: BoxDecoration(\n                            color: Colors.purple.shade50,\n                            borderRadius: BorderRadius.circular(4),\n                          ),\n                          child: Text(\n                            error.fieldName,\n                            style: TextStyle(\n                              fontSize: 11,\n                              fontWeight: FontWeight.w500,\n                              color: Colors.purple.shade800,\n                            ),\n                          ),\n                        ),\n                    ],\n                  ),\n                  const SizedBox(height: 3),\n\n                  // السطر الثاني: نوع الخطأ والوقت\n                  Row(\n                    children: [\n                      Container(\n                        padding: const EdgeInsets.symmetric(\n                          horizontal: 6,\n                          vertical: 1,\n                        ),\n                        decoration: BoxDecoration(\n                          color: errorColor.withOpacity(0.1),\n                          borderRadius: BorderRadius.circular(4),\n                        ),\n                        child: Text(\n                          error.errorTypeAr,\n                          style: TextStyle(\n                            fontSize: 10,\n                            fontWeight: FontWeight.bold,\n                            color: errorColor,\n                          ),\n                        ),\n                      ),\n                      if (timeLabel.isNotEmpty) ...[\n                        const SizedBox(width: 8),\n                        Text(\n                          timeLabel,\n                          style: TextStyle(\n                            fontSize: 10,\n                            color: Colors.grey.shade500,\n                          ),\n                        ),\n                      ],\n                    ],\n                  ),\n                ],\n              ),\n            ),\n\n            // سهم التفاصيل\n            Icon(\n              Icons.chevron_left,\n              size: 16,\n              color: Colors.grey.shade400,\n            ),\n          ],\n        ),\n      ),\n    );\n  }\n\n  /// أيقونة نوع الخطأ\n  IconData _getErrorIcon(String errorType) {\n    switch (errorType) {\n      case 'network':\n        return Icons.wifi_off;\n      case 'validation':\n        return Icons.rule;\n      case 'not_found':\n        return Icons.search_off;\n      case 'permission':\n        return Icons.lock;\n      case 'timeout':\n        return Icons.timer_off;\n      case 'data_mismatch':\n        return Icons.compare_arrows;\n      default:\n        return Icons.help_outline;\n    }\n  }\n\n  /// ترجمة نوع الخطأ\n  String _translateErrorType(String type) {\n    switch (type) {\n      case 'network':\n        return 'شبكة';\n      case 'validation':\n        return 'تحقق';\n      case 'not_found':\n        return 'غير موجود';\n      case 'permission':\n        return 'صلاحية';\n      case 'timeout':\n        return 'مهلة';\n      case 'data_mismatch':\n        return 'تضارب';\n      default:\n        return 'أخرى';\n    }\n  }\n\n  /// عرض تفاصيل خطأ واحد\n  void _showErrorDetailDialog(FieldSyncError error) {\n    final timeStr = error.timestamp > 0\n        ? DateTime.fromMillisecondsSinceEpoch(error.timestamp * 1000)\n            .toString()\n            .substring(0, 19)\n        : 'غير معروف';\n\n    showDialog(\n      context: context,\n      builder: (ctx) => AlertDialog(\n        title: const Row(\n          children: [\n            Icon(Icons.error_outline, color: Colors.red),\n            SizedBox(width: 8),\n            Text('تفاصيل الخطأ'),\n          ],\n        ),\n        content: SingleChildScrollView(\n          child: Column(\n            crossAxisAlignment: CrossAxisAlignment.start,\n            mainAxisSize: MainAxisSize.min,\n            children: [\n              _buildDetailRow('الجدول', _translateEntity(error.entityName)),\n              _buildDetailRow('الحقل', error.fieldName),\n              _buildDetailRow('نوع الخطأ', error.errorTypeAr),\n              _buildDetailRow('العملية', error.operation),\n              _buildDetailRow('الوقت', timeStr),\n              if (error.recordUuid.isNotEmpty)\n                _buildDetailRow(\n                  'رقم السجل',\n                  error.recordUuid.length > 12\n                      ? '${error.recordUuid.substring(0, 12)}...'\n                      : error.recordUuid,\n                ),\n              const Divider(),\n              const Text(\n                'رسالة الخطأ:',\n                style: TextStyle(fontWeight: FontWeight.bold),\n              ),\n              const SizedBox(height: 4),\n              Container(\n                padding: const EdgeInsets.all(8),\n                decoration: BoxDecoration(\n                  color: Colors.red.shade50,\n                  borderRadius: BorderRadius.circular(8),\n                ),\n                child: SelectableText(\n                  error.errorMessage,\n                  style: const TextStyle(\n                    fontSize: 12,\n                    fontFamily: 'monospace',\n                  ),\n                ),\n              ),\n            ],\n          ),\n        ),\n        actions: [\n          TextButton(\n            onPressed: () => Navigator.pop(ctx),\n            child: const Text('حسناً'),\n          ),\n        ],\n      ),\n    );\n  }\n\n  /// صف تفصيلي في نافذة التفاصيل\n  Widget _buildDetailRow(String label, String value) {\n    return Padding(\n      padding: const EdgeInsets.symmetric(vertical: 3),\n      child: Row(\n        crossAxisAlignment: CrossAxisAlignment.start,\n        children: [\n          SizedBox(\n            width: 80,\n            child: Text(\n              '$label:',\n              style: TextStyle(\n                fontSize: 13,\n                fontWeight: FontWeight.w600,\n                color: Colors.grey.shade700,\n              ),\n            ),\n          ),\n          Expanded(\n            child: Text(\n              value,\n              style: const TextStyle(fontSize: 13),\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n\n  /// تأكيد مسح الأخطاء\n  void _showClearErrorsDialog() {\n    showDialog(\n      context: context,\n      builder: (ctx) => AlertDialog(\n        title: const Row(\n          children: [\n            Icon(Icons.delete_sweep, color: Colors.orange),\n            SizedBox(width: 8),\n            Text('مسح أخطاء المزامنة'),\n          ],\n        ),\n        content: Text(\n          'سيتم حذف جميع سجلات أخطاء مزامنة الحقول (${_fieldErrors.length} خطأ).'\n          ' هذا الإجراء لا يمكن التراجع عنه.',\n        ),\n        actions: [\n          TextButton(\n            onPressed: () => Navigator.pop(ctx),\n            child: const Text('إلغاء'),\n          ),\n          ElevatedButton(\n            onPressed: () async {\n              Navigator.pop(ctx);\n              await AppwriteDeltaSync.clearFieldSyncErrors();\n              _loadFieldErrors();\n              if (mounted) {\n                ScaffoldMessenger.of(context).showSnackBar(\n                  const SnackBar(\n                    content: Text('تم مسح أخطاء المزامنة'),\n                    backgroundColor: Colors.green,\n                  ),\n                );\n              }\n            },\n            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),\n            child: const Text(\n              'مسح',\n              style: TextStyle(color: Colors.white),\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n\n  String _nextSyncLabel(String? lastSyncTime) {
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
