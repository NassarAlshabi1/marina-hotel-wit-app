import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/core.dart';
import '../../../../providers/appwrite_providers.dart' as ap;
import '../../../../services/appwrite_backup_service.dart';
import '../../../../services/sync_integrity_checker.dart';
import '../../../../services/providers.dart';
import '../../appwrite_logs_screen.dart';
import '../../appwrite_sync_stats_screen.dart';

/// ✅ Debounce provider: tracks which action is currently running.
/// `null` = idle, otherwise holds the action key name.
final _toolsLoadingProvider = StateProvider<String?>((ref) => null);

/// Appwrite Tools Tab - أدوات الصيانة والاختبار
class AppwriteToolsTab extends ConsumerWidget {
  const AppwriteToolsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: const [
        SectionHeader(title: 'أدوات الاختبار', icon: Icons.bug_report),
        _ToolsCard(
          children: [
            _ToolActionTile(
              actionKey: 'testConnection',
              icon: Icons.network_check,
              color: Colors.blue,
              title: 'اختبار الاتصال',
              subtitle: 'التحقق من الاتصال بالخادم',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: 'testApi',
              icon: Icons.api,
              color: Colors.purple,
              title: 'اختبار API',
              subtitle: 'إرسال طلبات تجريبية',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: 'integrityCheck',
              icon: Icons.verified,
              color: Colors.green,
              title: 'التحقق من البيانات',
              subtitle: 'فحص سلامة البيانات المحلية',
            ),
          ],
        ),
        SizedBox(height: UIConstants.spacingLG),
        SectionHeader(title: 'أدوات الصيانة', icon: Icons.build),
        _ToolsCard(
          children: [
            _ToolActionTile(
              actionKey: 'clearCache',
              icon: Icons.cleaning_services,
              color: Colors.orange,
              title: 'مسح التخزين المؤقت',
              subtitle: 'حذف البيانات المؤقتة',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: 'resetConnection',
              icon: Icons.restore,
              color: Colors.red,
              title: 'إعادة تعيين الاتصال',
              subtitle: 'إعادة تهيئة الاتصال',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: 'rebuildIndexes',
              icon: Icons.refresh,
              color: Colors.blue,
              title: 'إعادة بناء الفهارس',
              subtitle: 'تحسين أداء البحث',
            ),
          ],
        ),
        SizedBox(height: UIConstants.spacingLG),
        SectionHeader(title: 'إدارة البيانات', icon: Icons.storage),
        _ToolsCard(
          children: [
            _ToolActionTile(
              actionKey: 'pullBackup',
              icon: Icons.cloud_download,
              color: Colors.teal,
              title: 'نسخة احتياطية شاملة من السحابة',
              subtitle: 'سحب جميع البيانات من Appwrite إلى الجهاز',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: 'exportBackup',
              icon: Icons.backup,
              color: Colors.green,
              title: 'تصدير نسخة احتياطية',
              subtitle: 'تصدير بيانات Appwrite كملف JSON',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: '_restoreData',
              icon: Icons.restore_page,
              color: Colors.blue,
              title: 'استعادة البيانات',
              subtitle: 'استعادة من نسخة احتياطية',
              isNotAvailable: true,
              notAvailableFeature: 'استعادة البيانات',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: '_compareData',
              icon: Icons.compare_arrows,
              color: Colors.purple,
              title: 'مقارنة البيانات',
              subtitle: 'مقارنة البيانات المحلية مع السحابة',
              isNotAvailable: true,
              notAvailableFeature: 'مقارنة البيانات',
            ),
          ],
        ),
        SizedBox(height: UIConstants.spacingLG),
        SectionHeader(title: 'السجلات والإحصائيات', icon: Icons.analytics),
        _ToolsCard(
          children: [
            _ToolActionTile(
              actionKey: 'openLogs',
              icon: Icons.description,
              color: Colors.blue,
              title: 'عرض السجلات',
              subtitle: 'سجلات Appwrite المفصلة',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: 'openStats',
              icon: Icons.bar_chart,
              color: Colors.green,
              title: 'إحصائيات المزامنة',
              subtitle: 'تقارير وإحصائيات مفصلة',
            ),
            Divider(height: 1),
            _ToolActionTile(
              actionKey: 'exportLogs',
              icon: Icons.download,
              color: Colors.orange,
              title: 'تصدير السجلات',
              subtitle: 'حفظ السجلات كملف',
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// ✅ Reusable Widgets — eliminate repeated Card & ListTile decoration
// ============================================================================

/// ✅ Reusable Card with consistent styling — replaces 4+ duplicated Card widgets
class _ToolsCard extends StatelessWidget {
  const _ToolsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(children: children),
    );
  }
}

/// ✅ Reusable action tile with colored icon + debounce + loading indicator.
/// Eliminates 12+ repeated leading Container patterns.
class _ToolActionTile extends ConsumerWidget {
  const _ToolActionTile({
    required this.actionKey,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.isNotAvailable = false,
    this.notAvailableFeature,
  });
  final String actionKey;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool isNotAvailable;
  final String? notAvailableFeature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(_toolsLoadingProvider) == actionKey;

    return ListTile(
      leading: _ColoredIcon(icon: icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: isNotAvailable ? Colors.grey : null),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isNotAvailable ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
      ),
      trailing: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isNotAvailable ? Colors.grey : null,
            ),
      onTap: isLoading
          ? null
          : isNotAvailable
          ? () => _showNotAvailable(context, notAvailableFeature ?? title)
          : () => _dispatchAction(context, ref, actionKey),
    );
  }
}

