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

typedef RemoteChangeHandler = Future<void> Function(PendingRemoteRecord change);

/// In-memory coalescing queue for realtime/FCM record changes.
/// Multiple events for one record result in one handler invocation.
class RemoteChangeQueue {
  RemoteChangeQueue({
    required this.onFlush,
    this.debounce = const Duration(milliseconds: 400),
  });

  final RemoteChangeHandler onFlush;
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
        for (final change in batch) {
          try {
            await onFlush(change);
          } catch (_) {
            // Keep the realtime listener alive. Recovery delta will reconcile
            // a record whose targeted application failed.
          }
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
