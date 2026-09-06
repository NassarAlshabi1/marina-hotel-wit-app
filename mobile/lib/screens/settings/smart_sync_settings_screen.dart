import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../services/smart_sync_manager.dart';
import '../../services/sync_guardian.dart';
import '../../utils/performance_monitor.dart';
import 'sync_health/sync_health_screen.dart';

class SmartSyncSettingsScreen extends ConsumerStatefulWidget {
  const SmartSyncSettingsScreen({super.key});

  @override
  ConsumerState<SmartSyncSettingsScreen> createState() =>
      _SmartSyncSettingsScreenState();
}

class _SmartSyncSettingsScreenState
    extends ConsumerState<SmartSyncSettingsScreen> {
  bool _isLoading = false;

  final List<int> _intervalOptions = [1, 2, 5, 10, 15, 30, 60]; // بالدقائق
  final Map<ConflictResolution, String> _conflictResolutionLabels = {
    ConflictResolution.newerWins: 'الأحدث يفوز (موصى به)',
    ConflictResolution.manualResolve: 'حل يدوي',
    ConflictResolution.devicePriority: 'أولوية للجهاز الرئيسي',
  };

  Future<void> _toggleSync(bool enabled) async {
    setState(() => _isLoading = true);

    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.setEnabled(enabled);
      if (!mounted) return;

      ref.invalidate(smartSyncStatusProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '✅ تم تفعيل المزامنة التلقائية'
                : '⏸️ تم إيقاف المزامنة التلقائية',
          ),
          backgroundColor: enabled ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في تغيير حالة المزامنة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _changeSyncInterval(int minutes) async {
    setState(() => _isLoading = true);

    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.setSyncInterval(minutes);
      if (!mounted) return;

      ref.invalidate(smartSyncStatusProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏰ تم تغيير فترة المزامنة إلى $minutes دقائق'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في تغيير فترة المزامنة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _changeConflictResolution(ConflictResolution resolution) async {
    setState(() => _isLoading = true);

    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.setConflictResolution(resolution);
      if (!mounted) return;

      ref.invalidate(smartSyncStatusProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🤝 تم تغيير استراتيجية حل التضارب'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في تغيير استراتيجية التضارب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _performManualSync() async {
    setState(() => _isLoading = true);

    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.forceSyncNow();
      if (!mounted) return;

      ref.invalidate(smartSyncStatusProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 تمت المزامنة اليدوية بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشلت المزامنة اليدوية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _forceGuardianSync() async {
    setState(() => _isLoading = true);
    try {
      final guardian = ref.read(syncGuardianProvider);
      await guardian.forceSync();
      if (!mounted) return;
      ref.invalidate(syncHealthProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚡ تم تشغيل مزامنة WorkManager فوراً'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ تعذر تشغيل مزامنة WorkManager: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _togglePriorityOverride(bool enabled) async {
    setState(() => _isLoading = true);
    try {
      final guardian = ref.read(syncGuardianProvider);
      await guardian.setDevicePriority(enabled ? 200 : 100);
      if (!mounted) return;
      ref.invalidate(syncHealthProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '🏅 هذا الجهاز أصبح صاحب الأولوية'
                : '↩︎ تم العودة للأولوية الافتراضية',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ تعذر تغيير أولوية الجهاز: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(smartSyncStatusProvider);
    final healthAsync = ref.watch(syncHealthProvider);

    return PerformanceInspector(
      name: 'SmartSyncSettingsScreen',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المزامنة التلقائية الذكية'),
          centerTitle: true,
          elevation: 0,
          actions: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: statusAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('خطأ في تحميل الإعدادات: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(smartSyncStatusProvider),
                  child: const Text('إعادة تحميل'),
                ),
              ],
            ),
          ),
          data: (status) => healthAsync.when(
            data: (health) => _buildSettingsUI(status, health),
            loading: () => _buildSettingsUI(status, null),
            error: (_, __) => _buildSettingsUI(status, null),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsUI(
    Map<String, dynamic> status,
    SyncHealthSnapshot? health,
  ) {
    final isEnabled = status['enabled'] as bool;
    final isSyncing = status['is_syncing'] as bool;
    final syncInterval = status['sync_interval_minutes'] as int;
    final lastSync = status['last_sync_check'] as String?;
    final deviceId = status['device_id'] as String?;
    final conflictResolution = status['conflict_resolution'] as String;
    final isSignedIn = status['signed_in'] as bool;
    final monitoringActive = status['monitoring_active'] as bool;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // معلومات الحالة
          _buildStatusCard(
            isEnabled,
            isSyncing,
            lastSync,
            deviceId,
            isSignedIn,
            monitoringActive,
            health,
          ),

          const SizedBox(height: 20),

          // إعدادات التفعيل
          _buildEnableCard(isEnabled, isSignedIn),

          const SizedBox(height: 20),

          // إعدادات الفترة الزمنية
          if (isEnabled) _buildIntervalCard(syncInterval),

          if (isEnabled) const SizedBox(height: 20),

          // إعدادات حل التضارب
          if (isEnabled) _buildConflictResolutionCard(conflictResolution),

          const SizedBox(height: 20),
          _buildGuardianCard(health),

          const SizedBox(height: 20),

          // أزرار الإجراءات
          _buildActionButtons(isEnabled, isSignedIn),

          const SizedBox(height: 20),

          // الوصول إلى لوحة مراقبة صحة المزامنة
          _buildHealthDashboardButton(),

          const SizedBox(height: 20),

          // شرح النظام
          _buildExplanationCard(),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    bool isEnabled,
    bool isSyncing,
    String? lastSync,
    String? deviceId,
    bool isSignedIn,
    bool monitoringActive,
    SyncHealthSnapshot? health,
  ) {
    final guardianStatus = health?.status;
    final pendingEvents = health?.pendingEvents ?? false;
    final failedAttempts = health?.failedAttempts ?? 0;
    final guardianLastSync = health?.lastSyncAt;
    final combinedLastSync = guardianLastSync != null
        ? _formatDateTime(guardianLastSync.toLocal())
        : (lastSync != null ? _formatDateTime(DateTime.parse(lastSync)) : null);
    final shortenedDeviceId = deviceId == null
        ? null
        : deviceId.length > 20
        ? '${deviceId.substring(0, 20)}...'
        : deviceId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEnabled && monitoringActive
                      ? Icons.sync
                      : Icons.sync_disabled,
                  color: isEnabled && monitoringActive
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'حالة المزامنة التلقائية',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              'الحالة',
              isEnabled
                  ? (monitoringActive
                        ? 'مُفعلة ونشطة ✅'
                        : 'مُفعلة ولكن غير نشطة ⚠️')
                  : 'معطلة ❌',
            ),
            _buildStatusRow(
              'تسجيل الدخول',
              isSignedIn ? 'متصل بـ Google Drive ✅' : 'غير متصل ❌',
            ),
            if (isSyncing)
              _buildStatusRow('النشاط الحالي', 'جارِ المزامنة... 🔄'),
            if (combinedLastSync != null)
              _buildStatusRow('آخر تزامن فعلي', combinedLastSync),
            if (shortenedDeviceId != null)
              _buildStatusRow('معرف الجهاز', shortenedDeviceId),
            if (guardianStatus != null)
              _buildStatusRow('وضع الحارس', guardianStatus),
            if (pendingEvents)
              _buildStatusRow(
                'أحداث في الانتظار',
                'نعم - سيتم استهلاكها عند توفر التطبيق',
              ),
            if (failedAttempts > 0)
              _buildStatusRow('محاولات فاشلة', failedAttempts.toString()),
            if (health != null)
              _buildStatusRow(
                'أولوية هذا الجهاز',
                health.priorityOverridden ? 'أولوية قصوى' : 'أولوية افتراضية',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildGuardianCard(SyncHealthSnapshot? health) {
    final pending = health?.pendingEvents ?? false;
    final failed = health?.failedAttempts ?? 0;
    final lastSync = health?.lastSyncAt;
    final isPriority = health?.priorityOverridden ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'حارس المزامنة الخلفي',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'يتكفل WorkManager باستهلاك جميع الأحداث المؤجلة وتوليد نسخ احتياطية محلية وسحابية بدون تدخل يدوي.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              'آخر استهلاك',
              lastSync != null
                  ? _formatDateTime(lastSync.toLocal())
                  : 'لم يبدأ بعد',
            ),
            if (pending)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '🔄 توجد أحداث قيد الانتظار وسيتم معالجتها تلقائياً',
                ),
              ),
            if (failed > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '⚠️ فشلت $failed محاولات أخيرة، سيتم إعادة المحاولة تلقائياً',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _forceGuardianSync,
                    icon: const Icon(Icons.autorenew, size: 16),
                    label: const Text('مزامنة فورية الآن'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _togglePriorityOverride(!isPriority),
                    icon: Icon(
                      isPriority ? Icons.shield : Icons.shield_outlined,
                      size: 16,
                    ),
                    label: Text(
                      isPriority
                          ? 'إلغاء أولوية هذا الجهاز'
                          : 'اجعل هذا الجهاز أولوية',
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

  Widget _buildEnableCard(bool isEnabled, bool isSignedIn) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تفعيل المزامنة التلقائية',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'عندما تكون مُفعلة، سيراقب التطبيق Google Drive باستمرار للتحقق من وجود نسخ احتياطية جديدة من الأجهزة الأخرى ويزامنها تلقائياً.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('تفعيل المزامنة التلقائية بين الأجهزة'),
              subtitle: Text(
                isEnabled
                    ? 'مُفعلة - يتم فحص النسخ الجديدة باستمرار'
                    : 'معطلة - لا يتم البحث عن نسخ جديدة',
              ),
              value: isEnabled,
              onChanged: isSignedIn && !_isLoading ? _toggleSync : null,
            ),
            if (!isSignedIn) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ يجب تسجيل الدخول في Google Drive أولاً',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalCard(int currentInterval) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('فترة الفحص', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'كم مرة يتحقق التطبيق من وجود نسخ احتياطية جديدة على Google Drive.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _intervalOptions.contains(currentInterval)
                  ? currentInterval
                  : _intervalOptions.first,
              decoration: const InputDecoration(
                labelText: 'فترة الفحص (بالدقائق)',
                prefixIcon: Icon(Icons.timer),
              ),
              items: _intervalOptions
                  .map(
                    (minutes) => DropdownMenuItem(
                      value: minutes,
                      child: Text(_getIntervalLabel(minutes)),
                    ),
                  )
                  .toList(),
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        _changeSyncInterval(value);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictResolutionCard(String currentResolution) {
    final currentEnum = ConflictResolution.values.firstWhere(
      (e) => e.name == currentResolution,
      orElse: () => ConflictResolution.newerWins,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'حل تضارب البيانات',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'ماذا يحدث عندما يتم تعديل نفس البيانات على أجهزة مختلفة في نفس الوقت.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ConflictResolution>(
              initialValue: currentEnum,
              decoration: const InputDecoration(
                labelText: 'استراتيجية حل التضارب',
                prefixIcon: Icon(Icons.merge_type),
              ),
              items: _conflictResolutionLabels.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        _changeConflictResolution(value);
                      }
                    },
            ),
            const SizedBox(height: 8),
            _buildConflictExplanation(currentEnum),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictExplanation(ConflictResolution resolution) {
    String explanation;
    Color color;

    switch (resolution) {
      case ConflictResolution.newerWins:
        explanation =
            '💡 البيانات الأحدث تاريخياً ستحل محل الأقدم. هذا الخيار آمن ومُوصى به.';
        color = Colors.green;
      case ConflictResolution.manualResolve:
        explanation =
            '⚠️ سيتم إيقاف المزامنة التلقائية وطلب تدخلك لحل التضارب يدوياً.';
        color = Colors.orange;
      case ConflictResolution.devicePriority:
        explanation =
            '📱 الجهاز الرئيسي له الأولوية. يتطلب تحديد الجهاز الرئيسي مسبقاً.';
        color = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        explanation,
        style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
      ),
    );
  }

  Widget _buildActionButtons(bool isEnabled, bool isSignedIn) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_isLoading || !isSignedIn || !isEnabled)
                ? null
                : _performManualSync,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('مزامنة يدوية الآن'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(smartSyncStatusProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث الحالة'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (!isSignedIn || !isEnabled) ...[
          const SizedBox(height: 8),
          Text(
            !isSignedIn
                ? '⚠️ يجب تسجيل الدخول في Google Drive'
                : '⚠️ يجب تفعيل المزامنة التلقائية',
            style: const TextStyle(color: Colors.orange, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildHealthDashboardButton() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.monitor_heart, color: Colors.blue, size: 28),
        title: const Text(
          'لوحة مراقبة صحة المزامنة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('إحصائيات وتشخيص متقدم للنظام'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const SyncHealthScreen()),
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
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'كيف تعمل المزامنة التلقائية؟',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '🔄 1. يراقب التطبيق Google Drive بالفترة المحددة للبحث عن نسخ احتياطية جديدة',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '📱 2. عند العثور على نسخة جديدة من جهاز آخر، يقارن التواريخ والأوقات',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '⚡ 3. يدمج البيانات الجديدة تلقائياً حسب استراتيجية حل التضارب المختارة',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '✅ 4. يشعرك بنجاح العملية ويحدث بيانات التطبيق فوراً',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '💡 نصيحة: استخدم فترة فحص قصيرة (1-5 دقائق) للمزامنة السريعة، أو فترة أطول (15-30 دقيقة) لتوفير البطارية.',
                style: TextStyle(fontSize: 11, color: Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getIntervalLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes دقائق';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '$hours ${hours == 1 ? "ساعة" : "ساعات"}';
      } else {
        return '$hours:${remainingMinutes.toString().padLeft(2, '0')} ساعة';
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
