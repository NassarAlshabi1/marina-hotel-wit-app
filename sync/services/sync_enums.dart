enum SyncQueueStatus {
  pending('pending'),
  synced('synced'),
  failed('failed');

  final String value;
  const SyncQueueStatus(this.value);

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

  final String value;
  const DeviceStatus(this.value);

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

  final String value;
  const SyncLogStatus(this.value);

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

  final String value;
  const SyncOperationType(this.value);

  static SyncOperationType fromString(String value) {
    return SyncOperationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncOperationType.upsert,
    );
  }
}
