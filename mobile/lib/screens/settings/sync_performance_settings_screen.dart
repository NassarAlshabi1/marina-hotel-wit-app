import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/service_providers.dart';
import '../../services/sync_performance_settings.dart';

class SyncPerformanceSettingsScreen extends ConsumerStatefulWidget {
  const SyncPerformanceSettingsScreen({super.key});

  @override
  ConsumerState<SyncPerformanceSettingsScreen> createState() =>
      _SyncPerformanceSettingsScreenState();
}

class _SyncPerformanceSettingsScreenState
    extends ConsumerState<SyncPerformanceSettingsScreen> {
  bool _isLoading = false;
  String _currentProfile = 'balanced';

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    final profile = await SyncPerformanceSettings.getCurrentProfile();
    setState(() => _currentProfile = profile);
  }

  Future<void> _applyProfile(String profileKey) async {
    setState(() => _isLoading = true);

    try {
      await SyncPerformanceSettings.applyProfile(profileKey);
      setState(() => _currentProfile = profileKey);

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ تم تطبيق ملف التعريف: ${SyncPerformanceSettings.predefinedProfiles[profileKey]!['name']}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في تطبيق ملف التعريف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحسين أداء المزامنة'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // شرح النظام
            _buildExplanationCard(),

            const SizedBox(height: 20),

            // ملفات التعريف المحددة مسبقاً
            _buildProfilesSection(),

            const SizedBox(height: 20),

            // إعدادات مخصصة
            _buildCustomSettingsSection(),

            const SizedBox(height: 20),

            // إحصائيات الأداء
            _buildPerformanceStatsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'تحسين الأداء والبطارية',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'يتيح لك هذا النظام تخصيص أداء المزامنة حسب احتياجاتك. يمكنك اختيار ملف تعريف محدد مسبقاً أو تخصيص الإعدادات يدوياً.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '💡 النصيحة: ملف "متوازن" مُوصى به لمعظم الاستخدامات، بينما "توفير البطارية" مثالي للأجهزة القديمة أو الاستخدام المحدود.',
                style: TextStyle(fontSize: 11, color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ملفات التعريف المحددة مسبقاً',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...SyncPerformanceSettings.predefinedProfiles.entries.map(
          (entry) => _buildProfileCard(entry.key, entry.value),
        ),
      ],
    );
  }

  Widget _buildProfileCard(String key, Map<String, dynamic> profile) {
    final isSelected = _currentProfile == key;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
        color: isSelected ? Colors.blue.withValues(alpha: 0.05) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          profile['name'] as String,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.blue : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(profile['description'] as String),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _buildProfileBadge('${profile['interval']} دقائق', Icons.timer),
                if (profile['wifi_only'] as bool)
                  _buildProfileBadge('WiFi فقط', Icons.wifi),
                if (profile['low_power_mode'] as bool)
                  _buildProfileBadge('توفير طاقة', Icons.battery_saver),
                _buildProfileBadge(
                  '${profile['daily_limit_mb']} MB',
                  Icons.data_usage,
                ),
              ],
            ),
          ],
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.blue)
            : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
        onTap: _isLoading ? null : () => _applyProfile(key),
      ),
    );
  }

  Widget _buildProfileBadge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSettingsSection() {
    return FutureBuilder<Map<String, bool>>(
      future: _loadCustomSettings(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final settings = snapshot.data!;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إعدادات مخصصة متقدمة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('الفترة التكيفية'),
                  subtitle: const Text(
                    'تعديل فترة المزامنة حسب الاستخدام والاتصال',
                  ),
                  value: settings['adaptive_interval'] ?? true,
                  onChanged: _isLoading
                      ? null
                      : (value) async {
                          await ref.read(syncPerformanceOptimizerProvider)
                              .setAdaptiveInterval(value);
                          setState(() {});
                        },
                ),
                SwitchListTile(
                  title: const Text('تحسين البطارية'),
                  subtitle: const Text('تقليل استهلاك البطارية تلقائياً'),
                  value: settings['battery_optimization'] ?? true,
                  onChanged: _isLoading
                      ? null
                      : (value) async {
                          await ref.read(syncPerformanceOptimizerProvider)
                              .setBatteryOptimization(value);
                          setState(() {});
                        },
                ),
                SwitchListTile(
                  title: const Text('WiFi فقط'),
                  subtitle: const Text('مزامنة عند الاتصال بـ WiFi فقط'),
                  value: settings['wifi_only'] ?? false,
                  onChanged: _isLoading
                      ? null
                      : (value) async {
                          await ref.read(syncPerformanceOptimizerProvider)
                              .setWifiOnlySync(value);
                          setState(() {});
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPerformanceStatsSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadPerformanceStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final stats = snapshot.data!;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إحصائيات الأداء',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),

                // استهلاك البيانات
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('استهلاك البيانات اليوم:'),
                    Text(
                      '${(stats['used_mb'] as double).toStringAsFixed(1)} / ${stats['limit_mb']} MB',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (stats['is_limit_exceeded'] as bool)
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (stats['usage_percentage'] as double) / 100,
                  backgroundColor: Colors.grey.shade200,
                  color: (stats['is_limit_exceeded'] as bool)
                      ? Colors.red
                      : Colors.blue,
                ),

                const SizedBox(height: 16),

                // حالة الاتصال
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('نوع الاتصال:'),
                    Text(
                      stats['connection_type'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // حالة البطارية
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('حالة البطارية:'),
                    Text(
                      (stats['is_battery_low'] as bool)
                          ? 'منخفضة 🔋'
                          : 'عادية 🔋',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (stats['is_battery_low'] as bool)
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                  ],
                ),

                if ((stats['consecutive_failures'] as int? ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('فشل متتالي:'),
                      Text(
                        '${stats['consecutive_failures']} مرات',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, bool>> _loadCustomSettings() async {
    final optimizer = ref.read(syncPerformanceOptimizerProvider);

    return {
      'adaptive_interval': await optimizer.isAdaptiveIntervalEnabled(),
      'battery_optimization': await optimizer.isBatteryOptimizationEnabled(),
      'wifi_only': await optimizer.isWifiOnlyEnabled(),
    };
  }

  Future<Map<String, dynamic>> _loadPerformanceStats() async {
    final performanceStats = ref.read(syncPerformanceOptimizerProvider)
        .getPerformanceStatus();
    final usageStats = await ref.read(dataUsageManagerProvider).getUsageStats();

    return {...performanceStats, ...usageStats};
  }
}
