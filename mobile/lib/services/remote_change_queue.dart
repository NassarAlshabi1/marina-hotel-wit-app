import 'dart:async';

enum RemoteOperation { create, update, delete, unknown }

class PendingRemoteRecord {
  const PendingRemoteRecord({
    required this.collectionId,
    required this.documentId,
    required this.operation,
    this.serverUpdatedAt,
    this.payload,
  });

  final String collectionId;
  final String documentId;
  final RemoteOperation operation;
  final DateTime? serverUpdatedAt;
  final Map<String, dynamic>? payload;

  String get key => '$collectionId/$documentId';

  PendingRemoteRecord merge(PendingRemoteRecord newer) {
    final newerTimestamp = newer.serverUpdatedAt;
    final currentTimestamp = serverUpdatedAt;
    return PendingRemoteRecord(
      collectionId: collectionId,
      documentId: documentId,
      operation: newer.operation,
      serverUpdatedAt: newerTimestamp ?? currentTimestamp,
      payload: newer.payload ?? payload,
    );
  }
}

typedef RemoteChangeBatchHandler =
    Future<void> Function(List<PendingRemoteRecord> changes);

/// In-memory coalescing queue for Appwrite Realtime record changes.
/// Multiple events in one burst are delivered as one coalesced batch.
class RemoteChangeQueue {
  RemoteChangeQueue({
    required this.onFlush,
    this.debounce = const Duration(milliseconds: 400),
  });

  final RemoteChangeBatchHandler onFlush;
  final Duration debounce;
  final Map<String, PendingRemoteRecord> _pending = {};
  Timer? _timer;
  bool _flushing = false;

  int get length => _pending.length;

  void add(PendingRemoteRecord change) {
    final previous = _pending[change.key];
    _pending[change.key] = previous == null ? change : previous.merge(change);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final batch = List<PendingRemoteRecord>.of(_pending.values);
        _pending.clear();
        try {
          await onFlush(batch);
        } catch (_) {
          // Keep the realtime listener alive. The next Delta recovery will
          // reconcile the coalesced batch if the trigger fails.
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
