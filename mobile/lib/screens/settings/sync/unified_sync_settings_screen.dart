import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../components/app_scaffold.dart';
import '../../../services/appwrite_realtime_sync.dart';
import '../../../services/appwrite_sync_manager.dart';
import '../../../core/core.dart';

/// Unified Sync Settings Screen
///
/// شاشة موحدة لجميع إعدادات المزامنة
/// تجمع الإعدادات المبعثرة في:
/// - smart_sync_settings_screen.dart
/// - appwrite_settings_screen.dart (جزء المزامنة)
/// - data_protection_screen.dart (جزء المزامنة)
/// - sync_performance_settings_screen.dart
class UnifiedSyncSettingsScreen extends ConsumerStatefulWidget {
  const UnifiedSyncSettingsScreen({super.key});

  @override
  ConsumerState<UnifiedSyncSettingsScreen> createState() =>
      _UnifiedSyncSettingsScreenState();
}

class _UnifiedSyncSettingsScreenState
    extends ConsumerState<UnifiedSyncSettingsScreen> {
  bool _autoSyncEnabled = true;
  bool _syncOnStartup = true;
  bool _batteryOptimization = true;
  bool _wifiOnly = false;
  bool _smartSyncEnabled = true;
  bool _appwriteSyncEnabled = true;
  bool _realtimeSyncEnabled = true;
  int _syncIntervalMinutes = 15;
  bool _isSaving = false;

  static const _autoSyncKey = 'appwrite_auto_sync_enabled';
  static const _syncOnStartupKey = 'appwrite_sync_on_startup';
  static const _batteryOptimizationKey = 'appwrite_battery_optimization';
  static const _wifiOnlyKey = 'appwrite_wifi_only_sync';
  static const _smartSyncKey = 'appwrite_smart_sync_enabled';
  static const _appwriteSyncKey = 'appwrite_sync_enabled';
  static const _realtimeSyncKey = 'appwrite_realtime_sync_enabled';
  static const _syncIntervalKey = 'appwrite_sync_interval_minutes';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _autoSyncEnabled = prefs.getBool(_autoSyncKey) ?? true;
      _syncOnStartup = prefs.getBool(_syncOnStartupKey) ?? true;
      _batteryOptimization = prefs.getBool(_batteryOptimizationKey) ?? true;
      _wifiOnly = prefs.getBool(_wifiOnlyKey) ?? false;
      _smartSyncEnabled = prefs.getBool(_smartSyncKey) ?? true;
      _appwriteSyncEnabled = prefs.getBool(_appwriteSyncKey) ?? true;
      _realtimeSyncEnabled = prefs.getBool(_realtimeSyncKey) ?? true;
      _syncIntervalMinutes = prefs.getInt(_syncIntervalKey) ?? 15;
    });
  }

  Future<void> _saveBoolSetting({
    required String key,
    required bool value,
    required VoidCallback apply,
    required String successMessage,
    Future<void> Function(bool value)? applyToService,
  }) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
      await applyToService?.call(value);
      if (!mounted) return;
      setState(apply);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الإعداد. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _applyAutoSync(bool enabled, {int? intervalMinutes}) async {
    final manager = AppwriteSyncManager.instance;
    if (manager == null) return;

    if (enabled) {
      manager.startAutoSync(
        interval: Duration(minutes: intervalMinutes ?? _syncIntervalMinutes),
      );
    } else {
      manager.stopAutoSync();
    }
  }

  Future<void> _applyAppwriteSync(bool enabled) async {
    await _applyAutoSync(enabled && _autoSyncEnabled);
    final realtime = AppwriteRealtimeSync();
    if (enabled && _realtimeSyncEnabled) {
      await realtime.start();
    } else {
      await realtime.stop();
    }
  }

  Future<void> _applyRealtimeSync(bool enabled) async {
    if (!_appwriteSyncEnabled) return;
    final realtime = AppwriteRealtimeSync();
    if (enabled) {
      await realtime.start();
    } else {
      await realtime.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات المزامنة',
      body: ListView(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        children: [
          // نظرة عامة
          _buildOverviewSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // الإعدادات العامة
          _buildGeneralSettingsSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // إعدادات الأداء
          _buildPerformanceSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // المزامنة الذكية
          _buildSmartSyncSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // Appwrite Sync
          _buildAppwriteSyncSection(),
        ],
      ),
    );
  }

  Widget _buildOverviewSection() {
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
                  Icons.info_outline,
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
              label: 'آخر مزامنة',
              value: DateTimeFormatter.getRelativeTime('2024-01-29T18:00:00'),
              icon: Icons.schedule,
            ),
            const InfoRow(
              label: 'حالة الاتصال',
              value: 'متصل',
              icon: Icons.wifi,
              iconColor: Colors.green,
            ),
            const InfoRow(
              label: 'عناصر معلقة',
              value: '0',
              icon: Icons.pending,
              iconColor: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettingsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('تفعيل المزامنة التلقائية'),
            subtitle: const Text('مزامنة البيانات تلقائياً عند التغيير'),
            value: _autoSyncEnabled,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _autoSyncKey,
                    value: value,
                    apply: () => _autoSyncEnabled = value,
                    successMessage: value
                        ? 'تم تفعيل المزامنة التلقائية'
                        : 'تم إيقاف المزامنة التلقائية',
                    applyToService: (enabled) =>
                        _applyAutoSync(enabled && _appwriteSyncEnabled),
                  ),
            secondary: const Icon(Icons.sync),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('المزامنة عند بدء التشغيل'),
            subtitle: const Text('مزامنة البيانات عند فتح التطبيق'),
            value: _syncOnStartup,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _syncOnStartupKey,
                    value: value,
                    apply: () => _syncOnStartup = value,
                    successMessage: value
                        ? 'ستعمل المزامنة عند بدء التطبيق'
                        : 'لن تعمل المزامنة تلقائياً عند البدء',
                  ),
            secondary: const Icon(Icons.power_settings_new),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('فترة المزامنة'),
            subtitle: Text('كل $_syncIntervalMinutes دقيقة'),
            leading: const Icon(Icons.timer),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _isSaving ? null : _showSyncIntervalDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection() {
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
                  Icons.speed,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'الأداء والبطارية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تحسين البطارية'),
            subtitle: const Text('تقليل استهلاك البطارية أثناء المزامنة'),
            value: _batteryOptimization,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _batteryOptimizationKey,
                    value: value,
                    apply: () => _batteryOptimization = value,
                    successMessage: value
                        ? 'تم تفعيل تحسين البطارية'
                        : 'تم إيقاف تحسين البطارية',
                  ),
            secondary: const Icon(Icons.battery_saver),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('WiFi فقط'),
            subtitle: const Text('مزامنة عند الاتصال بـ WiFi فقط'),
            value: _wifiOnly,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _wifiOnlyKey,
                    value: value,
                    apply: () => _wifiOnly = value,
                    successMessage: value
                        ? 'ستقتصر المزامنة على WiFi'
                        : 'ستعمل المزامنة على جميع الشبكات',
                  ),
            secondary: const Icon(Icons.wifi),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartSyncSection() {
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
                  Icons.psychology,
                  color: Colors.purple,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'المزامنة الذكية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل المزامنة الذكية'),
            subtitle: const Text('مزامنة تكيفية حسب الاستخدام والظروف'),
            value: _smartSyncEnabled,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _smartSyncKey,
                    value: value,
                    apply: () => _smartSyncEnabled = value,
                    successMessage: value
                        ? 'تم تفعيل المزامنة الذكية'
                        : 'تم إيقاف المزامنة الذكية',
                  ),
            secondary: const Icon(Icons.smart_toy),
          ),
        ],
      ),
    );
  }

  Widget _buildAppwriteSyncSection() {
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
                  Icons.cloud_sync,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'Appwrite Sync',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل مزامنة Appwrite'),
            subtitle: const Text('مزامنة البيانات مع سحابة Appwrite'),
            value: _appwriteSyncEnabled,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _appwriteSyncKey,
                    value: value,
                    apply: () => _appwriteSyncEnabled = value,
                    successMessage: value
                        ? 'تم تفعيل مزامنة Appwrite'
                        : 'تم إيقاف مزامنة Appwrite',
                    applyToService: _applyAppwriteSync,
                  ),
            secondary: const Icon(Icons.cloud),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('المزامنة الفورية'),
            subtitle: const Text('مزامنة فورية عند حدوث تغييرات'),
            value: _realtimeSyncEnabled,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _realtimeSyncKey,
                    value: value,
                    apply: () => _realtimeSyncEnabled = value,
                    successMessage: value
                        ? 'تم تفعيل المزامنة الفورية'
                        : 'تم إيقاف المزامنة الفورية',
                    applyToService: _applyRealtimeSync,
                  ),
            secondary: const Icon(Icons.flash_on),
          ),
        ],
      ),
    );
  }

  Future<void> _selectSyncInterval(int minutes) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_syncIntervalKey, minutes);
      await _applyAutoSync(
        _autoSyncEnabled && _appwriteSyncEnabled,
        intervalMinutes: minutes,
      );
      if (!mounted) return;
      setState(() => _syncIntervalMinutes = minutes);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ضبط فترة المزامنة على كل $minutes دقيقة')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديث فترة المزامنة. حاول مرة أخرى.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSyncIntervalDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فترة المزامنة'),
        content: RadioGroup<int>(
          groupValue: _syncIntervalMinutes,
          onChanged: (value) {
            if (value != null) _selectSyncInterval(value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('5 دقائق'),
                leading: const Radio<int>(value: 5),
                onTap: () => _selectSyncInterval(5),
              ),
              ListTile(
                title: const Text('15 دقيقة'),
                leading: const Radio<int>(value: 15),
                onTap: () => _selectSyncInterval(15),
              ),
              ListTile(
                title: const Text('30 دقيقة'),
                leading: const Radio<int>(value: 30),
                onTap: () => _selectSyncInterval(30),
              ),
              ListTile(
                title: const Text('ساعة واحدة'),
                leading: const Radio<int>(value: 60),
                onTap: () => _selectSyncInterval(60),
              ),
            ],
          ),
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
}
