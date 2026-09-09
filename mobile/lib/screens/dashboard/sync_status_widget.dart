import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/sync/realtime_sync_indicator.dart';

/// شاشة حالة المزامنة الحضية — للدمج في Dashboard
class SyncStatusWidget extends ConsumerWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: const RealtimeSyncIndicator(),
    );
  }
}

/// نسخة مضغوطة للـ AppBar
class AppBarSyncIndicator extends ConsumerWidget {
  const AppBarSyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const RealtimeSyncIndicator(
      compact: true,
      showDetailedStats: false,
    );
  }
}

/// عرض شريط المزامنة في الأسفل
class SyncStatusBottomBar extends ConsumerWidget {
  const SyncStatusBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: RealtimeSyncIndicator(
              compact: true,
              showDetailedStats: false,
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () {
              // تنفيذ مزامنة يدوية
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('مزامنة'),
          ),
        ],
      ),
    );
  }
}

/// مؤشر سريع في FloatingActionButton
class SyncFAB extends ConsumerWidget {
  const SyncFAB({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 80),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        icon: const CompactSyncDot(),
        label: const Text('مزامنة حيّة'),
      ),
    );
  }
}
