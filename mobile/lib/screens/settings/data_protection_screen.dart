import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auto_backup_provider.dart';
import '../../providers/smart_sync_provider.dart';
import '../../services/alarm_backup.dart';
import '../../services/auto_backup_manager.dart';
import '../../services/smart_sync_manager.dart';

class DataProtectionScreen extends ConsumerStatefulWidget {
  const DataProtectionScreen({super.key});

  @override
  ConsumerState<DataProtectionScreen> createState() => _DataProtectionScreenState();
}

class _DataProtectionScreenState extends ConsumerState<DataProtectionScreen> {
  late TextEditingController _maxBackupsController;
  late TextEditingController _retentionDaysController;
  bool _backupBusy = false;
  bool _syncBusy = false;
  bool _scheduledEnabled = false;
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 21, minute: 0);
  final List<int> _intervalOptions = [1, 2, 5, 10, 15, 30, 60];
  final Map<ConflictResolution, String> _conflictDescriptions = {
    ConflictResolution.newerWins: 'الأحدث يفوز (موصى به)',
    ConflictResolution.manualResolve: 'حل يدوي عند الكشف عن تضارب',
    ConflictResolution.devicePriority: 'أولوية للجهاز الحالي',
  };

  @override
  void initState() {
    super.initState();
    _maxBackupsController = TextEditingController();
    _retentionDaysController = TextEditingController();
    _loadBackupForm();
  }

  @override
  void dispose() {
    _maxBackupsController.dispose();
    _retentionDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadBackupForm() async {
    final manager = AutoBackupManager.instance;
    final maxBackups = await manager.getMaxBackupCount();
    final retentionDays = await manager.getRetentionDays();
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString('auto_backup_time') ?? '21:0';
    final parts = timeString.split(':');
    final scheduled = prefs.getBool('scheduled_backup_enabled') ?? false;
    if (!mounted) return;
    setState(() {
      _maxBackupsController.text = maxBackups.toString();
      _retentionDaysController.text = retentionDays.toString();
      _scheduledTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      _scheduledEnabled = scheduled;
    });
  }

  Future<void> _saveBackupSettings() async {
    setState(() => _backupBusy = true);
    try {
      final manager = AutoBackupManager.instance;
      final maxBackups = int.tryParse(_maxBackupsController.text) ?? 25;
      final retentionDays = int.tryParse(_retentionDaysController.text) ?? 45;
      await manager.setMaxBackupCount(maxBackups);
      await manager.setRetentionDays(retentionDays);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات النسخ الاحتياطي')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل حفظ الإعدادات: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _toggleAutoBackup(bool enabled) async {
    setState(() => _backupBusy = true);
    try {
      final manager = AutoBackupManager.instance;
      await manager.setEnabled(enabled);
      ref.invalidate(autoBackupStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? 'تم تفعيل النسخ التلقائي' : 'تم إيقاف النسخ التلقائي')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تغيير الحالة: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _cleanupBackups() async {
    setState(() => _backupBusy = true);
    try {
      await AutoBackupManager.instance.cleanupNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تنظيف النسخ القديمة')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل التنظيف: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _toggleScheduledBackup(bool enabled) async {
    setState(() => _backupBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('scheduled_backup_enabled', enabled);
      if (enabled) {
        await AlarmBackup.scheduleDailyAlarm(_scheduledTime.hour, _scheduledTime.minute);
      } else {
        await AlarmBackup.cancelAlarm();
      }
      if (!mounted) return;
      setState(() => _scheduledEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? 'تم تفعيل النسخ المجدول' : 'تم إيقاف النسخ المجدول')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الجدولة: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (picked == null || picked == _scheduledTime) return;
    setState(() => _scheduledTime = picked);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_backup_time', '${picked.hour}:${picked.minute}');
    if (_scheduledEnabled) {
      await AlarmBackup.rescheduleDaily(picked.hour, picked.minute);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تحديث وقت النسخ إلى ${picked.format(context)}')), 
      );
    }
  }

  Future<void> _toggleSmartSync(bool enabled) async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).setEnabled(enabled);
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? 'تم تفعيل المزامنة' : 'تم إيقاف المزامنة')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تغيير حالة المزامنة: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _changeSyncInterval(int minutes) async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).setSyncInterval(minutes);
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ضبط الفحص على كل $minutes دقيقة')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تعديل الفترة: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _changeConflictResolution(ConflictResolution strategy) async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).setConflictResolution(strategy);
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث استراتيجية حل التضارب')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الاستراتيجية: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _manualSync() async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).forceSyncNow();
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت المزامنة اليدوية')), 
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشلت المزامنة اليدوية: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backupStatus = ref.watch(autoBackupStatusProvider);
    final syncStatus = ref.watch(smartSyncStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة النسخ والمزامنة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryRow(backupStatus, syncStatus),
            const SizedBox(height: 24),
            _buildSectionTitle('المزامنة الذكية', Icons.sync_alt),
            const SizedBox(height: 12),
            _buildSyncSection(syncStatus),
            const SizedBox(height: 32),
            _buildSectionTitle('النسخ الاحتياطي الذكي', Icons.backup),
            const SizedBox(height: 12),
            _buildBackupSection(backupStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(AsyncValue<Map<String, dynamic>> backupStatus, AsyncValue<Map<String, dynamic>> syncStatus) {
    return Row(
      children: [
        Expanded(child: _buildSummaryTile('المزامنة', syncStatus, Colors.teal)),
        const SizedBox(width: 12),
        Expanded(child: _buildSummaryTile('النسخ الاحتياطي', backupStatus, Colors.indigo)),
      ],
    );
  }

  Widget _buildSummaryTile(String title, AsyncValue<Map<String, dynamic>> status, Color color) {
    return status.when(
      loading: () => _buildSummarySkeleton(title),
      error: (error, stack) => _buildSummaryError(title),
      data: (data) {
        final active = (data['enabled'] as bool?) ?? false;
        final subtitle = data.containsKey('last_auto_backup')
            ? _formatOptionalDate(data['last_auto_backup'] as String?)
            : _formatOptionalDate(data['last_sync_check'] as String?);
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 8),
                Text(active ? 'مفعل' : 'معطل', style: TextStyle(color: active ? Colors.green : Colors.red)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummarySkeleton(String title) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryError(String title) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('تعذر التحميل', style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSyncSection(AsyncValue<Map<String, dynamic>> statusAsync) {
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorCard('تعذر تحميل إعدادات المزامنة'),
      data: (status) => _buildSyncContent(status),
    );
  }

  Widget _buildSyncContent(Map<String, dynamic> status) {
    final isEnabled = status['enabled'] as bool;
    final monitoringActive = status['monitoring_active'] as bool;
    final isSyncing = status['is_syncing'] as bool;
    final isSignedIn = status['signed_in'] as bool;
    final lastSync = status['last_sync_check'] as String?;
    final deviceId = status['device_id'] as String?;
    final syncInterval = status['sync_interval_minutes'] as int;
    final conflictKey = status['conflict_resolution'] as String;
    final resolution = ConflictResolution.values.firstWhere(
      (e) => e.name == conflictKey,
      orElse: () => ConflictResolution.newerWins,
    );
    return Column(
      children: [
        _buildCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow('الحالة', isEnabled ? (monitoringActive ? 'مفعلة ونشطة' : 'مفعلة لكن متوقفة') : 'معطلة'),
              _buildStatusRow('تسجيل الدخول', isSignedIn ? 'متصل بـ Google Drive' : 'غير متصل'),
              if (isSyncing) _buildStatusRow('النشاط الحالي', 'جارٍ المزامنة'),
              if (lastSync != null) _buildStatusRow('آخر فحص', _formatDateTime(DateTime.parse(lastSync))),
              if (deviceId != null) _buildStatusRow('معرف الجهاز', '${deviceId.substring(0, 8)}...'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          Column(
            children: [
              SwitchListTile(
                title: const Text('تفعيل المزامنة التلقائية بين الأجهزة'),
                subtitle: Text(isEnabled ? 'التحقق جارٍ بشكل دوري' : 'لن يتم فحص النسخ الجديدة'),
                value: isEnabled,
                onChanged: isSignedIn && !_syncBusy ? _toggleSmartSync : null,
              ),
              if (!isSignedIn)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('يتطلب تسجيل الدخول في Google Drive', style: TextStyle(color: Colors.orange, fontSize: 12)),
                ),
            ],
          ),
        ),
        if (isEnabled) ...[
          const SizedBox(height: 12),
          _buildCard(
            DropdownButtonFormField<int>(
              value: _intervalOptions.contains(syncInterval) ? syncInterval : _intervalOptions.first,
              decoration: const InputDecoration(labelText: 'فترة الفحص بالدقائق', prefixIcon: Icon(Icons.timer)),
              items: _intervalOptions
                  .map((minutes) => DropdownMenuItem(value: minutes, child: Text(_intervalLabel(minutes))))
                  .toList(),
              onChanged: _syncBusy ? null : (value) {
                if (value != null) _changeSyncInterval(value);
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            Column(
              children: [
                DropdownButtonFormField<ConflictResolution>(
                  value: resolution,
                  decoration: const InputDecoration(labelText: 'استراتيجية حل التضارب', prefixIcon: Icon(Icons.merge_type)),
                  items: _conflictDescriptions.entries
                      .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: _syncBusy ? null : (value) {
                    if (value != null) _changeConflictResolution(value);
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _conflictDescriptions[resolution] ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _syncBusy || !isSignedIn ? null : _manualSync,
                icon: _syncBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                label: const Text('مزامنة الآن'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackupSection(AsyncValue<Map<String, dynamic>> statusAsync) {
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorCard('تعذر تحميل إعدادات النسخ الاحتياطي'),
      data: (status) => _buildBackupContent(status),
    );
  }

  Widget _buildBackupContent(Map<String, dynamic> status) {
    final isEnabled = status['enabled'] as bool;
    final isBackingUp = status['is_backing_up'] as bool;
    final isSignedIn = status['signed_in'] as bool;
    final pendingChanges = status['pending_changes'] as int;
    final lastBackup = status['last_auto_backup'] as String?;
    final maxBackups = status['max_backups'] as int;
    final retentionDays = status['retention_days'] as int;
    if (_maxBackupsController.text.isEmpty) {
      _maxBackupsController.text = maxBackups.toString();
    }
    if (_retentionDaysController.text.isEmpty) {
      _retentionDaysController.text = retentionDays.toString();
    }
    return Column(
      children: [
        _buildCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow('الحالة', isEnabled ? 'مفعلة' : 'معطلة'),
              _buildStatusRow('تسجيل الدخول', isSignedIn ? 'متصل بـ Google Drive' : 'غير متصل'),
              if (isBackingUp) _buildStatusRow('النشاط الحالي', 'جارٍ إنشاء نسخة'),
              if (pendingChanges > 0) _buildStatusRow('تغييرات معلقة', pendingChanges.toString()),
              if (lastBackup != null) _buildStatusRow('آخر نسخة تلقائية', _formatDateTime(DateTime.parse(lastBackup))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          SwitchListTile(
            title: const Text('تفعيل النسخ الاحتياطي التلقائي بعد التغييرات'),
            subtitle: Text(isEnabled ? 'سيتم إنشاء نسخة بعد كل تعديل' : 'لن يتم إنشاء نسخ تلقائية'),
            value: isEnabled,
            onChanged: !_backupBusy ? _toggleAutoBackup : null,
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          Column(
            children: [
              TextFormField(
                controller: _maxBackupsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'عدد النسخ القصوى', suffixIcon: Icon(Icons.numbers)),
                enabled: !_backupBusy,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _retentionDaysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'فترة الاحتفاظ بالأيام', suffixIcon: Icon(Icons.calendar_today)),
                enabled: !_backupBusy,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          Column(
            children: [
              SwitchListTile(
                title: const Text('النسخ الاحتياطي المجدول يومياً'),
                subtitle: Text(_scheduledEnabled ? 'وقت التنفيذ ${_scheduledTime.format(context)}' : 'غير مفعل'),
                value: _scheduledEnabled,
                onChanged: _backupBusy ? null : _toggleScheduledBackup,
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('وقت التنفيذ'),
                subtitle: Text(_scheduledTime.format(context)),
                trailing: const Icon(Icons.edit),
                enabled: !_backupBusy,
                onTap: _backupBusy ? null : _selectTime,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _backupBusy ? null : _saveBackupSettings,
                icon: _backupBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('حفظ الإعدادات'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _backupBusy || !isSignedIn ? null : _cleanupBackups,
                icon: const Icon(Icons.cleaning_services),
                label: const Text('تنظيف النسخ القديمة'),
              ),
            ),
          ],
        ),
        if (!isSignedIn)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('يتطلب تسجيل الدخول في Google Drive لتنفيذ الإجراءات', style: TextStyle(color: Colors.orange, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildCard(Widget child) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  String? _formatOptionalDate(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    return _formatDateTime(dt);
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m';
  }

  String _intervalLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes دقيقة';
    }
    final hours = (minutes / 60).round();
    return '$hours ساعة';
  }
}
