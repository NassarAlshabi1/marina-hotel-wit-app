import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/repository_providers.dart';
import '../../services/daos/sync_log_dao.dart';

/// Provider لسجل المزامنة
final syncHistoryProvider = FutureProvider.family<List<SyncLogEntry>, SyncFilter>(
  (ref, filter) async {
    final db = ref.read(databaseProvider);
    final dao = SyncLogDao(db);
    return dao.getSyncHistory(
      limit: filter.limit,
      offset: filter.offset,
      direction: filter.direction,
      status: filter.status,
    );
  },
);

class SyncFilter {

  const SyncFilter({
    this.limit = 100,
    this.offset = 0,
    this.direction,
    this.status,
  });
  final int limit;
  final int offset;
  final String? direction;
  final String? status;
}

class SyncHistoryScreen extends ConsumerStatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  ConsumerState<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends ConsumerState<SyncHistoryScreen> {
  String? _selectedDirection;
  String? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final filter = SyncFilter(
      direction: _selectedDirection,
      status: _selectedStatus,
    );

    final logsAsync = ref.watch(syncHistoryProvider(filter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المزامنة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'تصفية',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(syncHistoryProvider),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: logsAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'لا توجد عمليات مزامنة مسجلة',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildLogCard(log);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('خطأ: $error', style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  Widget _buildLogCard(SyncLogEntry log) {
    final isSuccess = log.status == 'success';
    final isPartial = log.status == 'partial';
    final isPull = log.direction == 'pull';

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isSuccess) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'نجح';
    } else if (isPartial) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
      statusText = 'نجح جزئياً';
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.error;
      statusText = 'فشل';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSuccess ? Colors.green.shade200 : Colors.red.shade200,
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPull ? Colors.blue.shade50 : Colors.purple.shade50,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isPull ? Icons.download : Icons.upload,
                color: isPull ? Colors.blue : Colors.purple,
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  isPull ? 'سحب من السيرفر' : 'رفع إلى السيرفر',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    _formatDateTime(log.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (log.recordsCount != null) ...[
                    Icon(Icons.storage, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '${log.recordsCount} سجل',
                      style: TextStyle(
                        fontSize: 12,
                        color: isPull ? Colors.blue.shade700 : Colors.purple.shade700,
                      ),
                    ),
                  ],
                  if (log.durationMs != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.timer, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '${log.durationMs}ms',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
              if (log.errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          onTap: () => _showLogDetails(log),
        ),
      ),
    );
  }

  void _showLogDetails(SyncLogEntry log) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: log.direction == 'pull'
                          ? Colors.blue.shade50
                          : Colors.purple.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        log.direction == 'pull' ? Icons.download : Icons.upload,
                        color: log.direction == 'pull' ? Colors.blue : Colors.purple,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.direction == 'pull' ? 'سحب من السيرفر' : 'رفع إلى السيرفر',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          log.syncId,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              _buildDetailRow('الحالة', log.status == 'success' ? 'نجح' : log.status == 'partial' ? 'نجح جزئياً' : 'فشل'),
              _buildDetailRow('الجهاز', log.deviceId),
              _buildDetailRow('الوجهة', log.target ?? 'غير معروف'),
              _buildDetailRow('وقت البدء', _formatFullDateTime(log.createdAt)),
              if (log.completedAt != null)
                _buildDetailRow('وقت الانتهاء', _formatFullDateTime(log.completedAt!)),
              if (log.durationMs != null)
                _buildDetailRow('المدة', '${log.durationMs} مللي ثانية'),
              if (log.recordsCount != null)
                _buildDetailRow('عدد السجول', '${log.recordsCount}'),
              if (log.errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'رسالة الخطأ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        log.errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'الآن';
    } else if (diff.inHours < 1) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inDays < 1) {
      return 'منذ ${diff.inHours} ساعة';
    } else if (diff.inDays < 7) {
      return 'منذ ${diff.inDays} يوم';
    } else {
      return '${dateTime.year}/${dateTime.month}/${dateTime.day}';
    }
  }

  String _formatFullDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تصفية السجل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _selectedDirection,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'pull', child: Text('سحب')),
                  DropdownMenuItem(value: 'push', child: Text('رفع')),
                ],
                onChanged: (value) => setState(() => _selectedDirection = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _selectedStatus,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'success', child: Text('نجح')),
                  DropdownMenuItem(value: 'partial', child: Text('نجح جزئياً')),
                  DropdownMenuItem(value: 'failed', child: Text('فشل')),
                ],
                onChanged: (value) => setState(() => _selectedStatus = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('تطبيق'),
            ),
          ],
        );
      },
    );
  }
}
