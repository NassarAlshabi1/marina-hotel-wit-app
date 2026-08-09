// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../services/conflict_manager.dart';
import '../../utils/performance_monitor.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// شاشة مراقبة التعارضات — تعرض التعارضات المعلقة وتسمح بحلها
class SyncConflictsScreen extends ConsumerStatefulWidget {
  const SyncConflictsScreen({super.key});

  @override
  ConsumerState<SyncConflictsScreen> createState() =>
      _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends ConsumerState<SyncConflictsScreen> {
  late final ConflictManager _conflictManager;

  @override
  void initState() {
    super.initState();
    _conflictManager = ConflictManager(ref.read(databaseProvider));
    _conflictManager.loadPendingConflicts();
  }

  @override
  void dispose() {
    _conflictManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PerformanceInspector(
      name: 'SyncConflictsScreen',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تعارضات المزامنة'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _conflictManager.loadPendingConflicts(),
            ),
            IconButton(
              icon: const Icon(Icons.auto_delete),
              tooltip: 'حذف التعارضات المحلولة',
              onPressed: () async {
                final deleted = await _conflictManager
                    .deleteResolvedConflicts();
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(content: Text('تم حذف $deleted تعارضاً محلولاً')),
                  );
                }
              },
            ),
          ],
        ),
        body: RepaintBoundary(
          child: StreamBuilder<List<PendingConflict>>(
            stream: _conflictManager.conflictsStream,
            builder: (context, snapshot) {
              // ✅ معالجة حالة الخطأ — بدونها يظهر للمستخدم قائمة فارغة (كأنه لا توجد
              // تعارضات) حتى لو انفجر الـ stream، وهو مضلِّل.
              if (snapshot.hasError) {
                // 🔒 نسجّل التفاصيل التقنية في debugPrint فقط (للمطورين)، ولا نُظهرها
                // للمستخدم — قد تحتوي على أسماء جداول/حقول داخلية أو رسائل Appwrite.
                dlog(() => '❌ sync_conflicts stream error: ${snapshot.error}');
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'حدث خطأ أثناء تحميل التعارضات',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'تحقّق من اتصال الشبكة وحاول مرة أخرى.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () =>
                              _conflictManager.loadPendingConflicts(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // ✅ معالجة حالة التحميل — تمنع الشاشة البيضاء قبل وصول أول بيانات.
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final conflicts = snapshot.data ?? [];

              if (conflicts.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'لا توجد تعارضات معلقة',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'جميع التعارضات تم حلها تلقائياً',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => _conflictManager.loadPendingConflicts(),
                child: ListView.builder(
                  itemCount: conflicts.length,
                  itemBuilder: (context, index) {
                    final conflict = conflicts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ExpansionTile(
                        title: Text(
                          '${conflict.table} — ${conflict.uuid.substring(0, 8)}...',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${conflict.resolution != null ? "محلول" : "معلق"} — ${_formatDate(conflict.detectedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'البيانات المحلية:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  conflict.localData.toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const Divider(),
                                const Text(
                                  'البيانات البعيدة:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  conflict.remoteData.toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ), // RepaintBoundary
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
