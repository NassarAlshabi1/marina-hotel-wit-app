import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/admin_layout.dart';
import '../../services/providers.dart';
import '../../services/ditto_sync_service.dart';
import '../../services/local_db.dart';

class SyncDiagnosticsScreen extends ConsumerStatefulWidget {
  const SyncDiagnosticsScreen({super.key});

  @override
  ConsumerState<SyncDiagnosticsScreen> createState() => _SyncDiagnosticsScreenState();
}

class _SyncDiagnosticsScreenState extends ConsumerState<SyncDiagnosticsScreen> {
  bool _reloading = false;

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentRoute: '/diagnostics',
      title: 'تشخيص المزامنة',
      actions: [
        IconButton(
          tooltip: 'تشغيل المزامنة الآن',
          onPressed: _reloading ? null : () async {
            setState(() => _reloading = true);
            try {
              await ref.read(syncServiceProvider).runSync();
            } finally {
              setState(() => _reloading = false);
            }
          },
          icon: _reloading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync),
        ),
      ],
      body: _buildBody(ref),
      onRouteSelected: (_) {},
    );
  }

  Widget _buildBody(WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder(
      future: _loadData(db),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data! as _DiagData;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('حالة المزامنة'),
            _kv('الحالة الحالية', _statusLabel(ref)),
            const SizedBox(height: 8),
            _kv('آخر وقت سحب', _fmtEpoch(data.syncState?.lastPullTs)),
            _kv('آخر وقت دفع', _fmtEpoch(data.syncState?.lastPushTs)),
            _kv('آخر وقت من الخادم', _fmtEpoch(data.syncState?.lastServerTs)),
            const Divider(height: 32),
            _sectionTitle('قائمة الانتظار (Outbox)'),
            _kv('عدد العناصر', data.outboxCount.toString()),
            _kv('عدد العناصر ذات الأخطاء', data.outboxErrors.length.toString()),
            const SizedBox(height: 12),
            _subTitle('آخر الأخطاء (20)'),
            if (data.outboxErrors.isEmpty)
              const Text('لا توجد أخطاء حالياً')
            else
              ...data.outboxErrors.map((e) => _errorTile(e)).toList(),
            const SizedBox(height: 16),
            _subTitle('عناصر حديثة (20)'),
            if (data.outboxRecent.isEmpty)
              const Text('لا توجد عناصر حديثة')
            else
              ...data.outboxRecent.map((e) => _itemTile(e)).toList(),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
  Widget _subTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );
  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 160, child: Text(k, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  String _statusLabel(WidgetRef ref) {
    final asyncStatus = ref.watch(syncStatusProvider);
    return asyncStatus.when(
      data: (s) {
        switch (s) {
          case SyncStatus.syncing:
            return 'يتم المزامنة';
          case SyncStatus.connected:
            return 'متصل';
          case SyncStatus.disconnected:
            return 'غير متصل';
          case SyncStatus.error:
            return 'خطأ';
          case SyncStatus.idle:
          default:
            return 'جاهز';
        }
      },
      loading: () => 'جار التحقق...',
      error: (_, __) => 'خطأ',
    );
  }

  String _fmtEpoch(int? ts) {
    if (ts == null || ts <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return dt.toIso8601String();
  }

  Widget _errorTile(OutboxData e) {
    final err = (e.lastError ?? '').trim();
    final errShort = err.length > 160 ? err.substring(0, 160) + '…' : err;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text('${e.entity} • ${e.op} • محاولات: ${e.attempts}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errShort),
            const SizedBox(height: 4),
            Text('uuid=${e.localUuid} • ${_fmtEpoch(e.clientTs)}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(OutboxData e) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.history, color: Colors.blueGrey),
        title: Text('${e.entity} • ${e.op}'),
        subtitle: Text('uuid=${e.localUuid} • ${_fmtEpoch(e.clientTs)}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
      ),
    );
  }

  Future<_DiagData> _loadData(AppDatabase db) async {
    final state = await (db.select(db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();

    final allOutbox = await db.select(db.outbox).get();
    final outboxCount = allOutbox.length;

    final errors = allOutbox
        .where((o) => (o.lastError ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) => b.clientTs.compareTo(a.clientTs));
    final recent = [...allOutbox]..sort((a, b) => b.clientTs.compareTo(a.clientTs));

    return _DiagData(
      syncState: state,
      outboxCount: outboxCount,
      outboxErrors: errors.take(20).toList(),
      outboxRecent: recent.take(20).toList(),
    );
  }
}

class _DiagData {
  final SyncStateData? syncState;
  final int outboxCount;
  final List<OutboxData> outboxErrors;
  final List<OutboxData> outboxRecent;
  _DiagData({required this.syncState, required this.outboxCount, required this.outboxErrors, required this.outboxRecent});
}
