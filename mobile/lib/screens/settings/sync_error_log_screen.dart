import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/daos/outbox_dao.dart';

/// Provider لجلب سجلات الأخطاء
final syncErrorLogProvider = FutureProvider<List<SyncErrorRecord>>((ref) async {
  final db = ref.watch(databaseProvider);
  final outboxDao = OutboxDao(db);
  return outboxDao.getAllErrorRecords(limit: 100);
});

/// شاشة سجل أخطاء المزامنة
class SyncErrorLogScreen extends ConsumerWidget {
  const SyncErrorLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errorsAsync = ref.watch(syncErrorLogProvider);

    return AppScaffold(
      title: 'سجل أخطاء المزامنة',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(syncErrorLogProvider),
          tooltip: 'تحديث',
        ),
        PopupMenuButton<String>(
          onSelected: (value) => _handleMenuAction(context, ref, value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'clear_errors',
              child: ListTile(
                leading: Icon(Icons.cleaning_services, color: Colors.orange),
                title: Text('مسح الأخطاء'),
                subtitle: Text('حذف جميع سجلات الأخطاء'),
              ),
            ),
            const PopupMenuItem(
              value: 'retry_all',
              child: ListTile(
                leading: Icon(Icons.refresh, color: Colors.blue),
                title: Text('إعادة محاولة الكل'),
                subtitle: Text('إعادة جميع الفاشلة للحالة pending'),
              ),
            ),
          ],
        ),
      ],
      body: errorsAsync.when(
        data: (errors) => _buildContent(context, ref, errors),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('خطأ في تحميل السجل: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(syncErrorLogProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<SyncErrorRecord> errors,
  ) {
    if (errors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 80, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text(
              'لا توجد أخطاء',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'جميع عمليات المزامنة تمت بنجاح',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // تجميع الأخطاء حسب النوع
    final groupedErrors = _groupErrorsByEntity(errors);

    return Column(
      children: [
        // شريط الملخص
        _buildSummaryBar(errors),

        // قائمة الأخطاء
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groupedErrors.length + 1, // +1 للرأس
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildGroupedHeader(errors);
              }

              final groupIndex = index - 1;
              final entry = groupedErrors.entries.elementAt(groupIndex);
              return _buildErrorGroup(context, ref, entry.key, entry.value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(List<SyncErrorRecord> errors) {
    final failedCount = errors.where((e) => e.status == 'failed').length;
    final conflictCount = errors.where((e) => e.status == 'conflict').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Text(
            'إجمالي: ${errors.length} خطأ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          _buildBadge('فشل: $failedCount', Colors.red),
          const SizedBox(width: 8),
          _buildBadge('تعارض: $conflictCount', Colors.orange),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildGroupedHeader(List<SyncErrorRecord> errors) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        'مجمعة حسب الجدول',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }

  Map<String, List<SyncErrorRecord>> _groupErrorsByEntity(
    List<SyncErrorRecord> errors,
  ) {
    final grouped = <String, List<SyncErrorRecord>>{};
    for (final error in errors) {
      grouped.putIfAbsent(error.entity, () => []).add(error);
    }
    // ترتيب حسب عدد الأخطاء
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Map.fromEntries(sortedEntries);
  }

  Widget _buildErrorGroup(
    BuildContext context,
    WidgetRef ref,
    String entity,
    List<SyncErrorRecord> groupErrors,
  ) {
    final isExpanded = ValueNotifier<bool>(true);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ValueListenableBuilder<bool>(
        valueListenable: isExpanded,
        builder: (context, expanded, child) {
          return Column(
            children: [
              // رأس المجموعة
              ListTile(
                leading: Icon(
                  _getEntityIcon(entity),
                  color: _getEntityColor(entity),
                ),
                title: Text(
                  _getEntityLabel(entity),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${groupErrors.length} خطأ'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_sweep, color: Colors.red),
                      onPressed: () => _clearEntityErrors(context, ref, entity),
                      tooltip: 'مسح أخطاء هذا الجدول',
                    ),
                    IconButton(
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () => isExpanded.value = !isExpanded.value,
                    ),
                  ],
                ),
                onTap: () => isExpanded.value = !isExpanded.value,
              ),

              // قائمة الأخطاء
              if (expanded)
                ...groupErrors.map(
                  (error) => _buildErrorItem(context, ref, error),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorItem(
    BuildContext context,
    WidgetRef ref,
    SyncErrorRecord error,
  ) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 16, right: 8),
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: error.isConflict ? Colors.orange : Colors.red,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(
        error.shortError,
        style: const TextStyle(fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(
            DateFormat('MM/dd HH:mm').format(error.timestamp),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          _buildMiniBadge(
            error.statusLabel,
            error.isConflict ? Colors.orange : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            'المحاولات: ${error.attempts}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // تفاصيل الخطأ
              _buildDetailRow('UUID', error.uuid),
              _buildDetailRow('العملية', error.operation),
              _buildDetailRow('الحالة', error.statusLabel),
              _buildDetailRow('المحاولات', error.attempts.toString()),
              _buildDetailRow(
                'الوقت',
                DateFormat('yyyy-MM-dd HH:mm:ss').format(error.timestamp),
              ),

              const Divider(height: 24),

              // نص الخطأ الكامل
              const Text(
                'نص الخطأ:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: SelectableText(
                  error.error,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.red.shade900,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // أزرار الإجراءات
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('إعادة محاولة'),
                    onPressed: () => _retryError(context, ref, error),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: const Text(
                      'حذف',
                      style: TextStyle(color: Colors.red),
                    ),
                    onPressed: () => _deleteError(context, ref, error),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  IconData _getEntityIcon(String entity) {
    switch (entity) {
      case 'bookings':
        return Icons.hotel;
      case 'payments':
        return Icons.payment;
      case 'expenses':
        return Icons.receipt_long;
      case 'debts':
        return Icons.account_balance_wallet;
      case 'rooms':
        return Icons.meeting_room;
      case 'employees':
        return Icons.people;
      case 'cash_transactions':
        return Icons.attach_money;
      case 'shift_notes':
        return Icons.note;
      default:
        return Icons.table_chart;
    }
  }

  Color _getEntityColor(String entity) {
    switch (entity) {
      case 'bookings':
        return Colors.blue;
      case 'payments':
        return Colors.green;
      case 'expenses':
        return Colors.orange;
      case 'debts':
        return Colors.red;
      case 'rooms':
        return Colors.purple;
      case 'employees':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _getEntityLabel(String entity) {
    switch (entity) {
      case 'bookings':
        return 'الحجوزات';
      case 'payments':
        return 'المدفوعات';
      case 'expenses':
        return 'المصروفات';
      case 'debts':
        return 'الديون';
      case 'rooms':
        return 'الغرف';
      case 'employees':
        return 'الموظفين';
      case 'cash_transactions':
        return 'المعاملات النقدية';
      case 'shift_notes':
        return 'ملاحظات الوردية';
      case 'salary_payments':
        return 'مدفوعات الرواتب';
      case 'salary_withdrawals':
        return 'سحوبات الرواتب';
      default:
        return entity;
    }
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final db = ref.read(databaseProvider);
    final outboxDao = OutboxDao(db);

    switch (action) {
      case 'clear_errors':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد المسح'),
            content: const Text('هل تريد مسح جميع سجلات الأخطاء؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('مسح الكل'),
              ),
            ],
          ),
        );

        if (confirmed ?? false) {
          await outboxDao.clearStale(attemptsThreshold: 0);
          ref.invalidate(syncErrorLogProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم مسح جميع سجلات الأخطاء')),
            );
          }
        }

      case 'retry_all':
        await outboxDao.resetErrors();
        ref.invalidate(syncErrorLogProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إعادة تعيين جميع الأخطاء للمحاولة مرة أخرى'),
            ),
          );
        }
    }
  }

  void _clearEntityErrors(
    BuildContext context,
    WidgetRef ref,
    String entity,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد المسح'),
        content: Text(
          'هل تريد مسح جميع أخطاء جدول "${_getEntityLabel(entity)}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      // TODO: Add deleteByEntity method to OutboxDao
      ref.invalidate(syncErrorLogProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم مسح أخطاء ${_getEntityLabel(entity)}')),
        );
      }
    }
  }

  void _retryError(
    BuildContext context,
    WidgetRef ref,
    SyncErrorRecord error,
  ) async {
    final db = ref.read(databaseProvider);
    final outboxDao = OutboxDao(db);
    await outboxDao.scheduleRetry(error.id, error.error, error.attempts);
    ref.invalidate(syncErrorLogProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت جدولة إعادة المحاولة')));
    }
  }

  void _deleteError(
    BuildContext context,
    WidgetRef ref,
    SyncErrorRecord error,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا السجل؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      await outboxDao.cleanupSingleSuccess(error.id);
      ref.invalidate(syncErrorLogProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حذف السجل')));
      }
    }
  }
}
