import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../utils/debug_logs.dart';

class SyncDebugLogsScreen extends ConsumerStatefulWidget {
  const SyncDebugLogsScreen({super.key});

  @override
  ConsumerState<SyncDebugLogsScreen> createState() =>
      _SyncDebugLogsScreenState();
}

class _SyncDebugLogsScreenState extends ConsumerState<SyncDebugLogsScreen> {
  void _clearLogs() {
    DebugLogs.clear();
  }

  void _copyAllLogs() {
    final text = DebugLogs.entries.join('\n');
    if (text.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ جميع السجلات.')));
  }

  void _copyEntry(String entry) {
    Clipboard.setData(ClipboardData(text: entry));
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
          onPressed: _copyAllLogs,
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'مسح السجلات',
          onPressed: _clearLogs,
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'تمت إزالة SmartSyncManager. المزامنة تتم عبر Appwrite فقط.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
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
}
