import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_logs.dart';
import '../utils/time.dart';
import 'google_drive_logger.dart';
import 'hybrid_logical_clock.dart';
import 'logging/log_models.dart';
import 'vector_clock.dart';

enum ConflictResolutionStrategy {
  newerWins,
  localWins,
  remoteWins,
  devicePriorityBased,
  manualReview,
}

class ConflictDetails {
  final String tableName;
  final String localUuid;
  final Map<String, dynamic> localRecord;
  final Map<String, dynamic> remoteRecord;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  final int localVersion;
  final int remoteVersion;
  final String? localDeviceId;
  final String? remoteDeviceId;
  final HybridLogicalClock? localHlc;
  final HybridLogicalClock? remoteHlc;
  final VectorClock? localVc;
  final VectorClock? remoteVc;
  
  const ConflictDetails({
    required this.tableName,
    required this.localUuid,
    required this.localRecord,
    required this.remoteRecord,
    required this.localTimestamp,
    required this.remoteTimestamp,
    required this.localVersion,
    required this.remoteVersion,
    this.localDeviceId,
    this.remoteDeviceId,
    this.localHlc,
    this.remoteHlc,
    this.localVc,
    this.remoteVc,
  });
  
  bool get isLocalNewer => localTimestamp.isAfter(remoteTimestamp);
  bool get isRemoteNewer => remoteTimestamp.isAfter(localTimestamp);
  bool get isSameTimestamp => localTimestamp == remoteTimestamp;
  bool get isLocalVersionHigher => localVersion > remoteVersion;
  bool get isRemoteVersionHigher => remoteVersion > localVersion;
  
  Duration get timeDifference => localTimestamp.difference(remoteTimestamp).abs();
  
  @override
  String toString() {
    return 'Conflict[$tableName/$localUuid] '
           'Local(v$localVersion@${localTimestamp.toIso8601String()}) '
           'vs Remote(v$remoteVersion@${remoteTimestamp.toIso8601String()})';
  }
}

class ConflictResolutionResult {
  final bool resolved;
  final Map<String, dynamic>? selectedRecord;
  final String? reason;
  final bool requiresManualReview;
  
  const ConflictResolutionResult({
    required this.resolved,
    this.selectedRecord,
    this.reason,
    this.requiresManualReview = false,
  });
  
  factory ConflictResolutionResult.selectLocal(Map<String, dynamic> record, String reason) {
    return ConflictResolutionResult(
      resolved: true,
      selectedRecord: record,
      reason: 'Local selected: $reason',
    );
  }
  
  factory ConflictResolutionResult.selectRemote(Map<String, dynamic> record, String reason) {
    return ConflictResolutionResult(
      resolved: true,
      selectedRecord: record,
      reason: 'Remote selected: $reason',
    );
  }
  
  factory ConflictResolutionResult.needsManualReview(String reason) {
    return ConflictResolutionResult(
      resolved: false,
      requiresManualReview: true,
      reason: reason,
    );
  }
}

class GoogleDriveConflictResolver {
  GoogleDriveConflictResolver._();
  static final instance = GoogleDriveConflictResolver._();
  
  GoogleDriveLogger? _logger;
  
  static const String _prefsStrategyKey = 'gd_conflict_strategy';
  static const String _prefsDevicePriorityKey = 'gd_device_priority';
  static const String _prefsThresholdSecondsKey = 'gd_conflict_threshold_seconds';
  
  static const int _defaultConflictThresholdSeconds = 30;

  void _log(String message, {LogLevel level = LogLevel.info}) {
    DebugLogs.add('ConflictResolver', message);
    debugPrint('[ConflictResolver] $message');
    _logger?.log(message, level: level, tag: 'CONFLICT');
  }

  void initialize(GoogleDriveLogger? logger) {
    _logger = logger;
    _log('✅ Conflict Resolver initialized with Advanced Clocks (HLC/VC)');
  }

