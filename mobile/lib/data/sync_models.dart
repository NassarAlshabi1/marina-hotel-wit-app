import 'dart:convert';

/// حالة المزامنة الحالية لبث التحديثات إلى الواجهة
class SyncStatus {
  SyncStatus({
    required this.phase,
    required this.message,
    this.progress,
    this.error,
  });

  final SyncPhase phase;
  final String message;
  final double? progress;
  final Object? error;

  SyncStatus copyWith({
    SyncPhase? phase,
    String? message,
    double? progress,
    Object? error,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}

/// المراحل العامة لدورة المزامنة
enum SyncPhase { idle, preparing, pushing, pulling, merging, completing, error }

/// بيانات التعريف المرافقة للملف الرئيسي في Google Drive
class SyncMetadata {
  SyncMetadata({
    required this.version,
    required this.lastUpdatedAt,
    required this.devicePriority,
    required this.snapshotSize,
    required this.lastSyncId,
    required this.checksum,
    required this.lastDeviceId,
  });

  final int version;
  final String lastUpdatedAt;
  final int devicePriority;
  final int snapshotSize;
  final String lastSyncId;
  final String checksum;
  final String lastDeviceId;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'lastUpdatedAt': lastUpdatedAt,
      'devicePriority': devicePriority,
      'snapshotSize': snapshotSize,
      'lastSyncId': lastSyncId,
      'checksum': checksum,
      'lastDeviceId': lastDeviceId,
    };
  }

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    return SyncMetadata(
      version: json['version'] as int? ?? 1,
      lastUpdatedAt: json['lastUpdatedAt'] as String? ?? '',
      devicePriority: json['devicePriority'] as int? ?? 0,
      snapshotSize: json['snapshotSize'] as int? ?? 0,
      lastSyncId: json['lastSyncId'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
      lastDeviceId: json['lastDeviceId'] as String? ?? '',
    );
  }
}

/// حاوية اللقطة الكاملة لجميع الجداول
class SyncSnapshot {
  SyncSnapshot({required this.metadata, required this.tables});

  final SyncMetadata metadata;
  final Map<String, List<Map<String, dynamic>>> tables;

  Map<String, dynamic> toJson() {
    return {'metadata': metadata.toJson(), 'tables': tables};
  }

  factory SyncSnapshot.fromJson(Map<String, dynamic> json) {
    final rawTables = json['tables'] as Map<String, dynamic>? ?? {};
    final parsedTables = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawTables.entries) {
      final list = (entry.value as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      parsedTables[entry.key] = list;
    }
    final metadataSource = json['metadata'];
    final metadataJson = metadataSource is Map
        ? Map<String, dynamic>.from(metadataSource)
        : <String, dynamic>{};
    return SyncSnapshot(
      metadata: SyncMetadata.fromJson(metadataJson),
      tables: parsedTables,
    );
  }
}

/// عنصر من طابور التغييرات المحلي
class SyncQueueEntry {
  SyncQueueEntry({
    required this.id,
    required this.uuid,
    required this.tableName,
    required this.operation,
    required this.payload,
    required this.updatedAt,
    required this.deviceId,
    required this.status,
  });

  final int id;
  final String uuid;
  final String tableName;
  final String operation;
  final Map<String, dynamic> payload;
  final String updatedAt;
  final String deviceId;
  final String status;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'tableName': tableName,
      'operation': operation,
      'payload': payload,
      'updatedAt': updatedAt,
      'deviceId': deviceId,
      'status': status,
    };
  }

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    return SyncQueueEntry(
      id: json['id'] as int? ?? 0,
      uuid: json['uuid'] as String? ?? '',
      tableName: json['tableName'] as String? ?? '',
      operation: json['operation'] as String? ?? 'update',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      updatedAt: json['updatedAt'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
    );
  }
}

/// نتيجة الدمج تحتوي على النسخة المحدثة وقائمة العمليات المطبقة
class SyncMergeResult {
  SyncMergeResult({
    required this.mergedSnapshot,
    required this.appliedOperations,
    required this.conflicts,
  });

  final SyncSnapshot mergedSnapshot;
  final List<SyncOperation> appliedOperations;
  final List<SyncConflictModel> conflicts;
}

/// عملية تمت أثناء الدمج (إدراج/تحديث/حذف)
class SyncOperation {
  SyncOperation({
    required this.table,
    required this.uuid,
    required this.operation,
    required this.payload,
    required this.timestamp,
  });

  final String table;
  final String uuid;
  final String operation;
  final Map<String, dynamic> payload;
  final String timestamp;
}

/// سجل تضارب تم اكتشافه أثناء الدمج
class SyncConflictModel {
  SyncConflictModel({
    required this.table,
    required this.uuid,
    required this.localPayload,
    required this.remotePayload,
    required this.resolution,
  });

  final String table;
  final String uuid;
  final Map<String, dynamic> localPayload;
  final Map<String, dynamic> remotePayload;
  final String resolution;

  Map<String, dynamic> toJson() {
    return {
      'table': table,
      'uuid': uuid,
      'localPayload': localPayload,
      'remotePayload': remotePayload,
      'resolution': resolution,
    };
  }
}

/// أداة مساعدة لحساب تجزئة ثابتة لأي JSON
class SyncChecksum {
  SyncChecksum._();

  static String compute(Map<String, dynamic> data) {
    final normalized = _normalize(data);
    return base64Url.encode(utf8.encode(jsonEncode(normalized)));
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> input) {
    final sortedKeys = input.keys.toList()..sort();
    final result = <String, dynamic>{};
    for (final key in sortedKeys) {
      final value = input[key];
      if (value is Map<String, dynamic>) {
        result[key] = _normalize(value);
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _normalize(item);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    }
    return result;
  }
}

/// نتيجة عملية المزامنة مع تفاصيل النجاح والفشل
class SyncResult {
  SyncResult({
    required this.success,
    this.syncedCount = 0,
    this.failedCount = 0,
    this.failedItems = const [],
    this.errorMessage,
  });

  final bool success;
  final int syncedCount;
  final int failedCount;
  final List<dynamic> failedItems;
  final String? errorMessage;

  bool get hasPartialFailure => !success && syncedCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'syncedCount': syncedCount,
      'failedCount': failedCount,
      'failedItems': failedItems,
      'hasPartialFailure': hasPartialFailure,
      'errorMessage': errorMessage,
    };
  }
}

/// نتيجة التحقق من صحة Mirror
class MirrorValidationResult {
  MirrorValidationResult({
    required this.isValid,
    required this.issues,
    required this.validatedAt,
  });

  final bool isValid;
  final List<String> issues;
  final DateTime validatedAt;

  Map<String, dynamic> toJson() {
    return {
      'isValid': isValid,
      'issuesCount': issues.length,
      'issues': issues,
      'validatedAt': validatedAt.toIso8601String(),
    };
  }
}
