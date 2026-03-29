import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';
import '../../../services/appwrite_logger.dart';
import '../../../services/google_drive_logger.dart';
import '../../../services/logging/log_models.dart';

/// Providers للوصول إلى السجلات
final appwriteLogsProvider = Provider<List<LogEntry>>((ref) {
  return AppwriteLogger().getLogs();
});

final googleDriveLogsProvider = Provider<List<LogEntry>>((ref) {
  final logger = GoogleDriveLogger();
  logger.addListener(() => ref.invalidateSelf());
  return logger.getLogs();
});

final allLogsProvider = Provider<List<LogEntry>>((ref) {
  final appwriteLogs = ref.watch(appwriteLogsProvider);
  final driveLogs = ref.watch(googleDriveLogsProvider);
  final allLogs = [...appwriteLogs, ...driveLogs];
  allLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return allLogs;
});

final syncLogsProvider = Provider<List<LogEntry>>((ref) {
  final allLogs = ref.watch(allLogsProvider);
  return allLogs.where((log) {
    final tag = log.tag.toUpperCase();
    return tag.contains('SYNC') ||
        tag.contains('DELTA') ||
        tag.contains('OUTBOX') ||
        tag.contains('MIRROR');
  }).toList();
});

/// Unified Logs Screen - شاشة موحدة لجميع السجلات
///
/// تدمج السجلات من:
/// - AppwriteLogger
/// - GoogleDriveLogger
/// - سجلات المزامنة
class UnifiedLogsScreen extends ConsumerStatefulWidget {
  const UnifiedLogsScreen({super.key});

  @override
  ConsumerState<UnifiedLogsScreen> createState() => _UnifiedLogsScreenState();
}

