import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import '../vector_clock.dart';

/// استراتيجية حل التضارب
enum ConflictStrategy { newerWins, devicePriority, manualResolve }

/// معلومات التضارب
class DataConflict {
  DataConflict({
    required this.table,
    required this.uuid,
    required this.localData,
    required this.remoteData,
    required this.localTimestamp,
    required this.remoteTimestamp,
    this.localVectorClock,
    this.remoteVectorClock,
  });
  final String table;
  final String uuid;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  final VectorClock? localVectorClock;
  final VectorClock? remoteVectorClock;

  bool get isLocalNewer => localTimestamp.isAfter(remoteTimestamp);

  @override
  String toString() =>
      'DataConflict($table/$uuid: local=${localTimestamp.toIso8601String()}, remote=${remoteTimestamp.toIso8601String()})';
}

/// محلل التضارب - مسؤول عن كشف وحل التضارب فقط
///
/// الاستخدام:
/// ```dart
/// final resolver = ConflictResolver(
///   deviceId: 'device-123',
///   strategy: ConflictStrategy.newerWins,
/// );
///
/// final conflicts = await resolver.detectConflicts(localData, remoteData);
/// final resolved = await resolver.resolveConflicts(conflicts);
/// ```
class ConflictResolver {
  ConflictResolver({
    required this.deviceId,
    this.strategy = ConflictStrategy.newerWins,
    this.devicePriority = 100,
  });

  final String deviceId;
  final ConflictStrategy strategy;
  final int devicePriority;

  /// كشف التضارب بين البيانات المحلية والبعيدة
  Future<List<DataConflict>> detectConflicts(
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) async {
    final conflicts = <DataConflict>[];

    for (final table in localData.keys) {
      if (!remoteData.containsKey(table)) continue;

      final localRecords = localData[table] as Map<String, dynamic>? ?? {};
      final remoteRecords = remoteData[table] as Map<String, dynamic>? ?? {};

      for (final uuid in localRecords.keys) {
        if (!remoteRecords.containsKey(uuid)) continue;

        final localRecord = localRecords[uuid] as Map<String, dynamic>;
        final remoteRecord = remoteRecords[uuid] as Map<String, dynamic>;

        final localUpdated = _parseTimestamp(localRecord['updated_at']);
        final remoteUpdated = _parseTimestamp(remoteRecord['updated_at']);

        if (localUpdated != null && remoteUpdated != null) {
          final localVc = VectorClock.fromJson(localRecord['vector_clock'] as String? ?? '{}');
          final remoteVc = VectorClock.fromJson(remoteRecord['vector_clock'] as String? ?? '{}');

          if (_hasConflict(
            localRecord,
            remoteRecord,
            localUpdated,
            remoteUpdated,
            localVc,
            remoteVc,
          )) {
            conflicts.add(
              DataConflict(
                table: table,
                uuid: uuid,
                localData: localRecord,
                remoteData: remoteRecord,
                localTimestamp: localUpdated,
                remoteTimestamp: remoteUpdated,
              ),
            );
          }
        }
      }
    }

    debugPrint('🔍 ConflictResolver: اكتشف ${conflicts.length} تضارب');
    return conflicts;
  }

  /// التحقق من وجود تضارب
  ///
  /// يستخدم مقارنة عميقة (deep comparison) لضمان دقة اكتشاف التضاربات.
  /// أي اختلاف في المحتوى يُعتبر تضارباً محتملاً.
  /// الاستراتيجية المحددة (مثل newerWins) ستحدد الفائز بناءً على التوقيت.
  bool _hasConflict(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    DateTime localTs,
    DateTime remoteTs,
    VectorClock localVc,
    VectorClock remoteVc,
  ) {
        if (localVc.isConcurrent(remoteVc)) {
      return true; // True concurrent conflict detected by vector clocks
    }
    return !const DeepCollectionEquality().equals(local, remote);
  }

  /// حل التضارب حسب الاستراتيجية المختارة
  Future<Map<String, Map<String, dynamic>>> resolveConflicts(
    List<DataConflict> conflicts,
  ) async {
    final resolved = <String, Map<String, dynamic>>{};

    for (final conflict in conflicts) {
      final winner = _selectWinner(conflict);

      if (!resolved.containsKey(conflict.table)) {
        resolved[conflict.table] = {};
      }
      resolved[conflict.table]![conflict.uuid] = winner;

      final winnerType = winner == conflict.localData ? 'محلي' : 'بعيد';
      debugPrint(
        '✅ ConflictResolver: حُل تضارب ${conflict.table}/${conflict.uuid} - الفائز: $winnerType',
      );
    }

    return resolved;
  }

  /// اختيار البيانات الفائزة حسب الاستراتيجية
  Map<String, dynamic> _selectWinner(DataConflict conflict) {
    // Prioritize vector clock comparison for newerWins and devicePriority
    if (conflict.localVectorClock != null && conflict.remoteVectorClock != null) {
      final comparison = conflict.localVectorClock!.compare(conflict.remoteVectorClock!);
      switch (comparison) {
        case 'after':
          return conflict.localData; // Local is causally newer
        case 'before':
          return conflict.remoteData; // Remote is causally newer
        case 'concurrent':
          debugPrint('⚠️ Concurrent update detected, falling back to strategy for ${conflict.table}/${conflict.uuid}');
          // Fallback to strategy if concurrent, or introduce manual resolve
          // Fallthrough to strategy
        case 'equal':
          return conflict.localData; // They are the same, local wins by default
      }
    }

    switch (strategy) {
      case ConflictStrategy.newerWins:
        return conflict.isLocalNewer ? conflict.localData : conflict.remoteData;

      case ConflictStrategy.devicePriority:
        // ignore: unused_local_variable
        final remoteDevice = conflict.remoteData['device_id'] as String?;
        final remotePriority =
            conflict.remoteData['device_priority'] as int? ?? 100;

        if (devicePriority >= remotePriority) {
          return conflict.localData;
        } else {
          return conflict.remoteData;
        }

      case ConflictStrategy.manualResolve:
        return conflict.isLocalNewer ? conflict.localData : conflict.remoteData;
    }
  }

  /// تحويل timestamp إلى DateTime
  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;

    try {
      if (timestamp is String) {
        return DateTime.parse(timestamp);
      } else if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      debugPrint('⚠️ ConflictResolver: فشل تحليل timestamp: $e');
    }

    return null;
  }

  /// تغيير الاستراتيجية ديناميكياً
  ConflictResolver copyWith({ConflictStrategy? strategy, int? devicePriority}) {
    return ConflictResolver(
      deviceId: deviceId,
      strategy: strategy ?? this.strategy,
      devicePriority: devicePriority ?? this.devicePriority,
    );
  }
}
