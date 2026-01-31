import '../events/sync_event.dart';

enum SyncTargetType { appwrite, googleDrive, localJson }

sealed class SyncTargetResult {
  bool get success;
  String? get error;
  int get affectedCount;
  Duration get duration;
}

class SyncPushResult implements SyncTargetResult {
  @override
  final bool success;
  @override
  final String? error;
  @override
  final int affectedCount;
  @override
  final Duration duration;
  final List<String> syncedIds;
  final List<String> failedIds;
  final Map<String, String>? idMappings;

  const SyncPushResult({
    required this.success,
    this.error,
    this.affectedCount = 0,
    this.duration = Duration.zero,
    this.syncedIds = const [],
    this.failedIds = const [],
    this.idMappings,
  });

  factory SyncPushResult.success({
    int affectedCount = 0,
    Duration duration = Duration.zero,
    List<String> syncedIds = const [],
    Map<String, String>? idMappings,
  }) {
    return SyncPushResult(
      success: true,
      affectedCount: affectedCount,
      duration: duration,
      syncedIds: syncedIds,
      idMappings: idMappings,
    );
  }

  factory SyncPushResult.failure({
    required String error,
    Duration duration = Duration.zero,
    List<String> failedIds = const [],
  }) {
    return SyncPushResult(
      success: false,
      error: error,
      duration: duration,
      failedIds: failedIds,
    );
  }

  factory SyncPushResult.partial({
    required List<String> syncedIds,
    required List<String> failedIds,
    String? error,
    Duration duration = Duration.zero,
  }) {
    return SyncPushResult(
      success: failedIds.isEmpty,
      error: error,
      affectedCount: syncedIds.length,
      duration: duration,
      syncedIds: syncedIds,
      failedIds: failedIds,
    );
  }
}

class SyncPullResult implements SyncTargetResult {
  @override
  final bool success;
  @override
  final String? error;
  @override
  final int affectedCount;
  @override
  final Duration duration;
  final int created;
  final int updated;
  final int deleted;
  final List<SyncConflict> conflicts;
  final DateTime? lastSyncTimestamp;

  const SyncPullResult({
    required this.success,
    this.error,
    this.affectedCount = 0,
    this.duration = Duration.zero,
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.conflicts = const [],
    this.lastSyncTimestamp,
  });

  factory SyncPullResult.success({
    int created = 0,
    int updated = 0,
    int deleted = 0,
    Duration duration = Duration.zero,
    List<SyncConflict> conflicts = const [],
    DateTime? lastSyncTimestamp,
  }) {
    return SyncPullResult(
      success: true,
      affectedCount: created + updated + deleted,
      duration: duration,
      created: created,
      updated: updated,
      deleted: deleted,
      conflicts: conflicts,
      lastSyncTimestamp: lastSyncTimestamp,
    );
  }

  factory SyncPullResult.failure({
    required String error,
    Duration duration = Duration.zero,
  }) {
    return SyncPullResult(success: false, error: error, duration: duration);
  }

  bool get hasConflicts => conflicts.isNotEmpty;
}

class SyncConflict {
  final String entityId;
  final String table;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  final ConflictResolution? resolution;

  const SyncConflict({
    required this.entityId,
    required this.table,
    required this.localData,
    required this.remoteData,
    required this.localTimestamp,
    required this.remoteTimestamp,
    this.resolution,
  });

  SyncConflict withResolution(ConflictResolution resolution) {
    return SyncConflict(
      entityId: entityId,
      table: table,
      localData: localData,
      remoteData: remoteData,
      localTimestamp: localTimestamp,
      remoteTimestamp: remoteTimestamp,
      resolution: resolution,
    );
  }

  bool get isNewerLocally => localTimestamp.isAfter(remoteTimestamp);
  bool get isNewerRemotely => remoteTimestamp.isAfter(localTimestamp);
}

enum ConflictResolution { useLocal, useRemote, merge, skip }

class SyncTargetStatus {
  final SyncTargetType type;
  final bool isAvailable;
  final bool isEnabled;
  final bool isConnected;
  final DateTime? lastSyncAt;
  final DateTime? lastErrorAt;
  final String? lastError;
  final int pendingCount;
  final Map<String, dynamic>? metadata;

  const SyncTargetStatus({
    required this.type,
    required this.isAvailable,
    required this.isEnabled,
    required this.isConnected,
    this.lastSyncAt,
    this.lastErrorAt,
    this.lastError,
    this.pendingCount = 0,
    this.metadata,
  });

  bool get isReady => isAvailable && isEnabled && isConnected;
}

abstract class SyncTargetAdapter {
  SyncTargetType get type;
  String get name;
  String get displayName;

  bool get isAvailable;
  bool get isEnabled;
  bool get isInitialized;

  Future<void> initialize();

  Future<bool> checkConnection();

  Future<SyncTargetStatus> getStatus();

  Future<SyncPushResult> push(List<EnhancedSyncEvent> events);

  Future<SyncPushResult> pushSingle(EnhancedSyncEvent event) async {
    return push([event]);
  }

  Future<SyncPullResult> pull({
    DateTime? since,
    List<String>? tables,
    int? limit,
  });

  Future<SyncPullResult> pullTable(String table, {DateTime? since}) {
    return pull(since: since, tables: [table]);
  }

  Future<void> setEnabled(bool enabled);

  Future<void> reset();

  Future<void> dispose();
}

abstract class BackupCapableAdapter extends SyncTargetAdapter {
  Future<String> createBackup({String? tag});

  Future<void> restoreFromBackup(String backupId);

  Future<List<BackupInfo>> listBackups({int? limit});

  Future<void> deleteBackup(String backupId);
}

class BackupInfo {
  final String id;
  final DateTime createdAt;
  final int sizeBytes;
  final String? tag;
  final Map<String, int>? tableCounts;
  final String? checksum;

  const BackupInfo({
    required this.id,
    required this.createdAt,
    required this.sizeBytes,
    this.tag,
    this.tableCounts,
    this.checksum,
  });
}

class AdapterConfig {
  final Duration connectionTimeout;
  final Duration requestTimeout;
  final int maxRetries;
  final Duration retryDelay;
  final int batchSize;
  final bool enableCompression;
  final bool enableEncryption;

  const AdapterConfig({
    this.connectionTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.batchSize = 50,
    this.enableCompression = true,
    this.enableEncryption = false,
  });
}
