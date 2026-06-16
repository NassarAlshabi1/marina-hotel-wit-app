import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/core.dart';
import '../../../../providers/appwrite_providers.dart' as ap;
import '../../../../services/appwrite_backup_service.dart';
import '../../../../services/providers.dart';
import '../../../../services/sync_integrity_checker.dart';
import '../../appwrite_logs_screen.dart';
import '../../appwrite_sync_stats_screen.dart';

/// Appwrite Tools Tab - أدوات الصيانة والاختبار
class AppwriteToolsTab extends ConsumerWidget {
  const AppwriteToolsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        const SectionHeader(title: 'أدوات الاختبار', icon: Icons.bug_report),
        _buildTestingToolsCard(context, ref),
        const SizedBox(height: UIConstants.spacingLG),
        const SectionHeader(title: 'أدوات الصيانة', icon: Icons.build),
        _buildMaintenanceToolsCard(context, ref),
        const SizedBox(height: UIConstants.spacingLG),
        const SectionHeader(title: 'إدارة البيانات', icon: Icons.storage),
        _buildDataManagementCard(context, ref),
        const SizedBox(height: UIConstants.spacingLG),
        const SectionHeader(title: 'السجلات والإحصائيات', icon: Icons.analytics),
        _buildLogsStatsCard(context, ref),
      ],
    );
  }

  Widget _buildTestingToolsCard(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.network_check, color: Colors.blue),
            ),
            title: const Text('اختبار الاتصال'),
            subtitle: const Text('التحقق من الاتصال بالخادم'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _testConnection(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.api, color: Colors.purple),
            ),
            title: const Text('اختبار API'),
            subtitle: const Text('إرسال طلبات تجريبية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _testConnection(context, ref, fullTest: true),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.verified, color: Colors.green),
            ),
            title: const Text('التحقق من البيانات'),
            subtitle: const Text('فحص سلامة البيانات المحلية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _runIntegrityCheck(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceToolsCard(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.cleaning_services, color: Colors.orange),
            ),
            title: const Text('مسح التخزين المؤقت'),
            subtitle: const Text('حذف البيانات المؤقتة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _clearCache(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.restore, color: Colors.red),
            ),
            title: const Text('إعادة تعيين الاتصال'),
            subtitle: const Text('إعادة تهيئة الاتصال'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _resetConnection(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.refresh, color: Colors.blue),
            ),
            title: const Text('إعادة بناء الفهارس'),
            subtitle: const Text('تحسين أداء البحث'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _rebuildIndexes(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementCard(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.cloud_download, color: Colors.teal),
            ),
            title: const Text('نسخة احتياطية شاملة من السحابة'),
            subtitle: const Text('سحب جميع البيانات من Appwrite إلى الجهاز'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _pullFullBackupFromAppwrite(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.cloud_upload, color: Colors.indigo),
            ),
            title: const Text('رفع نسخة شاملة إلى السحابة'),
            subtitle: const Text('رفع جميع البيانات المحلية إلى Appwrite Cloud'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _pushFullBackupToAppwrite(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.backup, color: Colors.green),
            ),
            title: const Text('تصدير نسخة احتياطية'),
            subtitle: const Text('تصدير بيانات Appwrite كملف JSON'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _backupAppwrite(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.restore_page, color: Colors.blue),
            ),
            title: const Text('استعادة البيانات'),
            subtitle: const Text('استعادة من نسخة احتياطية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showNotAvailable(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.compare_arrows, color: Colors.purple),
            ),
            title: const Text('مقارنة البيانات'),
            subtitle: const Text('مقارنة البيانات المحلية مع السحابة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showNotAvailable(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsStatsCard(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.description, color: Colors.blue),
            ),
            title: const Text('عرض السجلات'),
            subtitle: const Text('سجلات Appwrite المفصلة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _openLogs(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.bar_chart, color: Colors.green),
            ),
            title: const Text('إحصائيات المزامنة'),
            subtitle: const Text('تقارير وإحصائيات مفصلة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _openStats(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.download, color: Colors.orange),
            ),
            title: const Text('تصدير السجلات'),
            subtitle: const Text('حفظ السجلات كملف'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _exportLogs(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection(
    BuildContext context,
    WidgetRef ref, {
    bool fullTest = false,
  }) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('جاري اختبار الاتصال...')));

    final service = ref.read(ap.appwriteServiceProvider);
    await service.initialize();
    final result = await service.testConnection();

    if (context.mounted) {
      final ok = result['overall_success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'الاتصال يعمل بشكل طبيعي' : 'فشل الاتصال'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _runIntegrityCheck(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final report = await SyncIntegrityChecker.instance.verify(db);

    if (!context.mounted) {
      return;
    }

    final issues = report.issues.take(10).toList();
    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نتائج فحص السلامة'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('عدد المشاكل: ${report.issueCount}'),
              Text('مشاكل حرجة: ${report.criticalIssueCount}'),
              if (issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...issues.map(
                  (issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• ${issue.toArabicMessage()}'),
                  ),
                ),
                if (report.issueCount > issues.length) const Text('... والمزيد'),
              ],
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
    ),);
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    ref.read(ap.appwriteCacheManagerProvider).clear();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم مسح التخزين المؤقت')));
    }
  }

  Future<void> _resetConnection(BuildContext context, WidgetRef ref) async {
    final service = ref.read(ap.appwriteServiceProvider);
    await service.initialize();
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إعادة تهيئة الاتصال')));
    }
  }

  Future<void> _rebuildIndexes(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    await db.customStatement('REINDEX');
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إعادة بناء الفهارس')));
    }
  }

  Future<void> _backupAppwrite(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء النسخة الاحتياطية...')),
    );

    final deviceId = ref.read(ap.appwriteSyncManagerProvider).currentDeviceId;
    final service = AppwriteBackupService(
      appwriteService: ref.read(ap.appwriteServiceProvider),
    );
    final result = await service.exportBackup(deviceId: deviceId);

    if (!context.mounted) {
      return;
    }

    final sortedCounts = result.counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم إنشاء النسخة الاحتياطية'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المسار: ${result.file.path}'),
              const SizedBox(height: 12),
              Text('إجمالي السجلات: ${result.totalRecords}'),
              const SizedBox(height: 8),
              const Text('تفاصيل الجداول:'),
              const SizedBox(height: 6),
              ...sortedCounts.map((e) => Text('• ${e.key}: ${e.value}')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Share.shareXFiles([XFile(result.file.path)]);
            },
            child: const Text('مشاركة'),
          ),
        ],
      ),
    ),);
  }

  Future<void> _exportLogs(BuildContext context, WidgetRef ref) async {
    final logger = ref.read(ap.appwriteLoggerProvider);
    final file = await logger.exportLogs();
    if (!context.mounted) {
      return;
    }
    if (file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد سجلات للتصدير')));
      return;
    }
    await Share.shareXFiles([XFile(file.path)]);
  }

  void _openLogs(BuildContext context) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const AppwriteLogsScreen()));
  }

  void _openStats(BuildContext context) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const AppwriteSyncStatsScreen()));
  }

  /// ✅ رفع نسخة شاملة يدوياً إلى Appwrite Cloud.
  ///
  /// يستخدم `pushAllLocalDataToAppwrite(skipDeleted: false)` التي ترفع
  /// كل الجداول الـ16 (غرف، حجوزات، مدفوعات، مصروفات، موظفين، ديون، ...).
  /// يعرض تأكيداً قبل البدء، ومؤشر تقدم، وتقريراً بالنتائج.
  Future<void> _pushFullBackupToAppwrite(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // 1. تأكيد المستخدم
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_upload, color: Colors.indigo),
            SizedBox(width: 8),
            Text('رفع نسخة شاملة'),
          ],
        ),
        content: const Text(
          'سيتم رفع جميع البيانات المحلية إلى Appwrite Cloud.\n\n'
          'هذا يشمل: الغرف، الحجوزات، المدفوعات، المصروفات، الموظفين، '
          'الديون، ملاحظات الشيفت، ملاحظات الحجز، ليالي الحجز، '
          'المعاملات النقدية، دورات الرواتب، مدفوعات الرواتب، '
          'تسحيلات الرواتب، تعديلات الأسعار، تعديلات أسعار الحجوزات، '
          'وبيانات النزلاء.\n\n'
          '⚠️ قد تستغرق العملية عدة دقائق حسب حجم البيانات.\n'
          '⚠️ تأكد من اتصال الإنترنت المستقر.\n\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<bool>(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop<bool>(context, true),
            icon: const Icon(Icons.cloud_upload),
            label: const Text('رفع البيانات'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    // 2. مؤشر التقدم
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text('جاري رفع جميع البيانات إلى Appwrite Cloud...'),
            ),
          ],
        ),
        duration: Duration(minutes: 10),
      ),
    );

    try {
      // 3. تنفيذ الرفع
      final syncManager = ref.read(ap.appwriteSyncManagerProvider);
      await syncManager.appwriteService.initialize();

      if (!syncManager.appwriteService.isInitialized) {
        throw Exception('فشل تهيئة خدمة Appwrite');
      }

      // skipDeleted=false (افتراضي) — ارفع كل شيء بما فيه المحذوف softly
      final stats = await syncManager.pushAllLocalDataToAppwrite();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // 4. عرض تقرير النتائج
      final totalPushed = stats.values.fold<int>(0, (a, b) => a + b);
      final errors = stats['errors'] ?? 0;
      final isSuccess = errors == 0;

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            isSuccess ? Icons.check_circle : Icons.warning,
            color: isSuccess ? Colors.green : Colors.orange,
            size: 48,
          ),
          title: Text(isSuccess
              ? 'تم رفع البيانات بنجاح'
              : 'اكتمل الرفع مع بعض الأخطاء'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إجمالي السجلات المرفوعة: $totalPushed',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('التفاصيل حسب الجدول:'),
                const SizedBox(height: 4),
                ...stats.entries
                    .where((e) => e.key != 'errors' && e.value > 0)
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text('  • ${e.key}: ${e.value}'),
                        )),
                if (errors > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '⚠️ أخطاء: $errors',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل رفع البيانات: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'تفاصيل',
            textColor: Colors.white,
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تفاصيل الخطأ'),
                  content: SingleChildScrollView(
                    child: Text(e.toString()),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _pullFullBackupFromAppwrite(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نسخة احتياطية شاملة'),
        content: const Text(
          'سيتم سحب جميع البيانات من Appwrite Cloud وحفظها في قاعدة البيانات المحلية.\n\n'
          'هذا يشمل: الغرف، الحجوزات، المدفوعات، المصروفات، الموظفين، الديون، '
          'ملاحظات الشيفت، ملاحظات الحجز، ليالي الحجز، المعاملات النقدية، '
          'دورات الرواتب، ومدفوعات الرواتب.\n\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<bool>(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop<bool>(context, true),
            child: const Text('سحب البيانات'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('جاري سحب جميع البيانات من Appwrite...'),
          ],
        ),
        duration: Duration(minutes: 5),
      ),
    );

    try {
      final syncManager = ref.read(ap.appwriteSyncManagerProvider);
      await syncManager.appwriteService.initialize();
      final result = await syncManager.pullRemoteChanges();

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            result ? Icons.check_circle : Icons.info,
            color: result ? Colors.green : Colors.blue,
            size: 48,
          ),
          title: Text(result
              ? 'تم سحب البيانات بنجاح'
              : 'لا توجد بيانات جديدة',),
          content: Text(result
              ? 'تم سحب جميع البيانات من Appwrite وحفظها محلياً.'
              : 'البيانات المحلية محدّثة بالفعل.',),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),);
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل سحب البيانات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showNotAvailable(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('غير متاح حالياً')));
  }
}