  Future<void> setStrategy(ConflictResolutionStrategy strategy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsStrategyKey, strategy.name);
    _log('🔧 Conflict strategy set to: ${strategy.name}');
  }

  Future<ConflictResolutionStrategy> getStrategy() async {
    final prefs = await SharedPreferences.getInstance();
    final strategyName = prefs.getString(_prefsStrategyKey) ?? ConflictResolutionStrategy.newerWins.name;
    
    return ConflictResolutionStrategy.values.firstWhere(
      (s) => s.name == strategyName,
      orElse: () => ConflictResolutionStrategy.newerWins,
    );
  }

  Future<void> setDevicePriority(int priority) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDevicePriorityKey, priority);
    _log('📱 Device priority set to: $priority');
  }

  Future<int> getDevicePriority() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsDevicePriorityKey) ?? 100;
  }

  Future<void> setConflictThreshold(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsThresholdSecondsKey, seconds);
    _log('⏱️ Conflict threshold set to: $seconds seconds');
  }

  Future<int> getConflictThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsThresholdSecondsKey) ?? _defaultConflictThresholdSeconds;
  }

  Future<List<ConflictDetails>> detectConflicts({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    List<String>? tablesToCheck,
  }) async {
    final conflicts = <ConflictDetails>[];
    final threshold = await getConflictThreshold();
    
    final tables = tablesToCheck ?? [
      'bookings', 
      'payments', 
      'expenses', 
      'rooms',
      'debts',
      'employees',
    ];
    
    for (final tableName in tables) {
      final localRecords = _getRecordsMap(localData[tableName]);
      final remoteRecords = _getRecordsMap(remoteData[tableName]);
      
      for (final localUuid in localRecords.keys) {
        if (remoteRecords.containsKey(localUuid)) {
          final localRecord = localRecords[localUuid]!;
          final remoteRecord = remoteRecords[localUuid]!;
          
          bool isConflict = false;
          
          // 1. Try Vector Clock comparison (Causality)
          final localVc = _extractVectorClock(localRecord);
          final remoteVc = _extractVectorClock(remoteRecord);
          
          if (localVc != null && remoteVc != null) {
            if (localVc.happensBefore(remoteVc)) {
              // Remote is newer, no conflict (Remote should just win)
              // Currently we treat this as no conflict here, but resolution might needed
              isConflict = false; 
            } else if (remoteVc.happensBefore(localVc)) {
              // Local is newer, no conflict
              isConflict = false;
            } else if (localVc.isConcurrent(remoteVc)) {
              isConflict = true;
              _log('⚔️ Vector Clock detected concurrent modification for $tableName/$localUuid');
            }
          } else {
            // 2. Fallback to HLC
            final localHlc = _extractHybridLogicalClock(localRecord);
            final remoteHlc = _extractHybridLogicalClock(remoteRecord);
            
            if (localHlc != null && remoteHlc != null) {
               // HLC also imposes total ordering
               // If timestamps are close but logical counters differ...
               // For HLC, if physical parts differ by > threshold, it's a conflict
               // Otherwise we might assume one happened before other.
               // However, simple HLC comparison resolves "who is newer", but doesn't strictly detect "concurrency" 
               // without vector clocks. We treat it similar to timestamps but more precise.
               final timeDiff = (localHlc.physicalTime - remoteHlc.physicalTime).abs() / 1000.0;
               if (timeDiff > threshold) {
                 isConflict = true;
               }
            } else {
              // 3. Fallback to Physical Time
              final localTs = _extractTimestamp(localRecord);
              final remoteTs = _extractTimestamp(remoteRecord);
              
              if (localTs == null || remoteTs == null) continue;
              
              final timeDiff = localTs.difference(remoteTs).inSeconds.abs();
              if (timeDiff > threshold) {
                isConflict = true;
              }
            }
          }
          
          // Force resolving if strict version mismatch?
          // Existing logic relied on big time diff.
          
          if (isConflict) {
            final conflict = ConflictDetails(
              tableName: tableName,
              localUuid: localUuid,
              localRecord: localRecord,
              remoteRecord: remoteRecord,
              localTimestamp: _extractTimestamp(localRecord) ?? DateTime.now(),
              remoteTimestamp: _extractTimestamp(remoteRecord) ?? DateTime.now(),
              localVersion: _extractVersion(localRecord),
              remoteVersion: _extractVersion(remoteRecord),
              localDeviceId: _extractDeviceId(localRecord),
              remoteDeviceId: _extractDeviceId(remoteRecord),
              localHlc: _extractHybridLogicalClock(localRecord),
              remoteHlc: _extractHybridLogicalClock(remoteRecord),
              localVc: localVc,
              remoteVc: remoteVc,
            );
            
            conflicts.add(conflict);
            _log('⚠️ Detected conflict: ${conflict.toString()}', level: LogLevel.warning);
          }
        }
      }
    }
    
    _log('🔍 Detected ${conflicts.length} conflicts across ${tables.length} tables');
    return conflicts;
  }

  Future<ConflictResolutionResult> resolveConflict(ConflictDetails conflict) async {
    final strategy = await getStrategy();
    
    _log('🔧 Resolving conflict using strategy: ${strategy.name}');
    
    switch (strategy) {
      case ConflictResolutionStrategy.newerWins:
        return _resolveByNewerWins(conflict);
        
      case ConflictResolutionStrategy.localWins:
        return ConflictResolutionResult.selectLocal(
          conflict.localRecord,
          'Local always wins strategy',
        );
        
      case ConflictResolutionStrategy.remoteWins:
        return ConflictResolutionResult.selectRemote(
          conflict.remoteRecord,
          'Remote always wins strategy',
        );
        
      case ConflictResolutionStrategy.devicePriorityBased:
        return await _resolveByDevicePriority(conflict);
        
      case ConflictResolutionStrategy.manualReview:
        return ConflictResolutionResult.needsManualReview(
          'Strategy requires manual review',
        );
    }
  }

  ConflictResolutionResult _resolveByNewerWins(ConflictDetails conflict) {
    if (conflict.localVc != null && conflict.remoteVc != null) {
      if (conflict.remoteVc!.happensBefore(conflict.localVc!)) {
         return ConflictResolutionResult.selectLocal(
          conflict.localRecord,
          'Local happened after Remote (Vector Clock)',
        );
      }
      if (conflict.localVc!.happensBefore(conflict.remoteVc!)) {
         return ConflictResolutionResult.selectRemote(
          conflict.remoteRecord,
          'Remote happened after Local (Vector Clock)',
        );
      }
      // Concurrent: Fallback to HLC or Time
    }

    if (conflict.localHlc != null && conflict.remoteHlc != null) {
      if (conflict.localHlc!.compare(conflict.remoteHlc!) > 0) {
        return ConflictResolutionResult.selectLocal(
          conflict.localRecord,
          'Local HLC is higher',
        );
      } else {
        return ConflictResolutionResult.selectRemote(
          conflict.remoteRecord,
          'Remote HLC is higher or equal',
        );
      }
    }

    // Fallback to Physical Time
    if (conflict.isLocalNewer) {
      return ConflictResolutionResult.selectLocal(
        conflict.localRecord,
        'Local record is newer (${conflict.timeDifference.inSeconds}s difference)',
      );
    } else if (conflict.isRemoteNewer) {
      return ConflictResolutionResult.selectRemote(
        conflict.remoteRecord,
        'Remote record is newer (${conflict.timeDifference.inSeconds}s difference)',
      );
    } else {
      if (conflict.isLocalVersionHigher) {
        return ConflictResolutionResult.selectLocal(
          conflict.localRecord,
          'Same timestamp, but local version is higher (v${conflict.localVersion} > v${conflict.remoteVersion})',
        );
      } else {
        return ConflictResolutionResult.selectRemote(
          conflict.remoteRecord,
          'Same timestamp, remote version is higher (v${conflict.remoteVersion} >= v${conflict.localVersion})',
        );
      }
    }
  }

  Future<ConflictResolutionResult> _resolveByDevicePriority(ConflictDetails conflict) async {
    final localPriority = await getDevicePriority();
    
    // Safety break: if time difference is huge, prefer newer regardless of priority
    if (conflict.isLocalNewer && conflict.timeDifference.inMinutes > 5) {
      return ConflictResolutionResult.selectLocal(
        conflict.localRecord,
        'Local record significantly newer (${conflict.timeDifference.inMinutes}min)',
      );
    } else if (conflict.isRemoteNewer && conflict.timeDifference.inMinutes > 5) {
      return ConflictResolutionResult.selectRemote(
        conflict.remoteRecord,
        'Remote record significantly newer (${conflict.timeDifference.inMinutes}min)',
      );
    }
    
    if (localPriority > 100) {
      return ConflictResolutionResult.selectLocal(
        conflict.localRecord,
        'Local device has higher priority (priority=$localPriority)',
      );
    } else {
      if (conflict.isRemoteNewer || conflict.remoteVersion >= conflict.localVersion) {
        return ConflictResolutionResult.selectRemote(
          conflict.remoteRecord,
          'Remote record is newer/equal and local priority is standard',
        );
      } else {
        return ConflictResolutionResult.selectLocal(
          conflict.localRecord,
          'Local record is newer despite standard priority',
        );
      }
    }
  }

  Future<Map<String, dynamic>> mergeRecords({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required List<ConflictResolutionResult> resolutions,
  }) async {
    // Start with Remote Data
    final merged = Map<String, dynamic>.from(remoteData);
    
    // 1. Apply Resolutions (Handling Collisions)
    for (final entry in resolutions) {
      if (entry.resolved && entry.selectedRecord != null) {
        final tableName = _findTableName(entry.selectedRecord!, remoteData) ?? _findTableName(entry.selectedRecord!, localData);
        if (tableName != null) {
          final recordsList = (merged[tableName] as List<dynamic>?) ?? [];
          final uuid = entry.selectedRecord!['local_uuid'];
          
          final existingIndex = recordsList.indexWhere(
            (r) => r is Map && r['local_uuid'] == uuid,
          );
          
          // Make list mutable if it came partly from unmodifiable source
          final mutableRecords = List<dynamic>.from(recordsList);
          
          if (existingIndex >= 0) {
            mutableRecords[existingIndex] = entry.selectedRecord!;
          } else {
            mutableRecords.add(entry.selectedRecord!);
          }
          
          merged[tableName] = mutableRecords;
        }
      }
    }
    
    // 2. Perform Union: Add Exclusive Local Records (Non-Conflicting)
    final tables = [
    final tables = SyncConstants.allTablesInOrder;
    ];

    for (final tableName in tables) {
       final localRecords = _getRecordsMap(localData[tableName]);
       final remoteRecords = _getRecordsMap(remoteData[tableName]);
       
       // Prepare merged list for this table
       final currentMergedList = (merged[tableName] as List<dynamic>?) ?? [];
       final mutableMergedList = List<dynamic>.from(currentMergedList);
       final mergedUuids = mutableMergedList
           .where((r) => r is Map && r['local_uuid'] != null)
           .map((r) => r['local_uuid'] as String)
           .toSet();

       for (final localUuid in localRecords.keys) {
         if (!remoteRecords.containsKey(localUuid) && !mergedUuids.contains(localUuid)) {
           final localRecord = localRecords[localUuid]!;
           
           // Check if this is a deleted record - don't resurrect it
           final deletedAt = localRecord['deleted_at'] ?? localRecord['deletedAt'];
           if (deletedAt != null) {
             // This record is deleted locally, skip it
             continue;
           }
           
           // This record exists locally but not remotely, and is not deleted.
           // It's a new local record -> Add it.
           mutableMergedList.add(localRecord);
         }
       }
       merged[tableName] = mutableMergedList;
    }
    
    return merged;
  }

  Map<String, Map<String, dynamic>> _getRecordsMap(dynamic tableData) {
    if (tableData is! List) return {};
    
    final map = <String, Map<String, dynamic>>{};
    for (final record in tableData) {
      if (record is Map<String, dynamic>) {
        final uuid = record['local_uuid'] ?? record['localUuid'];
        if (uuid != null && uuid is String) {
          map[uuid] = record;
        }
      }
    }
    return map;
  }

  DateTime? _extractTimestamp(Map<String, dynamic> record) {
    final lastModified = record['last_modified'] ?? record['lastModified'];
    
    if (lastModified is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(lastModified * 1000);
      } catch (_) {
        return null;
      }
    }
    
    final updatedAt = record['updated_at'] ?? record['updatedAt'];
    if (updatedAt is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);
      } catch (_) {
        return null;
      }
    }
    
    return null;
  }

  int _extractVersion(Map<String, dynamic> record) {
    final version = record['version'];
    if (version is int) return version;
    if (version is String) return int.tryParse(version) ?? 1;
    return 1;
  }

  String? _extractDeviceId(Map<String, dynamic> record) {
    return record['device_id'] ?? record['deviceId'];
  }
  
  HybridLogicalClock? _extractHybridLogicalClock(Map<String, dynamic> record) {
    final hlcStr = record['hlc'] as String?;
    if (hlcStr != null) {
      // إصلاح: إضافة try-catch لمعالجة أخطاء parsing بدون إيقاف عملية حل التعارضات
      try {
        return HybridLogicalClock.fromJson(
          hlcStr,
          _extractDeviceId(record) ?? 'unknown',
        );
      } catch (e) {
        _log('⚠️ Failed to parse HLC: $e');
        return null;
      }
    }
    return null;
  }
  
  VectorClock? _extractVectorClock(Map<String, dynamic> record) {
    final vcStr = record['vector_clock'] as String?;
    if (vcStr != null) {
      return VectorClock.fromJson(vcStr);
    }
    return null;
  }

  String? _findTableName(Map<String, dynamic> record, Map<String, dynamic> data) {
    for (final entry in data.entries) {
      if (entry.value is List) {
        final list = entry.value as List;
        for (final item in list) {
          if (item is Map && item['local_uuid'] == record['local_uuid']) {
            return entry.key;
          }
        }
      }
    }
    return null;
  }

  Future<void> logConflictHistory(ConflictDetails conflict, ConflictResolutionResult result) async {
    final historyEntry = {
      'timestamp': DateTime.now().toIso8601String(),
      'table': conflict.tableName,
      'uuid': conflict.localUuid,
      'strategy': (await getStrategy()).name,
      'resolution': result.reason,
      'selected': result.selectedRecord != null ? 'resolved' : 'manual',
      'time_diff_seconds': conflict.timeDifference.inSeconds,
    };
    
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('conflict_history') ?? [];
    history.insert(0, jsonEncode(historyEntry));
    
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
    
    await prefs.setStringList('conflict_history', history);
    
    _log('📝 Logged conflict resolution: ${result.reason}');
  }

  Future<List<Map<String, dynamic>>> getConflictHistory({int limit = 20}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('conflict_history') ?? [];
    
    final decoded = <Map<String, dynamic>>[];
    for (final entry in history.take(limit)) {
      try {
        decoded.add(jsonDecode(entry));
      } catch (_) {}
    }
    
    return decoded;
  }

  Future<Map<String, dynamic>> getConflictStatistics() async {
    final history = await getConflictHistory(limit: 100);
    
    final byTable = <String, int>{};
    final byStrategy = <String, int>{};

    final Map<String, dynamic> stats = {
      'total_conflicts': history.length,
      'by_table': byTable,
      'by_strategy': byStrategy,
      'avg_time_diff_seconds': 0.0,
      'manual_reviews_needed': 0,
    };
    
    int totalTimeDiff = 0;
    
    for (final entry in history) {
      final table = entry['table'] as String?;
      if (table != null) {
        byTable[table] = (byTable[table] ?? 0) + 1;
      }

      final strategy = entry['strategy'] as String?;
      if (strategy != null) {
        byStrategy[strategy] = (byStrategy[strategy] ?? 0) + 1;
      }
      
      final timeDiff = entry['time_diff_seconds'] as int? ?? 0;
      totalTimeDiff += timeDiff;
      
      if (entry['selected'] == 'manual') {
        stats['manual_reviews_needed'] = (stats['manual_reviews_needed'] as int) + 1;
      }
    }
    
    if (history.isNotEmpty) {
      stats['avg_time_diff_seconds'] = totalTimeDiff / history.length;
    }
    
    return stats;
  }
}