/// ✅ Reusable colored icon in a rounded container
class _ColoredIcon extends StatelessWidget {
  const _ColoredIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(UIConstants.spacingSM),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(UIConstants.radiusMD),
      ),
      child: Icon(icon, color: color),
    );
  }
}

// ============================================================================
// ✅ Action Dispatcher — routes action keys to handlers
// ============================================================================

void _dispatchAction(BuildContext context, WidgetRef ref, String actionKey) {
  switch (actionKey) {
    case 'testConnection':
      _testConnection(context, ref);
    case 'testApi':
      _testConnection(context, ref, fullTest: true);
    case 'integrityCheck':
      _runIntegrityCheck(context, ref);
    case 'clearCache':
      _clearCache(context, ref);
    case 'resetConnection':
      _resetConnection(context, ref);
    case 'rebuildIndexes':
      _rebuildIndexes(context, ref);
    case 'pullBackup':
      _pullFullBackupFromAppwrite(context, ref);
    case 'exportBackup':
      _backupAppwrite(context, ref);
    case 'exportLogs':
      _exportLogs(context, ref);
    case 'openLogs':
      _openLogs(context);
    case 'openStats':
      _openStats(context);
  }
}

// ============================================================================
// ✅ Action Handlers — all with debounce, error handling, mounted checks
// ============================================================================

