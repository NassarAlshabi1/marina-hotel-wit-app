import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../services/cloudflare_config.dart';
import '../../utils/debug_logs.dart';

/// ✅ (2026-09-17) Cloudflare-only: كانت هذه الشاشة تعرض حالة/أزرار
/// SmartSync (Google Drive) — أُزيل نظام Drive كاملاً بطلب المستخدم.
/// عُيدت كتابتها لتعرض الحالة الحقيقية لمزامنة Cloudflare D1 (المدير
/// الفعلي) مع بقية عارض السجلات كما هو.
class SyncDebugLogsScreen extends ConsumerStatefulWidget {
  const SyncDebugLogsScreen({super.key});

  @override
  ConsumerState<SyncDebugLogsScreen> createState() =>
      _SyncDebugLogsScreenState();
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

  Future<void> _syncNow() async {
    await _withBusy(() async {
      final manager = ref.read(appwriteSyncManagerProvider);
      if (manager.token == null) {
        await manager.initialize();
      }
      await manager.sync();
    });
  }

  Future<void> _pushLocal() async {
    await _withBusy(() async {
      final manager = ref.read(appwriteSyncManagerProvider);
      if (manager.token == null) {
        await manager.initialize();
      }
      await manager.sync(pull: false);
    });
  }

  Future<void> _pullRemote() async {
    await _withBusy(() async {
      final manager = ref.read(appwriteSyncManagerProvider);
      if (manager.token == null) {
        await manager.initialize();
      }
      await manager.sync(push: false, deltaOnly: true, forcePull: true);
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
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ جميع السجلات.')));
  }

  void _copyEntry(String entry) {
    unawaited(Clipboard.setData(ClipboardData(text: entry)));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ السطر.')));
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
                      title: SelectableText(
                        entry,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copyEntry(entry),
                      ),
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
    final connection = ref.watch(connectionStatusProvider);
    final manager = ref.read(appwriteSyncManagerProvider);
    final checked = connection.lastCheckedAt != null;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.memory,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'حالة مزامنة Cloudflare',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow('معرف الجهاز', manager.currentDeviceId ?? '---'),
            _buildStatusRow('نقطة النهاية', CloudflareConfig.workerUrl),
            _buildStatusRow(
              'Worker',
              checked
                  ? (connection.isConnected ? 'متصل' : 'غير متصل')
                  : 'لم يُفحص بعد',
            ),
            _buildStatusRow(
              'قاعدة D1',
              connection.isD1Connected == null
                  ? 'لم تُفحص بعد'
                  : (connection.isD1Connected!
                        ? 'تستجيب${connection.d1LatencyMs == null ? '' : ' (${connection.d1LatencyMs}ms)'}'
                        : (connection.d1Error ?? 'لا تستجيب')),
            ),
          ],
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
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _syncNow,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('مزامنة كاملة'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _pushLocal,
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('رفع'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _pullRemote,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('سحب'),
            ),
          ),
        ],
      ),
    );
  }
}
