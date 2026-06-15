import 'package:flutter/material.dart';
import '../../services/conflict_manager.dart';
import '../../services/local_db.dart';
import '../../providers/repository_providers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// شاشة مراقبة التعارضات — تعرض التعارضات المعلقة وتسمح بحلها
class SyncConflictsScreen extends ConsumerStatefulWidget {
  const SyncConflictsScreen({super.key});

  @override
  ConsumerState<SyncConflictsScreen> createState() => _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends ConsumerState<SyncConflictsScreen> {
  final _conflictManager = ConflictManager(
    DatabaseManager.instance,
  );

  @override
  void initState() {
    super.initState();
    _conflictManager.loadPendingConflicts();
  }

  @override
  void dispose() {
    _conflictManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              final deleted = await _conflictManager.deleteResolvedConflicts();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم حذف $deleted تعارضاً محلولاً')),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<ConflictRecord>>(
        stream: _conflictManager.pendingConflictsStream,
        builder: (context, snapshot) {
          final conflicts = snapshot.data ?? [];

          if (conflicts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
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
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ExpansionTile(
                    title: Text(
                      '${conflict.targetTable} — ${conflict.uuid.substring(0, 8)}...',
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${conflict.lastError} — ${_formatDate(conflict.timestamp)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('البيانات المحلية:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(conflict.localPayload.toString(), style: const TextStyle(fontSize: 12)),
                            const Divider(),
                            const Text('البيانات البعيدة:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(conflict.remotePayload.toString(), style: const TextStyle(fontSize: 12)),
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
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
