import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../services/conflict_manager.dart';
import '../../services/local_db.dart';
import '../../providers/repository_providers.dart';
import '../../services/sync_conflict_resolver.dart';

/// شاشة عرض وحل التعارضات اليدوي
class SyncConflictsScreen extends ConsumerStatefulWidget {
  const SyncConflictsScreen({super.key});

  @override
  ConsumerState<SyncConflictsScreen> createState() =>
      _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends ConsumerState<SyncConflictsScreen> {
  List<Map<String, dynamic>> _conflicts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final resolver = SyncConflictResolver(db);
      final rows = await db.customSelect(
        'SELECT * FROM sync_conflicts WHERE resolution = ? ORDER BY created_at DESC',
        variables: [const Variable<String>('pending')],
      ).get();
      if (mounted) {
        setState(() {
          _conflicts = rows.map((r) => Map<String, dynamic>.from(r.data)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل تحميل التعارضات: $e')),
        );
      }
    }
  }

  Future<void> _resolveConflict(int conflictId, bool useRemote) async {
    try {
      final db = ref.read(databaseProvider);
      final resolver = SyncConflictResolver(db);
      await resolver.resolveManually(
        conflictId: conflictId,
        useRemote: useRemote,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(useRemote ? '✅ تم اختيار بيانات السيرفر' : '✅ تم الاحتفاظ بالبيانات المحلية'),
            backgroundColor: Colors.green,
          ),
        );
        _loadConflicts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل حل التعارض: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '⚡ التعارضات',
      body: RefreshIndicator(
        onRefresh: _loadConflicts,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _conflicts.isEmpty
                ? _buildEmptyState()
                : _buildConflictsList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(Icons.check_circle_outline, size: 80, color: Colors.green.shade300),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            '🎉 لا توجد تعارضات معلقة',
            style: TextStyle(fontSize: 18),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'جميع البيانات متزامنة بشكل صحيح',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildConflictsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _conflicts.length,
      itemBuilder: (context, index) {
        final conflict = _conflicts[index];
        return _buildConflictCard(conflict);
      },
    );
  }

  Widget _buildConflictCard(Map<String, dynamic> conflict) {
    final id = conflict['id'] as int;
    final table = conflict['table_name'] as String? ?? '?';
    final uuid = conflict['uuid'] as String? ?? '?';
    final createdAt = conflict['created_at'] as String? ?? '?';

    String localSummary = 'لا توجد بيانات';
    String remoteSummary = 'لا توجد بيانات';
    try {
      final localPayload = conflict['local_payload'] as String?;
      final remotePayload = conflict['remote_payload'] as String?;
      if (localPayload != null && localPayload.isNotEmpty) {
        final decoded = jsonDecode(localPayload);
        localSummary = (decoded is Map) ? decoded.toString() : localPayload;
        if (localSummary.length > 200) localSummary = '${localSummary.substring(0, 200)}...';
      }
      if (remotePayload != null && remotePayload.isNotEmpty) {
        final decoded = jsonDecode(remotePayload);
        remoteSummary = (decoded is Map) ? decoded.toString() : remotePayload;
        if (remoteSummary.length > 200) remoteSummary = '${remoteSummary.substring(0, 200)}...';
      }
    } catch (_) {}

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: Text('$table • ${uuid.substring(0, 8)}...'),
        subtitle: Text(createdAt, style: const TextStyle(fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📱 البيانات المحلية:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(localSummary, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 12),
                const Text('☁️ البيانات البعيدة:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(remoteSummary, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _resolveConflict(id, false),
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('الاحتفاظ بالمحلي'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _resolveConflict(id, true),
                      icon: const Icon(Icons.cloud_download, size: 18),
                      label: const Text('استخدام البعيد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
