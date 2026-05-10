/// نماذج بيانات المزامنة الاحترافية
/// Delta Sync + Vector Clock + Event Sourcing

/// اتجاه المزامنة
enum SyncDirection { upload, download, bidirectional }

/// نوع عملية المزامنة
enum SyncOperation { create, update, delete }

/// حالة سجل المزامنة
enum SyncStatus { pending, syncing, synced, failed, conflict }

/// أنواع أحداث المزامنة
enum SyncEventType {
  localChange,
  remoteChange,
  syncStarted,
  syncCompleted,
  syncFailed,
  conflictDetected,
  conflictResolved,
  applied,
}

/// استراتيجية حل التعارض
enum ConflictStrategy {
  newerWins,
  devicePriority,
  manualResolve,
  smartMerge,
  lastWriterWins,
}

/// حالة الاتصال بالمزامنة
enum SyncConnectionState { disconnected, connecting, connected, syncing, error }

/// نتيجة مقارنة Vector Clock
enum VectorClockComparison { localNewer, remoteNewer, concurrent, equal }

/// تغيير دلتا (Delta Change)
class DeltaChange {

  DeltaChange({
    required this.id,
    required this.table,
    required this.uuid,
    required this.operation,
    required this.payload,
    required this.timestamp,
    required this.vectorClock,
    this.checksum,
    this.deviceId,
    this.retryCount = 0,
    this.lastError,
    this.nextRetryAt,
  });

  factory DeltaChange.fromJson(Map<String, dynamic> json) => DeltaChange(
        id: json['id'] as String,
        table: json['table'] as String,
        uuid: json['uuid'] as String,
        operation: SyncOperation.values.firstWhere(
          (e) => e.name == json['operation'],
          orElse: () => SyncOperation.update,
        ),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        timestamp: DateTime.parse(json['timestamp'] as String),
        vectorClock: json['vectorClock'] as String,
        checksum: json['checksum'] as String?,
        deviceId: json['deviceId'] as String?,
        retryCount: json['retryCount'] as int? ?? 0,
        lastError: json['lastError'] as String?,
        nextRetryAt: json['nextRetryAt'] != null
            ? DateTime.parse(json['nextRetryAt'] as String)
            : null,
      );
  final String id;
  final String table;
  final String uuid;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String vectorClock;
  final String? checksum;
  final String? deviceId;
  final int retryCount;
  final String? lastError;
  final DateTime? nextRetryAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'uuid': uuid,
        'operation': operation.name,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        'vectorClock': vectorClock,
        'checksum': checksum,
        'deviceId': deviceId,
        'retryCount': retryCount,
        'lastError': lastError,
        'nextRetryAt': nextRetryAt?.toIso8601String(),
      };
}

/// نتيجة مزامنة دلتا
class DeltaSyncResult {

  DeltaSyncResult({
    this.success = true,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.conflictCount = 0,
    this.errorCount = 0,
    this.conflicts = const [],
    this.errors = const [],
    this.timestamp,
  });
  final bool success;
  final int uploadedCount;
  final int downloadedCount;
  final int conflictCount;
  final int errorCount;
  final List<SyncConflict> conflicts;
  final List<String> errors;
  final DateTime? timestamp;

  DeltaSyncResult copyWith({
    bool? success,
    int? uploadedCount,
    int? downloadedCount,
    int? conflictCount,
    int? errorCount,
    List<SyncConflict>? conflicts,
    List<String>? errors,
    DateTime? timestamp,
  }) {
    return DeltaSyncResult(
      success: success ?? this.success,
      uploadedCount: uploadedCount ?? this.uploadedCount,
      downloadedCount: downloadedCount ?? this.downloadedCount,
      conflictCount: conflictCount ?? this.conflictCount,
      errorCount: errorCount ?? this.errorCount,
      conflicts: conflicts ?? this.conflicts,
      errors: errors ?? this.errors,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'uploadedCount': uploadedCount,
        'downloadedCount': downloadedCount,
        'conflictCount': conflictCount,
        'errorCount': errorCount,
        'conflicts': conflicts.map((c) => c.toJson()).toList(),
        'errors': errors,
        'timestamp': timestamp?.toIso8601String(),
      };
}

/// تعارض مزامنة
class SyncConflict {

  SyncConflict({
    required this.id,
    required this.table,
    required this.uuid,
    required this.remoteChange,
    required this.localRecord,
    required this.detectedAt,
    this.resolution,
    this.resolvedBy,
    this.resolvedAt,
  });

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
        id: json['id'] as String,
        table: json['table'] as String,
        uuid: json['uuid'] as String,
        remoteChange: DeltaChange.fromJson(
            Map<String, dynamic>.from(json['remoteChange'] as Map),),
        localRecord: Map<String, dynamic>.from(json['localRecord'] as Map),
        detectedAt: DateTime.parse(json['detectedAt'] as String),
        resolution: json['resolution'] != null
            ? ConflictResolution.values.firstWhere(
                (e) => e.name == json['resolution'],
                orElse: () => ConflictResolution.manual,
              )
            : null,
        resolvedBy: json['resolvedBy'] as String?,
        resolvedAt: json['resolvedAt'] != null
            ? DateTime.parse(json['resolvedAt'] as String)
            : null,
      );
  final String id;
  final String table;
  final String uuid;
  final DeltaChange remoteChange;
  final Map<String, dynamic> localRecord;
  final DateTime detectedAt;
  final ConflictResolution? resolution;
  final String? resolvedBy;
  final DateTime? resolvedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'uuid': uuid,
        'remoteChange': remoteChange.toJson(),
        'localRecord': localRecord,
        'detectedAt': detectedAt.toIso8601String(),
        'resolution': resolution?.name,
        'resolvedBy': resolvedBy,
        'resolvedAt': resolvedAt?.toIso8601String(),
      };
}

