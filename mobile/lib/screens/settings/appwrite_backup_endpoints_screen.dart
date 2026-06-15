import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../services/appwrite_backup_endpoint.dart';
import '../../services/appwrite_backup_endpoints_manager.dart';
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
  bool _loading = true;
  bool _isPushing = false;

  @override
  void initState() {
    super.initState();
    _loadEndpoints();
  }

  Future<void> _loadEndpoints() async {
    setState(() => _loading = true);
    final endpoints = await BackupEndpointsManager.loadEndpoints(includeInactive: true);
    if (mounted) {
      setState(() {
        _endpoints = endpoints;
        _loading = false;
      });
    }
  }

  Future<void> _toggleEndpoint(BackupEndpoint endpoint) async {
    final updated = endpoint.copyWith(isActive: !endpoint.isActive);
    await BackupEndpointsManager.updateEndpoint(updated);
    await _loadEndpoints();
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
    if (confirmed ?? false) {
      await BackupEndpointsManager.removeEndpoint(endpoint.id);
      await _loadEndpoints();
    }
  }

  Future<void> _testEndpoint(BackupEndpoint endpoint) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(content: Text('جاري اختبار الاتصال...')),
    );

    final success = await AppwriteBackupSyncService.testConnection(endpoint);

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

  /// رفع جميع البيانات إلى نقطة نهاية واحدة
  Future<void> _fullPushToEndpoint(BackupEndpoint endpoint) async {
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
    setState(() => _isPushing = true);

    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('جاري رفع جميع البيانات...'),
          ],
        ),
        duration: Duration(minutes: 10),
      ),
    );

    try {
      final db = DatabaseManager.instance;
      final service = AppwriteBackupSyncService();
      final stats = await service.fullPushAllToEndpoint(
        db: db,
        endpoint: endpoint,
        onProgress: (table, current, total) {
          AppLogger.debug('⏳ $table: $current/$total');
        },
      );

      scaffold.hideCurrentSnackBar();
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            '✅ اكتمل الرفع إلى ${endpoint.name}:\n'
            'غرف: ${stats['rooms']} | موظفين: ${stats['employees']}\n'
            'حجوزات: ${stats['bookings']} | مدفوعات: ${stats['payments']}\n'
            'مصروفات: ${stats['expenses']} | ديون: ${stats['debts']}\n'
            'ملاحظات حجوزات: ${stats['booking_notes']} | ليالي: ${stats['booking_nights']}\n'
            'ملاحظات نوبة: ${stats['shift_notes']} | معاملات نقدية: ${stats['cash_transactions']}\n'
            'نزلاء: ${stats['guest_infos']} | دورات رواتب: ${stats['salary_cycles']}\n'
            'دفعات رواتب: ${stats['salary_payments']} | سحوبات: ${stats['salary_withdrawals']}\n'
            'تعديلات أسعار: ${stats['price_adjustments']} | تعديلات حجوزات: ${stats['booking_price_adjustments']}\n'
            'سجلات تدقيق: ${stats['audit_logs']} | إلغاءات دفع: ${stats['payment_voids']}\n'
            '❌ أخطاء: ${stats['errors']}',
          ),
          backgroundColor: (stats['errors'] ?? 0) > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 12),
        ),
      );
    } catch (e) {
      scaffold.hideCurrentSnackBar();
      scaffold.showSnackBar(
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

  /// رفع شامل لجميع نقاط النهاية النشطة دفعة واحدة
  Future<void> _fullPushToAllEndpoints() async {
    final activeEndpoints = _endpoints.where((e) => e.isActive).toList();
    if (activeEndpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد نقاط نهاية نشطة للرفع إليها'),
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
          'سيتم رفع جميع البيانات المحلية (18 جدول شامل) إلى '
          '${activeEndpoints.length} نقطة نهاية نشطة:\n\n'
          '${activeEndpoints.map((e) => '• ${e.name}').join('\n')}\n\n'
          '⚠️ هذه العملية قد تستغرق وقتاً طويلاً حسب حجم البيانات وعدد العناوين.',
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
    setState(() => _isPushing = true);

    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('جاري الرفع الشامل إلى ${activeEndpoints.length} عنوان...'),
          ],
        ),
        duration: const Duration(minutes: 30),
      ),
    );

    try {
      final db = DatabaseManager.instance;
      final service = AppwriteBackupSyncService();
      final allStats = await service.fullPushAllToAllEndpoints(
        db: db,
        onProgress: (endpointName, table, current, total) {
          AppLogger.debug('⏳ [$endpointName] $table: $current/$total');
        },
      );

      scaffold.hideCurrentSnackBar();

      // عرض ملخص النتائج لكل عنوان
      final buffer = StringBuffer('✅ اكتمل الرفع الشامل:\n');
      for (final entry in allStats.entries) {
        final s = entry.value;
        final totalRecords = s.values.fold<int>(0, (sum, v) => sum + v) - (s['errors'] ?? 0);
        buffer.writeln('${entry.key}: $totalRecords سجل | أخطاء: ${s['errors']}');
      }

      scaffold.showSnackBar(
        SnackBar(
          content: Text(buffer.toString()),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 15),
        ),
      );
    } catch (e) {
      scaffold.hideCurrentSnackBar();
      scaffold.showSnackBar(
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

    final isEditing = existing != null;
    final title = isEditing ? 'تعديل نقطة النهاية' : 'إضافة نقطة نهاية';

    final result = await showDialog<BackupEndpoint>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
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
                    hintText: 'اختياري — المفتاح السري',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
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
                const uuid = Uuid();
                final endpoint = BackupEndpoint(
                  id: existing?.id ?? uuid.v4(),
                  name: nameController.text.trim(),
                  endpoint: endpointController.text.trim(),
                  projectId: projectIdController.text.trim(),
                  databaseId: databaseIdController.text.trim(),
                  apiKey: apiKeyController.text.trim(),
                  isActive: existing?.isActive ?? true,
                  createdAt: existing?.createdAt,
                );
                Navigator.pop(ctx, endpoint);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      if (isEditing) {
        await BackupEndpointsManager.updateEndpoint(result);
      } else {
        await BackupEndpointsManager.addEndpoint(result);
      }
      await _loadEndpoints();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _endpoints.where((e) => e.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('نقاط النهاية الاحتياطية'),
        actions: [
          if (_endpoints.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'رفع شامل للجميع',
              onPressed: _isPushing ? null : _fullPushToAllEndpoints,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة نقطة نهاية',
            onPressed: _showAddEditDialog,
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
                      const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
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
                        onPressed: _showAddEditDialog,
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
              : Column(
                  children: [
                    // شريط معلومات العناوين
                    if (activeCount > 0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.deepPurple.shade50,
                        child: Row(
                          children: [
                            Icon(Icons.cloud_done, size: 18, color: Colors.deepPurple.shade700),
                            const SizedBox(width: 8),
                            Text(
                              '$activeCount عنوان نشط من ${_endpoints.length}',
                              style: TextStyle(
                                color: Colors.deepPurple.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            if (_isPushing)
                              const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                      ),

                    // زر رفع شامل للجميع
                    if (activeCount > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isPushing ? null : _fullPushToAllEndpoints,
                            icon: const Icon(Icons.cloud_upload, size: 20),
                            label: Text(
                              _isPushing
                                ? 'جاري الرفع...'
                                : 'رفع نسخة شاملة للجميع ($activeCount عنوان)',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),

                    // قائمة العناوين
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _endpoints.length,
                        itemBuilder: (context, index) {
                          final ep = _endpoints[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            child: ListTile(
                              leading: Icon(
                                ep.isActive
                                    ? Icons.cloud_done
                                    : Icons.cloud_off,
                                color: ep.isActive ? Colors.green : Colors.grey,
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    ep.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  if (ep.isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green.shade200),
                                      ),
                                      child: const Text(
                                        'نشط',
                                        style: TextStyle(fontSize: 10, color: Colors.green),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                '${ep.endpoint}\n${ep.projectId} / ${ep.databaseId}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  switch (value) {
                                    case 'toggle':
                                      await _toggleEndpoint(ep);
                                    case 'edit':
                                      await _showAddEditDialog(existing: ep);
                                    case 'test':
                                      await _testEndpoint(ep);
                                    case 'fullpush':
                                      await _fullPushToEndpoint(ep);
                                    case 'delete':
                                      await _deleteEndpoint(ep);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(
                                          ep.isActive
                                              ? Icons.pause_circle
                                              : Icons.play_circle,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          ep.isActive ? 'إيقاف' : 'تفعيل',
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 20),
                                        SizedBox(width: 8),
                                        Text('تعديل'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'test',
                                    child: Row(
                                      children: [
                                        Icon(Icons.wifi_find, size: 20),
                                        SizedBox(width: 8),
                                        Text('اختبار الاتصال'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'fullpush',
                                    child: Row(
                                      children: [
                                        Icon(Icons.cloud_upload, size: 20, color: Colors.orange),
                                        SizedBox(width: 8),
                                        Text('رفع جميع البيانات', style: TextStyle(color: Colors.orange)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 20, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('حذف', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
