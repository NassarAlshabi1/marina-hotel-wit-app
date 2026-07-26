/// حالة المزامنة
enum SyncStatus { idle, syncing, success, failed, partial }

enum SyncQueueStatus {
  pending('pending'),
  synced('synced'),
  failed('failed');

  const SyncQueueStatus(this.value);
  final String value;

  static SyncQueueStatus fromString(String value) {
    return SyncQueueStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncQueueStatus.pending,
    );
  }
}

enum DeviceStatus {
  active('active'),
  inactive('inactive'),
  suspended('suspended');

  const DeviceStatus(this.value);
  final String value;

  static DeviceStatus fromString(String value) {
    return DeviceStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DeviceStatus.active,
    );
  }
}

enum SyncLogStatus {
  success('success'),
  failed('failed'),
  inProgress('in_progress'),
  completed('completed');

  const SyncLogStatus(this.value);
  final String value;

  static SyncLogStatus fromString(String value) {
    return SyncLogStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncLogStatus.success,
    );
  }
}

enum SyncOperationType {
  insert('insert'),
  update('update'),
  delete('delete'),
  upsert('upsert');

  const SyncOperationType(this.value);
  final String value;

  static SyncOperationType fromString(String value) {
    return SyncOperationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncOperationType.upsert,
    );
  }
}
