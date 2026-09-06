import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/appwrite_providers.dart';
import '../providers/cloudflare_connection_providers.dart';
import '../services/cloudflare_config.dart';
import '../services/local_db.dart';

/// بطاقة «بيانات الاتصال التلقائي مع Cloudflare».
///
/// تعرض — بتحديث تلقائي كل 30 ثانية عبر [connectionAutoRefreshProvider] —
/// حالة اتصال Cloudflare Worker (/health)، نية المزامنة التلقائية
/// وفترتها وحالة محركها الفعلية، آخر مزامنة ناجحة من sync_log،
/// وعدد سجلات outbox المعلقة التي لم تُسلَّم للسحابة بعد.
///
/// عديمة الحالة كلياً: لا setState — كل شيء عبر Riverpod providers
/// (autoSyncSnapshotProvider / lastSuccessfulSyncProvider /
/// pendingUploadCountProvider / connectionStatusProvider).
class CloudflareAutoConnectionCard extends ConsumerWidget {
  const CloudflareAutoConnectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // يُبقي مؤقّت التحديث التلقائي حياً ما دامت البطاقة معروضة.
    ref.watch(connectionAutoRefreshProvider);

    final connection = ref.watch(connectionStatusProvider);
    final autoSync = ref.watch(autoSyncSnapshotProvider);
    final lastSync = ref.watch(lastSuccessfulSyncProvider);
    final pending = ref.watch(pendingUploadCountProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'الاتصال التلقائي مع Cloudflare',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث الآن',
                  onPressed: () {
                    ref.invalidate(autoSyncSnapshotProvider);
                    ref.invalidate(lastSuccessfulSyncProvider);
                    ref.invalidate(pendingUploadCountProvider);
                    unawaited(
                      ref
                          .read(connectionStatusProvider.notifier)
                          .checkConnection(),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _connectionRow(context, connection),
            const Divider(height: 20),
            _autoSyncRow(context, autoSync),
            const SizedBox(height: 10),
            _lastSyncRow(context, lastSync),
            const SizedBox(height: 10),
            _pendingRow(context, pending),
            const SizedBox(height: 10),
            _endpointRow(context, colorScheme),
          ],
        ),
      ),
    );
  }

  // ─── الصفوف ──────────────────────────────────────────────────

  Widget _connectionRow(
    BuildContext context,
    ConnectionState connection,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color dotColor;
    final String label;
    if (connection.isChecking) {
      dotColor = Colors.orange;
      label = 'جارٍ فحص الاتصال…';
    } else if (connection.isConnected) {
      dotColor = colorScheme.primary;
      label = 'متصل بسحابة Cloudflare';
    } else {
      dotColor = colorScheme.error;
      label =
          'غير متصل${connection.errorMessage == null ? '' : ' — ${connection.errorMessage}'}';
    }
    return Row(
      children: [
        _StatusDot(color: dotColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _autoSyncRow(
    BuildContext context,
    AsyncValue<AutoSyncSnapshot> autoSync,
  ) {
    return autoSync.when(
      loading: () => const _RowSkeleton(),
      error: (_, _) =>
          const _RowError('تعذّر قراءة إعدادات المزامنة التلقائية'),
      data: (snapshot) {
        final String value;
        if (snapshot.enabled) {
          value =
              'مفعّلة — ${_intervalLabelAr(snapshot.intervalMinutes)}'
              '${snapshot.engineRunning ? '' : ' (المحرك متوقف حتى إعادة التشغيل)'}';
        } else {
          value = 'متوقفة من الإعدادات';
        }
        return _DataRow(
          icon: Icons.autorenew,
          label: 'المزامنة التلقائية',
          value: value,
        );
      },
    );
  }

  Widget _lastSyncRow(
    BuildContext context,
    AsyncValue<SyncLogData?> lastSync,
  ) {
    return lastSync.when(
      loading: () => const _RowSkeleton(),
      error: (_, _) => const _RowError('تعذّر قراءة سجل المزامنة'),
      data: (log) {
        if (log == null) {
          return const _DataRow(
            icon: Icons.history,
            label: 'آخر مزامنة ناجحة',
            value: 'لا توجد بعد',
          );
        }
        final direction = switch (log.direction) {
          'push' => 'رفع',
          'pull' => 'سحب',
          _ => log.direction,
        };
        final when = DateTime.tryParse(log.completedAt ?? log.createdAt);
        final relative = when == null
            ? ''
            : ' — ${_relativeAr(when, DateTime.now())}';
        return _DataRow(
          icon: Icons.history,
          label: 'آخر مزامنة ناجحة',
          value: '$direction$relative',
        );
      },
    );
  }

  Widget _pendingRow(BuildContext context, AsyncValue<int> pending) {
    return pending.when(
      loading: () => const _RowSkeleton(),
      error: (_, _) => const _RowError('تعذّر قراءة السجلات المعلقة'),
      data: (count) => _DataRow(
        icon: Icons.outbox_outlined,
        label: 'سجلات بانتظار الرفع',
        value: '$count',
      ),
    );
  }

  Widget _endpointRow(BuildContext context, ColorScheme colorScheme) {
    final host =
        Uri.tryParse(CloudflareConfig.workerUrl)?.host ??
        CloudflareConfig.workerUrl;
    return _DataRow(
      icon: Icons.dns_outlined,
      label: 'نقطة الاتصال',
      value: host,
    );
  }

  // ─── أدوات ───────────────────────────────────────────────────

  /// تسمية الفترة بالعربية الصحيحة (جمع/مثنى/مفرد).
  String _intervalLabelAr(int minutes) {
    if (minutes == 1) {
      return 'كل دقيقة';
    }
    if (minutes == 2) {
      return 'كل دقيقتين';
    }
    if (minutes >= 3 && minutes <= 10) {
      return 'كل $minutes دقائق';
    }
    return 'كل $minutes دقيقة';
  }

  String _relativeAr(DateTime when, DateTime now) {
    final diff = now.difference(when);
    if (diff.inMinutes < 1) {
      return 'الآن';
    }
    if (diff.inMinutes < 60) {
      return 'قبل ${diff.inMinutes} دقيقة';
    }
    if (diff.inHours < 24) {
      return 'قبل ${diff.inHours} ساعة';
    }
    return 'قبل ${diff.inDays} يوم';
  }
}

// ─── عناصر عرض صغيرة (كلها const-قابلة) ────────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text('$label: ', style: Theme.of(context).textTheme.bodyMedium),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 14,
        width: 140,
        child: LinearProgressIndicator(minHeight: 14),
      ),
    );
  }
}

class _RowError extends StatelessWidget {
  const _RowError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: colorScheme.error),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    );
  }
}
