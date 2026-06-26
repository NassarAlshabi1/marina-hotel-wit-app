import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
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

  // ✅ فلترة أخطاء المزامنة لكل جدول (null = عرض الكل).
  // القيم المحتملة: null (الكل)، 'SYNC_ERRORS_ALL' (كل أخطاء المزامنة)،
  // أو اسم جدول محدد: 'rooms'، 'bookings'، 'payments'، 'debts'،
  // 'employees'، 'expenses'، 'guest_infos'، 'salary_withdrawals'،
  // 'salary_payments'، 'salary_cycles'، 'cash_transactions'، 'shift_notes'،
  // 'booking_notes'، 'booking_nights'، 'booking_price_adjustments'،
  // 'price_adjustments'، 'audit_logs'، 'payment_voids'، 'blacklist'.
  String? _filterEntity;

  /// قائمة الجداول المتاحة للفلترة (مرتبة حسب الأولوية).
  static const List<String> _syncEntities = [
    'rooms',
    'bookings',
    'payments',
    'debts',
    'employees',
    'expenses',
    'guest_infos',
    'cash_transactions',
    'booking_notes',
    'booking_nights',
    'booking_price_adjustments',
    'price_adjustments',
    'salary_cycles',
    'salary_payments',
    'salary_withdrawals',
    'shift_notes',
    'audit_logs',
    'payment_voids',
    'blacklist',
  ];

  /// أسماء عربية للجداول لعرضها في الـ chips.
  static const Map<String, String> _entityArabicNames = {
    'rooms': 'الغرف',
    'bookings': 'الحجوزات',
    'payments': 'المدفوعات',
    'debts': 'الديون',
    'employees': 'الموظفون',
    'expenses': 'المصروفات',
    'guest_infos': 'بيانات الضيوف',
    'cash_transactions': 'المعاملات النقدية',
    'booking_notes': 'ملاحظات الحجز',
    'booking_nights': 'ليالي الحجز',
    'booking_price_adjustments': 'تعديلات أسعار الحجز',
    'price_adjustments': 'تعديلات الأسعار',
    'salary_cycles': 'دورات الرواتب',
    'salary_payments': 'مدفوعات الرواتب',
    'salary_withdrawals': 'سحوبات الرواتب',
    'shift_notes': 'ملاحظات الوردية',
    'audit_logs': 'سجلات التدقيق',
    'payment_voids': 'إلغاء المدفوعات',
    'blacklist': 'القائمة السوداء',
  };

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logsProvider);
    final filteredLogs = _filterLogs(logs);

    return AppScaffold(
      title: 'سجلات Appwrite',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'export':
                unawaited(_exportLogs());
              case 'share':
                unawaited(_shareLogs(filteredLogs));
              case 'copy_errors':
                unawaited(_copyErrorsToClipboard(filteredLogs));
              case 'copy_errors_only':
                unawaited(_copyErrorsOnlyToClipboard(filteredLogs));
              case 'clear':
                unawaited(_clearLogs());
            }
          },
          itemBuilder: (context) => [
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
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'copy_errors',
              child: Row(
                children: [
                  Icon(Icons.copy, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('نسخ السجلات المعروضة'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'copy_errors_only',
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text('نسخ الأخطاء فقط (Error/Critical)'),
                ],
              ),
            ),
            const PopupMenuDivider(),
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
                const SizedBox(height: 8),

                // ✅ فلترة حسب الجدول (entity) لأخطاء المزامنة
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildEntityChip('كل السجلات', null, logs.length),
                      const SizedBox(width: 8),
                      _buildEntityChip(
                        '⚠️ أخطاء المزامنة',
                        'SYNC_ERRORS_ALL',
                        _countSyncErrors(logs),
                      ),
                      const SizedBox(width: 8),
                      ..._syncEntities.map((entity) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: _buildEntityChip(
                              _entityArabicNames[entity] ?? entity,
                              entity,
                              _countEntityErrors(logs, entity),
                            ),
                          )),
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

  /// ✅ chip لفلترة حسب الجدول (entity). null = عرض الكل.
  Widget _buildEntityChip(String label, String? entity, int count) {
    final isSelected = _filterEntity == entity;
    final color = entity == null
        ? Colors.blueGrey
        : (entity == 'SYNC_ERRORS_ALL' ? Colors.orange : Colors.indigo);

    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          // النقر على chip نشط = إلغاء الفلتر (رجوع للكل).
          // النقر على chip آخر = تفعيل فلتره.
          _filterEntity = selected ? entity : null;
        });
      },
      backgroundColor: Colors.white,
      selectedColor: color.withValues(alpha: 0.2),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  /// عدّ أخطاء المزامنة الإجمالية (push + pull + ERROR_HANDLER).
  int _countSyncErrors(List<LogEntry> logs) {
    return logs.where((log) {
      final tag = log.tag;
      final msg = log.message.toLowerCase();
      return tag.startsWith('SYNC_PUSH:') ||
          (tag == 'ERROR_HANDLER' &&
              (msg.contains('push:') ||
                  msg.contains('فشل سحب') ||
                  msg.contains('فشل دفع'))) ||
          (tag == 'SYNC' &&
              (msg.contains('فشل سحب') || msg.contains('فشل دفع')));
    }).length;
  }

  /// عدّ أخطاء المزامنة لجدول محدد.
  int _countEntityErrors(List<LogEntry> logs, String entity) {
    return logs.where((log) {
      final tag = log.tag;
      final msg = log.message.toLowerCase();
      if (tag == 'SYNC_PUSH:$entity') {
        return true;
      }
      if ((tag == 'SYNC' || tag == 'ERROR_HANDLER') &&
          msg.contains(entity)) {
        return true;
      }
      if (tag == 'ERROR_HANDLER' && msg.contains('push:$entity:')) {
        return true;
      }
      return false;
    }).length;
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

    // ✅ فلترة حسب الجدول (entity) لأخطاء المزامنة.
    // نمط الـ tag المستخدم في _processOutboxEntry: 'SYNC_PUSH:<entity>'
    // نمط الـ tag المستخدم في _syncXxx (أخطاء السحب): 'SYNC' + رسالة تحتوي اسم الجدول
    // نمط الـ tag المستخدم في _errorHandler: 'ERROR_HANDLER' + context يحوي 'push:<entity>:...'
    if (_filterEntity != null) {
      if (_filterEntity == 'SYNC_ERRORS_ALL') {
        // عرض كل أخطاء المزامنة (push + pull + ERROR_HANDLER)
        filtered = filtered.where((log) {
          final tag = log.tag;
          final msg = log.message.toLowerCase();
          return tag.startsWith('SYNC_PUSH:') ||
              tag == 'ERROR_HANDLER' &&
                  (msg.contains('push:') ||
                      msg.contains('فشل سحب') ||
                      msg.contains('فشل دفع')) ||
              (tag == 'SYNC' &&
                  (msg.contains('فشل سحب') || msg.contains('فشل دفع')));
        }).toList();
      } else {
        // عرض أخطاء جدول محدد فقط
        final entity = _filterEntity!;
        filtered = filtered.where((log) {
          final tag = log.tag;
          final msg = log.message.toLowerCase();
          // push errors: tag = 'SYNC_PUSH:<entity>'
          if (tag == 'SYNC_PUSH:$entity') {
            return true;
          }
          // pull errors: tag = 'SYNC' أو 'ERROR_HANDLER' + رسالة تذكر اسم الجدول
          if ((tag == 'SYNC' || tag == 'ERROR_HANDLER') &&
              msg.contains(entity)) {
            return true;
          }
          // context 'push:<entity>:' في رسائل ERROR_HANDLER
          if (tag == 'ERROR_HANDLER' && msg.contains('push:$entity:')) {
            return true;
          }
          return false;
        }).toList();
      }
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

  Future<void> _exportLogs() async {
    final logger = ref.read(appwriteLoggerProvider);
    final file = await logger.exportLogs();

    if (file != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم التصدير إلى: ${file.path}')));
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

  /// ✅ نسخ جميع السجلات المعروضة حالياً (بعد الفلترة) إلى الحافظة.
  /// مفيد للمشاركة السريعة في رسالة واتساب/تيليجرام/بريد.
  Future<void> _copyErrorsToClipboard(List<LogEntry> logs) async {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات لنسخها')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Appwrite Logs (المسجلات المعروضة)');
    buffer.writeln('═' * 50);
    buffer.writeln(
      'Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
    );
    buffer.writeln('Total: ${logs.length} | Filter: ${_filterEntity ?? "الكل"} | Level: ${_filterLevel?.name ?? "الكل"}');
    buffer.writeln('═' * 50);
    buffer.writeln();

    for (final log in logs) {
      buffer.writeln(log.toFormattedString());
      buffer.writeln('─' * 50);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم نسخ ${logs.length} سجل إلى الحافظة'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'مشاركة',
            textColor: Colors.white,
            onPressed: () {
              Share.share(
                buffer.toString(),
                subject: 'Appwrite Logs - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
              );
            },
          ),
        ),
      );
    }
  }

  /// ✅ نسخ الأخطاء فقط (Error + Critical) من السجلات المعروضة حالياً.
  /// مفيد للإبلاغ عن المشاكل بسرعة دون تشويش بـ Info/Debug.
  Future<void> _copyErrorsOnlyToClipboard(List<LogEntry> logs) async {
    final errorsOnly = logs
        .where(
          (l) => l.level == LogLevel.error || l.level == LogLevel.critical,
        )
        .toList();

    if (errorsOnly.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد أخطاء (Error/Critical) لنسخها'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Appwrite Errors Only (الأخطاء فقط)');
    buffer.writeln('═' * 50);
    buffer.writeln(
      'Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
    );
    buffer.writeln('Errors: ${errorsOnly.length}');
    buffer.writeln('═' * 50);
    buffer.writeln();

    for (final log in errorsOnly) {
      buffer.writeln(log.toFormattedString());
      buffer.writeln('─' * 50);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم نسخ ${errorsOnly.length} خطأ إلى الحافظة'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'مشاركة',
            textColor: Colors.white,
            onPressed: () {
              Share.share(
                buffer.toString(),
                subject:
                    'Appwrite Errors - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
              );
            },
          ),
        ),
      );
    }
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
      ref.read(appwriteLoggerProvider).clearLogs();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم مسح السجلات')));
      }
    }
  }
}
