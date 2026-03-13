import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'conflict_resolver.dart';
import 'conflict_manager.dart';
import 'vector_clock.dart';
import 'local_db.dart';
import 'logging/log_models.dart';

/// أنواع مصادر التعارض
enum ConflictSource {
  appwrite,
  googleDrive,
  both,
}

/// حالة حل التعارض الموحد
enum UnifiedConflictStatus {
  pending,
  autoResolved,
  manualResolved,
  failed,
}

/// نتيجة حل تعارض موحد
class UnifiedConflictResolution {
  final bool resolved;
  final Map<String, dynamic>? data;
  final ConflictStrategy strategy;
  final ConflictSource? source;
  final String? reason;
  final bool needsManualReview;
  final DateTime? resolvedAt;

  const UnifiedConflictResolution({
    required this.resolved,
    this.data,
    required this.strategy,
    this.source,
    this.reason,
    this.needsManualReview = false,
    this.resolvedAt,
  });

  factory UnifiedConflictResolution.auto({
    required Map<String, dynamic> data,
    required ConflictStrategy strategy,
    ConflictSource? source,
    String? reason,
  }) {
    return UnifiedConflictResolution(
      resolved: true,
      data: data,
      strategy: strategy,
      source: source,
      reason: reason ?? 'Auto resolved',
      resolvedAt: DateTime.now(),
    );
  }

  factory UnifiedConflictResolution.manual({
    required Map<String, dynamic> data,
    required ConflictSource source,
    String? reason,
  }) {
    return UnifiedConflictResolution(
      resolved: true,
      data: data,
      strategy: ConflictStrategy.manualResolve,
      source: source,
      reason: reason ?? 'Manually resolved',
      resolvedAt: DateTime.now(),
    );
  }

  factory UnifiedConflictResolution.needsReview({
    required ConflictSource source,
    required String reason,
  }) {
    return UnifiedConflictResolution(
      resolved: false,
      strategy: ConflictStrategy.manualResolve,
      source: source,
      reason: reason,
      needsManualReview: true,
    );
  }
}

/// سجل تعارض موحد (من أي مصدر)
class UnifiedConflictRecord {
  final String id;
  final String table;
  final String uuid;
  final ConflictSource source;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final Map<String, dynamic>? appwriteData;
  final Map<String, dynamic>? googleDriveData;
  final DateTime detectedAt;
  final DateTime? resolvedAt;
  final UnifiedConflictResolution? resolution;

  UnifiedConflictRecord({
    required this.id,
    required this.table,
    required this.uuid,
    required this.source,
    required this.localData,
    required this.remoteData,
    this.appwriteData,
    this.googleDriveData,
    required this.detectedAt,
    this.resolvedAt,
    this.resolution,
  });

  bool get isPending => resolution == null || !resolution!.resolved;
  bool get isResolved => resolution?.resolved ?? false;
  bool get needsManualReview => resolution?.needsManualReview ?? false;

