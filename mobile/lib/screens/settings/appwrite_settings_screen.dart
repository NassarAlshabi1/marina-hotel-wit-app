import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart' as ap;
import '../../services/restore_fix_service.dart';
import '../../services/local_db.dart';
import 'appwrite_logs_screen.dart';
import 'appwrite_sync_stats_screen.dart';

class AppwriteSettingsScreen extends ConsumerStatefulWidget {
  const AppwriteSettingsScreen({super.key});

  @override
  ConsumerState<AppwriteSettingsScreen> createState() =>
      _AppwriteSettingsScreenState();
}

class _AppwriteSettingsScreenState
    extends ConsumerState<AppwriteSettingsScreen> {
  bool _syncEnabled = false;
  int _syncInterval = 15;
  bool _autoSyncOnConnect = true;
  bool _cacheEnabled = true;
  int _cacheTTLHours = 6;
  int _cacheMaxSizeMB = 20;
  String _logLevel = 'info';
  bool _logConsole = true;
  bool _logFile = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkConnection();
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
      _cacheTTLHours = prefs.getInt('appwrite_cache_ttl') ?? 6;
      _cacheMaxSizeMB = prefs.getInt('appwrite_cache_max_size') ?? 20;
      _logLevel = prefs.getString('appwrite_log_level') ?? 'info';
      _logConsole = prefs.getBool('appwrite_log_console') ?? true;
      _logFile = prefs.getBool('appwrite_log_file') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appwrite_sync_enabled', _syncEnabled);
    await prefs.setInt('appwrite_sync_interval', _syncInterval);
    await prefs.setBool('appwrite_auto_sync_on_connect', _autoSyncOnConnect);
    await prefs.setBool('appwrite_cache_enabled', _cacheEnabled);
    await prefs.setInt('appwrite_cache_ttl', _cacheTTLHours);
    await prefs.setInt('appwrite_cache_max_size', _cacheMaxSizeMB);
    await prefs.setString('appwrite_log_level', _logLevel);
    await prefs.setBool('appwrite_log_console', _logConsole);
    await prefs.setBool('appwrite_log_file', _logFile);
  }

  Future<void> _checkConnection() async {
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(ap.connectionStatusProvider);
    final syncStatsAsync = ref.watch(ap.syncStatsProvider);
    final cacheStats = ref.watch(ap.cacheStatsProvider);
    final logStats = ref.watch(ap.logStatsProvider);
    final projectInfo = ref.watch(ap.projectInfoProvider);
    final devicesAsync = ref.watch(ap.devicesListProvider);

    return AppScaffold(
      title: 'إعدادات Appwrite',
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkConnection();
          ref.invalidate(ap.syncStatsProvider);
          ref.invalidate(ap.devicesListProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // قسم حالة الاتصال
            _buildConnectionSection(context, connectionState, projectInfo),
            const SizedBox(height: 16),

            // قسم المزامنة
            _buildSyncSection(context, syncStatsAsync),
            const SizedBox(height: 16),

            // قسم التخزين المؤقت
            _buildCacheSection(context, cacheStats),
            const SizedBox(height: 16),

            // قسم السجلات
            _buildLogsSection(context, logStats),
            const SizedBox(height: 16),

            // قسم الأجهزة المسجلة
            _buildDevicesSection(context, devicesAsync),
            const SizedBox(height: 16),

            // قسم إدارة البيانات
            _buildDataManagementSection(context),
            const SizedBox(height: 16),

            // قسم الاختبارات
            _buildTestingSection(context),
          ],
        ),
      ),
    );
  }

  // ==================== قسم حالة الاتصال ====================
  Widget _buildConnectionSection(
    BuildContext context,
    ap.ConnectionState state,
    Map<String, String> info,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.cloud, color: Colors.blue, size: 24),
                SizedBox(width: 8),
                Text(
                  'حالة الاتصال',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // مؤشر الحالة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: state.isConnected
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: state.isConnected ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    state.isConnected ? Icons.check_circle : Icons.error,
                    color: state.isConnected ? Colors.green : Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.isConnected ? 'متصل بنجاح' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                state.isConnected ? Colors.green : Colors.red,
                          ),
                        ),
                        if (state.errorMessage != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            state.errorMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // معلومات المشروع
            _buildInfoRow('Endpoint', info['endpoint'] ?? '---'),
            _buildInfoRow('Project ID', info['projectId'] ?? '---'),
            _buildInfoRow('Database ID', info['databaseId'] ?? '---'),

            const SizedBox(height: 12),

            // زر اختبار الاتصال
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isChecking ? null : _checkConnection,
                icon: state.isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  state.isChecking ? 'جاري الفحص...' : 'اختبار الاتصال',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== قسم المزامنة ====================
  Widget _buildSyncSection(
    BuildContext context,
    AsyncValue<Map<String, dynamic>> statsAsync,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.sync, color: Colors.cyan, size: 24),
                SizedBox(width: 8),
                Text(
                  'إعدادات المزامنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // تفعيل المزامنة
            _buildSettingSwitch(
              title: 'تفعيل المزامنة التلقائية',
              subtitle: 'المزامنة التلقائية معطّلة (يدوي فقط)',
              value: false,
              onChanged: null,
            ),

            // فترة المزامنة
            ListTile(
              title: const Text('فترة المزامنة الدورية'),
              subtitle: Text('كل $_syncInterval دقيقة'),
              trailing: DropdownButton<int>(
                value: _syncInterval,
                items: [5, 10, 15, 30, 60].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value دقيقة'),
                  );
                }).toList(),
                onChanged: null,
              ),
            ),

            // مزامنة عند الاتصال
            _buildSettingSwitch(
              title: 'مزامنة عند الاتصال التلقائي',
              subtitle: 'المزامنة التلقائية معطّلة',
              value: false,
              onChanged: null,
            ),

            const Divider(height: 24),

            // إحصائيات المزامنة
            statsAsync.when(
              data: (stats) => _buildSyncStats(context, stats),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Text('خطأ: $e', style: const TextStyle(color: Colors.red)),
            ),

            const SizedBox(height: 12),

            // أزرار المزامنة
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _syncNow,
                    icon: const Icon(Icons.sync),
                    label: const Text('مزامنة الآن'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AppwriteSyncStatsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.analytics),
                    label: const Text('التفاصيل'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStats(BuildContext context, Map<String, dynamic> stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'إجمالي',
                value: '${stats['totalSyncs'] ?? 0}',
                icon: Icons.sync_alt,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                title: 'ناجح',
                value: '${stats['successfulSyncs'] ?? 0}',
                icon: Icons.check_circle,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                title: 'فشل',
                value: '${stats['failedSyncs'] ?? 0}',
                icon: Icons.error,
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'رفع',
                value: '${stats['totalRecordsPushed'] ?? 0}',
                icon: Icons.upload,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                title: 'تحميل',
                value: '${stats['totalRecordsPulled'] ?? 0}',
                icon: Icons.download,
                color: Colors.purple,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                title: 'تضارب',
                value: '${stats['totalConflicts'] ?? 0}',
                icon: Icons.warning,
                color: Colors.amber,
              ),
            ),
          ],
        ),
        if (stats['lastSyncTime'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'آخر مزامنة: ${_formatDateTime(stats['lastSyncTime'])}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  // ==================== قسم التخزين المؤقت ====================
  Widget _buildCacheSection(BuildContext context, cacheStats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.storage, color: Colors.purple, size: 24),
                SizedBox(width: 8),
                Text(
                  'إعدادات التخزين المؤقت',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // تفعيل التخزين المؤقت
            _buildSettingSwitch(
              title: 'تفعيل التخزين المؤقت',
              subtitle: 'تحسين الأداء وتقليل استهلاك البيانات',
              value: _cacheEnabled,
              onChanged: (value) {
                setState(() => _cacheEnabled = value);
                _saveSettings();
                ref.read(ap.appwriteCacheManagerProvider).setEnabled(value);
              },
            ),

            // مدة الصلاحية
            ListTile(
              title: const Text('مدة صلاحية البيانات'),
              subtitle: Text('$_cacheTTLHours ساعة'),
              trailing: DropdownButton<int>(
                value: _cacheTTLHours,
                items: [1, 2, 6, 12, 24].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value ساعة'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _cacheTTLHours = value);
                    _saveSettings();
                    ref
                        .read(ap.appwriteCacheManagerProvider)
                        .setDefaultTTL(Duration(hours: value));
                  }
                },
              ),
            ),

            // الحد الأقصى للحجم
            ListTile(
              title: const Text('الحد الأقصى لحجم الذاكرة'),
              subtitle: Text('$_cacheMaxSizeMB ميجابايت'),
              trailing: DropdownButton<int>(
                value: _cacheMaxSizeMB,
                items: [5, 10, 20, 50, 100].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value MB'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _cacheMaxSizeMB = value);
                    _saveSettings();
                    ref
                        .read(ap.appwriteCacheManagerProvider)
                        .setMaxSizeMB(value);
                  }
                },
              ),
            ),

            const Divider(height: 24),

            // إحصائيات الذاكرة المؤقتة
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'العناصر',
                    value: '${cacheStats.validEntries}',
                    icon: Icons.inventory_2,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    title: 'الحجم',
                    value: '${cacheStats.totalSizeMB} MB',
                    icon: Icons.data_usage,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    title: 'الاستخدام',
                    value: '${cacheStats.usagePercentage.toStringAsFixed(0)}%',
                    icon: Icons.pie_chart,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // زر مسح الذاكرة المؤقتة
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _clearCache,
                icon: const Icon(Icons.delete_sweep),
                label: const Text('مسح الذاكرة المؤقتة'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== قسم السجلات ====================
  Widget _buildLogsSection(BuildContext context, Map<String, int> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.article, color: Colors.green, size: 24),
                SizedBox(width: 8),
                Text(
                  'إعدادات السجلات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // مستوى التسجيل
            ListTile(
              title: const Text('مستوى التسجيل'),
              subtitle: Text(_logLevel.toUpperCase()),
              trailing: DropdownButton<String>(
                value: _logLevel,
                items: ['debug', 'info', 'warning', 'error', 'critical'].map((
                  String value,
                ) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _logLevel = value);
                    _saveSettings();
                  }
                },
              ),
            ),

            // تسجيل في Console
            _buildSettingSwitch(
              title: 'تسجيل في Console',
              subtitle: 'عرض السجلات في وحدة التحكم',
              value: _logConsole,
              onChanged: (value) {
                setState(() => _logConsole = value);
                _saveSettings();
              },
            ),

            // تسجيل في الملفات
            _buildSettingSwitch(
              title: 'تسجيل في الملفات',
              subtitle: 'حفظ السجلات في ملفات نصية',
              value: _logFile,
              onChanged: (value) {
                setState(() => _logFile = value);
                _saveSettings();
              },
            ),

            const Divider(height: 24),

            // إحصائيات السجلات
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'الإجمالي',
                    value: '${stats['total'] ?? 0}',
                    icon: Icons.article,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    title: 'أخطاء',
                    value: '${stats['error'] ?? 0}',
                    icon: Icons.error,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    title: 'تحذيرات',
                    value: '${stats['warning'] ?? 0}',
                    icon: Icons.warning,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // أزرار السجلات
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AppwriteLogsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.visibility),
                    label: const Text('عرض السجلات'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _exportLogs,
                    icon: const Icon(Icons.file_download),
                    label: const Text('تصدير'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _clearLogs,
                    icon: const Icon(Icons.delete),
                    label: const Text('مسح'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
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

  // ==================== قسم الأجهزة المسجلة ====================
  Widget _buildDevicesSection(BuildContext context, AsyncValue devicesAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.devices, color: Colors.teal, size: 24),
                SizedBox(width: 8),
                Text(
                  'الأجهزة المسجلة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            devicesAsync.when(
              data: (devices) {
                if (devices.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('لا توجد أجهزة مسجلة'),
                    ),
                  );
                }
                return Column(
                  children: devices.map<Widget>((device) {
                    return ListTile(
                      leading: Icon(Icons.phone_android, color: Colors.teal),
                      title: Text(device.deviceName),
                      subtitle: Text(
                        '${device.deviceModel} - ${device.osVersion}',
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: device.status == 'active'
                              ? Colors.green
                              : Colors.grey,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          device.status == 'active' ? 'نشط' : 'غير نشط',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Text('خطأ: $e', style: const TextStyle(color: Colors.red)),
            ),

            const SizedBox(height: 12),

            // زر تحديث
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(ap.devicesListProvider);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث قائمة الأجهزة'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== قسم إدارة البيانات ====================
  Widget _buildDataManagementSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.data_usage, color: Colors.indigo, size: 24),
                SizedBox(width: 8),
                Text(
                  'إدارة البيانات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDataActionCard(
              icon: Icons.cloud_upload,
              color: Colors.blue,
              title: 'رفع البيانات إلى Appwrite',
              subtitle: 'يرفع جميع البيانات المحلية إلى السحابة',
              details: const [
                'الغرف والحجوزات والمدفوعات والديون',
                'استخدام آخر نسخة محفوظة محلياً',
                'قد يستغرق وقتاً حسب حجم البيانات',
              ],
              actionLabel: 'بدء الرفع',
              onPressed: _pushAllData,
            ),
            const SizedBox(height: 12),
            _buildDataActionCard(
              icon: Icons.cloud_download,
              color: Colors.green,
              title: 'سحب البيانات من Appwrite',
              subtitle: 'يحمّل البيانات من السحابة إلى الجهاز',
              details: const [
                'قد يستبدل بعض البيانات المحلية',
                'يتطلب اتصالاً مستقراً بالإنترنت',
                'يُنصح بأخذ نسخة احتياطية قبل السحب',
              ],
              actionLabel: 'بدء السحب',
              onPressed: _pullAllData,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.restart_alt, color: Colors.orange),
              title: const Text('إعادة تعيين المزامنة'),
              subtitle: const Text('مسح حالة المزامنة والبدء من جديد'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _resetSync,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== قسم الاختبارات ====================
  Widget _buildTestingSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.science, color: Colors.deepOrange, size: 24),
                SizedBox(width: 8),
                Text(
                  'الاختبارات والتشخيص',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildActionButton(
              label: 'اختبار الاتصال',
              icon: Icons.network_check,
              onPressed: _testConnection,
            ),
            const SizedBox(height: 8),
            _buildActionButton(
              label: 'اختبار المزامنة',
              icon: Icons.sync_problem,
              onPressed: _testSync,
            ),
            const SizedBox(height: 8),
            _buildActionButton(
              label: 'اختبار الذاكرة المؤقتة',
              icon: Icons.memory,
              onPressed: _testCache,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== مكونات مساعدة ====================

  Widget _buildDataActionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required List<String> details,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 8),
          ...details.map(
            (detail) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $detail',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : onPressed,
              icon: Icon(icon),
              label: Text(actionLabel),
              style: ElevatedButton.styleFrom(backgroundColor: color),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: color != null
            ? ElevatedButton.styleFrom(backgroundColor: color)
            : null,
      ),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '---';
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (e) {
      return '---';
    }
  }

  // ==================== الأحداث ====================

  Future<void> _syncNow() async {
    setState(() => _isLoading = true);
    try {
      final syncManager = ref.read(ap.appwriteSyncManagerProvider);
      final result = await syncManager.sync();

      if (result.isSuccess && result.recordsPulled > 0) {
        final fixService = RestoreFixService(DatabaseManager.instance);
        final fixReport = await fixService.runAutoFixAfterRestore();
        debugPrint(
          'Auto-fix after sync: ${fixReport.bookingsFixed} bookings fixed',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isSuccess
                  ? 'تمت المزامنة بنجاح'
                  : 'فشلت المزامنة: ${result.errorMessage}',
            ),
            backgroundColor: result.isSuccess ? Colors.green : Colors.red,
          ),
        );
        ref.invalidate(ap.syncStatsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هل تريد مسح جميع البيانات المؤقتة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(ap.appwriteCacheManagerProvider).clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم مسح الذاكرة المؤقتة')));
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هل تريد مسح جميع السجلات؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(ap.appwriteLoggerProvider).clearLogs();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم مسح السجلات')));
      }
    }
  }

  Future<void> _exportLogs() async {
    setState(() => _isLoading = true);
    try {
      final file = await ref.read(ap.appwriteLoggerProvider).exportLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              file != null ? 'تم التصدير إلى: ${file.path}' : 'فشل التصدير',
            ),
            backgroundColor: file != null ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pushAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الرفع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('سيتم رفع جميع البيانات المحلية إلى السحابة.'),
            SizedBox(height: 8),
            Text('• الغرف والحجوزات والمدفوعات والديون'),
            Text('• قد يستغرق وقتاً حسب حجم البيانات'),
            Text('• يُفضل توفر اتصال مستقر بالإنترنت'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بدء الرفع'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final manager = ref.read(ap.appwriteSyncManagerProvider);
      await manager.pushAllLocalData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم رفع البيانات بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(ap.syncStatsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الرفع: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
  }

  Future<void> _pullAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد السحب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('سيتم تحميل البيانات من السحابة إلى الجهاز.'),
            SizedBox(height: 8),
            Text('• قد يتم استبدال بعض البيانات المحلية'),
            Text('• يُنصح بأخذ نسخة احتياطية قبل السحب'),
            Text('• قد يستغرق وقتاً حسب حجم البيانات'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بدء السحب'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final manager = ref.read(ap.appwriteSyncManagerProvider);
      await manager.pullAllRemoteData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم سحب البيانات بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(ap.syncStatsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل السحب: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
  }

  Future<void> _resetSync() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هل تريد إعادة تعيين حالة المزامنة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(ap.appwriteSyncManagerProvider).resetSyncState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إعادة تعيين المزامنة')),
        );
        ref.invalidate(ap.syncStatsProvider);
      }
    }
  }

  Future<void> _testConnection() async {
    await _checkConnection();
  }

  Future<void> _testSync() async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('اختبار المزامنة...')));
    await _syncNow();
  }

  Future<void> _testCache() async {
    final stats = ref.read(ap.cacheStatsProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نتائج اختبار الذاكرة المؤقتة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إجمالي العناصر: ${stats.totalEntries}'),
            Text('العناصر الصالحة: ${stats.validEntries}'),
            Text('العناصر منتهية: ${stats.expiredEntries}'),
            Text('الحجم المستخدم: ${stats.totalSizeMB} MB'),
            Text(
              'نسبة الاستخدام: ${stats.usagePercentage.toStringAsFixed(1)}%',
            ),
            Text('معدل الإصابة: ${(stats.hitRate * 100).toStringAsFixed(1)}%'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