/// حل التعارض
enum ConflictResolution { localWins, remoteWins, merged, manual, discarded }

/// نتيجة حل التعارض
class ConflictResolutionResult {

  ConflictResolutionResult({
    required this.winner,
    required this.data,
    this.requiresReview = false,
  });
  final Winner winner;
  final Map<String, dynamic> data;
  final bool requiresReview;
}

/// الفائز في التعارض
enum Winner { local, remote, merged }

/// إعدادات المزامنة
class SyncConfiguration {

  const SyncConfiguration({
    this.enabled = true,
    this.defaultDirection = SyncDirection.bidirectional,
    this.batchSize = 50,
    this.autoSyncInterval = const Duration(minutes: 15),
    this.backgroundSyncEnabled = true,
    this.realtimeSyncEnabled = true,
    this.maxRetries = 3,
    this.conflictStrategy = ConflictStrategy.newerWins,
    this.requireWifi = false,
    this.requireCharging = false,
  });
  final bool enabled;
  final SyncDirection defaultDirection;
  final int batchSize;
  final Duration autoSyncInterval;
  final bool backgroundSyncEnabled;
  final bool realtimeSyncEnabled;
  final int maxRetries;
  final ConflictStrategy conflictStrategy;
  final bool requireWifi;
  final bool requireCharging;

  SyncConfiguration copyWith({
    bool? enabled,
    SyncDirection? defaultDirection,
    int? batchSize,
    Duration? autoSyncInterval,
    bool? backgroundSyncEnabled,
    bool? realtimeSyncEnabled,
    int? maxRetries,
    ConflictStrategy? conflictStrategy,
    bool? requireWifi,
    bool? requireCharging,
  }) {
    return SyncConfiguration(
      enabled: enabled ?? this.enabled,
      defaultDirection: defaultDirection ?? this.defaultDirection,
      batchSize: batchSize ?? this.batchSize,
      autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
      backgroundSyncEnabled: backgroundSyncEnabled ?? this.backgroundSyncEnabled,
      realtimeSyncEnabled: realtimeSyncEnabled ?? this.realtimeSyncEnabled,
      maxRetries: maxRetries ?? this.maxRetries,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
      requireWifi: requireWifi ?? this.requireWifi,
      requireCharging: requireCharging ?? this.requireCharging,
    );
  }
}

/// إحصائيات المزامنة
class SyncStats {

  SyncStats({
    required this.lastSyncAt,
    required this.totalSynced,
    required this.totalConflicts,
    required this.totalErrors,
    required this.averageSyncTime,
    this.byTable = const {},
  });
  final DateTime lastSyncAt;
  final int totalSynced;
  final int totalConflicts;
  final int totalErrors;
  final Duration averageSyncTime;
  final Map<String, int> byTable;

  Map<String, dynamic> toJson() => {
        'lastSyncAt': lastSyncAt.toIso8601String(),
        'totalSynced': totalSynced,
        'totalConflicts': totalConflicts,
        'totalErrors': totalErrors,
        'averageSyncTimeMs': averageSyncTime.inMilliseconds,
        'byTable': byTable,
      };
}

/// معلومات الجهاز للمزامنة
class SyncDeviceInfo {

  SyncDeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    this.priority = 100,
    this.lastSeen,
    this.appVersion,
  });
  final String id;
  final String name;
  final String platform;
  final int priority;
  final DateTime? lastSeen;
  final String? appVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'priority': priority,
        'lastSeen': lastSeen?.toIso8601String(),
        'appVersion': appVersion,
      };
}

/// حدث مزامنة
class SyncEvent {

  SyncEvent({
    required this.id,
    required this.type,
    this.table,
    this.uuid,
    this.operation,
    this.payload,
    this.timestamp,
  });
  final String id;
  final SyncEventType type;
  final String? table;
  final String? uuid;
  final String? operation;
  final Map<String, dynamic>? payload;
  final DateTime? timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'table': table,
        'uuid': uuid,
        'operation': operation,
        'payload': payload,
        'timestamp': timestamp?.toIso8601String(),
      };
}

/// نتيجة تطبيق تغيير
class ApplyResult {

  ApplyResult({
    this.successCount = 0,
    this.failCount = 0,
    this.conflicts = const [],
    this.errors = const [],
  });
  final int successCount;
  final int failCount;
  final List<SyncConflict> conflicts;
  final List<String> errors;

  ApplyResult copyWith({
    int? successCount,
    int? failCount,
    List<SyncConflict>? conflicts,
    List<String>? errors,
  }) {
    return ApplyResult(
      successCount: successCount ?? this.successCount,
      failCount: failCount ?? this.failCount,
      conflicts: conflicts ?? this.conflicts,
      errors: errors ?? this.errors,
    );
  }
}