  /// إنشاء من بيانات Appwrite
  factory UnifiedConflictRecord.fromAppwrite({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) {
    return UnifiedConflictRecord(
      id: 'appwrite_${table}_${uuid}_${DateTime.now().millisecondsSinceEpoch}',
      table: table,
      uuid: uuid,
      source: ConflictSource.appwrite,
      localData: localData,
      remoteData: remoteData,
      appwriteData: remoteData,
      detectedAt: DateTime.now(),
    );
  }

  /// إنشاء من بيانات Google Drive
  factory UnifiedConflictRecord.fromGoogleDrive({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) {
    return UnifiedConflictRecord(
      id: 'gdrive_${table}_${uuid}_${DateTime.now().millisecondsSinceEpoch}',
      table: table,
      uuid: uuid,
      source: ConflictSource.googleDrive,
      localData: localData,
      remoteData: remoteData,
      googleDriveData: remoteData,
      detectedAt: DateTime.now(),
    );
  }

  /// إنشاء من تعارض ثلاثي الاتجاهات (محلي vs Appwrite vs Google Drive)
  factory UnifiedConflictRecord.fromTriple({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> appwriteData,
    required Map<String, dynamic> googleDriveData,
  }) {
    // اختيار الأحدث كـ "remote" للمقارنة
    final appwriteTime = _extractTimestamp(appwriteData);
    final googleDriveTime = _extractTimestamp(googleDriveData);

    final remoteData = (appwriteTime != null && googleDriveTime != null)
        ? (appwriteTime.isAfter(googleDriveTime) ? appwriteData : googleDriveData)
        : (appwriteData.isNotEmpty ? appwriteData : googleDriveData);

    return UnifiedConflictRecord(
      id: 'triple_${table}_${uuid}_${DateTime.now().millisecondsSinceEpoch}',
      table: table,
      uuid: uuid,
      source: ConflictSource.both,
      localData: localData,
      remoteData: remoteData,
      appwriteData: appwriteData,
      googleDriveData: googleDriveData,
      detectedAt: DateTime.now(),
    );
  }

  static DateTime? _extractTimestamp(Map<String, dynamic> data) {
    final lastModified = data['lastModified'] ?? data['lastModified'];
    if (lastModified is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(lastModified * 1000);
      } catch (_) {
        return null;
      }
    }
    final updatedAt = data['updatedAt'] ?? data['updatedAt'];
    if (updatedAt is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

/// محلل تعارضات موحد يعمل مع Appwrite و Google Drive
class UnifiedConflictResolver {
  UnifiedConflictResolver._();
  static final UnifiedConflictResolver instance = UnifiedConflictResolver._();

  EnhancedConflictResolver? _appwriteResolver;
  EnhancedConflictResolver? _googleDriveResolver;
  ConflictManager? _conflictManager;
  VectorClockManager? _vectorClockManager;
  AppDatabase? _database;

  final _conflictsController = StreamController<List<UnifiedConflictRecord>>.broadcast();
  final List<UnifiedConflictRecord> _pendingConflicts = [];

  Stream<List<UnifiedConflictRecord>> get conflictsStream => _conflictsController.stream;
  List<UnifiedConflictRecord> get pendingConflicts => List.unmodifiable(_pendingConflicts);
  int get pendingCount => _pendingConflicts.length;

  /// تهيئة المحلل
  void initialize({
    required AppDatabase database,
    ConflictManager? conflictManager,
  }) {
    _database = database;
    _conflictManager = conflictManager ?? ConflictManager(database);
    _vectorClockManager = VectorClockManager(deviceId: 'unified');

    // محلل Appwrite
    _appwriteResolver = EnhancedConflictResolver(
      defaultStrategy: ConflictStrategy.lastWriteWins,
      tableStrategies: _criticalTableStrategies,
      criticalFieldsOverrides: _criticalFieldsConfig,
    );

    // محلل Google Drive (نفس الإعدادات)
    _googleDriveResolver = EnhancedConflictResolver(
      defaultStrategy: ConflictStrategy.lastWriteWins,
      tableStrategies: _criticalTableStrategies,
      criticalFieldsOverrides: _criticalFieldsConfig,
    );

    debugPrint('✅ UnifiedConflictResolver initialized');
  }

  /// استراتيجيات الجداول الحرجة
  Map<String, ConflictStrategy> get _criticalTableStrategies => {
    'bookings': ConflictStrategy.fieldLevel,
    'payments': ConflictStrategy.fieldLevel,
    'cash_transactions': ConflictStrategy.fieldLevel,
    'expenses': ConflictStrategy.fieldLevel,
    'debts': ConflictStrategy.fieldLevel,
    'rooms': ConflictStrategy.lastWriteWins,
    'employees': ConflictStrategy.lastWriteWins,
    'guests': ConflictStrategy.lastWriteWins,
  };

  /// تكوين الحقول الحرجة
  Map<String, Set<String>> get _criticalFieldsConfig => {
    'bookings': {
      'status', 'checkout_date', 'actual_checkout', 'room_number',
      'total_due_cached', 'total_paid_cached', 'remaining_balance_cached',
      'guest_name', 'is_fully_paid', 'discount',
    },
    'payments': {
      'amount', 'payment_date', 'payment_method', 'booking_uuid',
      'status', 'revenue_type',
    },
    'cash_transactions': {
      'amount', 'transaction_type', 'transaction_time',
      'reference_type', 'reference_id',
    },
    'expenses': {
      'amount', 'date', 'category', 'description',
      'status', 'expense_type', 'hotel_day_key',
    },
    'debts': {
      'amount', 'status', 'due_date', 'paid_amount',
      'guest_name', 'remaining_amount', 'is_settled',
    },
    'rooms': {
      'status', 'price', 'room_number', 'cleaning_status',
    },
    'employees': {
      'name', 'phone', 'basic_salary', 'position', 'status',
    },
  };

  /// حل تعارض من Appwrite
  Future<UnifiedConflictResolution> resolveAppwriteConflict({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    String? deviceId,
  }) async {
    return _resolveConflict(
      source: ConflictSource.appwrite,
      table: table,
      uuid: uuid,
      localData: localData,
      remoteData: remoteData,
      deviceId: deviceId,
    );
  }

  /// حل تعارض من Google Drive
  Future<UnifiedConflictResolution> resolveGoogleDriveConflict({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    String? deviceId,
  }) async {
    return _resolveConflict(
      source: ConflictSource.googleDrive,
      table: table,
      uuid: uuid,
      localData: localData,
      remoteData: remoteData,
      deviceId: deviceId,
    );
  }

  /// حل تعارض ثلاثي (محلي vs Appwrite vs Google Drive)
  Future<UnifiedConflictResolution> resolveTripleConflict({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> appwriteData,
    required Map<String, dynamic> googleDriveData,
  }) async {
    // 1. حل بين Appwrite و Google Drive أولاً
    final sourceResolution = await _resolveConflict(
      source: ConflictSource.both,
      table: table,
      uuid: uuid,
      localData: appwriteData,
      remoteData: googleDriveData,
    );

    if (!sourceResolution.resolved) {
      return UnifiedConflictResolution.needsReview(
        source: ConflictSource.both,
        reason: 'Could not resolve between Appwrite and Google Drive',
      );
    }

    // 2. حل بين المحلي والفائز من الخطوة 1
    final finalResolution = await _resolveConflict(
      source: ConflictSource.both,
      table: table,
      uuid: uuid,
      localData: localData,
      remoteData: sourceResolution.data!,
    );

    return finalResolution;
  }

  /// الحل الأساسي للتعارض
  Future<UnifiedConflictResolution> _resolveConflict({
    required ConflictSource source,
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    String? deviceId,
  }) async {
    try {
      final resolver = source == ConflictSource.googleDrive
          ? _googleDriveResolver!
          : _appwriteResolver!;

      final localTs = _extractTimestamp(localData) ?? DateTime.now();
      final remoteTs = _extractTimestamp(remoteData) ?? DateTime.now();

      final context = ConflictContext(
        table: table,
        uuid: uuid,
        localData: localData,
        remoteData: remoteData,
        localTimestamp: localTs,
        remoteTimestamp: remoteTs,
        localDeviceId: deviceId ?? 'local',
        remoteDeviceId: remoteData['deviceId'] ?? remoteData['deviceId'] ?? 'remote',
        localVectorClock: _vectorClockManager?.getClock(uuid),
        remoteVectorClock: _parseVectorClock(remoteData['vectorClock']),
      );

      final result = resolver.resolve(context);

      if (result.needsManualReview) {
        // تسجيل للمراجعة اليدوية
        final record = source == ConflictSource.googleDrive
            ? UnifiedConflictRecord.fromGoogleDrive(
                table: table,
                uuid: uuid,
                localData: localData,
                remoteData: remoteData,
              )
            : UnifiedConflictRecord.fromAppwrite(
                table: table,
                uuid: uuid,
                localData: localData,
                remoteData: remoteData,
              );

        _addPendingConflict(record);

        return UnifiedConflictResolution.needsReview(
          source: source,
          reason: result.strategy == ConflictStrategy.manualResolve
              ? 'Manual review required by strategy'
              : 'Could not auto-resolve',
        );
      }

      return UnifiedConflictResolution.auto(
        data: result.mergedData ?? result.winner,
        strategy: result.strategy,
        source: source,
        reason: 'Auto resolved using ${result.strategy.name}',
      );
    } catch (e) {
      debugPrint('❌ Error resolving conflict: $e');
      return UnifiedConflictResolution.needsReview(
        source: source,
        reason: 'Error: $e',
      );
    }
  }

  /// حل تعارض يدوياً
  Future<void> resolveManually({
    required String conflictId,
    required Map<String, dynamic> resolution,
    required ConflictSource chosenSource,
  }) async {
    final index = _pendingConflicts.indexWhere((c) => c.id == conflictId);
    if (index == -1) return;

    final conflict = _pendingConflicts[index];
    final resolved = UnifiedConflictRecord(
      id: conflict.id,
      table: conflict.table,
      uuid: conflict.uuid,
      source: chosenSource,
      localData: conflict.localData,
      remoteData: conflict.remoteData,
      appwriteData: conflict.appwriteData,
      googleDriveData: conflict.googleDriveData,
      detectedAt: conflict.detectedAt,
      resolvedAt: DateTime.now(),
      resolution: UnifiedConflictResolution.manual(
        data: resolution,
        source: chosenSource,
      ),
    );

    _pendingConflicts[index] = resolved;
    _conflictsController.add(List.unmodifiable(_pendingConflicts));

    // حفظ في قاعدة البيانات
    await _persistResolution(resolved);

    // إزالة من القائمة بعد الحل
    _pendingConflicts.removeAt(index);
    _conflictsController.add(List.unmodifiable(_pendingConflicts));

    debugPrint('✅ Manually resolved conflict: $conflictId');
  }

  /// اختيار مصدر للبيانات (للحل اليدوي)
  Future<void> chooseSource({
    required String conflictId,
    required ConflictSource source,
  }) async {
    final index = _pendingConflicts.indexWhere((c) => c.id == conflictId);
    if (index == -1) return;

    final conflict = _pendingConflicts[index];
    Map<String, dynamic> chosenData;

    switch (source) {
      case ConflictSource.appwrite:
        chosenData = conflict.appwriteData ?? conflict.remoteData;
        break;
      case ConflictSource.googleDrive:
        chosenData = conflict.googleDriveData ?? conflict.remoteData;
        break;
      case ConflictSource.both:
      default:
        chosenData = conflict.remoteData;
        break;
    }

    await resolveManually(
      conflictId: conflictId,
      resolution: chosenData,
      chosenSource: source,
    );
  }

  /// حل جميع التعارضات المتعلقة بجدول معين
  Future<void> resolveAllForTable(String table, ConflictSource source) async {
    final tableConflicts = _pendingConflicts.where((c) => c.table == table).toList();
    for (final conflict in tableConflicts) {
      await chooseSource(conflictId: conflict.id, source: source);
    }
  }

  /// رفض جميع التعارضات (الاحتفاظ بالمحلي)
  Future<void> rejectAll() async {
    for (final conflict in List<UnifiedConflictRecord>.from(_pendingConflicts)) {
      await resolveManually(
        conflictId: conflict.id,
        resolution: conflict.localData,
        chosenSource: ConflictSource.appwrite, // المحلي يُعتبر المصدر الأساسي
      );
    }
  }

  /// قبول جميع التعارضات (اختيار حسب المصدر الأحدث)
  Future<void> acceptAllAuto() async {
    for (final conflict in List<UnifiedConflictRecord>.from(_pendingConflicts)) {
      final localTs = _extractTimestamp(conflict.localData);
      final remoteTs = _extractTimestamp(conflict.remoteData);

      final chosenSource = (remoteTs != null && localTs != null && remoteTs.isAfter(localTs))
          ? conflict.source
          : ConflictSource.appwrite;

      await chooseSource(conflictId: conflict.id, source: chosenSource);
    }
  }

  /// الحصول على إحصائيات التعارضات
  Map<String, dynamic> getStatistics() {
    final bySource = <ConflictSource, int>{};
    final byTable = <String, int>{};
    final byStatus = <UnifiedConflictStatus, int>{};

    for (final conflict in _pendingConflicts) {
      bySource[conflict.source] = (bySource[conflict.source] ?? 0) + 1;
      byTable[conflict.table] = (byTable[conflict.table] ?? 0) + 1;

      final status = conflict.isResolved
          ? UnifiedConflictStatus.manualResolved
          : UnifiedConflictStatus.pending;
      byStatus[status] = (byStatus[status] ?? 0) + 1;
    }

    return {
      'total_pending': _pendingConflicts.length,
      'by_source': bySource.map((k, v) => MapEntry(k.name, v)),
      'by_table': byTable,
      'by_status': byStatus.map((k, v) => MapEntry(k.name, v)),
    };
  }

  void _addPendingConflict(UnifiedConflictRecord record) {
    _pendingConflicts.add(record);
    _conflictsController.add(List.unmodifiable(_pendingConflicts));
    _persistConflict(record);
  }

  Future<void> _persistConflict(UnifiedConflictRecord record) async {
    if (_database == null) return;

    try {
      final existingQuery = _database!.select(_database!.syncConflicts)
        ..where(
          (t) => t.targetTable.equals(record.table) & t.uuid.equals(record.uuid),
        );

      final existing = await existingQuery.getSingleOrNull();

      final payload = {
        'source': record.source.name,
        'appwrite_data': record.appwriteData,
        'google_drive_data': record.googleDriveData,
      };

      if (existing != null) {
        await (_database!.update(_database!.syncConflicts)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          SyncConflictsCompanion(
            localPayload: Value(jsonEncode(record.localData)),
            remotePayload: Value(jsonEncode(record.remoteData)),
            resolution: record.resolution != null
                ? Value(jsonEncode({
                    'data': record.resolution!.data,
                    'strategy': record.resolution!.strategy.name,
                    'resolved_at': record.resolution!.resolvedAt?.toIso8601String(),
                  }))
                : const Value(''),
          ),
        );
      } else {
        final latestLog = await (_database!.select(_database!.syncLog)
              ..orderBy([(t) => d.OrderingTerm.desc(t.id)])
              ..limit(1))
            .getSingleOrNull();

        await _database!.into(_database!.syncConflicts).insert(
              SyncConflictsCompanion.insert(
                logId: latestLog?.id ?? 0,
                targetTable: record.table,
                uuid: record.uuid,
                localPayload: jsonEncode(record.localData),
                remotePayload: jsonEncode(record.remoteData),
                resolution: record.resolution != null
                    ? jsonEncode({
                        'data': record.resolution!.data,
                        'strategy': record.resolution!.strategy.name,
                      })
                    : '',
                createdAt: record.detectedAt.toIso8601String(),
              ),
            );
      }
    } catch (e) {
      debugPrint('❌ Failed to persist conflict: $e');
    }
  }

  Future<void> _persistResolution(UnifiedConflictRecord record) async {
    await _persistConflict(record);
  }

  /// تحميل التعارضات المعلقة من قاعدة البيانات
  Future<void> loadPendingConflicts() async {
    if (_database == null) return;

    try {
      final conflicts = await (_database!.select(_database!.syncConflicts)
            ..where((t) => t.resolution.equals(''))
            ..orderBy([(t) => d.OrderingTerm.desc(t.id)]))
          .get();

      _pendingConflicts.clear();

      for (final row in conflicts) {
        try {
          final localData = jsonDecode(row.localPayload) as Map<String, dynamic>;
          final remoteData = jsonDecode(row.remotePayload) as Map<String, dynamic>;

          _pendingConflicts.add(UnifiedConflictRecord(
            id: '${row.targetTable}_${row.uuid}_${DateTime.parse(row.createdAt).millisecondsSinceEpoch}',
            table: row.targetTable,
            uuid: row.uuid,
            source: ConflictSource.appwrite, // افتراضي
            localData: localData,
            remoteData: remoteData,
            detectedAt: DateTime.parse(row.createdAt),
          ));
        } catch (e) {
          debugPrint('❌ Failed to decode conflict: $e');
        }
      }

      _conflictsController.add(List.unmodifiable(_pendingConflicts));
    } catch (e) {
      debugPrint('❌ Failed to load pending conflicts: $e');
    }
  }

  DateTime? _extractTimestamp(Map<String, dynamic> data) {
    final lastModified = data['lastModified'] ?? data['lastModified'];
    if (lastModified is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(lastModified * 1000);
      } catch (_) {
        return null;
      }
    }
    final updatedAt = data['updatedAt'] ?? data['updatedAt'];
    if (updatedAt is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  VectorClock? _parseVectorClock(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) {
      return VectorClock.fromJson(data);
    }
    if (data is String) {
      try {
        return VectorClock.fromJson(jsonDecode(data));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void dispose() {
    _conflictsController.close();
  }
}

/// امتدادات مفيدة
extension ConflictStrategyExtension on ConflictStrategy {
  String get name => toString().split('.').last;
}
