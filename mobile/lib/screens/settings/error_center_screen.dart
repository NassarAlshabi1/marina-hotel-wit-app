import 'dart:async';
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
import 'error_tracker_screen.dart'
    show ErrorCategory, ErrorTrackerStore, TrackedError;

/// ✅ (2026-09-09) مركز أخطاء المزامنة — يعرض الآن تسجيل أخطاء
/// Cloudflare وWorker الحقيقي من ErrorTrackerStore (نفس المخزن الذي
/// يغذي شاشة تتبع الأخطاء):
///   • أخطاء Worker (الخادم): errors[] أثناء السحب (جداول مُتخطّاة)،
///     رفض سجلات الدفع الفردية، تطبيع الطوابع غير المكتمل.
///   • أخطاء Cloudflare (اتصال/HTTP): فشل تسجيل الدخول، أخطاء الشبكة،
///     4xx/5xx، تجاوز الحد (429)، فشل تسجيل الجهاز.
///   • أخطاء المزامنة والتطبيق: فشل تطبيق السجلات، العلاقات غير
///     المحلولة، تجميد المؤشر، الترحيل.
/// مع الأقسام التاريخية: Appwrite وGoogle Drive وسجلات التصحيح.
class ErrorCenterScreen extends ConsumerStatefulWidget {
  const ErrorCenterScreen({super.key});

  @override
  ConsumerState<ErrorCenterScreen> createState() => _ErrorCenterScreenState();
}

class _ErrorCenterScreenState extends ConsumerState<ErrorCenterScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // ErrorTrackerStore ليس ChangeNotifier — تحديث دوري خفيف (نفس
    // نمط ErrorTrackerScreen) ليظهر أي خطأ جديد خلال ثوانٍ.
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  List<TrackedError> _storeByCategories(List<ErrorCategory> categories) {
    final allowed = Set<ErrorCategory>.from(categories);
    return ErrorTrackerStore.instance.errors
        .where((e) => allowed.contains(e.category))
        .toList(growable: false);
  }

  List<LogEntry> _onlyErrors(List<LogEntry> logs) {
    return logs
        .where((l) => l.level == LogLevel.error || l.level == LogLevel.critical)
        .toList(growable: false);
  }

  _ViewEntry _trackedToView(TrackedError e) {
    final status = e.statusCode != null ? ' (HTTP ${e.statusCode})' : '';
    final message = e.message.length > 220
        ? '${e.message.substring(0, 220)}…'
        : e.message;
    return _ViewEntry(
      title: '${e.title}$status',
      subtitle: '[${e.category.label}] ${e.source ?? '—'}\n$message',
      timestamp: e.timestamp,
    );
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
    List<TrackedError> worker,
    List<TrackedError> cloudflare,
    List<TrackedError> sync,
    List<LogEntry> appwrite,
    List<LogEntry> drive,
    List<String> debug,
  ) {
    final buffer = StringBuffer();
    for (final e in worker) {
      buffer.writeln('[WORKER] ${e.toFormattedString()}');
    }
    for (final e in cloudflare) {
      buffer.writeln('[CLOUDFLARE] ${e.toFormattedString()}');
    }
    for (final e in sync) {
      buffer.writeln('[SYNC] ${e.toFormattedString()}');
    }
    for (final e in appwrite) {
      buffer.writeln('[APPWRITE] ${e.toFormattedString()}');
    }
    for (final e in drive) {
      buffer.writeln('[DRIVE] ${e.toFormattedString()}');
    }
    for (final e in debug) {
      buffer.writeln('[DEBUG] $e');
    }
    unawaited(Clipboard.setData(ClipboardData(text: buffer.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final appwriteLogs = ref.watch(appwriteLogsProvider);
    final driveLogs = ref.watch(googleDriveLogsProvider);

    final appwriteErrors = _onlyErrors(appwriteLogs);
    final driveErrors = _onlyErrors(driveLogs);
    final debugEntries = DebugLogs.entries;

    final workerErrors = _storeByCategories([ErrorCategory.worker]);
    // أخطاء الاتصال بالـ worker: الشبكة/المصادقة/تجاوز الحد — كل
    // مواضعها الحالية في الكود هي endpoints مزامنة Cloudflare.
    final cloudflareErrors = _storeByCategories([
      ErrorCategory.network,
      ErrorCategory.auth,
      ErrorCategory.rateLimit,
    ]);
    final syncErrors = _storeByCategories([
      ErrorCategory.sync,
      ErrorCategory.migration,
    ]);

    return AppScaffold(
      title: 'مركز الأخطاء',
      actions: [
        IconButton(
          icon: const Icon(Icons.copy_all),
          tooltip: 'نسخ كل السجلات',
          onPressed: () => _copyAll(
            workerErrors,
            cloudflareErrors,
            syncErrors,
            appwriteErrors,
            driveErrors,
            debugEntries,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'مسح السجلات المؤقتة',
          onPressed: () {
            DebugLogs.clear();
            ErrorTrackerStore.instance.clear();
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
            chips: [
              (
                label: 'Worker',
                count: workerErrors.length,
                color: Colors.deepPurple,
              ),
              (
                label: 'Cloudflare',
                count: cloudflareErrors.length,
                color: Colors.redAccent,
              ),
              (
                label: 'المزامنة',
                count: syncErrors.length,
                color: Colors.indigo,
              ),
              (
                label: 'Appwrite',
                count: appwriteErrors.length,
                color: Colors.teal,
              ),
              (
                label: 'Google Drive',
                count: driveErrors.length,
                color: Colors.deepOrange,
              ),
            ],
            debugCount: debugEntries.length,
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            title: 'أخطاء Worker (الخادم)',
            color: Colors.deepPurple,
            entries: workerErrors.map(_trackedToView).toList(),
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            title: 'أخطاء Cloudflare (اتصال/HTTP)',
            color: Colors.redAccent,
            entries: cloudflareErrors.map(_trackedToView).toList(),
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            title: 'أخطاء المزامنة والتطبيق',
            color: Colors.indigo,
            entries: syncErrors.map(_trackedToView).toList(),
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            title: 'أخطاء Appwrite',
            color: Colors.teal,
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
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.chips, required this.debugCount});

  /// شرائح الملخص: (التسمية، العدد، اللون)
  final List<({String label, int count, Color color})> chips;
  final int debugCount;

  @override
  Widget build(BuildContext context) {
    final total = chips.fold<int>(0, (sum, c) => sum + c.count) + debugCount;
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
                for (final c in chips) _chip(c.label, c.count, c.color),
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
                const Spacer(),
                Text(
                  '${entries.length}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
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
                  isThreeLine: e.subtitle.contains('\n'),
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
