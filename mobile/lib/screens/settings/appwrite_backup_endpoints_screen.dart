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
    if (confirmed == true) {
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

  Future<void> _fullPushToEndpoint(BackupEndpoint endpoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفع جميع البيانات'),
        content: Text(
          'هل أنت متأكد من رفع جميع البيانات المحلية إلى "${endpoint.name}"؟\n\n'
          'سيتم رفع جميع السجلات الموجودة حالياً.\n'
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
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('جاري رفع جميع البيانات...'),
          ],
        ),
        duration: Duration(seconds: 30),
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
            '✅ اكتمل الرفع:\n'
            'غرف: ${stats['rooms']} | موظفين: ${stats['employees']}\n'
            'حجوزات: ${stats['bookings']} | مدفوعات: ${stats['payments']}\n'
            'أخطاء: ${stats['errors']}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 8),
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
                final _uuid = const Uuid();
                final endpoint = BackupEndpoint(
                  id: existing?.id ?? _uuid.v4(),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('نقاط النهاية الاحتياطية'),
        actions: [
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
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'لا توجد نقاط نهاية احتياطية',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'أضف نقطة نهاية Appwrite إضافية\nلنسخ البيانات احتياطياً',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
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
                        title: Text(
                          ep.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                                break;
                              case 'edit':
                                await _showAddEditDialog(existing: ep);
                                break;
                              case 'test':
                                await _testEndpoint(ep);
                                break;
                              case 'fullpush':
                                await _fullPushToEndpoint(ep);
                                break;
                              case 'delete':
                                await _deleteEndpoint(ep);
                                break;
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
                                  Icon(Icons.wifi_find, size: 20),
                                  SizedBox(width: 8),
                                  Text('اختبار الاتصال'),
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
    );
  }
}
