import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/backup_provider.dart';
import '../../services/appwrite_logger.dart';
import '../../services/logging/log_models.dart';
import '../../utils/debug_logs.dart';

class ErrorCenterScreen extends ConsumerWidget {
  const ErrorCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appwriteLogs = ref.watch(logsProvider);
    final driveLogs = ref.watch(googleDriveLogsProvider);

    final appwriteErrors = _onlyErrors(appwriteLogs);
    final driveErrors = _onlyErrors(driveLogs);
    final debugEntries = DebugLogs.entries;

    return AppScaffold(
      title: 'مركز الأخطاء',
      actions: [
        IconButton(
          icon: const Icon(Icons.copy_all),
          tooltip: 'نسخ كل السجلات',
          onPressed: () => _copyAll(appwriteErrors, driveErrors, debugEntries),
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'مسح السجلات المؤقتة',
          onPressed: () {
            DebugLogs.clear();
            ref.read(appwriteLoggerProvider).clearLogs();
            ref.read(googleDriveLoggerProvider).clearLogs();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('تم مسح السجلات.')));
          },
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(
            appwriteCount: appwriteErrors.length,
            driveCount: driveErrors.length,
            debugCount: debugEntries.length,
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            title: 'أخطاء Appwrite',
            color: Colors.redAccent,
            entries: appwriteErrors.map(_toViewEntry).toList(),
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            title: 'أخطاء Google Drive',
            color: Colors.deepOrange,
            entries: driveErrors.map(_toViewEntry).toList(),
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            title: 'سجلات المزامنة والدمج',
            color: Colors.blueGrey,
            entries: debugEntries
                .map(
                  (e) => _ViewEntry(
                    title: e,
                    subtitle: 'DebugLogs',
                    timestamp: null,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  List<LogEntry> _onlyErrors(List<LogEntry> logs) {
    return logs
        .where((l) => l.level == LogLevel.error || l.level == LogLevel.critical)
        .toList(growable: false);
  }

  _ViewEntry _toViewEntry(LogEntry entry) {
    return _ViewEntry(
      title: entry.message,
      subtitle:
          '[${entry.tag}] ${entry.level.name.toUpperCase()}${entry.error != null ? ' • ${entry.error}' : ''}',
      timestamp: entry.timestamp,
    );
  }

  void _copyAll(
    List<LogEntry> appwrite,
    List<LogEntry> drive,
    List<String> debug,
  ) {
    final buffer = StringBuffer();
    for (final e in appwrite) {
      buffer.writeln('[APPWRITE] ${e.toFormattedString()}');
    }
    for (final e in drive) {
      buffer.writeln('[DRIVE] ${e.toFormattedString()}');
    }
    for (final e in debug) {
      buffer.writeln('[DEBUG] $e');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
  }
}

class _SummaryCard extends StatelessWidget {

  const _SummaryCard({
    required this.appwriteCount,
    required this.driveCount,
    required this.debugCount,
  });
  final int appwriteCount;
  final int driveCount;
  final int debugCount;

  @override
  Widget build(BuildContext context) {
    final total = appwriteCount + driveCount + debugCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'ملخص الأخطاء',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _chip('Appwrite', appwriteCount, Colors.redAccent),
                _chip('Google Drive', driveCount, Colors.deepOrange),
                _chip('Sync/Debug', debugCount, Colors.blueGrey),
                _chip('الإجمالي', total, Colors.black87),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, child: const SizedBox()),
      label: Text('$label: $count'),
    );
  }
}

class _ErrorSection extends StatelessWidget {

  const _ErrorSection({
    required this.title,
    required this.color,
    required this.entries,
  });
  final String title;
  final Color color;
  final List<_ViewEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا توجد أخطاء مسجلة'),
              )
            else
              ...entries.map(
                (e) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.title),
                  subtitle: Text(
                    e.subtitle,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: e.timestamp != null
                      ? Text(
                          _formatTime(e.timestamp!),
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    return DateFormat('yyyy/MM/dd HH:mm').format(value);
  }
}

class _ViewEntry {

  _ViewEntry({
    required this.title,
    required this.subtitle,
    required this.timestamp,
  });
  final String title;
  final String subtitle;
  final DateTime? timestamp;
}
