import 'dart:async';

class SyncEvent {
  SyncEvent({
    required this.table,
    required this.operation,
    this.count = 1,
    this.source = 'local',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String? table;
  final String? operation;
  final int count;
  final String source;
  final DateTime timestamp;
}

class SyncEventBus {
  SyncEventBus._();

  static final SyncEventBus instance = SyncEventBus._();

  final StreamController<SyncEvent> _controller =
      StreamController<SyncEvent>.broadcast();

  Stream<SyncEvent> get stream => _controller.stream;

  void publish(SyncEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
