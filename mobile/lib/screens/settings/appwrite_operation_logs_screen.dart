import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../services/appwrite_logger.dart';

/// شاشة سجلات أخطاء العمليات (اتصال، رفع، سحب)
class AppwriteOperationLogsScreen extends ConsumerStatefulWidget {
  const AppwriteOperationLogsScreen({super.key});

  @override
  ConsumerState<AppwriteOperationLogsScreen> createState() =>
      _AppwriteOperationLogsScreenState();
}

class _AppwriteOperationLogsScreenState
    extends ConsumerState<AppwriteOperationLogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  OperationType? _filterOperation;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);

    // تحديث دوري كل 5 ثواني
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      switch (_tabController.index) {
        case 0:
          _filterOperation = null; // الكل
        case 1:
          _filterOperation = OperationType.connection;
        case 2:
          _filterOperation = OperationType.push;
        case 3:
          _filterOperation = OperationType.pull;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final logger = ref.watch(appwriteLoggerProvider);
    final stats = logger.getStatistics();
    final errors = logger.getOperationErrors(operationType: _filterOperation);

    return AppScaffold(
      title: 'سجلات أخطاء العمليات',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'export':
                _exportLogs(errors);
              case 'clear':
                _clearErrors();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.file_download),
                  SizedBox(width: 8),
                  Text('تصدير الأخطاء'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('مسح الأخطاء', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
      body: Column(
        children: [
          // إحصائيات الأخطاء
          _buildErrorStats(stats),

          // شريط التبويبات
          Container(
            color: Colors.grey.shade100,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.black87,
              indicatorColor: Colors.blue,
              tabs: [
                Tab(text: 'الكل (${stats['total'] ?? 0})'),
                Tab(
                  text: 'اتصال (${stats['connection_errors'] ?? 0})',
                  icon: const Icon(Icons.link, size: 18),
                ),
                Tab(
                  text: 'رفع (${stats['push_errors'] ?? 0})',
                  icon: const Icon(Icons.upload, size: 18),
                ),
                Tab(
                  text: 'سحب (${stats['pull_errors'] ?? 0})',
                  icon: const Icon(Icons.download, size: 18),
                ),
              ],
            ),
          ),

          // قائمة الأخطاء
          Expanded(
            child: errors.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: errors.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final error =
                          errors[errors.length - 1 - index]; // الأحدث أولاً
                      return _buildErrorCard(error);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorStats(Map<String, int> stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.red.shade200),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              icon: Icons.link_off,
              label: 'أخطاء الاتصال',
              count: stats['connection_errors'] ?? 0,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatItem(
              icon: Icons.cloud_upload,
              label: 'أخطاء الرفع',
              count: stats['push_errors'] ?? 0,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatItem(
              icon: Icons.cloud_download,
              label: 'أخطاء السحب',
              count: stats['pull_errors'] ?? 0,
              color: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد أخطاء',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'جميع العمليات تعمل بشكل صحيح',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(LogEntry error) {
    final color = error.level == LogLevel.critical
        ? Colors.deepPurple
        : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: InkWell(
        onTap: () => _showErrorDetails(error),
        onLongPress: () => _copyError(error),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // العنوان: نوع العملية + الوقت
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getOperationIcon(error.operationType), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          error.operationName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('HH:mm:ss').format(error.timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  if (error.retryCount != null && error.retryCount! > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'محاولة ${error.retryCount}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // الرسالة
              Text(
                error.message,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // معلومات إضافية
              if (error.entity != null ||
                  error.recordId != null ||
                  error.statusCode != null ||
                  error.duration != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (error.entity != null)
                      _buildInfoChip('الكيان', error.entity!),
                    if (error.recordId != null)
                      _buildInfoChip('المعرف', error.recordId!),
                    if (error.statusCode != null)
                      _buildInfoChip('الكود', '${error.statusCode}'),
                    if (error.duration != null)
                      _buildInfoChip('المدة', '${error.duration}ms'),
                  ],
                ),
              ],

              // معاينة الخطأ
              if (error.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    error.error.toString(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10,
          color: Colors.blue.shade800,
        ),
      ),
    );
  }

  IconData _getOperationIcon(OperationType type) {
    switch (type) {
      case OperationType.connection:
        return Icons.link;
      case OperationType.push:
        return Icons.upload;
      case OperationType.pull:
        return Icons.download;
      case OperationType.general:
        return Icons.info;
    }
  }

  void _showErrorDetails(LogEntry error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getOperationIcon(error.operationType),
              color: Colors.red,
            ),
            const SizedBox(width: 8),
            Text('${error.operationName} - ${error.level.name.toUpperCase()}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('الوقت', DateFormat('yyyy-MM-dd HH:mm:ss').format(error.timestamp)),
              _buildDetailRow('العملية', error.operationName),
              if (error.entity != null) _buildDetailRow('الكيان', error.entity!),
              if (error.recordId != null) _buildDetailRow('المعرف', error.recordId!),
              if (error.statusCode != null) _buildDetailRow('رمز الحالة', '${error.statusCode}'),
              if (error.duration != null) _buildDetailRow('المدة', '${error.duration}ms'),
              if (error.retryCount != null) _buildDetailRow('محاولات الإعادة', '${error.retryCount}'),
              const SizedBox(height: 12),
              const Text(
                'الرسالة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(error.message),
              if (error.error != null) ...[
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
                  child: SelectableText(
                    error.error.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              if (error.stackTrace != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Stack Trace:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      error.stackTrace.toString(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copyError(error),
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

  void _copyError(LogEntry error) {
    Clipboard.setData(ClipboardData(text: error.toFormattedString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الخطأ إلى الحافظة')),
    );
  }

  Future<void> _exportLogs(List<LogEntry> errors) async {
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أخطاء للتصدير')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('سجلات أخطاء العمليات - Appwrite');
    buffer.writeln('═' * 60);
    buffer.writeln(
      'تاريخ التصدير: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
    );
    buffer.writeln('عدد الأخطاء: ${errors.length}');
    buffer.writeln('═' * 60);
    buffer.writeln();

    for (final error in errors) {
      buffer.writeln('【${error.operationName}】 ${error.level.name.toUpperCase()}');
      buffer.writeln('الوقت: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(error.timestamp)}');
      if (error.entity != null) buffer.writeln('الكيان: ${error.entity}');
      if (error.recordId != null) buffer.writeln('المعرف: ${error.recordId}');
      if (error.statusCode != null) buffer.writeln('رمز الحالة: ${error.statusCode}');
      if (error.retryCount != null) buffer.writeln('محاولات الإعادة: ${error.retryCount}');
      if (error.duration != null) buffer.writeln('المدة: ${error.duration}ms');
      buffer.writeln('الرسالة: ${error.message}');
      if (error.error != null) buffer.writeln('الخطأ: ${error.error}');
      if (error.stackTrace != null) {
        buffer.writeln('Stack Trace:');
        buffer.writeln(error.stackTrace);
      }
      buffer.writeln('─' * 60);
    }

    await Share.share(
      buffer.toString(),
      subject: 'أخطاء العمليات - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
    );
  }

  Future<void> _clearErrors() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هل تريد مسح جميع سجلات الأخطاء؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      ref.read(appwriteLoggerProvider).clearLogs();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم مسح السجلات')),
        );
      }
    }
  }
}
