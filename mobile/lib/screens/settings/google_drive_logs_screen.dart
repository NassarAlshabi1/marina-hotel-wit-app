import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../components/app_scaffold.dart';
import '../../providers/backup_provider.dart';
import '../../services/logging/log_models.dart';

class GoogleDriveLogsScreen extends ConsumerStatefulWidget {
  const GoogleDriveLogsScreen({super.key});

  @override
  ConsumerState<GoogleDriveLogsScreen> createState() =>
      _GoogleDriveLogsScreenState();
}

class _GoogleDriveLogsScreenState extends ConsumerState<GoogleDriveLogsScreen> {
  LogLevel? _filterLevel;
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(googleDriveLogsProvider);
    final logStats = ref.watch(googleDriveLogStatsProvider);
    final filteredLogs = _filterLogs(logs);

    return AppScaffold(
      title: 'سجلات Google Drive',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'export':
                _exportLogs();
                break;
              case 'share':
                _shareLogs(filteredLogs);
                break;
              case 'clear':
                _clearLogs();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.file_download),
                  SizedBox(width: 8),
                  Text('تصدير السجلات'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share),
                  SizedBox(width: 8),
                  Text('مشاركة السجلات'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('مسح السجلات', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
      body: Column(
        children: [
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'البحث في سجلات Google Drive...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (value) {
                    _debounceTimer?.cancel();
                    _debounceTimer = Timer(
                      const Duration(milliseconds: 300),
                      () {
                        setState(() => _searchQuery = value.toLowerCase());
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('الكل', null, logStats['total'] ?? 0),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Debug',
                        LogLevel.debug,
                        logStats['debug'] ?? 0,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Info',
                        LogLevel.info,
                        logStats['info'] ?? 0,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Warning',
                        LogLevel.warning,
                        logStats['warning'] ?? 0,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Error',
                        LogLevel.error,
                        logStats['error'] ?? 0,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Critical',
                        LogLevel.critical,
                        logStats['critical'] ?? 0,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredLogs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد سجلات Google Drive',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredLogs.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = filteredLogs[filteredLogs.length - 1 - index];
                      return _buildLogEntry(log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, LogLevel? level, int count) {
    final isSelected = _filterLevel == level;
    final color = _getColorForLevel(level);

    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterLevel = selected ? level : null);
      },
      backgroundColor: Colors.white,
      selectedColor: color.withOpacity(0.2),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    final color = _getColorForLevel(log.level);
    final icon = _getIconForLevel(log.level);
    final formatter = DateFormat('yyyy/MM/dd HH:mm:ss');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _showLogDetails(log),
        onLongPress: () => _copyLog(log),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    log.level.name.toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    formatter.format(log.timestamp),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                log.message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: color.withOpacity(0.1),
                    ),
                    child: Text(
                      log.tag,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (log.error != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        log.error.toString(),
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getColorForLevel(LogLevel? level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.blueGrey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.critical:
        return Colors.purple;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getIconForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.warning:
        return Icons.warning;
      case LogLevel.error:
        return Icons.error;
      case LogLevel.critical:
        return Icons.warning_amber;
    }
  }

  List<LogEntry> _filterLogs(List<LogEntry> logs) {
    return logs.where((log) {
      final matchesLevel = _filterLevel == null || log.level == _filterLevel;
      final matchesQuery = _searchQuery.isEmpty ||
          log.message.toLowerCase().contains(_searchQuery) ||
          log.tag.toLowerCase().contains(_searchQuery) ||
          (log.error?.toString().toLowerCase().contains(_searchQuery) ?? false);
      return matchesLevel && matchesQuery;
    }).toList();
  }

  void _showLogDetails(LogEntry log) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final formatter = DateFormat('yyyy/MM/dd HH:mm:ss');
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    log.level.name.toUpperCase(),
                    style: TextStyle(
                      color: _getColorForLevel(log.level),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      _copyLog(log);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatter.format(log.timestamp),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Text(log.message, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.label, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(log.tag, style: const TextStyle(color: Colors.grey)),
                ],
              ),
              if (log.error != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'الخطأ:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  log.error.toString(),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              if (log.stackTrace != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Stack Trace:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 120,
                  child: SingleChildScrollView(
                    child: Text(
                      log.stackTrace.toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _copyLog(LogEntry log) {
    Clipboard.setData(ClipboardData(text: log.toFormattedString()));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم نسخ السجل إلى الحافظة')));
    }
  }

  Future<void> _shareLogs(List<LogEntry> logs) async {
    if (logs.isEmpty) {
      return;
    }
    final file = await ref.read(googleDriveLoggerProvider).exportLogs();
    if (file == null) {
      return;
    }
    await Share.shareXFiles([XFile(file.path)], text: 'سجلات Google Drive');
  }

  Future<void> _exportLogs() async {
    final file = await ref.read(googleDriveLoggerProvider).exportLogs();
    if (file == null) {
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم حفظ الملف في ${file.path}')));
    }
  }

  void _clearLogs() {
    ref.read(googleDriveLoggerProvider).clearLogs();
  }
}
