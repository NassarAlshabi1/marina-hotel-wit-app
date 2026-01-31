import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../../services/restore_fix_service.dart';
import '../../services/local_db.dart';

// مقدم خدمة الإصلاح التلقائي
final restoreFixServiceProvider = Provider<RestoreFixService>(
  (ref) => RestoreFixService(DatabaseManager.instance),
);

// مقدم لتقرير الإصلاح الأخير
final lastFixReportProvider = StateProvider<RestoreFixReport?>((ref) => null);

// مقدم لسجلات الإصلاح
final fixLogsProvider = FutureProvider.autoDispose<List<RestoreFixLogData>>((
  ref,
) async {
  final service = ref.read(restoreFixServiceProvider);
  return await service.getFixLogs(limit: 50);
});

// مقدم لحالة التحميل
final fixServiceLoadingProvider = StateProvider<bool>((ref) => false);

/// شاشة إعدادات الإصلاح التلقائي
class RestoreFixScreen extends ConsumerWidget {
  const RestoreFixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastReport = ref.watch(lastFixReportProvider);
    final fixLogsAsyncValue = ref.watch(fixLogsProvider);
    final isLoading = ref.watch(fixServiceLoadingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإصلاح التلقائي للنسخة الاحتياطية'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // بطاقة التحكم الرئيسية
            _buildMainControlCard(context, ref, isLoading),
            const SizedBox(height: 20),

            // بطاقة التقرير الأخير
            if (lastReport != null) ...[
              _buildLastReportCard(context, lastReport),
              const SizedBox(height: 20),
            ],

            // بطاقة سجلات الإصلاح
            _buildFixLogsCard(context, ref, fixLogsAsyncValue),
          ],
        ),
      ),
    );
  }

  /// بطاقة التحكم الرئيسية
  Widget _buildMainControlCard(
    BuildContext context,
    WidgetRef ref,
    bool isLoading,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.build_circle, size: 48, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'الإصلاح التلقائي',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'يقوم بإعادة حساب الليالي، حالات الغرف، والمدفوعات لضمان اتساق البيانات',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isLoading ? null : () => _runManualFix(context, ref),
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                isLoading ? 'جاري التشغيل...' : 'تشغيل الإصلاح التلقائي يدوياً',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة التقرير الأخير
  Widget _buildLastReportCard(BuildContext context, RestoreFixReport report) {
    final isSuccess = report.success;
    final statusColor = isSuccess ? Colors.green : Colors.red;
    final statusIcon = isSuccess ? Icons.check_circle : Icons.error;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'نتيجة آخر تشغيل',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildReportRow('الحالة', isSuccess ? 'نجح' : 'فشل', statusColor),
            _buildReportRow('وقت التنفيذ', _formatDateTime(report.executedAt)),
            _buildReportRow('المدة', '${report.durationMs} مللي ثانية'),
            if (isSuccess) ...[
              _buildReportRow('الحجوزات المُصلحة', '${report.bookingsFixed}'),
              _buildReportRow('الغرف المحدثة', '${report.roomsUpdated}'),
              _buildReportRow(
                'المدفوعات المتحقق منها',
                '${report.paymentsRecalculated}',
              ),
              if (report.changes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'التغييرات المُطبقة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: report.changes
                        .take(5)
                        .map(
                          (change) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $change',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (report.changes.length > 5)
                  Text(
                    '... و ${report.changes.length - 5} تغيير إضافي',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ] else if (report.error != null) ...[
              const SizedBox(height: 12),
              const Text(
                'تفاصيل الخطأ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  report.error!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// بطاقة سجلات الإصلاح
  Widget _buildFixLogsCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<RestoreFixLogData>> fixLogsAsyncValue,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'سجلات الإصلاح',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => _exportLogsAsJson(context, ref),
                  icon: const Icon(Icons.download),
                  tooltip: 'تصدير كـ JSON',
                ),
              ],
            ),
            const SizedBox(height: 12),
            fixLogsAsyncValue.when(
              data: (logs) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Icon(Icons.history, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'لا توجد سجلات إصلاح',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children:
                      logs.take(10).map((log) => _buildLogEntry(log)).toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      const Icon(Icons.error, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'خطأ في تحميل السجلات: $error',
                        style: const TextStyle(fontSize: 14, color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// عنصر سجل واحد
  Widget _buildLogEntry(RestoreFixLogData log) {
    Color getFixTypeColor(String fixType) {
      switch (fixType) {
        case 'nights_recalc':
          return Colors.blue;
        case 'room_status':
          return Colors.orange;
        case 'payment_check':
          return Colors.red;
        default:
          return Colors.grey;
      }
    }

    String getFixTypeLabel(String fixType) {
      switch (fixType) {
        case 'nights_recalc':
          return 'إعادة حساب الليالي';
        case 'room_status':
          return 'حالة الغرفة';
        case 'payment_check':
          return 'فحص المدفوعات';
        default:
          return fixType;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: getFixTypeColor(log.fixType),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  getFixTypeLabel(log.fixType),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDateTime(
                  DateTime.fromMillisecondsSinceEpoch(log.executedAt * 1000),
                ),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(log.reason, style: const TextStyle(fontSize: 12)),
          if (log.oldValue != null && log.newValue != null) ...[
            const SizedBox(height: 4),
            Text(
              '${log.fieldName}: ${log.oldValue} ← ${log.newValue}',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// صف في التقرير
  Widget _buildReportRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.black87,
              fontWeight: valueColor != null ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }

  /// تشغيل الإصلاح يدوياً
  Future<void> _runManualFix(BuildContext context, WidgetRef ref) async {
    final service = ref.read(restoreFixServiceProvider);
    ref.read(fixServiceLoadingProvider.notifier).state = true;

    try {
      // إظهار رسالة بدء التشغيل
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 بدء عملية الإصلاح التلقائي...'),
          duration: Duration(seconds: 2),
        ),
      );

      // تشغيل الإصلاح
      final report = await service.runAutoFixAfterRestore();

      // حفظ التقرير
      ref.read(lastFixReportProvider.notifier).state = report;

      // تحديث السجلات
      ref.invalidate(fixLogsProvider);

      // إظهار النتيجة
      if (report.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ اكتمل الإصلاح بنجاح: ${report.bookingsFixed} حجز، ${report.roomsUpdated} غرفة',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل الإصلاح: ${report.error}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ غير متوقع: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      ref.read(fixServiceLoadingProvider.notifier).state = false;
    }
  }

  /// تصدير السجلات كـ JSON
  Future<void> _exportLogsAsJson(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(restoreFixServiceProvider);
      final jsonData = await service.exportFixLogsAsJson();

      // حفظ الملف
      final directory = await getApplicationCacheDirectory();
      final fileName =
          'restore_fix_logs_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${directory.path}/$fileName');

      await file.writeAsString(jsonEncode(jsonData));

      // مشاركة الملف
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Marina Hotel - سجلات الإصلاح التلقائي',
        text: 'سجلات الإصلاح التلقائي للنسخة الاحتياطية',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم تصدير السجلات بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في التصدير: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// تنسيق التاريخ والوقت
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
