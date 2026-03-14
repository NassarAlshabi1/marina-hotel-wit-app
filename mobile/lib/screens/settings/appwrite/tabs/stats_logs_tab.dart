import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/appwrite_providers.dart';

class AppwriteStatsLogsTab extends ConsumerWidget {
  const AppwriteStatsLogsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outboxCountAsync = ref.watch(outboxCountProvider);
    final syncStatsAsync = ref.watch(syncStatsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatCard(
          'السجلات المعلقة',
          '${outboxCountAsync.valueOrNull ?? 0}',
          Icons.outbox,
          Colors.orange,
        ),
        const SizedBox(height: 16),
        _buildStatCard(
          'إجمالي السجلات المرفوعة',
          '${syncStatsAsync.valueOrNull?['totalRecordsPushed'] ?? 0}',
          Icons.cloud_upload,
          Colors.blue,
        ),
        const SizedBox(height: 16),
        _buildStatCard(
          'إجمالي السجلات المسحوبة',
          '${syncStatsAsync.valueOrNull?['totalRecordsPulled'] ?? 0}',
          Icons.cloud_download,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
    );
  }
}
