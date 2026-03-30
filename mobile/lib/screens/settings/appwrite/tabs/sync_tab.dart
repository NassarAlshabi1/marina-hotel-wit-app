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

  // ==========================================================================
  // Field-Level Sync Errors - أخطاء مزامنة الحقول
  // ==========================================================================

  /// تحميل أخطاء مزامنة الحقول من SharedPreferences
  Future<void> _loadFieldErrors() async {
    setState(() => _isLoadingErrors = true);
    try {
      final errors = await AppwriteDeltaSync.getFieldSyncErrors();
      if (mounted) {
        setState(() {
          _fieldErrors = errors;
          _isLoadingErrors = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingErrors = false);
      }
    }
  }

  /// بناء بطاقة أخطاء مزامنة الحقول
  Widget _buildFieldSyncErrorsCard() {
    // تطبيق الفلاتر
    final filteredErrors = _fieldErrors.where((e) {
      if (_errorFilterType != null && e.errorType != _errorFilterType) {
        return false;
      }
      if (_errorFilterEntity != null && e.entityName != _errorFilterEntity) {
        return false;
      }
      return true;
    }).toList();

    // تجميع الأخطاء حسب الجدول
    final errorsByEntity = <String, int>{};
    for (final e in _fieldErrors) {
      errorsByEntity[e.entityName] = (errorsByEntity[e.entityName] ?? 0) + 1;
    }

    // تجميع الأخطاء حسب النوع
    final errorsByType = <String, int>{};
    for (final e in _fieldErrors) {
      errorsByType[e.errorType] = (errorsByType[e.errorType] ?? 0) + 1;
    }

    // ألوان أنواع الأخطاء
    final errorTypeColors = {
      'network': Colors.orange,
      'validation': Colors.red,
      'not_found': Colors.amber,
      'permission': Colors.purple,
      'timeout': Colors.deepOrange,
      'data_mismatch': Colors.redAccent,
      'unknown': Colors.grey,
    };

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
        side: BorderSide(
          color: _fieldErrors.isEmpty
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header مع عداد وزر تحديث ومسح
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  _fieldErrors.isEmpty
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: _fieldErrors.isEmpty ? Colors.green : Colors.red,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                Expanded(
                  child: Text(
                    'أخطاء مزامنة الحقول',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // زر تحديث
                if (!_isLoadingErrors)
                  IconButton(
                    onPressed: _loadFieldErrors,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'تحديث',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                if (_fieldErrors.isNotEmpty)
                  IconButton(
                    onPressed: _showClearErrorsDialog,
                    icon: const Icon(Icons.delete_sweep, size: 20),
                    tooltip: 'مسح الأخطاء',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
              ],
            ),
          ),

          // حالة التحميل
          if (_isLoadingErrors)
            const Padding(
              padding: EdgeInsets.all(UIConstants.spacingLG),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          // لا توجد أخطاء
          else if (_fieldErrors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: UIConstants.spacingMD,
                vertical: UIConstants.spacingSM,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'لا توجد أخطاء في مزامنة الحقول',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // ملخص سريع
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: UIConstants.spacingMD,
              ),
              child: Text(
                '${_fieldErrors.length} خطأ مسجل - عرض ${filteredErrors.length}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),

            // أشرطة الفلترة حسب نوع الخطأ
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: UIConstants.spacingSM,
                ),
                children: [
                  // زر \"الكل\"
                  _buildFilterChip(
                    label: 'الكل',
                    count: _fieldErrors.length,
                    isSelected: _errorFilterType == null,
                    selectedColor: Colors.blue,
                    onTap: () {
                      setState(() => _errorFilterType = null);
                    },
                  ),
                  // أشرطة حسب النوع
                  ...errorsByType.entries.map((entry) {
                    final color = errorTypeColors[entry.key] ?? Colors.grey;
                    return _buildFilterChip(
                      label: _translateErrorType(entry.key),
                      count: entry.value,
                      isSelected: _errorFilterType == entry.key,
                      selectedColor: color,
                      onTap: () {
                        setState(() {
                          _errorFilterType = _errorFilterType == entry.key
                              ? null
                              : entry.key;
                        });
                      },
                    );
                  }),
                ],
              ),
            ),

            // أشرطة الفلترة حسب الجدول
            if (errorsByEntity.length > 1) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: UIConstants.spacingSM,
                  ),
                  children: [
                    _buildFilterChip(
                      label: 'كل الجداول',
                      count: _fieldErrors.length,
                      isSelected: _errorFilterEntity == null,
                      selectedColor: Colors.teal,
                      onTap: () {
                        setState(() => _errorFilterEntity = null);
                      },
                    ),
                    ...errorsByEntity.entries.map((entry) {
                      return _buildFilterChip(
                        label: _translateEntity(entry.key),
                        count: entry.value,
                        isSelected: _errorFilterEntity == entry.key,
                        selectedColor: Colors.teal,
                        onTap: () {
                          setState(() {
                            _errorFilterEntity = _errorFilterEntity == entry.key
                                ? null
                                : entry.key;
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],

            const Divider(height: 1),

            // قائمة الأخطاء
            if (filteredErrors.isEmpty)
              Padding(
                padding: const EdgeInsets.all(UIConstants.spacingLG),
                child: Center(
                  child: Text(
                    'لا توجد أخطاء تطابق الفلتر المحدد',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              ...filteredErrors.take(20).map((error) {
                final errorColor =
                    errorTypeColors[error.errorType] ?? Colors.grey;
                return _buildErrorItem(error, errorColor);
              }),

            // عرض \"عرض المزيد\" إذا كان هناك أكثر من 20 خطأ
            if (filteredErrors.length > 20)
              Padding(
                padding: const EdgeInsets.all(UIConstants.spacingSM),
                child: Center(
                  child: Text(
                    'وأكثر... (إجمالي ${filteredErrors.length} خطأ)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// بناء شريحة فلتر
  Widget _buildFilterChip({
    required String label,
    required int count,
    required bool isSelected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ActionChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? selectedColor.withOpacity(0.2)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? selectedColor : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        onPressed: onTap,
        backgroundColor: isSelected
            ? selectedColor.withOpacity(0.12)
            : Colors.grey.shade100,
        side: BorderSide(
          color: isSelected ? selectedColor : Colors.grey.shade300,
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// بناء عنصر خطأ واحد
  Widget _buildErrorItem(FieldSyncError error, Color errorColor) {
    final timeStr = error.timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(error.timestamp * 1000)
        : null;
    final timeLabel = timeStr != null
        ? '${timeStr.hour.toString().padLeft(2, '0')}:${timeStr.minute.toString().padLeft(2, '0')}'
        : '';

    return InkWell(
      onTap: () => _showErrorDetailDialog(error),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UIConstants.spacingMD,
          vertical: 6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // أيقونة نوع الخطأ
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: errorColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                _getErrorIcon(error.errorType),
                size: 14,
                color: errorColor,
              ),
            ),
            const SizedBox(width: 10),

            // محتوى الخطأ
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // السطر الأول: الجدول والحقل
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _translateEntity(error.entityName),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (error.fieldName.isNotEmpty &&
                          error.fieldName != 'general')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            error.fieldName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.purple.shade800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // السطر الثاني: نوع الخطأ والوقت
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          error.errorTypeAr,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: errorColor,
                          ),
                        ),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // سهم التفاصيل
            Icon(Icons.chevron_left, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  /// أيقونة نوع الخطأ
  IconData _getErrorIcon(String errorType) {
    switch (errorType) {
      case 'network':
        return Icons.wifi_off;
      case 'validation':
        return Icons.rule;
      case 'not_found':
        return Icons.search_off;
      case 'permission':
        return Icons.lock;
      case 'timeout':
        return Icons.timer_off;
      case 'data_mismatch':
        return Icons.compare_arrows;
      default:
        return Icons.help_outline;
    }
  }

  /// ترجمة نوع الخطأ
  String _translateErrorType(String type) {
    switch (type) {
      case 'network':
        return 'شبكة';
      case 'validation':
        return 'تحقق';
      case 'not_found':
        return 'غير موجود';
      case 'permission':
        return 'صلاحية';
      case 'timeout':
        return 'مهلة';
      case 'data_mismatch':
        return 'تضارب';
      default:
        return 'أخرى';
    }
  }

  /// عرض تفاصيل خطأ واحد
  void _showErrorDetailDialog(FieldSyncError error) {
    final timeStr = error.timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            error.timestamp * 1000,
          ).toString().substring(0, 19)
        : 'غير معروف';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('تفاصيل الخطأ'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('الجدول', _translateEntity(error.entityName)),
              _buildDetailRow('الحقل', error.fieldName),
              _buildDetailRow('نوع الخطأ', error.errorTypeAr),
              _buildDetailRow('العملية', error.operation),
              _buildDetailRow('الوقت', timeStr),
              if (error.recordUuid.isNotEmpty)
                _buildDetailRow(
                  'رقم السجل',
                  error.recordUuid.length > 12
                      ? '${error.recordUuid.substring(0, 12)}...'
                      : error.recordUuid,
                ),
              const Divider(),
              const Text(
                'رسالة الخطأ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  error.errorMessage,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  /// صف تفصيلي في نافذة التفاصيل
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// تأكيد مسح الأخطاء
  void _showClearErrorsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.orange),
            SizedBox(width: 8),
            Text('مسح أخطاء المزامنة'),
          ],
        ),
        content: Text(
          'سيتم حذف جميع سجلات أخطاء مزامنة الحقول (${_fieldErrors.length} خطأ).'
          ' هذا الإجراء لا يمكن التراجع عنه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AppwriteDeltaSync.clearFieldSyncErrors();
              _loadFieldErrors();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم مسح أخطاء المزامنة'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
