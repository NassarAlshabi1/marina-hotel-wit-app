import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../services/appwrite_backup_endpoint.dart';
import '../../services/appwrite_backup_endpoints_manager.dart';
import '../../services/appwrite_backup_history_manager.dart';
import '../../services/appwrite_backup_operation_log.dart';
import '../../services/appwrite_backup_sync_service.dart';
import '../../services/local_db.dart';
import '../../utils/app_logger.dart';

/// شاشة إدارة نقاط النهاية الاحتياطية (Master/Slave)
class AppwriteBackupEndpointsScreen extends StatefulWidget {
  const AppwriteBackupEndpointsScreen({super.key});

  @override
  State<AppwriteBackupEndpointsScreen> createState() =>
      _AppwriteBackupEndpointsScreenState();
}

class _AppwriteBackupEndpointsScreenState
    extends State<AppwriteBackupEndpointsScreen> {
  List<BackupEndpoint> _endpoints = [];
  List<BackupOperationLog> _history = [];
  bool _loading = true;
  bool _isPushing = false;
  bool _isPulling = false;
  bool _showHistory = false;
  String? _pushProgressText;
  double? _pushProgressValue;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final endpoints =
        await BackupEndpointsManager.loadEndpoints(includeInactive: true);
    final history = await BackupHistoryManager.loadLogs();
    if (mounted) {
      setState(() {
        _endpoints = endpoints;
        _history = history;
        _loading = false;
      });
    }
  }

  Future<void> _toggleEndpoint(BackupEndpoint endpoint) async {
    final updated = endpoint.copyWith(isActive: !endpoint.isActive);
    await BackupEndpointsManager.updateEndpoint(updated);
    await _loadData();
  }

  Future<void> _togglePush(BackupEndpoint endpoint) async {
    final updated = endpoint.copyWith(pushEnabled: !endpoint.pushEnabled);
    await BackupEndpointsManager.updateEndpoint(updated);
    await _loadData();
  }

  Future<void> _togglePull(BackupEndpoint endpoint) async {
    final updated = endpoint.copyWith(pullEnabled: !endpoint.pullEnabled);
    await BackupEndpointsManager.updateEndpoint(updated);
    await _loadData();
  }

  Future<void> _deleteEndpoint(BackupEndpoint endpoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف نقطة النهاية'),
        content: Text('هل أنت متأكد من حذف "${endpoint.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await BackupEndpointsManager.removeEndpoint(endpoint.id);
      await _loadData();
    }
  }

  Future<void> _testEndpoint(BackupEndpoint endpoint) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(content: Text('جاري اختبار الاتصال...')),
    );

    final success = await AppwriteBackupSyncService.testConnection(endpoint);

    if (!mounted) return;
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        content: Text(success
            ? '✅ الاتصال ناجح — تم التحقق من نقطة النهاية'
            : '❌ فشل الاتصال — تحقق من البيانات'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _fullPushToEndpoint(BackupEndpoint endpoint) async {
    if (!endpoint.pushEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرفع غير مفعّل لهذه النقطة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفع جميع البيانات'),
        content: Text(
          'هل أنت متأكد من رفع جميع البيانات المحلية إلى "${endpoint.name}"؟\n\n'
          'سيتم رفع جميع السجلات الموجودة حالياً (18 جدول شامل).\n'
          '⚠️ هذه العملية قد تستغرق وقتاً حسب حجم البيانات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('بدء الرفع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    _showProgressDialog('push', endpoint.name);
    setState(() {
      _isPushing = true;
      _pushProgressText = 'جاري التجهيز...';
      _pushProgressValue = 0.0;
    });

    try {
      final db = DatabaseManager.instance;
      final service = AppwriteBackupSyncService();
      final stats = await service.fullPushAllToEndpoint(
        db: db,
        endpoint: endpoint,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _pushProgressText =
                  '${progress.tableName}: ${progress.current}/${progress.total}';
              _pushProgressValue = progress.percentage;
            });
          }
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close progress dialog

      final errors = stats['errors'] ?? 0;
      final total = stats.values.fold<int>(0, (sum, v) => sum + v) - errors;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ اكتمل الرفع إلى ${endpoint.name}: $total سجل | أخطاء: $errors'),
          backgroundColor: errors > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل الرفع: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPushing = false);
      }
    }
  }

  Future<void> _fullPullFromEndpoint(BackupEndpoint endpoint) async {
    if (!endpoint.pullEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('السحب غير مفعّل لهذه النقطة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سحب جميع البيانات'),
        content: Text(
          'هل أنت متأكد من سحب جميع البيانات من "${endpoint.name}"؟\n\n'
          'سيتم سحب جميع السجلات من Appwrite وحفظها في ملف JSON.\n'
          '⚠️ قد يستغرق وقتاً حسب حجم البيانات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('بدء السحب'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    _showProgressDialog('pull', endpoint.name);
    setState(() {
      _isPulling = true;
      _pushProgressText = 'جاري التجهيز...';
      _pushProgressValue = 0.0;
    });

    try {
      final service = AppwriteBackupSyncService();
      final file = await service.pullAllFromEndpoint(
        endpoint: endpoint,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _pushProgressText =
                  '${progress.tableName}: ${progress.current} سجل';
              _pushProgressValue = progress.percentage;
            });
          }
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (file != null) {
        final fileSize = _formatFileSize(file.lengthSync());
        if (!mounted) return;
        _showPullResult(endpoint.name, file, fileSize);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ فشل السحب — لم يتم إنشاء الملف'),
            backgroundColor: Colors.red,
          ),
        );
      }

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل السحب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPulling = false);
      }
    }
  }

  void _showProgressDialog(String type, String endpointName) {
    final label = type == 'push' ? 'رفع' : 'سحب';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('جاري $label إلى $endpointName'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_pushProgressText ?? 'جاري التجهيز...'),
                const SizedBox(height: 12),
                if (_pushProgressValue != null)
                  LinearProgressIndicator(value: _pushProgressValue),
                if (_pushProgressValue != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(_pushProgressValue! * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPullResult(
      String endpointName, File file, String fileSize) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('تم السحب بنجاح'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('البيانات من: $endpointName'),
            const SizedBox(height: 8),
            Text('حجم الملف: $fileSize'),
            const SizedBox(height: 4),
            Text(
              'المسار: ${file.path}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await Share.shareXFiles([XFile(file.path)]);
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('مشاركة'),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _fullPushToAllEndpoints() async {
    final activeEndpoints =
        _endpoints.where((e) => e.isActive && e.pushEnabled).toList();
    if (activeEndpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد نقاط نهاية نشطة ومفعّلة للرفع إليها'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفع شامل لجميع العناوين'),
        content: Text(
          'سيتم رفع جميع البيانات المحلية إلى '
          '${activeEndpoints.length} نقطة نهاية:\n\n'
          '${activeEndpoints.map((e) => '• ${e.name}').join('\n')}\n\n'
          '⚠️ قد تستغرق وقتاً طويلاً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text('بدء الرفع للجميع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    _showProgressDialog('push', 'جميع العناوين');
    setState(() {
      _isPushing = true;
      _pushProgressText = 'جاري التجهيز...';
      _pushProgressValue = 0.0;
    });

    try {
      final db = DatabaseManager.instance;
      final service = AppwriteBackupSyncService();
      final allStats = await service.fullPushAllToAllEndpoints(
        db: db,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _pushProgressText =
                  '[${progress.endpointName}] ${progress.tableName}: ${progress.current}/${progress.total}';
              _pushProgressValue = progress.percentage;
            });
          }
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      final buffer = StringBuffer('✅ اكتمل الرفع الشامل:\n');
      for (final entry in allStats.entries) {
        final s = entry.value;
        final total = s.values.fold<int>(0, (sum, v) => sum + v) -
            (s['errors'] ?? 0);
        buffer.writeln('${entry.key}: $total سجل | أخطاء: ${s['errors']}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(buffer.toString()),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 10),
        ),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل الرفع الشامل: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPushing = false);
      }
    }
  }

  Future<void> _showAddEditDialog({BackupEndpoint? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final endpointController =
        TextEditingController(text: existing?.endpoint ?? '');
    final projectIdController =
        TextEditingController(text: existing?.projectId ?? '');
    final databaseIdController =
        TextEditingController(text: existing?.databaseId ?? '');
    final apiKeyController =
        TextEditingController(text: existing?.apiKey ?? '');
    bool pushEnabled = existing?.pushEnabled ?? true;
    bool pullEnabled = existing?.pullEnabled ?? false;

    final isEditing = existing != null;
    final title = isEditing ? 'تعديل نقطة النهاية' : 'إضافة نقطة نهاية';

    final result = await showDialog<BackupEndpoint>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'الاسم',
                      hintText: 'مثال: خادم احتياطي',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endpointController,
                    decoration: const InputDecoration(
                      labelText: 'Endpoint URL',
                      hintText: 'https://xxx.appwrite.io/v1',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: projectIdController,
                    decoration: const InputDecoration(
                      labelText: 'Project ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: databaseIdController,
                    decoration: const InputDecoration(
                      labelText: 'Database ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: 'اختياري',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  const Text('إعدادات العمليات:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('رفع (Push)'),
                    subtitle: const Text('إرسال البيانات إلى هذا العنوان'),
                    value: pushEnabled,
                    onChanged: (v) =>
                        setDialogState(() => pushEnabled = v),
                    dense: true,
                  ),
                  SwitchListTile(
                    title: const Text('سحب (Pull)'),
                    subtitle: const Text('سحب البيانات من هذا العنوان'),
                    value: pullEnabled,
                    onChanged: (v) =>
                        setDialogState(() => pullEnabled = v),
                    dense: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty ||
                      endpointController.text.trim().isEmpty ||
                      projectIdController.text.trim().isEmpty ||
                      databaseIdController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('يرجى تعبئة جميع الحقول الإجبارية'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  final uuid = const Uuid();
                  final endpoint = BackupEndpoint(
                    id: existing?.id ?? uuid.v4(),
                    name: nameController.text.trim(),
                    endpoint: endpointController.text.trim(),
                    projectId: projectIdController.text.trim(),
                    databaseId: databaseIdController.text.trim(),
                    apiKey: apiKeyController.text.trim(),
                    isActive: existing?.isActive ?? true,
                    pushEnabled: pushEnabled,
                    pullEnabled: pullEnabled,
                    createdAt: existing?.createdAt,
                    lastPushAt: existing?.lastPushAt,
                    lastPullAt: existing?.lastPullAt,
                  );
                  Navigator.pop(ctx, endpoint);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      if (isEditing) {
        await BackupEndpointsManager.updateEndpoint(result);
      } else {
        await BackupEndpointsManager.addEndpoint(result);
      }
      await _loadData();
    }
  }

  void _showHistoryDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('سجل العمليات'),
          content: SizedBox(
            width: double.maxFinite,
            child: _history.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('لا توجد عمليات مسجلة بعد',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _history.length,
                    itemBuilder: (ctx, i) {
                      final log = _history[i];
                      final isPush = log.operationType == 'push';
                      final dateStr = DateFormat('yyyy-MM-dd HH:mm')
                          .format(log.timestamp);
                      final total = log.totalRecords;
                      final errors = log.stats['errors'] ?? 0;

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isPush ? Icons.cloud_upload : Icons.cloud_download,
                          color: log.success ? Colors.green : Colors.red,
                          size: 28,
                        ),
                        title: Text(
                          '${log.endpointName} — ${isPush ? "رفع" : "سحب"}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '$dateStr | $total سجل'
                          '${errors > 0 ? " | أخطاء: $errors" : ""}'
                          '${log.errorMessage != null ? "\n${log.errorMessage}" : ""}',
                        ),
                        isThreeLine: errors > 0 || log.errorMessage != null,
                      );
                    },
                  ),
          ),
          actions: [
            if (_history.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await BackupHistoryManager.clearLogs();
                  await _loadData();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('مسح السجل'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _endpoints.where((e) => e.isActive).length;
    final pushCount =
        _endpoints.where((e) => e.isActive && e.pushEnabled).length;
    final pullCount =
        _endpoints.where((e) => e.isActive && e.pullEnabled).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('نقاط النهاية الاحتياطية'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _history.isNotEmpty,
              label: Text('${_history.length}'),
              child: const Icon(Icons.history),
            ),
            tooltip: 'سجل العمليات',
            onPressed: _showHistoryDialog,
          ),
          if (_endpoints.isNotEmpty && pushCount > 0)
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'رفع شامل للجميع',
              onPressed: _isPushing ? null : _fullPushToAllEndpoints,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة نقطة نهاية',
            onPressed: () => _showAddEditDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _endpoints.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'لا توجد نقاط نهاية احتياطية',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أضف نقطة نهاية Appwrite إضافية\nلنسخ البيانات احتياطياً',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة عنوان جديد'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      // شريط المعلومات
                      _buildInfoBar(
                          activeCount, pushCount, pullCount),
                      if (pushCount > 0) _buildPushAllButton(pushCount),
                      if (_history.isNotEmpty) _buildHistoryButton(),
                      ..._endpoints.map(
                          (ep) => _buildEndpointCard(ep)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoBar(int active, int push, int pull) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_done, size: 20, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$active عنوان نشط | رفع: $push | سحب: $pull',
              style: TextStyle(
                color: Colors.deepPurple.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPushAllButton(int pushCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isPushing ? null : _fullPushToAllEndpoints,
          icon: _isPushing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload, size: 20),
          label: Text(_isPushing
              ? 'جاري الرفع...'
              : 'رفع نسخة شاملة للجميع ($pushCount عنوان)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: TextButton.icon(
        onPressed: _showHistoryDialog,
        icon: const Icon(Icons.history, size: 18),
        label: Text('سجل العمليات (${_history.length})'),
      ),
    );
  }

  Widget _buildEndpointCard(BackupEndpoint ep) {
    final isBusy = _isPushing || _isPulling;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // السطر الأول: الاسم + حالة النشاط
            Row(
              children: [
                Icon(
                  ep.isActive ? Icons.cloud_done : Icons.cloud_off,
                  color: ep.isActive ? Colors.green : Colors.grey,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ep.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (ep.isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: const Text('نشط',
                        style: TextStyle(fontSize: 10, color: Colors.green)),
                  ),
              ],
            ),

            const SizedBox(height: 6),

            // معلومات الاتصال
            Text(
              ep.endpoint,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${ep.projectId} / ${ep.databaseId}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),

            // أزرار التشغيل: Push / Pull
            const SizedBox(height: 8),
            Row(
              children: [
                // زر تشغيل/إيقاف Push
                _buildToggleChip(
                  icon: Icons.cloud_upload,
                  label: 'رفع',
                  active: ep.pushEnabled,
                  onToggle: ep.isActive ? () => _togglePush(ep) : null,
                  activeColor: Colors.orange,
                ),
                const SizedBox(width: 6),
                // زر تشغيل/إيقاف Pull
                _buildToggleChip(
                  icon: Icons.cloud_download,
                  label: 'سحب',
                  active: ep.pullEnabled,
                  onToggle: ep.isActive ? () => _togglePull(ep) : null,
                  activeColor: Colors.blue,
                ),
                const Spacer(),
                // زر تفعيل/إيقاف
                _buildToggleChip(
                  icon: ep.isActive ? Icons.pause : Icons.play_arrow,
                  label: ep.isActive ? 'إيقاف' : 'تفعيل',
                  active: ep.isActive,
                  onToggle: () => _toggleEndpoint(ep),
                  activeColor: Colors.green,
                ),
              ],
            ),

            // آخر عمليات
            if (ep.lastPushAt != null || ep.lastPullAt != null) ...[
              const Divider(height: 12),
              if (ep.lastPushAt != null)
                Text(
                  'آخر رفع: ${dateFormat.format(ep.lastPushAt!)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              if (ep.lastPullAt != null)
                Text(
                  'آخر سحب: ${dateFormat.format(ep.lastPullAt!)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],

            const Divider(height: 12),

            // أزرار الإجراءات
            Row(
              children: [
                _buildActionButton(
                  icon: Icons.cloud_upload,
                  label: 'رفع نسخة كاملة',
                  color: Colors.orange,
                  enabled: ep.isActive && ep.pushEnabled && !isBusy,
                  onPressed: () => _fullPushToEndpoint(ep),
                ),
                const SizedBox(width: 6),
                _buildActionButton(
                  icon: Icons.cloud_download,
                  label: 'سحب نسخة',
                  color: Colors.blue,
                  enabled: ep.isActive && ep.pullEnabled && !isBusy,
                  onPressed: () => _fullPullFromEndpoint(ep),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // أزرار ثانوية
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.wifi_find, size: 20),
                  tooltip: 'اختبار الاتصال',
                  onPressed:
                      isBusy ? null : () => _testEndpoint(ep),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'تعديل',
                  onPressed:
                      isBusy ? null : () => _showAddEditDialog(existing: ep),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  tooltip: 'حذف',
                  onPressed:
                      isBusy ? null : () => _deleteEndpoint(ep),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onToggle,
    required Color activeColor,
  }) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? activeColor.withValues(alpha: 0.4) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? activeColor : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? activeColor : Colors.grey,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Material(
        color: enabled ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: enabled ? color : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled ? color : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
