import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';
import '../../../providers/appwrite_providers.dart';
import '../../../services/appwrite_logger.dart';
import '../../../services/google_drive_logger.dart';

/// Unified Logs Screen - شاشة موحدة لجميع السجلات
///
/// تدمج السجلات من:
/// - Appwrite Logger
/// - Google Drive Logger
/// - Sync Debug Logs
class UnifiedLogsScreen extends ConsumerStatefulWidget {
  const UnifiedLogsScreen({super.key});

  @override
  ConsumerState<UnifiedLogsScreen> createState() => _UnifiedLogsScreenState();
}

class _UnifiedLogsScreenState extends ConsumerState<UnifiedLogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  LogLevel? _filterLevel;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'السجلات',
      actions: [
        IconButton(
          onPressed: _showFilterDialog,
          icon: Icon(Icons.filter_list,
              color: _filterLevel != null ? Colors.blue : null),
          tooltip: 'تصفية',
        ),
        IconButton(
          onPressed: _exportLogs,
          icon: const Icon(Icons.download),
          tooltip: 'تصدير',
        ),
        PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 20),
                  SizedBox(width: 8),
                  Text('تحديث'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_forever, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'مسح السجلات',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'clear') _clearLogs();
            if (value == 'refresh') setState(() {});
          },
        ),
      ],
      body: Column(
        children: [
          // Search Bar
          _buildSearchBar(),

          // Tab Bar
          ColoredBox(
            color: Colors.grey.shade100,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              isScrollable: true,
              tabs: const [
                Tab(text: 'الكل'),
                Tab(text: 'Appwrite'),
                Tab(text: 'Google Drive'),
                Tab(text: 'أخطاء المزامنة'),
              ],
            ),
          ),

          // Tabs Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllLogsTab(),
                _buildAppwriteLogsTab(),
                _buildGoogleDriveLogsTab(),
                _buildSyncErrorsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      color: Colors.white,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'بحث في السجلات...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildAllLogsTab() {
    final appwriteLogs = ref.watch(logsProvider);
    final driveLogs = GoogleDriveLogger().logs;

    // دمج كل السجلات
    final allLogs = <LogEntry>[...appwriteLogs, ...driveLogs];
    allLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return _buildLogsList(allLogs, 'الكل');
  }

  Widget _buildAppwriteLogsTab() {
    final logs = ref.watch(logsProvider);
    final filteredLogs = logs.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _buildLogsList(filteredLogs, 'Appwrite');
  }

  Widget _buildGoogleDriveLogsTab() {
    final logs = GoogleDriveLogger().logs;
    final filteredLogs = logs.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _buildLogsList(filteredLogs, 'Google Drive');
  }

  Widget _buildSyncErrorsTab() {
    final logs = ref.watch(logsProvider);
    final errorLogs = logs.where((l) =>
        l.level == LogLevel.error ||
        l.level == LogLevel.critical ||
        l.tag.contains('SYNC') ||
        l.tag.contains('DELTA')).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _buildLogsList(errorLogs, 'أخطاء المزامنة');
  }

  Widget _buildLogsList(List<LogEntry> logs, String source) {
    // Apply filters
    var filteredLogs = logs;

    if (_filterLevel != null) {
      filteredLogs = logs.where((log) => log.level == _filterLevel).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filteredLogs = filteredLogs.where((log) {
        return log.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            log.tag.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (log.error?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      }).toList();
    }

    if (filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'لا توجد سجلات',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            if (_filterLevel != null || _searchQuery.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  _filterLevel = null;
                  _searchQuery = '';
                }),
                icon: const Icon(Icons.clear_all),
                label: const Text('مسح الفلاتر'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        // شريط الإحصائيات
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Text(
                '${filteredLogs.length} سجل',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              _buildMiniStat('أخطاء', filteredLogs.where((l) => l.level == LogLevel.error).length, Colors.red),
              const SizedBox(width: 12),
              _buildMiniStat('تحذيرات', filteredLogs.where((l) => l.level == LogLevel.warning).length, Colors.orange),
            ],
          ),
        ),
        // قائمة السجلات
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            itemCount: filteredLogs.length,
            itemBuilder: (context, index) {
              return _buildLogItem(filteredLogs[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }

  Widget _buildLogItem(LogEntry log) {
    final color = _getColorForLevel(log.level);
    final icon = _getIconForLevel(log.level);

    return Card(
      margin: const EdgeInsets.only(bottom: UIConstants.spacingSM),
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
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.level.name.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          log.tag,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('HH:mm:ss').format(log.timestamp),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // الرسالة
              Text(
                log.message,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

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
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.error.toString(),
                          style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                          maxLines: 1,
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

  Color _getColorForLevel(LogLevel level) {
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

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصفية السجلات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('الكل'),
              leading: Radio<LogLevel?>(
                value: null,
                groupValue: _filterLevel,
                onChanged: (value) {
                  setState(() => _filterLevel = value);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('Debug'),
              leading: Radio<LogLevel?>(
                value: LogLevel.debug,
                groupValue: _filterLevel,
                onChanged: (value) {
                  setState(() => _filterLevel = value);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('Info'),
              leading: Radio<LogLevel?>(
                value: LogLevel.info,
                groupValue: _filterLevel,
                onChanged: (value) {
                  setState(() => _filterLevel = value);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('تحذيرات'),
              leading: Radio<LogLevel?>(
                value: LogLevel.warning,
                groupValue: _filterLevel,
                onChanged: (value) {
                  setState(() => _filterLevel = value);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('أخطاء'),
              leading: Radio<LogLevel?>(
                value: LogLevel.error,
                groupValue: _filterLevel,
                onChanged: (value) {
                  setState(() => _filterLevel = value);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('حرجة'),
              leading: Radio<LogLevel?>(
                value: LogLevel.critical,
                groupValue: _filterLevel,
                onChanged: (value) {
                  setState(() => _filterLevel = value);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showLogDetails(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getIconForLevel(log.level), color: _getColorForLevel(log.level)),
            const SizedBox(width: 8),
            Text(log.level.name.toUpperCase()),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('الوقت', DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp)),
              _buildDetailRow('Tag', log.tag),
              const SizedBox(height: 12),
              const Text('الرسالة:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText(log.message),
              if (log.error != null) ...[
                const SizedBox(height: 12),
                const Text('الخطأ:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    log.error.toString(),
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  ),
                ),
              ],
              if (log.stackTrace != null) ...[
                const SizedBox(height: 12),
                const Text('Stack Trace:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.stackTrace.toString(),
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _copyLog(log), child: const Text('نسخ')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _copyLog(LogEntry log) {
    Clipboard.setData(ClipboardData(text: log.toFormattedString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ السجل إلى الحافظة')),
    );
  }

  Future<void> _exportLogs() async {
    final appwriteLogs = ref.read(logsProvider);
    final driveLogs = GoogleDriveLogger().logs;
    final allLogs = <LogEntry>[...appwriteLogs, ...driveLogs]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (allLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات للتصدير')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Marina Hotel - Logs Export');
    buffer.writeln('═' * 50);
    buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buffer.writeln('Total Logs: ${allLogs.length}');
    buffer.writeln('═' * 50);
    buffer.writeln();

    for (final log in allLogs) {
      buffer.writeln(log.toFormattedString());
      buffer.writeln('─' * 50);
    }

    await Share.share(
      buffer.toString(),
      subject: 'Marina Hotel Logs - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
    );
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text('هل تريد حذف جميع السجلات؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(appwriteLoggerProvider).clearLogs();
              GoogleDriveLogger().clearLogs();
              setState(() {});
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم مسح جميع السجلات')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
