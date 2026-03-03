import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/offline_queue_provider.dart';
import '../services/offline_queue/offline_queue_manager.dart';
import '../services/connectivity_service.dart';

/// ويدجت عرض حالة قائمة الانتظار للعمليات دون اتصال
class OfflineQueueWidget extends ConsumerWidget {
  final bool showBadge;
  final bool showCount;
  final bool showLabel;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  const OfflineQueueWidget({
    super.key,
    this.showBadge = true,
    this.showCount = true,
    this.showLabel = true,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(offlineQueueStatusProvider);

    return statusAsync.when(
      data: (status) => _buildContent(context, ref, status),
      loading: () => _buildLoading(),
      error: (_, __) => _buildError(),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, OfflineQueueStatus status) {
    final theme = Theme.of(context);

    if (!status.hasItems && !status.isProcessing) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap ?? () => _showQueueDetails(context, ref),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _getBackgroundColor(status, theme),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _getBorderColor(status, theme),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(status),
            if (showCount && status.pendingCount > 0) ...[
              const SizedBox(width: 6),
              _buildBadge(status.pendingCount, theme),
            ],
            if (showLabel) ...[
              const SizedBox(width: 8),
              Text(
                status.displayText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _getTextColor(status, theme),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(OfflineQueueStatus status) {
    if (status.isProcessing) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            status.isOnline ? Colors.blue : Colors.grey,
          ),
        ),
      );
    }

    if (!status.isOnline && status.pendingCount > 0) {
      return const Icon(Icons.offline_bolt, size: 16, color: Colors.orange);
    }

    if (status.failedCount > 0) {
      return const Icon(Icons.error_outline, size: 16, color: Colors.red);
    }

    if (status.pendingCount > 0) {
      return const Icon(Icons.sync, size: 16, color: Colors.blue);
    }

    return const Icon(Icons.check_circle, size: 16, color: Colors.green);
  }

  Widget _buildBadge(int count, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count.toString(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _buildError() {
    return const Icon(Icons.error, size: 16, color: Colors.red);
  }

  Color _getBackgroundColor(OfflineQueueStatus status, ThemeData theme) {
    if (!status.isOnline && status.pendingCount > 0) {
      return Colors.orange.withOpacity(0.1);
    }
    if (status.failedCount > 0) {
      return Colors.red.withOpacity(0.1);
    }
    if (status.isProcessing) {
      return theme.colorScheme.primary.withOpacity(0.1);
    }
    return theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
  }

  Color _getBorderColor(OfflineQueueStatus status, ThemeData theme) {
    if (!status.isOnline && status.pendingCount > 0) {
      return Colors.orange.withOpacity(0.3);
    }
    if (status.failedCount > 0) {
      return Colors.red.withOpacity(0.3);
    }
    if (status.isProcessing) {
      return theme.colorScheme.primary.withOpacity(0.3);
    }
    return theme.dividerColor;
  }

  Color _getTextColor(OfflineQueueStatus status, ThemeData theme) {
    if (!status.isOnline && status.pendingCount > 0) {
      return Colors.orange;
    }
    if (status.failedCount > 0) {
      return Colors.red;
    }
    return theme.colorScheme.onSurface;
  }

  void _showQueueDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const OfflineQueueDetailsSheet(),
    );
  }
}

/// شاشة تفاصيل قائمة الانتظار
class OfflineQueueDetailsSheet extends ConsumerStatefulWidget {
  const OfflineQueueDetailsSheet({super.key});

