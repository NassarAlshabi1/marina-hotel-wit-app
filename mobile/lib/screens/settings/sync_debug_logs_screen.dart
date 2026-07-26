import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/smart_sync_provider.dart';
import '../../utils/debug_logs.dart';

class SyncDebugLogsScreen extends ConsumerStatefulWidget {
  const SyncDebugLogsScreen({super.key});

  @override
  ConsumerState<SyncDebugLogsScreen> createState() => _SyncDebugLogsScreenState();
}

class _SyncDebugLogsScreenState extends ConsumerState<SyncDebugLogsScreen> {
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    if (!mounted) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _forceSync() async {
    await _withBusy(() async {
      await ref.read(smartSyncManagerProvider).forceSyncNow();
      ref.invalidate(smartSyncStatusProvider);
    });
  }

  Future<void> _pushLocal() async {
    await _withBusy(() async {
      await ref.read(smartSyncManagerProvider).pushLocalChanges();
      ref.invalidate(smartSyncStatusProvider);
    });
  }

  Future<void> _pullRemote() async {
    await _withBusy(() async {
      await ref.read(smartSyncManagerProvider).pullRemoteChanges();
      ref.invalidate(smartSyncStatusProvider);
    });
  }

  void _clearLogs() {
    DebugLogs.clear();
  }

  void _copyAllLogs() {
    final text = DebugLogs.entries.join('\n');
    if (text.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ جميع السجلات.')));
  }

  void _copyEntry(String entry) {
    Clipboard.setData(ClipboardData(text: entry));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ السطر.')));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'سجلات المزامنة',
      actions: [
        IconButton(
          icon: const Icon(Icons.copy_all),
          tooltip: 'نسخ جميع السجلات',
          onPressed: _isBusy ? null : _copyAllLogs,
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'مسح السجلات',
          onPressed: _isBusy ? null : _clearLogs,
        ),
      ],
      body: Column(
        children: [
          _buildStatusCard(context),
          _buildActionsRow(context),
          const Divider(height: 0),
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: DebugLogs.notifier,
              builder: (context, logs, _) {
                if (logs.isEmpty) {
                  return const Center(child: Text('لا توجد سجلات بعد'));
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final entry = logs[logs.length - 1 - index];
                    return ListTile(
                      dense: true,
                      title: SelectableText(entry, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      trailing: IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () => _copyEntry(entry)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final statusAsync = ref.watch(smartSyncStatusProvider);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: statusAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
          data: (status) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.memory, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('حالة مدير المزامنة', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              _buildStatusRow('معرف الجهاز', (status['device_id'] ?? '---') as String),
              _buildStatusRow('تفعيل المزامنة', (status['enabled'] as bool? ?? false) ? 'مفعل' : 'معطل'),
              _buildStatusRow('تسجيل الدخول', (status['signed_in'] as bool? ?? false) ? 'متصل' : 'غير متصل'),
              _buildStatusRow('المراقبة الدورية', (status['monitoring_active'] as bool? ?? false) ? 'نشطة' : 'متوقفة'),
              _buildStatusRow('آخر فحص', (status['last_sync_check'] ?? '---') as String),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildActionButton(Icons.sync, 'مزامنة الآن', _forceSync),
          _buildActionButton(Icons.cloud_upload, 'رفع محلي', _pushLocal),
          _buildActionButton(Icons.cloud_download, 'سحب جديد', _pullRemote),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Future<void> Function() onPressed) {
    return ElevatedButton.icon(
      onPressed: _isBusy ? null : () => onPressed(),
      icon: _isBusy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
