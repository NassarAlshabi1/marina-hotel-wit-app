import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../components/app_scaffold.dart';
import '../../services/appwrite_logger.dart';

class AppwriteLogsScreen extends ConsumerStatefulWidget {
  const AppwriteLogsScreen({super.key});

  @override
  ConsumerState<AppwriteLogsScreen> createState() => _AppwriteLogsScreenState();
}

class _AppwriteLogsScreenState extends ConsumerState<AppwriteLogsScreen> {
  LogLevel? _filterLevel;
  String _searchQuery = '';
  Timer? _debounceTimer;
  Timer? _refreshTimer;
  List<LogEntry> _currentLogs = [];

  @override
  void initState() {
    super.initState();
    // بدء التحديث التلقائي كل ثانية
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// بدء التحديث التلقائي
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // ✅ لفّ في try-catch — لو رمى setState/build استثناء، لا يتوقف الـ timer
      // صامتاً (يفقد المستخدم auto-refresh دون أن يعرف).
      try {
        if (mounted) {
          setState(() {}); // تحديث الشاشة
        }
      } catch (e) {
        debugPrint('⚠️ appwrite_logs auto-refresh setState failed: $e');
      }
    });
  }

  /// إيقاف التحديث التلقائي
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// الحصول على السجلات الحالية من Logger
  List<LogEntry> _getCurrentLogs() {
    try {
      // TODO: integrate with CloudflareSyncManager audit log
      return <LogEntry>[];
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // الحصول على السجلات مباشرة من Logger في كل تحديث
    final logs = _getCurrentLogs();
    final filteredLogs = _filterLogs(logs);

    // حفظ السجلات الحالية للنسخ والتصدير
    _currentLogs = filteredLogs;

    return AppScaffold(
      title: 'سجلات Appwrite',
      actions: [
        // زر تحديث يدوي
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
          onPressed: () => setState(() {}),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'export':
                unawaited(_exportLogs());
              case 'share':
                unawaited(_shareLogs(_currentLogs));
              case 'clear':
                unawaited(_clearLogs());
              case 'copy_all':
                unawaited(_copyAllLogs());
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'copy_all',
              child: Row(
                children: [
                  Icon(Icons.copy_all),
                  SizedBox(width: 8),
                  Text('نسخ جميع السجلات'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.file_download),
                  SizedBox(width: 8),
                  Text('تصدير السجلات'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share),
                  SizedBox(width: 8),
                  Text('مشاركة السجلات'),
                ],
              ),
            ),
            const PopupMenuItem(
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
          // شريط الفلترة والبحث
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // عدد السجلات
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'عدد السجلات: ${filteredLogs.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (_searchQuery.isNotEmpty || _filterLevel != null)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _filterLevel = null;
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('إعادة تعيين'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // شريط البحث
                TextField(
                  decoration: InputDecoration(
                    hintText: 'البحث في السجلات...',
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

                // فلترة حسب المستوى
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('الكل', null, filteredLogs.length),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Debug',
                        LogLevel.debug,
                        logs.where((l) => l.level == LogLevel.debug).length,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Info',
                        LogLevel.info,
                        logs.where((l) => l.level == LogLevel.info).length,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Warning',
                        LogLevel.warning,
                        logs.where((l) => l.level == LogLevel.warning).length,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Error',
                        LogLevel.error,
                        logs.where((l) => l.level == LogLevel.error).length,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Critical',
                        LogLevel.critical,
                        logs.where((l) => l.level == LogLevel.critical).length,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // قائمة السجلات
          Expanded(
            child: filteredLogs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد سجلات',
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
                      final log =
                          filteredLogs[filteredLogs.length -
                              1 -
                              index]; // عكس الترتيب
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
      selectedColor: color.withValues(alpha: 0.2),
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
              // العنوان (المستوى + الوقت)
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    log.level.name.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('HH:mm:ss').format(log.timestamp),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // الرسالة
              Text(
                log.message,
                style: const TextStyle(fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // Tag
              if (log.tag.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.tag,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],

              // معاينة الخطأ
              if (log.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.error.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getColorForLevel(LogLevel? level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.critical:
        return Colors.deepPurple;
      default:
        return Colors.black87;
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
        return Icons.crisis_alert;
    }
  }

  List<LogEntry> _filterLogs(List<LogEntry> logs) {
    var filtered = logs;

    // فلترة حسب المستوى
    if (_filterLevel != null) {
      filtered = filtered.where((log) => log.level == _filterLevel).toList();
    }

    // فلترة حسب البحث
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((log) {
        return log.message.toLowerCase().contains(_searchQuery) ||
            log.tag.toLowerCase().contains(_searchQuery) ||
            (log.error?.toString().toLowerCase().contains(_searchQuery) ??
                false);
      }).toList();
    }

    return filtered;
  }

  void _showLogDetails(LogEntry log) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getIconForLevel(log.level),
              color: _getColorForLevel(log.level),
            ),
            const SizedBox(width: 8),
            Text(log.level.name.toUpperCase()),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                'الوقت',
                DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp),
              ),
              _buildDetailRow('Tag', log.tag),
              const SizedBox(height: 12),
              const Text(
                'الرسالة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(log.message),
              if (log.error != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'الخطأ:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.error.toString(),
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  ),
                ),
              ],
              if (log.stackTrace != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Stack Trace:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.stackTrace.toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _copyLog(log), child: const Text('نسخ')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _copyLog(LogEntry log) {
    Clipboard.setData(ClipboardData(text: log.toFormattedString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ السجل إلى الحافظة')));
  }

  /// نسخ جميع السجلات
  Future<void> _copyAllLogs() async {
    if (_currentLogs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد سجلات لنسخها')));
      return;
    }

    final buffer = StringBuffer();
    for (final log in _currentLogs) {
      buffer.writeln(log.toFormattedString());
      buffer.writeln('─' * 50);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text('تم نسخ ${_currentLogs.length} سجل إلى الحافظة'),
        ),
      );
    }
  }

  Future<void> _exportLogs() async {
    // TODO: integrate with CloudflareSyncManager audit log export
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد سجلات للتصدير')));
    }
  }

  Future<void> _shareLogs(List<LogEntry> logs) async {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد سجلات للمشاركة')));
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Appwrite Logs Export');
    buffer.writeln('═' * 50);
    buffer.writeln(
      'Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
    );
    buffer.writeln('Total Logs: ${logs.length}');
    buffer.writeln('═' * 50);
    buffer.writeln();

    for (final log in logs) {
      buffer.writeln(log.toFormattedString());
      buffer.writeln('─' * 50);
    }

    await Share.share(
      buffer.toString(),
      subject:
          'Appwrite Logs - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
    );
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هل تريد مسح جميع السجلات؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<bool>(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop<bool>(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      // إيقاف التحديث المؤقت
      _stopAutoRefresh();

      // مسح السجلات
      // تحديث الشاشة فوراً
      setState(() {
        _currentLogs = <LogEntry>[];
      });

      // إعادة تشغيل التحديث التلقائي
      _startAutoRefresh();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم مسح السجلات')));
      }
    }
  }
}
