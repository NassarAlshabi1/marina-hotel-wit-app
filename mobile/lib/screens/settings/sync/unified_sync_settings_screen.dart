// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';
import '../../../providers/appwrite_providers.dart' as ap;
import '../../../providers/repository_providers.dart' show databaseProvider;
import '../../../services/appwrite_sync_manager.dart';
import '../../../services/daos/outbox_dao.dart';
import '../../../services/sync/sync_gate.dart';
import '../../../services/worker_endpoints.dart';

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

  /// ✅ (2026-09-07) مؤشر تنفيذ مزامنة يدوية (سحب/كامل) من هذه الشاشة —
  /// يعطّل صفوف الأدوات ويُظهر مؤشر تحميل في trailing.
  bool _isManualSyncing = false;

  /// ✅ (2026-09-09) نطاق Worker مخصّص (تجاوز حجب workers.dev في اليمن).
  final TextEditingController _customUrlController = TextEditingController();
  bool _isProbingEndpoint = false;
  String? _endpointProbeResult;
  bool _endpointProbeOk = false;

  static const _autoSyncKey = 'appwrite_auto_sync_enabled';
  static const _syncOnStartupKey = 'appwrite_sync_on_startup';
  // ✅ (2026-09-05) تصحيح المفاتيح الميتة: كانت هذه المفاتيح تُكتب
  // هنا ولا يقرؤها أحد (القارئات الحقيقية في sync_performance_optimizer
  // وsmart_sync_manager تستخدم المفاتيح أدناه) — مفاتيح تبدو
  // فعّالة للمستخدم وهي معطّلة. الآن نفس مفتاح القارئ الحقيقي.
  // _batteryOptimizationKey → sync_performance_optimizer.dart:345,372
  // _wifiOnlyKey → sync_performance_optimizer.dart:259,297
  // _smartSyncKey → smart_sync_manager.dart:54 (_prefsEnabledKey)
  static const _batteryOptimizationKey = 'battery_optimization_enabled';
  static const _wifiOnlyKey = 'wifi_only_sync';
  static const _smartSyncKey = 'smart_sync_enabled';
  static const _appwriteSyncKey = 'appwrite_sync_enabled';
  static const _realtimeSyncKey = 'appwrite_realtime_sync_enabled';
  static const _syncIntervalKey = 'appwrite_sync_interval_minutes';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ السجل قد لا يكون حُمّل بعد إن فُتحت الشاشة مبكراً — idempotent.
    await WorkerEndpoints.load(prefs: prefs);
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
      _customUrlController.text = WorkerEndpoints.custom ?? '';
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
    // ✅ (2026-08-31) تفعيل Realtime الكامل: المفتاح المرئي يكتب المفتاحين
    // معاً — master switch (appwrite_realtime_sync_enabled) ووضع WebSocket
    // (appwrite_realtime_ws_enabled) — كي يتحكم المفتاح الواحد بالوضعين
    // فعلاً (كان WS يبقى على قيمته السابقة مهما غيّر المستخدم هنا).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appwrite_realtime_ws_enabled', enabled);
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

          const SizedBox(height: UIConstants.spacingLG),

          // ✅ (2026-09-09) نطاق Worker مخصّص — تجاوز حجب workers.dev
          // (اليمن) عبر دومين المستخدم المربوط بنفس الـ worker.
          _buildWorkerEndpointSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // ✅ (2026-09-07) أدوات السحب اليدوي — طلب المستخدم:
          // «شاشة الاعدادات لا يوجد زر سحب full sync»
          _buildManualActionsSection(),
        ],
      ),
    );
  }

  Widget _buildOverviewSection() {
    // ✅ (2026-09-05) كانت القيم هنا ثابتة مُبرمجة ('2024-01-29'،
    // 'متصل'، '0') تُعرض على المستخدم كحقيقة حية — تضليل إنتاجي.
    // الآن بيانات حية: آخر مزامنة من عدادات المدير الحقيقية
    // (syncStatsProvider → getSyncStatistics)، توفر الجلسة من المدير
    // (isAvailable/lastError)، والمعلّق من عدّ Outbox الفعلي.
    final statsAsync = ref.watch(ap.syncStatsProvider);
    final outboxAsync = ref.watch(ap.outboxCountProvider);
    final manager = ref.watch(ap.appwriteSyncManagerProvider);
    final connected = manager.isAvailable && manager.lastError == null;
    final lastSyncIso = statsAsync.valueOrNull?['lastSyncTime'] as String?;
    final lastSyncLabel = (lastSyncIso == null || lastSyncIso.isEmpty)
        ? 'لم تُنفَّذ مزامنة بعد'
        : DateTimeFormatter.getRelativeTime(lastSyncIso);
    final pending = outboxAsync.valueOrNull ?? 0;
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
              value: lastSyncLabel,
              icon: Icons.schedule,
            ),
            InfoRow(
              label: 'حالة الاتصال',
              value: connected ? 'متصل بالسحابة' : 'غير متصل',
              icon: Icons.wifi,
              iconColor: connected ? Colors.green : Colors.red,
            ),
            InfoRow(
              label: 'عناصر معلقة',
              value: '$pending',
              icon: Icons.pending,
              iconColor: pending > 0 ? Colors.orange : Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ (2026-09-09) قسم نطاق Worker المخصّص.
  ///
  /// الخلفية: شبكات اليمن تحجب *.workers.dev بفلترة SNI/IP — لا يوجد
  /// إصلاح برمجي بحت يتجاوز حجب SNI. الحل الصحيح: دومين يملكه المستخدم
  /// مربوط بنفس الـ worker (Cloudflare Custom Domain) — SNI مسموح،
  /// فيعمل التطبيق عبره تلقائياً (تبديل فوري + تثبيت sticky + رجوع
  /// تلقائي للمدمج إن تعذّر المخصّص).
  Widget _buildWorkerEndpointSection() {
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
                  Icons.dns_outlined,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Expanded(
                  child: Text(
                    'نطاق Worker مخصّص (تجاوز الحجب)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              'إذا كان اتصال المزامنة محبوساً (workers.dev محجوب في '
              'بعض الشبكات مثل اليمن): ربط دومينك بحساب Cloudflare '
              'ووجّهه لنفس الـ Worker، ثم ضعه هنا — يعمل التطبيق عبره '
              'تلقائياً ويرجع للمدمج إن تعذّر.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            InfoRow(
              label: 'النقطة الفعّالة الآن',
              value:
                  Uri.tryParse(WorkerEndpoints.active)?.host ??
                  WorkerEndpoints.active,
              icon: Icons.public,
            ),
            const SizedBox(height: UIConstants.spacingSM),
            TextField(
              controller: _customUrlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'النطاق المخصّص (اختياري)',
                hintText: 'api.mydomain.com',
                border: const OutlineInputBorder(),
                suffixIcon: WorkerEndpoints.hasCustom
                    ? Tooltip(
                        message: 'نطاق مخصّص مضبوط',
                        child: Icon(
                          Icons.verified_outlined,
                          color: Colors.green.shade700,
                        ),
                      )
                    : null,
              ),
            ),
            if (_endpointProbeResult != null) ...[
              const SizedBox(height: UIConstants.spacingSM),
              Row(
                children: [
                  Icon(
                    _endpointProbeOk ? Icons.check_circle : Icons.error_outline,
                    size: 16,
                    color: _endpointProbeOk
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _endpointProbeResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _endpointProbeOk
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: UIConstants.spacingSM),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProbingEndpoint
                        ? null
                        : () => unawaited(_probeCustomEndpoint()),
                    icon: _isProbingEndpoint
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('فحص الاتصال'),
                  ),
                ),
                const SizedBox(width: UIConstants.spacingSM),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isProbingEndpoint
                        ? null
                        : () => unawaited(_saveCustomEndpoint()),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ'),
                  ),
                ),
              ],
            ),
            if (WorkerEndpoints.hasCustom)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => unawaited(_clearCustomEndpoint()),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('مسح النطاق المخصّص'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// حفظ النطاق المُدخل (تطبيع + تخزين) — ثم فحص فوري.
  Future<void> _saveCustomEndpoint() async {
    try {
      final normalized = await WorkerEndpoints.setCustomUrl(
        _customUrlController.text,
      );
      if (!mounted) return;
      setState(() {
        if (normalized != null) {
          _customUrlController.text = normalized;
        }
        _endpointProbeResult = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            normalized == null
                ? 'تم مسح النطاق المخصّص — الرجوع للنطاق المدمج'
                : 'تم حفظ النطاق: $normalized',
          ),
        ),
      );
      if (normalized != null) await _probeCustomEndpoint();
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    }
  }

  /// مسح النطاق المخصّص والرجوع للمدمج.
  Future<void> _clearCustomEndpoint() async {
    try {
      await WorkerEndpoints.setCustomUrl(null);
      if (!mounted) return;
      setState(() {
        _customUrlController.clear();
        _endpointProbeResult = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم المسح — الرجوع للنطاق المدمج workers.dev'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر المسح: $e')));
    }
  }

  /// فحص صريح للنطاق المُدخل (أو الفعّال إن كان الحقل فارغاً):
  /// GET /api/ping بمهلة 8s — عميل عادي بلا تدوير لنقيس العنوان نفسه.
  Future<void> _probeCustomEndpoint() async {
    final raw = _customUrlController.text.trim().isNotEmpty
        ? _customUrlController.text.trim()
        : WorkerEndpoints.active;
    String? normalized;
    try {
      normalized = WorkerEndpoints.normalizeCustomUrl(raw);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _endpointProbeOk = false;
        _endpointProbeResult = e.message;
      });
      return;
    }
    if (normalized == null) {
      if (!mounted) return;
      setState(() {
        _endpointProbeOk = false;
        _endpointProbeResult = 'أدخل نطاقاً أولاً';
      });
      return;
    }

    setState(() => _isProbingEndpoint = true);
    try {
      final sw = Stopwatch()..start();
      final response = await http
          .get(Uri.parse('$normalized/api/ping'))
          .timeout(const Duration(seconds: 8));
      sw.stop();
      if (!mounted) return;
      setState(() {
        _endpointProbeOk = response.statusCode == 200;
        _endpointProbeResult = _endpointProbeOk
            ? 'نجح الاتصال (${response.statusCode}) في '
                  '${sw.elapsedMilliseconds}ms'
            : 'استجابة غير متوقعة: HTTP ${response.statusCode}';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _endpointProbeOk = false;
        _endpointProbeResult =
            'انتهت المهلة (8s) — النطاق غير قابل للوصول من هذه الشبكة';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _endpointProbeOk = false;
        _endpointProbeResult = 'فشل الاتصال: ${e.runtimeType}';
      });
    } finally {
      if (mounted) setState(() => _isProbingEndpoint = false);
    }
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
                  'Cloudflare Sync',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل مزامنة Cloudflare'),
            subtitle: const Text('مزامنة البيانات مع سحابة Cloudflare'),
            value: _appwriteSyncEnabled,
            onChanged: _isSaving
                ? null
                : (value) => _saveBoolSetting(
                    key: _appwriteSyncKey,
                    value: value,
                    apply: () => _appwriteSyncEnabled = value,
                    successMessage: value
                        ? 'تم تفعيل مزامنة Cloudflare'
                        : 'تم إيقاف مزامنة Cloudflare',
                    applyToService: _applyAppwriteSync,
                  ),
            secondary: const Icon(Icons.cloud),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('المزامنة الفورية (Realtime)'),
            subtitle: const Text(
              'استقبال تغييرات الأجهزة الأخرى فور حدوثها عبر WebSocket '
              'وسحبها خلال ثوانٍ — إن تعذر الاتصال يُستخدم سحب خفيف دوري',
            ),
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

  // ═══════════════════════════════════════════════════════════════
  // ✅ (2026-09-07) أدوات المزامنة اليدوية — طلب المستخدم الصريح:
  // «شاشة الاعدادات لا يوجد زر سحب full sync».
  //
  // قبل هذا القسم كانت الشاشة مفاتيح (Switch) فقط: لا سحب يدوي ولا
  // full sync، رغم أن المدير يوفر fullSync() (يصفّر مؤشر السحب ثم
  // sync(push+pull)) ولا شيء يعرضه في الإعدادات.
  //
  // قرارات التصميم (متسقة مع سياسة لوحة التحكم):
  // - كل عملية تمرّ عبر SyncGate (نفس البوّابة العامة) فلا تتصادم
  //   مع السحب التلقائي أو زر dashboard.
  // - النتيجة تُعرض كما هي: نجاح حقيقي بعدد السجلات، أو فشل مع
  //   السبب المُفسَّر بالعربية — لا رسائل نجاح كاذبة.
  // - «سحب التغييرات الآن» يحترم سياسة Offline-first نفسها
  //   (لا سحب ما دام outbox فيه سجلات غير مُسلّمة) لكنه يوجّه
  //   المستخدم إلى «المزامنة الكاملة» التي ترفع ثم تسحب.
  // ═══════════════════════════════════════════════════════════════

  Widget _buildManualActionsSection() {
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
                  Icons.touch_app,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'أدوات المزامنة اليدوية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.blue),
            title: const Text('سحب التغييرات الآن'),
            subtitle: const Text(
              'يجلب التغييرات الجديدة من السيرفر فقط (بدون رفع)',
            ),
            trailing: _isManualSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _isManualSyncing ? null : _runPullNow,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.restore, color: Colors.deepPurple),
            title: const Text('السحب الكامل من السيرفر'),
            subtitle: const Text(
              'سحب فقط بدون رفع: يعيد ضبط مؤشر السحب ويجلب كل البيانات '
              'من السيرفر من الصفر (صفحات أكبر وأسرع)',
            ),
            trailing: _isManualSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _isManualSyncing ? null : _confirmFullSync,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cloud_upload, color: Colors.teal),
            title: const Text('رفع التغييرات المحلية'),
            subtitle: const Text(
              'رفع فقط بدون سحب: يرفع كل التغييرات المحلية المعلّقة '
              'في outbox إلى السيرفر',
            ),
            trailing: _isManualSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _isManualSyncing ? null : _runPushNow,
          ),
        ],
      ),
    );
  }

  /// ترجمة أخطاء sync()/fullSync() الداخلية إلى رسائل عربية مفهومة.
  String _friendlySyncError(String? raw) {
    if (raw == null || raw.isEmpty) {
      return 'سبب غير معروف — جرّب مجدداً';
    }
    if (raw.contains('Not initialized')) {
      return 'لم يتم تسجيل الدخول إلى سيرفر المزامنة. أعد تشغيل التطبيق '
          'وتحقق من بطاقة الاتصال في الإعدادات';
    }
    if (raw.contains('disabled remotely')) {
      return 'مزامنة Cloudflare معطّلة مؤقتاً من الإعدادات البعيدة';
    }
    if (raw.contains('disabled locally')) {
      return 'مزامنة Cloudflare معطّلة — فعّلها من قسم Cloudflare Sync أعلاه';
    }
    if (raw.contains('already in progress')) {
      return 'توجد مزامنة جارية حالياً — انتظر انتهاءها ثم أعد المحاولة';
    }
    if (raw.contains('Partial sync failure')) {
      return raw.replaceFirst(
        'Partial sync failure — failed collections: ',
        'فشل جزئي أثناء المزامنة في: ',
      );
    }
    return raw;
  }

  void _showSyncResultSnack({required bool success, required String message}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: Duration(seconds: success ? 3 : 5),
      ),
    );
  }

  /// فحص اتصال حقيقي بالـ Worker قبل أي عملية مزامنة يدوية.
  /// يُرجع true إذا كان متصلاً، وإلا يعرض خطأً ويُرجع false.
  Future<bool> _ensureCloudflareConnected() async {
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
    final connected = ref.read(ap.connectionStatusProvider).isConnected;
    if (!connected) {
      _showSyncResultSnack(
        success: false,
        message: '❌ لا يوجد اتصال بـ Cloudflare Worker — تحقق من الإنترنت',
      );
    }
    return connected;
  }

  /// «سحب التغييرات الآن» — سحب دلتا (push:false).
  /// نفس سياسة لوحة التحكم: يُحجب إذا وُجدت سجلات محلية غير مُسلّمة
  /// في outbox (يجب رفعها أولاً — استخدم المزامنة الكاملة).
  Future<void> _runPullNow() async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);
    try {
      // 1) فحص outbox المحلي (عدّ حقيقي من قاعدة البيانات)
      final db = ref.read(databaseProvider);
      final pending = await OutboxDao(
        db,
      ).countUndeliveredToPrimary(sources: const ['local']);
      if (pending > 0) {
        _showSyncResultSnack(
          success: false,
          message:
              '⬆️ يوجد $pending تغييراً محلياً غير مرفوع — '
              'استخدم «رفع التغييرات المحلية» أدناه أولاً',
        );
        return;
      }

      // 2) فحص الاتصال بالـ Worker
      if (!await _ensureCloudflareConnected()) return;

      // 3) السحب عبر البوّابة العامة (منع التصادم مع أي مزامنة أخرى)
      final manager = ref.read(ap.appwriteSyncManagerProvider);
      final result = await SyncGate.instance.runGuarded<SyncResult>(
        operation: 'pull',
        source: 'settings',
        task: () => manager.sync(push: false),
      );

      if (result == null) {
        _showSyncResultSnack(
          success: false,
          message: '⏳ المزامنة مشغولة بعملية أخرى — أعد المحاولة بعد قليل',
        );
        return;
      }

      if (result.isSuccess) {
        _showSyncResultSnack(
          success: true,
          message: result.recordsPulled == 0
              ? '✅ اكتمل السحب — لا توجد تغييرات جديدة على السيرفر'
              : '✅ اكتمل السحب — استُلم ${result.recordsPulled} سجل',
        );
      } else {
        _showSyncResultSnack(
          success: false,
          message: '❌ تعذر السحب: ${_friendlySyncError(result.errorMessage)}',
        );
      }
    } catch (e) {
      _showSyncResultSnack(
        success: false,
        message: '❌ خطأ غير متوقع أثناء السحب: $e',
      );
    } finally {
      if (mounted) setState(() => _isManualSyncing = false);
    }
  }

  /// تأكيد قبل full pull — لأنه يصفّر مؤشر السحب ويعيد جلب كل شيء.
  Future<void> _confirmFullSync() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('السحب الكامل من السيرفر؟'),
        content: const Text(
          'سحب فقط بدون رفع:\n'
          '1. إعادة ضبط مؤشر السحب\n'
          '2. جلب جميع البيانات من السيرفر من الصفر\n\n'
          'لا يُرفع أي تغيير محلي في هذه العملية. متابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runFullSync();
    }
  }

  /// «السحب الكامل» — fullSync(push: false): تصفير مؤشر السحب + سحب
  /// كل البيانات من الصفر — **سحب فقط بدون أي رفع** (فصل صريح عن زر
  /// الرفع بناء على طلب المستخدم 2026-09-09).
  Future<void> _runFullSync() async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);

    // حوار تقدّم غير قابل للإغلاق — full pull قد يسحب عدة صفحات.
    // ✅ نلتقط NavigatorState متزامناً (قبل أي await) كي نستطيع إغلاق
    // الحوار في finally حتى لو غادر المستخدم الشاشة أثناء المزامنة —
    // استخدام context بعد dispose كان سيترك الحوار محجوزاً للأبد.
    var progressDialogOpen = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          title: Text('جاري السحب الكامل…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 12),
              Text(
                'سحب كل البيانات من السيرفر (بدون رفع)',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
    progressDialogOpen = true;
    final navigator = Navigator.of(context);

    try {
      if (!await _ensureCloudflareConnected()) return;

      final manager = ref.read(ap.appwriteSyncManagerProvider);
      final result = await SyncGate.instance.runGuarded<SyncResult>(
        operation: 'full_sync',
        source: 'settings',
        // ✅ فصل صريح: push:false — لا رفع إطلاقاً في السحب الكامل
        // (كان الاعتماد على قيمة افتراضية ضمنية — الآن الصراحة عقد).
        // ignore: avoid_redundant_argument_values
        task: () => manager.fullSync(push: false),
      );

      if (result == null) {
        _showSyncResultSnack(
          success: false,
          message: '⏳ المزامنة مشغولة بعملية أخرى — أعد المحاولة بعد قليل',
        );
        return;
      }

      if (result.isSuccess) {
        _showSyncResultSnack(
          success: true,
          message:
              '✅ اكتمل السحب الكامل — سُحب ${result.recordsPulled} سجل '
              'من السيرفر (بدون رفع)',
        );
      } else {
        _showSyncResultSnack(
          success: false,
          message:
              '❌ فشل السحب الكامل: '
              '${_friendlySyncError(result.errorMessage)}',
        );
      }
    } catch (e) {
      _showSyncResultSnack(
        success: false,
        message: '❌ خطأ غير متوقع أثناء السحب الكامل: $e',
      );
    } finally {
      if (progressDialogOpen) {
        // NavigatorState ملتقط مسبقاً — آمن حتى بعد dispose الشاشة
        navigator.pop(); // إغلاق حوار التقدّم
      }
      if (mounted) setState(() => _isManualSyncing = false);
    }
  }

  /// «رفع التغييرات المحلية» — زر مستقل تماماً عن السحب الكامل:
  /// sync(push: true, pull: false) — يفرّغ outbox إلى السيرفر فقط
  /// بلا أي سحب (فصل الرفع عن السحب الكامل — طلب المستخدم 2026-09-09).
  Future<void> _runPushNow() async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);
    try {
      if (!await _ensureCloudflareConnected()) return;

      final manager = ref.read(ap.appwriteSyncManagerProvider);
      final result = await SyncGate.instance.runGuarded<SyncResult>(
        operation: 'push',
        source: 'settings',
        // ✅ فصل صريح: الرفع وحده — الصراحة عقد لا افتراض.
        // ignore: avoid_redundant_argument_values
        task: () => manager.sync(push: true, pull: false),
      );

      if (result == null) {
        _showSyncResultSnack(
          success: false,
          message: '⏳ المزامنة مشغولة بعملية أخرى — أعد المحاولة بعد قليل',
        );
        return;
      }

      if (result.isSuccess) {
        _showSyncResultSnack(
          success: true,
          message: result.recordsPushed == 0
              ? '✅ لا توجد تغييرات محلية معلّقة للرفع'
              : '✅ اكتمل الرفع — رُفع ${result.recordsPushed} سجل إلى السيرفر',
        );
      } else {
        _showSyncResultSnack(
          success: false,
          message: '❌ تعذر الرفع: ${_friendlySyncError(result.errorMessage)}',
        );
      }
    } catch (e) {
      _showSyncResultSnack(
        success: false,
        message: '❌ خطأ غير متوقع أثناء الرفع: $e',
      );
    } finally {
      if (mounted) setState(() => _isManualSyncing = false);
    }
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
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('فترة المزامنة'),
          content: RadioGroup<int>(
            groupValue: _syncIntervalMinutes,
            onChanged: (value) {
              if (value != null) unawaited(_selectSyncInterval(value));
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
      ),
    );
  }
}