  @override
  ConsumerState<OfflineQueueDetailsSheet> createState() => _OfflineQueueDetailsSheetState();
}

class _OfflineQueueDetailsSheetState extends ConsumerState<OfflineQueueDetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(offlineQueueStatsProvider);
    final itemsAsync = ref.watch(offlineQueueItemsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        statsAsync.when(
                          data: (stats) => _buildStatsCard(stats),
                          loading: () => const CircularProgressIndicator(),
                          error: (_, __) => const Text('خطأ في تحميل الإحصائيات'),
                        ),
                        const SizedBox(height: 16),
                        itemsAsync.when(
                          data: (items) => _buildItemsList(items),
                          loading: () => const CircularProgressIndicator(),
                          error: (_, __) => const Text('خطأ في تحميل العناصر'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'عمليات قائمة الانتظار',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(OfflineQueueStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'معلقة',
                    stats.pendingCount.toString(),
                    Icons.hourglass_empty,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'فاشلة',
                    stats.failedCount.toString(),
                    Icons.error_outline,
                    Colors.red,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'مكتملة',
                    stats.completedCount.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'الحالة',
                    stats.isOnline ? 'متصل' : 'غير متصل',
                    stats.isOnline ? Icons.wifi : Icons.wifi_off,
                    stats.isOnline ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildItemsList(List<OfflineQueueItem> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('لا توجد عمليات في قائمة الانتظار'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'العمليات',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...items.map((item) => _buildItemCard(item)),
        const SizedBox(height: 16),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildItemCard(OfflineQueueItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildItemIcon(item),
        title: Text('${item.entity} - ${_getOperationText(item.operation)}'),
        subtitle: Text(
          'تم الإنشاء: ${_formatDate(item.createdAt)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _buildItemStatus(item),
      ),
    );
  }

  Widget _buildItemIcon(OfflineQueueItem item) {
    final color = _getItemColor(item);
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      child: Icon(_getItemIconData(item), color: color, size: 20),
    );
  }

  IconData _getItemIconData(OfflineQueueItem item) {
    switch (item.operation) {
      case OfflineOperationType.create:
        return Icons.add;
      case OfflineOperationType.update:
        return Icons.edit;
      case OfflineOperationType.delete:
        return Icons.delete;
      case OfflineOperationType.sync:
        return Icons.sync;
      case OfflineOperationType.upload:
        return Icons.cloud_upload;
      case OfflineOperationType.download:
        return Icons.cloud_download;
    }
  }

  Color _getItemColor(OfflineQueueItem item) {
    switch (item.status) {
      case OfflineQueueItemStatus.pending:
        return Colors.orange;
      case OfflineQueueItemStatus.processing:
        return Colors.blue;
      case OfflineQueueItemStatus.completed:
        return Colors.green;
      case OfflineQueueItemStatus.failed:
        return Colors.red;
      case OfflineQueueItemStatus.cancelled:
        return Colors.grey;
    }
  }

  Widget _buildItemStatus(OfflineQueueItem item) {
    final color = _getItemColor(item);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getStatusText(item.status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getStatusText(OfflineQueueItemStatus status) {
    switch (status) {
      case OfflineQueueItemStatus.pending:
        return 'معلقة';
      case OfflineQueueItemStatus.processing:
        return 'قيد المعالجة';
      case OfflineQueueItemStatus.completed:
        return 'مكتملة';
      case OfflineQueueItemStatus.failed:
        return 'فاشلة';
      case OfflineQueueItemStatus.cancelled:
        return 'ملغاة';
    }
  }

  String _getOperationText(OfflineOperationType operation) {
    switch (operation) {
      case OfflineOperationType.create:
        return 'إنشاء';
      case OfflineOperationType.update:
        return 'تحديث';
      case OfflineOperationType.delete:
        return 'حذف';
      case OfflineOperationType.sync:
        return 'مزامنة';
      case OfflineOperationType.upload:
        return 'رفع';
      case OfflineOperationType.download:
        return 'تحميل';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inDays < 1) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildActionButtons() {
    final manager = OfflineQueueManager.instance;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => manager.processQueue(),
            icon: const Icon(Icons.sync),
            label: const Text('مزامنة الآن'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => manager.retryFailed(),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => manager.clearAll(),
                icon: const Icon(Icons.clear_all),
                label: const Text('مسح الكل'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// زر عائم لقائمة الانتظار (Floating Action Button)
class OfflineQueueFab extends ConsumerWidget {
  final VoidCallback? onPressed;

  const OfflineQueueFab({super.key, this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(offlineQueueStatusProvider);

    return statusAsync.when(
      data: (status) {
        if (!status.hasItems) {
          return const SizedBox.shrink();
        }

        return FloatingActionButton.extended(
          onPressed: onPressed ?? () => _showQueueDetails(context, ref),
          backgroundColor: _getFabColor(status),
          icon: _buildFabIcon(status),
          label: Text('${status.pendingCount + status.failedCount}'),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildFabIcon(OfflineQueueStatus status) {
    if (status.isProcessing) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    if (!status.isOnline) {
      return const Icon(Icons.offline_bolt);
    }

    if (status.failedCount > 0) {
      return const Icon(Icons.error_outline);
    }

    return const Icon(Icons.sync);
  }

  Color _getFabColor(OfflineQueueStatus status) {
    if (!status.isOnline) {
      return Colors.orange;
    }
    if (status.failedCount > 0) {
      return Colors.red;
    }
    return Colors.blue;
  }

  void _showQueueDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const OfflineQueueDetailsSheet(),
    );
  }
}

/// شريط إشعار سفلي لقائمة الانتظار
class OfflineQueueBanner extends ConsumerWidget {
  final VoidCallback? onActionTap;

  const OfflineQueueBanner({super.key, this.onActionTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(offlineQueueStatusProvider);

    return statusAsync.when(
      data: (status) {
        if (!status.needsAttention) {
          return const SizedBox.shrink();
        }

        return Material(
          color: _getBannerColor(status),
          child: SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _getBannerIcon(status),
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      status.displayText,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: onActionTap ?? () => _retryQueue(ref),
                    child: const Text(
                      'مزامنة',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Color _getBannerColor(OfflineQueueStatus status) {
    if (!status.isOnline) {
      return Colors.orange;
    }
    if (status.failedCount > 0) {
      return Colors.red;
    }
    return Colors.blue;
  }

  IconData _getBannerIcon(OfflineQueueStatus status) {
    if (!status.isOnline) {
      return Icons.wifi_off;
    }
    if (status.failedCount > 0) {
      return Icons.error_outline;
    }
    return Icons.sync_problem;
  }

  void _retryQueue(WidgetRef ref) {
    final manager = OfflineQueueManager.instance;
    manager.processQueue();
  }
}
