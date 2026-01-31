import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/core.dart';

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
    setState(() {
      _syncEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
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
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        // Sync Status
        _buildSyncStatusCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Sync Settings
        _buildSyncSettingsCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Sync Statistics
        _buildSyncStatisticsCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Cache Settings
        _buildCacheSettingsCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Sync Actions
        _buildSyncActionsCard(),
      ],
    );
  }

  Widget _buildSyncStatusCard() {
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
              value: DateTimeFormatter.getRelativeTime('2024-01-29T18:00:00'),
              icon: Icons.schedule,
            ),
            InfoRow(
              label: 'المزامنة التالية',
              value: 'بعد 12 دقيقة',
              icon: Icons.timer,
            ),
            InfoRow(label: 'عناصر معلقة', value: '0', icon: Icons.pending),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل المزامنة'),
            subtitle: const Text('مزامنة البيانات مع Appwrite'),
            value: _syncEnabled,
            onChanged: (value) {
              setState(() => _syncEnabled = value);
              _saveSettings();
            },
            secondary: const Icon(Icons.sync),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('فترة المزامنة'),
            subtitle: Text('$_syncInterval دقيقة'),
            leading: const Icon(Icons.timer),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showIntervalDialog(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('مزامنة تلقائية عند الاتصال'),
            subtitle: const Text('مزامنة عند استعادة الاتصال'),
            value: _autoSyncOnConnect,
            onChanged: (value) {
              setState(() => _autoSyncOnConnect = value);
              _saveSettings();
            },
            secondary: const Icon(Icons.wifi),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatisticsCard() {
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  title: 'عمليات ناجحة',
                  value: '142',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
                StatCard(
                  title: 'عمليات فاشلة',
                  value: '3',
                  icon: Icons.error,
                  color: Colors.red,
                ),
                StatCard(
                  title: 'معدل النجاح',
                  value: '98%',
                  icon: Icons.trending_up,
                  color: Colors.blue,
                ),
                StatCard(
                  title: 'متوسط الوقت',
                  value: '2.3 ث',
                  icon: Icons.speed,
                  color: Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheSettingsCard() {
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
              _saveSettings();
            },
            secondary: const Icon(Icons.flash_on),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('حجم التخزين المستخدم'),
            subtitle: Text(FileSizeFormatter.formatBytes(5 * 1024 * 1024)),
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

  Widget _buildSyncActionsCard() {
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
            subtitle: const Text('حذف جميع سجلات المزامنة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showClearHistoryDialog(),
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

  void _clearCache() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم مسح التخزين المؤقت')));
  }

  void _syncNow() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('جاري المزامنة...')));
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
            onPressed: () {
              Navigator.pop(context);
              _syncNow();
            },
            child: const Text('بدء المزامنة'),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text('هل تريد حذف جميع سجلات المزامنة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('تم مسح السجلات')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