class _UnifiedLogsScreenState extends ConsumerState<UnifiedLogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedLevel = 'all';
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
          icon: const Icon(Icons.filter_list),
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
                  Text('مسح السجلات', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings, size: 20),
                  SizedBox(width: 8),
                  Text('إعدادات السجلات'),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'clear') _clearLogs();
            if (value == 'settings') _showSettingsDialog();
            if (value == 'refresh') {
              ref.invalidate(appwriteLogsProvider);
              ref.invalidate(googleDriveLogsProvider);
              ref.invalidate(allLogsProvider);
              ref.invalidate(syncLogsProvider);
            }
          },
        ),
      ],
      body: Column(
        children: [
          // Search Bar
          _buildSearchBar(),

          // Statistics Summary
          _buildStatisticsSummary(),

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
                Tab(text: 'المزامنة'),
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
                _buildSyncLogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSummary() {
    final appwriteStats = AppwriteLogger().getStatistics();
    final driveStats = GoogleDriveLogger().getStatistics();

    final totalErrors =
        (appwriteStats['error'] ?? 0) + (driveStats['error'] ?? 0);
    final totalWarnings =
        (appwriteStats['warning'] ?? 0) + (driveStats['warning'] ?? 0);
    final totalCritical =
        (appwriteStats['critical'] ?? 0) + (driveStats['critical'] ?? 0);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UIConstants.spacingMD,
        vertical: UIConstants.spacingSM,
      ),
      color: Colors.grey.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'أخطاء',
            totalErrors.toString(),
            Colors.red,
            Icons.error,
          ),
          _buildStatItem(
            'تحذيرات',
            totalWarnings.toString(),
            Colors.orange,
            Icons.warning,
          ),
          _buildStatItem(
            'حرجة',
            totalCritical.toString(),
            Colors.purple,
            Icons.priority_high,
          ),
          _buildStatItem(
            'إجمالي',
            ((appwriteStats['total'] ?? 0) + (driveStats['total'] ?? 0))
                .toString(),
            Colors.blue,
            Icons.list_alt,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
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
    final logs = ref.watch(allLogsProvider);
    return _buildLogsListFromEntries(logs, 'الكل');
  }

  Widget _buildAppwriteLogsTab() {
    final logs = ref.watch(appwriteLogsProvider);
    return _buildLogsListFromEntries(logs, 'Appwrite');
  }

  Widget _buildGoogleDriveLogsTab() {
    final logs = ref.watch(googleDriveLogsProvider);
    return _buildLogsListFromEntries(logs, 'Google Drive');
  }

  Widget _buildSyncLogsTab() {
    final logs = ref.watch(syncLogsProvider);
    return _buildLogsListFromEntries(logs, 'المزامنة');
  }

  Widget _buildLogsListFromEntries(List<LogEntry> logs, String source) {
    // Apply filters
    var filteredLogs = logs;

    if (_selectedLevel != 'all') {
      final level = _getLogLevelFromString(_selectedLevel);
      if (level != null) {
        filteredLogs = logs.where((log) => log.level == level).toList();
      }
    }

    if (_searchQuery.isNotEmpty) {
      filteredLogs = filteredLogs
          .where(
            (log) =>
                log.message.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                log.tag.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    if (filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'لا توجد سجلات ${source != 'الكل' ? "لـ $source" : ""}',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedLevel != 'all'
                  ? 'جرب تغيير فلتر المستوى'
                  : 'قم ببعض العمليات لإنشاء سجلات',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      itemCount: filteredLogs.length,
      itemBuilder: (context, index) {
        final log = filteredLogs[index];
        return _buildLogItemFromEntry(log);
      },
    );
  }

  LogLevel? _getLogLevelFromString(String level) {
    switch (level) {
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      case 'critical':
        return LogLevel.critical;
      default:
        return null;
    }
  }

  Widget _buildLogItemFromEntry(LogEntry log) {
    final level = log.level;
    final source = log.tag;
    final message = log.message;
    final timestamp = log.timestamp.toIso8601String();

    Color levelColor;
    IconData levelIcon;

    switch (level) {
      case LogLevel.debug:
        levelColor = Colors.grey;
        levelIcon = Icons.bug_report;
      case LogLevel.info:
        levelColor = Colors.blue;
        levelIcon = Icons.info;
      case LogLevel.warning:
        levelColor = Colors.orange;
        levelIcon = Icons.warning;
      case LogLevel.error:
        levelColor = Colors.red;
        levelIcon = Icons.error;
      case LogLevel.critical:
        levelColor = Colors.purple;
        levelIcon = Icons.priority_high;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: levelColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: Icon(levelIcon, color: levelColor, size: 20),
        ),
        title: Text(message, style: const TextStyle(fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.label, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  source,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 12),
                Icon(Icons.schedule, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  DateTimeFormatter.getRelativeTime(timestamp),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            if (log.error != null) ...[
              const SizedBox(height: 4),
              Text(
                'Error: ${log.error}',
                style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert, size: 20),
          onPressed: () => _showLogDetailsFromEntry(log),
        ),
      ),
    );
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
              leading: Radio<String>(
                value: 'all',
                groupValue: _selectedLevel,
                onChanged: (value) {
                  setState(() => _selectedLevel = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('Debug'),
              leading: Radio<String>(
                value: 'debug',
                groupValue: _selectedLevel,
                onChanged: (value) {
                  setState(() => _selectedLevel = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('معلومات'),
              leading: Radio<String>(
                value: 'info',
                groupValue: _selectedLevel,
                onChanged: (value) {
                  setState(() => _selectedLevel = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('تحذيرات'),
              leading: Radio<String>(
                value: 'warning',
                groupValue: _selectedLevel,
                onChanged: (value) {
                  setState(() => _selectedLevel = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('أخطاء'),
              leading: Radio<String>(
                value: 'error',
                groupValue: _selectedLevel,
                onChanged: (value) {
                  setState(() => _selectedLevel = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('حرجة'),
              leading: Radio<String>(
                value: 'critical',
                groupValue: _selectedLevel,
                onChanged: (value) {
                  setState(() => _selectedLevel = value!);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  void _showLogDetailsFromEntry(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفاصيل السجل'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('المستوى', log.level.name.toUpperCase()),
              _buildDetailRow('المصدر', log.tag),
              _buildDetailRow(
                'الوقت',
                DateTimeFormatter.formatDateTime(
                  log.timestamp.toIso8601String(),
                ),
              ),
              _buildDetailRow('الرسالة', log.message),
              if (log.error != null)
                _buildDetailRow('الخطأ', log.error.toString()),
              if (log.stackTrace != null)
                _buildDetailRow('Stack Trace', log.stackTrace.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _copyLogToClipboard(log);
            },
            child: const Text('نسخ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _copyLogToClipboard(LogEntry log) {
    Clipboard.setData(ClipboardData(text: log.toFormattedString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ السجل')));
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  void _exportLogs() async {
    try {
      final appwriteFile = await AppwriteLogger().exportLogs();
      final driveFile = await GoogleDriveLogger().exportLogs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تصدير السجلات:\n'
              'Appwrite: ${appwriteFile?.path ?? "فشل"}\n'
              'Google Drive: ${driveFile?.path ?? "فشل"}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل تصدير السجلات: $e')));
      }
    }
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text(
          'هل تريد حذف جميع السجلات؟ لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              AppwriteLogger().clearLogs();
              GoogleDriveLogger().clearLogs();
              ref.invalidate(appwriteLogsProvider);
              ref.invalidate(googleDriveLogsProvider);
              ref.invalidate(allLogsProvider);
              ref.invalidate(syncLogsProvider);
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

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات السجلات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('حفظ السجلات'),
              subtitle: const Text('تخزين السجلات على الجهاز'),
              value: true,
              onChanged: (value) {},
            ),
            ListTile(
              title: const Text('الاحتفاظ بالسجلات'),
              subtitle: const Text('7 أيام'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {},
            ),
            ListTile(
              title: const Text('مسار ملف السجل'),
              subtitle: Text(
                AppwriteLogger().currentLogFilePath ?? 'غير محدد',
                style: const TextStyle(fontSize: 11),
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
}
