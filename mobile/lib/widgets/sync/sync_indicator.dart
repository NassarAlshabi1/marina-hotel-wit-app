import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync/core/sync_orchestrator.dart';
import '../../services/sync/models/sync_state.dart';

/// مؤشر حالة المزامنة في شريط التطبيق
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStateAsync = ref.watch(syncStateProvider);

    return syncStateAsync.when(
      data: (state) => _buildIndicator(context, state),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const Icon(Icons.error_outline, color: Colors.red),
    );
  }

  Widget _buildIndicator(BuildContext context, SyncState state) {
    if (state.isSyncing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: state.progress > 0 ? state.progress / 100 : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            state.message ?? 'جاري المزامنة...',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
    }

    if (state.hasError) {
      return const Tooltip(
        message: 'خطأ في المزامنة',
        child: Icon(Icons.sync_problem, color: Colors.orange),
      );
    }

    if (state.isOffline) {
      return const Tooltip(
        message: 'وضع عدم الاتصال',
        child: Icon(Icons.offline_bolt, color: Colors.grey),
      );
    }

    if (state.pendingChanges > 0) {
      return Badge(
        label: Text('${state.pendingChanges}'),
        child: const Icon(Icons.sync, color: Colors.blue),
      );
    }

    return const Tooltip(
      message: 'تمت المزامنة',
      child: Icon(Icons.sync, color: Colors.green),
    );
  }
}

/// زر المزامنة المحسن
class EnhancedSyncButton extends ConsumerWidget {
  const EnhancedSyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStateAsync = ref.watch(syncStateProvider);
    final orchestrator = ref.read(syncOrchestratorProvider);

    return syncStateAsync.when(
      data: (state) {
        return _SyncButtonContent(
          state: state,
          onPressed: state.isSyncing
              ? null
              : () => _showSyncOptions(context, orchestrator),
        );
      },
      loading: () => const _SyncButtonContent(),
      error: (_, __) => _SyncButtonContent(
        onPressed: () => _showSyncOptions(context, orchestrator),
        isError: true,
      ),
    );
  }

  void _showSyncOptions(BuildContext context, SyncOrchestrator orchestrator) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('مزامنة كاملة'),
              subtitle: const Text('دفع + سحب'),
              onTap: () {
                Navigator.pop(context);
                orchestrator.syncNow();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('رفع التغييرات فقط'),
              subtitle: const Text('Push Only'),
              onTap: () {
                Navigator.pop(context);
                orchestrator.pushOnly();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('سحب التغييرات فقط'),
              subtitle: const Text('Pull Only'),
              onTap: () {
                Navigator.pop(context);
                orchestrator.pullOnly();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncButtonContent extends StatelessWidget {

  const _SyncButtonContent({
    this.state,
    this.onPressed,
    this.isError = false,
  });
  final SyncState? state;
  final VoidCallback? onPressed;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String tooltip;

    if (isError) {
      icon = Icons.sync_problem;
      color = Colors.orange;
      tooltip = 'خطأ في المزامنة';
    } else if (state?.isSyncing ?? false) {
      icon = Icons.sync;
      color = Colors.blue;
      tooltip = 'جاري المزامنة...';
    } else if (state?.pendingChanges != null && state!.pendingChanges > 0) {
      icon = Icons.sync;
      color = Colors.orange;
      tooltip = '${state!.pendingChanges} تغييرات معلقة';
    } else if (state?.isOffline ?? false) {
      icon = Icons.offline_bolt;
      color = Colors.grey;
      tooltip = 'وضع عدم الاتصال';
    } else {
      icon = Icons.sync;
      color = Colors.green;
      tooltip = 'النقر للمزامنة';
    }

    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: state?.isSyncing ?? false
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}
