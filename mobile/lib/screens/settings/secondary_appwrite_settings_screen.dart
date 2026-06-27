// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../providers/secondary_sync_provider.dart';
import '../../services/secondary_appwrite_config.dart';
import '../../services/secondary_appwrite_service.dart';
import '../../services/secondary_sync_manager.dart';

/// شاشة إعدادات الوجهة الثانوية لـ Appwrite
class SecondaryAppwriteSettingsScreen extends ConsumerStatefulWidget {
  const SecondaryAppwriteSettingsScreen({super.key});

  @override
  ConsumerState<SecondaryAppwriteSettingsScreen> createState() =>
      _SecondaryAppwriteSettingsScreenState();
}

class _SecondaryAppwriteSettingsScreenState
    extends ConsumerState<SecondaryAppwriteSettingsScreen> {
  final _endpointCtrl = TextEditingController();
  final _projectIdCtrl = TextEditingController();
  final _databaseIdCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();

  bool _obscureApiKey = true;
  bool _saving = false;
  bool _testing = false;
  bool _syncing = false;
  String? _message;
  bool? _success;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    await SecondaryAppwriteConfig.ensureInitialized();
    setState(() {
      _endpointCtrl.text = SecondaryAppwriteConfig.endpoint;
      _projectIdCtrl.text = SecondaryAppwriteConfig.projectId;
      _databaseIdCtrl.text = SecondaryAppwriteConfig.databaseId;
      _apiKeyCtrl.text = SecondaryAppwriteConfig.apiKey;
      _lastSync = SecondaryAppwriteConfig.lastSyncTime;
    });
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _projectIdCtrl.dispose();
    _databaseIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SecondaryAppwriteConfig.saveConfig(
        enabled: SecondaryAppwriteConfig.isEnabled,
        endpoint: _endpointCtrl.text.trim(),
        projectId: _projectIdCtrl.text.trim(),
        databaseId: _databaseIdCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        pushEnabled: SecondaryAppwriteConfig.isPushEnabled,
        pullEnabled: SecondaryAppwriteConfig.isPullEnabled,
      );
      SecondaryAppwriteService.instance.invalidate();
      ref.read(secondarySyncProvider.notifier).refresh();
      _showMessage(true, '✅ تم الحفظ');
    } catch (e) {
      _showMessage(false, '❌ فشل: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _toggleSync(bool value) async {
    await SecondaryAppwriteConfig.saveConfig(
      enabled: value,
      endpoint: _endpointCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      databaseId: _databaseIdCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      pushEnabled: SecondaryAppwriteConfig.isPushEnabled,
      pullEnabled: SecondaryAppwriteConfig.isPullEnabled,
    );

    // تحديث Provider
    ref.read(secondarySyncProvider.notifier).refresh();

    // التحكم بالتزامن التلقائي
    if (value) {
      SecondarySyncManager.instance.startAutoSync();
    } else {
      SecondarySyncManager.instance.stopAutoSync();
    }

    setState(() {});
    _showMessage(true, value ? '✅ المزامنة مُفعّلة' : '⏹️ المزامنة معطّلة');
  }

  Future<void> _togglePush(bool value) async {
    await SecondaryAppwriteConfig.saveConfig(
      enabled: SecondaryAppwriteConfig.isEnabled,
      endpoint: _endpointCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      databaseId: _databaseIdCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      pushEnabled: value,
      pullEnabled: SecondaryAppwriteConfig.isPullEnabled,
    );
    ref.read(secondarySyncProvider.notifier).refresh();
    setState(() {});
  }

  Future<void> _togglePull(bool value) async {
    await SecondaryAppwriteConfig.saveConfig(
      enabled: SecondaryAppwriteConfig.isEnabled,
      endpoint: _endpointCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      databaseId: _databaseIdCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      pushEnabled: SecondaryAppwriteConfig.isPushEnabled,
      pullEnabled: value,
    );
    ref.read(secondarySyncProvider.notifier).refresh();
    setState(() {});
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _message = null;
    });
    try {
      await _save();
      final result = await SecondaryAppwriteService.instance.testConnection();
      _showMessage(result, result ? '✅ الاتصال ناجح' : '❌ الاتصال فشل');
    } catch (e) {
      _showMessage(false, '❌ خطأ: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      final result = await SecondarySyncManager.instance.sync();
      _showMessage(result.success, result.message);
      if (result.success) {
        setState(() => _lastSync = DateTime.now());
        ref.read(secondarySyncProvider.notifier).updateLastSync(DateTime.now());
      }
    } catch (e) {
      _showMessage(false, '❌ خطأ: $e');
    } finally {
      setState(() => _syncing = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد المسح'),
        content: const Text('هل تريد مسح إعدادات الوجهة الثانوية؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await SecondaryAppwriteConfig.clear();
    SecondaryAppwriteService.instance.invalidate();
    SecondarySyncManager.instance.stopAutoSync();
    await _loadConfig();
    ref.read(secondarySyncProvider.notifier).refresh();
    _showMessage(true, '🧹 تم المسح');
  }

  void _showMessage(bool success, String msg) {
    setState(() {
      _success = success;
      _message = msg;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(success ? Icons.check_circle : Icons.error,
                color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = SecondaryAppwriteConfig.isEnabled;
    final isConfigured = SecondaryAppwriteConfig.isConfigured;

    return AppScaffold(
      title: 'Appwrite الثانوي',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── بطاقة معلوماتية ──
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'كيف تعمل المزامنة الثانوية؟',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• الـ outbox المحلي يُسلّم للوجهتين بالتوازي\n'
                    '• السجل يُحذف فقط بعد نجاح كلا الوجهتين\n'
                    '• لا فقدان بيانات عند فشل إحدى الوجهتين\n'
                    '• لا تكرار بسبب سباق البيانات\n'
                    '• تستخدم نفس collection IDs مثل Primary',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── حالة الاتصال ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud, color: Colors.blue, size: 24),
                      SizedBox(width: 8),
                      Text('حالة الاتصال',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: !enabled
                          ? Colors.grey.shade50
                          : !isConfigured
                              ? Colors.orange.shade50
                              : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !enabled
                            ? Colors.grey
                            : !isConfigured
                                ? Colors.orange
                                : Colors.green,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          !enabled
                              ? Icons.power_off
                              : !isConfigured
                                  ? Icons.warning
                                  : Icons.check_circle,
                          color: !enabled
                              ? Colors.grey
                              : !isConfigured
                                  ? Colors.orange
                                  : Colors.green,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            !enabled
                                ? 'معطّل'
                                : !isConfigured
                                    ? 'غير مُعدّ'
                                    : 'جاهز',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: !enabled
                                  ? Colors.grey
                                  : !isConfigured
                                      ? Colors.orange
                                      : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: Text(_testing ? 'جاري...' : 'اختبار الاتصال'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── إعدادات المزامنة ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sync, color: Colors.cyan, size: 24),
                      SizedBox(width: 8),
                      Text('إعدادات المزامنة',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    title: const Text('تفعيل المزامنة'),
                    subtitle: Text(enabled ? 'مُفعّلة' : 'معطّلة'),
                    value: enabled,
                    onChanged: _toggleSync,
                  ),
                  if (enabled) ...[
                    SwitchListTile(
                      title: const Text('Push (رفع البيانات)'),
                      subtitle: const Text('رفع التغييرات المحلية للثانوي'),
                      value: SecondaryAppwriteConfig.isPushEnabled,
                      onChanged: _togglePush,
                    ),
                    SwitchListTile(
                      title: const Text('Pull (سحب البيانات)'),
                      subtitle: const Text('سحب التغييرات من الثانوي — غير مُدعوم في هذه النسخة'),
                      value: SecondaryAppwriteConfig.isPullEnabled,
                      onChanged: _togglePull,
                    ),
                    const Divider(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _syncing ? null : _syncNow,
                        icon: _syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.sync),
                        label: Text(_syncing ? 'جاري...' : 'مزامنة الآن'),
                      ),
                    ),
                    if (_lastSync != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'آخر مزامنة: ${_formatDateTime(_lastSync!)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── إعدادات الاتصال ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.settings, color: Colors.grey, size: 24),
                      SizedBox(width: 8),
                      Text('إعدادات الاتصال',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  TextField(
                    controller: _endpointCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Endpoint',
                      hintText: 'https://example.appwrite.io/v1',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _projectIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Project ID',
                      hintText: 'معرف المشروع',
                      prefixIcon: Icon(Icons.folder),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _databaseIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Database ID',
                      hintText: 'معرف قاعدة البيانات',
                      prefixIcon: Icon(Icons.storage),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      prefixIcon: const Icon(Icons.key),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureApiKey
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureApiKey = !_obscureApiKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'جاري...' : 'حفظ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_message != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_success ?? false)
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    (_success ?? false) ? Icons.check_circle : Icons.error,
                    color: (_success ?? false) ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_message!)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── مسح ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 24),
                      SizedBox(width: 8),
                      Text('إدارة البيانات',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('مسح الإعدادات',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }
}
