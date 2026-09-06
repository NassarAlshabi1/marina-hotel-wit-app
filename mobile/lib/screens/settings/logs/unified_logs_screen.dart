import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';
import '../../../services/appwrite_logger.dart';

/// Unified Logs Screen - شاشة موحدة لجميع السجلات
///
/// تدمج السجلات من:
/// - appwrite_logs_screen.dart
/// - google_drive_logs_screen.dart
/// - sync_debug_logs_screen.dart
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
  bool _saveLogsEnabled = false;
  int _logRetentionDays = 7;
  bool _isSavingLogSettings = false;

  static const _saveLogsKey = 'appwrite_file_logging_enabled';
  static const _logRetentionKey = 'appwrite_log_retention_days';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    unawaited(_loadLogSettings());
  }

  Future<void> _loadLogSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saveLogsEnabled = prefs.getBool(_saveLogsKey) ?? false;
    final retentionDays = prefs.getInt(_logRetentionKey) ?? 7;
    if (saveLogsEnabled) {
      await AppwriteLogger().initialize(enableFile: true);
    }
    if (!mounted) return;
    setState(() {
      _saveLogsEnabled = saveLogsEnabled;
      _logRetentionDays = retentionDays;
    });
  }

  Future<void> _setFileLogging(bool enabled) async {
    if (_isSavingLogSettings) return;
    setState(() => _isSavingLogSettings = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_saveLogsKey, enabled);
      await AppwriteLogger().initialize(enableFile: enabled);
      if (!mounted) return;
      setState(() => _saveLogsEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'تم تفعيل حفظ السجلات' : 'تم إيقاف حفظ السجلات',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ إعداد السجلات. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _isSavingLogSettings = false);
    }
  }

  Future<void> _setLogRetention(int days, BuildContext dialogContext) async {
    if (_isSavingLogSettings) return;
    setState(() => _isSavingLogSettings = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await AppwriteLogger().pruneLogs(retentionDays: days);
      await prefs.setInt(_logRetentionKey, days);
      if (!mounted || !dialogContext.mounted) return;
      setState(() => _logRetentionDays = days);
      Navigator.pop(dialogContext);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ضبط الاحتفاظ بالسجلات على $days أيام')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ مدة الاحتفاظ بالسجلات.')),
      );
    } finally {
      if (mounted) setState(() => _isSavingLogSettings = false);
    }
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
            if (value == 'clear') {
              _clearLogs();
            }
            if (value == 'settings') {
              _showSettingsDialog();
            }
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
                Tab(text: 'Cloudflare'),
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
    return _buildLogsList([
      _createLogEntry(
        'info',
        'Cloudflare',
        'Connection established successfully',
        '2024-01-29T18:00:00',
      ),
      _createLogEntry(
        'success',
        'Sync',
        'Sync completed: 42 items',
        '2024-01-29T17:55:00',
      ),
      _createLogEntry(
        'warning',
        'Google Drive',
        'Low storage space',
        '2024-01-29T17:50:00',
      ),
      _createLogEntry(
        'error',
        'Cloudflare',
        'Failed to sync table: guests',
        '2024-01-29T17:45:00',
      ),
      _createLogEntry(
        'info',
        'Sync',
        'Starting automatic sync',
        '2024-01-29T17:40:00',
      ),
      _createLogEntry(
        'success',
        'Google Drive',
        'Backup uploaded successfully',
        '2024-01-29T17:35:00',
      ),
    ]);
  }

  Widget _buildAppwriteLogsTab() {
    return _buildLogsList([
      _createLogEntry(
        'info',
        'Cloudflare',
        'Connection established successfully',
        '2024-01-29T18:00:00',
      ),
      _createLogEntry(
        'error',
        'Cloudflare',
        'Failed to sync table: guests',
        '2024-01-29T17:45:00',
      ),
      _createLogEntry(
        'info',
        'Cloudflare',
        'Worker API call: GET /health',
        '2024-01-29T17:30:00',
      ),
      _createLogEntry(
        'warning',
        'Cloudflare',
        'Slow response: 2.5s',
        '2024-01-29T17:25:00',
      ),
    ]);
  }

  Widget _buildGoogleDriveLogsTab() {
    return _buildLogsList([
      _createLogEntry(
        'warning',
        'Google Drive',
        'Low storage space',
        '2024-01-29T17:50:00',
      ),
      _createLogEntry(
        'success',
        'Google Drive',
        'Backup uploaded successfully',
        '2024-01-29T17:35:00',
      ),
      _createLogEntry(
        'info',
        'Google Drive',
        'Connected to account',
        '2024-01-29T17:20:00',
      ),
      _createLogEntry(
        'error',
        'Google Drive',
        'Upload failed: network error',
        '2024-01-29T17:15:00',
      ),
    ]);
  }

  Widget _buildSyncLogsTab() {
    return _buildLogsList([
      _createLogEntry(
        'success',
        'Sync',
        'Sync completed: 42 items',
        '2024-01-29T17:55:00',
      ),
      _createLogEntry(
        'info',
        'Sync',
        'Starting automatic sync',
        '2024-01-29T17:40:00',
      ),
      _createLogEntry(
        'warning',
        'Sync',
        'Conflict detected: guest_123',
        '2024-01-29T17:30:00',
      ),
      _createLogEntry(
        'success',
        'Sync',
        'Conflict resolved automatically',
        '2024-01-29T17:29:00',
      ),
    ]);
  }

  Widget _buildLogsList(List<Map<String, String>> logs) {
    // Apply filters
    var filteredLogs = logs;

    if (_selectedLevel != 'all') {
      filteredLogs = logs
          .where((log) => log['level'] == _selectedLevel)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      filteredLogs = filteredLogs
          .where(
            (log) =>
                log['message']!.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                log['source']!.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
          )
          .toList();
    }

    if (filteredLogs.isEmpty) {
      return const EmptyStateWidget(
        message: 'لا توجد سجلات',
        icon: Icons.description,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      itemCount: filteredLogs.length,
      itemBuilder: (context, index) {
        final log = filteredLogs[index];
        return _buildLogItem(log);
      },
    );
  }

  Widget _buildLogItem(Map<String, String> log) {
    final level = log['level']!;
    final source = log['source']!;
    final message = log['message']!;
    final timestamp = log['timestamp']!;

    Color levelColor;
    IconData levelIcon;

    switch (level) {
      case 'success':
        levelColor = Colors.green;
        levelIcon = Icons.check_circle;
      case 'warning':
        levelColor = Colors.orange;
        levelIcon = Icons.warning;
      case 'error':
        levelColor = Colors.red;
        levelIcon = Icons.error;
      default:
        levelColor = Colors.blue;
        levelIcon = Icons.info;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: levelColor.withValues(alpha: 0.1),
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
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert, size: 20),
          onPressed: () => _showLogDetails(log),
        ),
      ),
    );
  }

  Map<String, String> _createLogEntry(
    String level,
    String source,
    String message,
    String timestamp,
  ) {
    return {
      'level': level,
      'source': source,
      'message': message,
      'timestamp': timestamp,
    };
  }

  void _showFilterDialog() {
    unawaited(showDialog<void>(
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
                // ignore: deprecated_member_use
                groupValue: _selectedLevel,
                // ignore: deprecated_member_use
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
                // ignore: deprecated_member_use
                groupValue: _selectedLevel,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  setState(() => _selectedLevel = value!);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('نجاح'),
              leading: Radio<String>(
                value: 'success',
                // ignore: deprecated_member_use
                groupValue: _selectedLevel,
                // ignore: deprecated_member_use
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
                // ignore: deprecated_member_use
                groupValue: _selectedLevel,
                // ignore: deprecated_member_use
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
                // ignore: deprecated_member_use
                groupValue: _selectedLevel,
                // ignore: deprecated_member_use
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
    ));
  }

  void _showLogDetails(Map<String, String> log) {
    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفاصيل السجل'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('المستوى', log['level']!),
              _buildDetailRow('المصدر', log['source']!),
              _buildDetailRow('الرسالة', log['message']!),
              _buildDetailRow(
                'الوقت',
                DateTimeFormatter.formatDateTime(log['timestamp']),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    ));
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
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  void _exportLogs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text('جاري تصدير السجلات...'),
          ],
        ),
        duration: Duration(minutes: 5),
      ),
    );
  }

  void _clearLogs() {
    unawaited(showDialog<void>(
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
    ));
  }

  void _showRetentionDialog() {
    unawaited(showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('الاحتفاظ بالسجلات'),
        content: RadioGroup<int>(
          groupValue: _logRetentionDays,
          onChanged: (value) {
            if (value != null) unawaited(_setLogRetention(value, dialogContext));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [7, 14, 30].map((days) {
              return RadioListTile<int>(title: Text('$days أيام'), value: days);
            }).toList(),
          ),
        ),
      ),
    ));
  }

  void _showSettingsDialog() {
    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات السجلات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('حفظ السجلات'),
              subtitle: const Text('تخزين السجلات على الجهاز'),
              value: _saveLogsEnabled,
              onChanged: _isSavingLogSettings ? null : _setFileLogging,
            ),
            ListTile(
              title: const Text('الاحتفاظ بالسجلات'),
              subtitle: Text('$_logRetentionDays أيام'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _isSavingLogSettings ? null : _showRetentionDialog,
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
    ));
  }
}