/// ✅ Enhanced: debounce guard + error handling
Future<void> _testConnection(
  BuildContext context,
  WidgetRef ref, {
  bool fullTest = false,
}) async {
  final actionKey = fullTest ? 'testApi' : 'testConnection';
  if (ref.read(_toolsLoadingProvider) != null) return;
  ref.read(_toolsLoadingProvider.notifier).state = actionKey;

  try {
    final service = ref.read(ap.appwriteServiceProvider);
    await service.initialize();
    final result = await service.testConnection();

    if (!context.mounted) return;
    final ok = result['overall_success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'الاتصال يعمل بشكل طبيعي' : 'فشل الاتصال'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشل اختبار الاتصال: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

/// ✅ Enhanced: debounce guard + error handling
Future<void> _runIntegrityCheck(BuildContext context, WidgetRef ref) async {
  if (ref.read(_toolsLoadingProvider) != null) return;
  ref.read(_toolsLoadingProvider.notifier).state = 'integrityCheck';

  try {
    final db = ref.read(databaseProvider);
    final report = await SyncIntegrityChecker.instance.verify(db);

    if (!context.mounted) return;

    final issues = report.issues.take(10).toList();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
                if (report.issueCount > issues.length)
                  const Text('... والمزيد'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشل فحص السلامة: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

/// ✅ Fixed: added try-catch error handling (was missing entirely)
Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
  if (ref.read(_toolsLoadingProvider) != null) return;
  ref.read(_toolsLoadingProvider.notifier).state = 'clearCache';

  try {
    ref.read(ap.appwriteCacheManagerProvider).clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم مسح التخزين المؤقت')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشل مسح التخزين: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

/// ✅ Enhanced: debounce guard + error handling (was missing entirely)
Future<void> _resetConnection(BuildContext context, WidgetRef ref) async {
  if (ref.read(_toolsLoadingProvider) != null) return;
  ref.read(_toolsLoadingProvider.notifier).state = 'resetConnection';

  try {
    final service = ref.read(ap.appwriteServiceProvider);
    await service.initialize();
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم إعادة تهيئة الاتصال')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشلت إعادة التعيين: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

/// ✅ Fixed: loading dialog + error handling for REINDEX
/// Note: REINDEX cannot run in a separate Isolate because the
/// SQLite database connection is thread-specific and not transferable.
Future<void> _rebuildIndexes(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تحذير'),
      content: const Text(
        'سيتم إعادة بناء جميع فهارس قاعدة البيانات.\n\n'
        'هذه العملية قد تستغرق بعض الوقت على قواعد البيانات الكبيرة.\n'
        'سيتم عرض مؤشر التحميل أثناء التنفيذ.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('متابعة'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;
  ref.read(_toolsLoadingProvider.notifier).state = 'rebuildIndexes';

  // ✅ Non-dismissible loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري إعادة بناء الفهارس...'),
          ],
        ),
      ),
    ),
  );

  try {
    final db = ref.read(databaseProvider);
    await db.customStatement('REINDEX');

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إعادة بناء الفهارس بنجاح'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشل إعادة بناء الفهارس: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

/// ✅ Fixed: mounted check + loading dialog instead of SnackBar
Future<void> _backupAppwrite(BuildContext context, WidgetRef ref) async {
  if (ref.read(_toolsLoadingProvider) != null) return;
  ref.read(_toolsLoadingProvider.notifier).state = 'exportBackup';

  if (!context.mounted) return;

  // ✅ Loading dialog instead of SnackBar
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري إنشاء النسخة الاحتياطية...'),
          ],
        ),
      ),
    ),
  );

  try {
    final deviceId = ref.read(ap.appwriteSyncManagerProvider).currentDeviceId;
    final service = AppwriteBackupService(
      appwriteService: ref.read(ap.appwriteServiceProvider),
    );
    final result = await service.exportBackup(deviceId: deviceId);

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    final sortedCounts = result.counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await Share.shareXFiles([XFile(result.file.path)]);
            },
            child: const Text('مشاركة'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشل إنشاء النسخة: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

/// ✅ Enhanced: debounce guard + error handling
Future<void> _exportLogs(BuildContext context, WidgetRef ref) async {
  if (ref.read(_toolsLoadingProvider) != null) return;
  ref.read(_toolsLoadingProvider.notifier).state = 'exportLogs';

  try {
    final logger = ref.read(ap.appwriteLoggerProvider);
    final file = await logger.exportLogs();
    if (!context.mounted) return;

    if (file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد سجلات للتصدير')));
      return;
    }
    await Share.shareXFiles([XFile(file.path)]);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشل تصدير السجلات: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

void _openLogs(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const AppwriteLogsScreen()));
}

void _openStats(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const AppwriteSyncStatsScreen()));
}

/// ✅ Fixed: replaced dangerous 5-minute SnackBar with non-dismissible loading dialog
Future<void> _pullFullBackupFromAppwrite(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
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
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('سحب البيانات'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;
  ref.read(_toolsLoadingProvider.notifier).state = 'pullBackup';

  // ✅ Loading dialog instead of 5-minute SnackBar (blocks all other SnackBars!)
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري سحب جميع البيانات من Appwrite...'),
            SizedBox(height: 8),
            Text(
              'قد يستغرق هذا بعض الوقت',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    final syncManager = ref.read(ap.appwriteSyncManagerProvider);
    await syncManager.appwriteService.initialize();
    final result = await syncManager.pullRemoteChanges();

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          result ? Icons.check_circle : Icons.info,
          color: result ? Colors.green : Colors.blue,
          size: 48,
        ),
        title: Text(result ? 'تم سحب البيانات بنجاح' : 'لا توجد بيانات جديدة'),
        content: Text(
          result
              ? 'تم سحب جميع البيانات من Appwrite وحفظها محلياً.'
              : 'البيانات المحلية محدّثة بالفعل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('فشل سحب البيانات: $e'),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_toolsLoadingProvider.notifier).state = null;
    }
  }
}

/// ✅ Improved: dialog with feature name instead of vague SnackBar
void _showNotAvailable(BuildContext context, String feature) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.construction, color: Colors.orange, size: 48),
      title: const Text('قريباً'),
      content: Text('ميزة "$feature" قيد التطوير وستتوفر في التحديث القادم.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('حسناً'),
        ),
      ],
    ),
  );
}
