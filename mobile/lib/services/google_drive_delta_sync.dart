import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as d;
import 'delta_sync_service.dart';
import 'google_drive_backup_service.dart';
import 'local_db.dart';
import 'sync_constants.dart';
import '../utils/time.dart';
import '../utils/id.dart';
import 'sync_locks.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'repositories/base_repository.dart';
import 'conflict_resolver.dart';

enum SyncFileType { fullBackup, deltaSync }

enum _DeltaSyncStartResult { ok, notInitialized, alreadySyncing, notSignedIn }

class GoogleDriveDeltaSync {
  GoogleDriveDeltaSync._();
  static final instance = GoogleDriveDeltaSync._();

  GoogleDriveBackupService? _driveService;
  DeltaSyncService? _deltaSyncService;
  AppDatabase? _database;
  AdapterRegistry? _adapterRegistry;
  String? _deviceId;
  bool _isSyncing = false;

  static const _prefsLegacyLastDeltaSyncKey = 'gd_last_delta_sync';
  static const _prefsLastPushTsKey = 'gd_last_push_ts';
  static const _prefsLastPullTsKey = 'gd_last_pull_ts';
  static const _prefsDeviceIdKey = 'gd_delta_device_id';
  // افتراضياً السحب معطل ما لم يتم تفعيله يدوياً
  static const _prefsDrivePullEnabledKey = 'gd_drive_pull_enabled';

  static const fullBackupPrefix = 'marina_backup_full_';
  static const deltaSyncPrefix = 'marina_sync_delta_';

  Future<void> initialize(
    GoogleDriveBackupService driveService,
    AppDatabase db,
  ) async {
    _driveService = driveService;
    _database = db;
    _adapterRegistry = AdapterRegistry(db);
    _deltaSyncService = DeltaSyncService(db);
    await _initializeDeviceId();
    debugPrint('✅ تم تهيئة خدمة المزامنة التفاضلية لـ Google Drive');
  }

  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_prefsDeviceIdKey);
    if (_deviceId == null) {
      _deviceId = IdGen.uuid();
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
    }
  }

  bool get isInitialized => _driveService != null && _deltaSyncService != null;
  bool get isSyncing => _isSyncing;
  String? get deviceId => _deviceId;

  Future<DeltaSyncResult> pushDeltaChanges() async {
    final canStart = await SyncLocks.deltaSyncLock.synchronized(() async {
      if (!isInitialized) return _DeltaSyncStartResult.notInitialized;
      if (_isSyncing) return _DeltaSyncStartResult.alreadySyncing;
      if (_driveService?.isSignedIn != true) {
        return _DeltaSyncStartResult.notSignedIn;
      }

      _isSyncing = true;
      return _DeltaSyncStartResult.ok;
    });

    if (canStart == _DeltaSyncStartResult.notInitialized ||
        canStart == _DeltaSyncStartResult.alreadySyncing) {
      return DeltaSyncResult(
        success: false,
        message: 'الخدمة غير جاهزة أو المزامنة جارية',
      );
    }

    if (canStart == _DeltaSyncStartResult.notSignedIn) {
      return DeltaSyncResult(
        success: false,
        message: 'غير مسجل الدخول في Google Drive',
      );
    }

    try {
      debugPrint('📤 بدء المزامنة التفاضلية إلى Google Drive...');

      final lastSyncTs = await _getLastPushTimestamp();
      final computation = await _deltaSyncService!.compute(since: lastSyncTs);

      if (computation.changes.isEmpty) {
        debugPrint('✅ لا توجد تغييرات للمزامنة');
        return DeltaSyncResult(
          success: true,
          message: 'لا توجد تغييرات',
          changesCount: 0,
        );
      }

      final deltaPayload = _buildDeltaPayload(computation);
      final fileName = _generateDeltaSyncFileName();

      await _uploadDeltaFile(fileName, deltaPayload);
      await _deltaSyncService!.persistMirror(computation);
      await _updateLastPushTimestamp();

      debugPrint(
        '✅ تم رفع ${computation.changes.length} تغيير إلى Google Drive',
      );

      return DeltaSyncResult(
        success: true,
        message: 'تم رفع التغييرات بنجاح',
        changesCount: computation.changes.length,
      );
    } catch (e, stackTrace) {
      final errorMessage = 'خطأ في رفع التغييرات: $e';
      debugPrint('❌ $errorMessage');
      debugPrint('🔍 Stack trace: $stackTrace');
      return DeltaSyncResult(success: false, message: errorMessage);
    } finally {
      await SyncLocks.deltaSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  Future<DeltaSyncResult> pullDeltaChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final isPullEnabled = prefs.getBool(_prefsDrivePullEnabledKey) ?? false;

    if (!isPullEnabled) {
      debugPrint('⚠️ Google Drive pull skipped (disabled in settings)');
      return DeltaSyncResult(
        success: true,
        message: 'السحب من Google Drive معطل',
        changesCount: 0,
      );
    }

    final canStart = await SyncLocks.deltaSyncLock.synchronized(() async {
      if (!isInitialized) return _DeltaSyncStartResult.notInitialized;
      if (_isSyncing) return _DeltaSyncStartResult.alreadySyncing;
      if (_driveService?.isSignedIn != true) {
        return _DeltaSyncStartResult.notSignedIn;
      }

      _isSyncing = true;
      return _DeltaSyncStartResult.ok;
    });

    if (canStart == _DeltaSyncStartResult.notInitialized ||
        canStart == _DeltaSyncStartResult.alreadySyncing) {
      return DeltaSyncResult(success: false, message: 'الخدمة غير جاهزة');
    }

    if (canStart == _DeltaSyncStartResult.notSignedIn) {
      return DeltaSyncResult(success: false, message: 'غير مسجل الدخول');
    }

    try {
      debugPrint('📥 فحص التغييرات من Google Drive...');

      final deltaFiles = await _listDeltaSyncFiles();
      if (deltaFiles.isEmpty) {
        return DeltaSyncResult(
          success: true,
          message: 'لا توجد ملفات مزامنة',
          changesCount: 0,
        );
      }

      deltaFiles.sort((a, b) => a.createdTime.compareTo(b.createdTime));

      int appliedChanges = 0;
      final lastPullTsSec = await _getLastPullTimestamp();
      var maxProcessedTsSec = lastPullTsSec;

      for (final file in deltaFiles) {
        final fileTsSec = file.createdTime.millisecondsSinceEpoch ~/ 1000;
        if (fileTsSec <= lastPullTsSec) continue;

        final sourceDeviceId = file.appProperties['device_id'];
        if (sourceDeviceId == _deviceId) {
          if (fileTsSec > maxProcessedTsSec) maxProcessedTsSec = fileTsSec;
          continue;
        }

        final deltaData = await _downloadDeltaFile(file.fileId);
        if (deltaData != null) {
          final changes = await _applyDeltaChanges(deltaData);
          appliedChanges += changes;
        }

        if (fileTsSec > maxProcessedTsSec) maxProcessedTsSec = fileTsSec;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsLastPullTsKey, maxProcessedTsSec);

      return DeltaSyncResult(
        success: true,
        message: 'تم تطبيق $appliedChanges تغيير',
        changesCount: appliedChanges,
      );
    } catch (e, stackTrace) {
      final errorMessage = 'خطأ في سحب التغييرات: $e';
      debugPrint('❌ $errorMessage');
      debugPrint('🔍 Stack trace: $stackTrace');
      return DeltaSyncResult(success: false, message: errorMessage);
    } finally {
      await SyncLocks.deltaSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  Future<List<DriveBackupFile>> _listDeltaSyncFiles() async {
    final allFiles = await _driveService!.listBackupFiles();
    return allFiles
        .where((f) => f.fileName.startsWith(deltaSyncPrefix))
        .toList();
  }

  Map<String, dynamic> _buildDeltaPayload(DeltaSyncComputation computation) {
    return {
      'type': 'delta_sync',
      'device_id': _deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      'epoch': Time.nowEpoch(),
      'changes_count': computation.changes.length,
      'changes': computation.toPayload(),
      'fallback_tables': computation.fallbackTables.toList(),
    };
  }

  String _generateDeltaSyncFileName() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}${now.millisecond.toString().padLeft(3, '0')}';
    return '$deltaSyncPrefix${dateStr}_$timeStr.json';
  }

  Future<void> _uploadDeltaFile(
    String fileName,
    Map<String, dynamic> payload,
  ) async {
    final jsonStr = jsonEncode(payload);
    final bytes = utf8.encode(jsonStr);

    await _driveService!.uploadBackupWithName(
      fileName,
      bytes,
      appProperties: {
        'type': 'delta_sync',
        'device_id': _deviceId ?? '',
        'changes_count': payload['changes_count'].toString(),
      },
    );
  }

  Future<Map<String, dynamic>?> _downloadDeltaFile(String fileId) async {
    try {
      return await _driveService!.downloadBackup(fileId);
    } catch (e) {
      debugPrint('⚠️ خطأ في تحميل ملف المزامنة: $e');
      return null;
    }
  }

  Future<int> _applyDeltaChanges(Map<String, dynamic> deltaData) async {
    final changes = deltaData['changes'] as List<dynamic>?;
    if (changes == null || changes.isEmpty) return 0;

    return _database!.transaction(() async {
      final sortedChanges = _sortChangesByDependency(changes);
      int applied = 0;

      for (final change in sortedChanges) {
        final entity = change['entity'] as String;
        final op = change['op'] as String;
        final data = change['data'] as Map<String, dynamic>;

        await _applyChange(entity, op, data);
        applied++;
      }

      debugPrint('✅ تم تطبيق $applied تغيير بنجاح داخل transaction واحدة');
      return applied;
    });
  }

  List<Map<String, dynamic>> _sortChangesByDependency(List<dynamic> changes) {
    final changesList = List<Map<String, dynamic>>.from(
      changes.map((c) => Map<String, dynamic>.from(c as Map)),
    );

    final deletes = <Map<String, dynamic>>[];
    final nonDeletes = <Map<String, dynamic>>[];

    for (final change in changesList) {
      final op = change['op'] as String;
      if (op == 'delete') {
        deletes.add(change);
      } else {
        nonDeletes.add(change);
      }
    }

    nonDeletes.sort((a, b) {
      final aOrder = _getTableOrderIndex(a['entity'] as String);
      final bOrder = _getTableOrderIndex(b['entity'] as String);
      return aOrder.compareTo(bOrder);
    });

    deletes.sort((a, b) {
      final aOrder = _getTableOrderIndex(a['entity'] as String);
      final bOrder = _getTableOrderIndex(b['entity'] as String);
      return bOrder.compareTo(aOrder);
    });

    return [...nonDeletes, ...deletes];
  }

  int _getTableOrderIndex(String entity) {
    final index = SyncConstants.tableOrder.indexOf(entity);
    return index == -1 ? 999 : index;
  }

  /// محلل تعارضات Google Drive - مطابق لاستراتيجيات Appwrite
  static final _driveConflictResolver = EnhancedConflictResolver(
    defaultStrategy: ConflictStrategy.lastWriteWins,
    tableStrategies: {
      'bookings': ConflictStrategy.lastWriteWins,
      'rooms': ConflictStrategy.lastWriteWins,
      'payments': ConflictStrategy.lastWriteWins,
      'expenses': ConflictStrategy.lastWriteWins,
      'debts': ConflictStrategy.fieldLevel,
      'employees': ConflictStrategy.fieldLevel,
      'cash_transactions': ConflictStrategy.lastWriteWins,
      'shift_notes': ConflictStrategy.fieldLevel,
      'booking_notes': ConflictStrategy.fieldLevel,
      'booking_nights': ConflictStrategy.lastWriteWins,
      'salary_cycles': ConflictStrategy.lastWriteWins,
      'salary_payments': ConflictStrategy.lastWriteWins,
      'salary_withdrawals': ConflictStrategy.lastWriteWins,
      'booking_price_adjustments': ConflictStrategy.lastWriteWins,
      'price_adjustments': ConflictStrategy.lastWriteWins,
      'audit_logs': ConflictStrategy.lastWriteWins,
      'payment_voids': ConflictStrategy.lastWriteWins,
    },
  );

  /// الحصول على Repository للكيان المحدد
  BaseRepository _getRepoForEntity(String entity) {
    final registry = _adapterRegistry!;
    switch (entity) {
      case 'rooms': return registry.rooms;
      case 'bookings': return registry.bookings;
      case 'payments': return registry.payments;
      case 'expenses': return registry.expenses;
      case 'debts': return registry.debts;
      case 'employees': return registry.employees;
      case 'booking_notes': return registry.bookingNotes;
      case 'booking_nights': return registry.nights;
      case 'salary_cycles': return registry.salaryCycles;
      case 'salary_payments': return registry.salaryPayments;
      case 'cash_transactions': return registry.cashTransactions;
      case 'shift_notes': return registry.shiftNotes;
      case 'price_adjustments': return registry.priceAdjustments;
      case 'audit_logs': return registry.auditLogs;
      case 'payment_voids': return registry.paymentVoids;
      case 'booking_price_adjustments': return registry.bookingPriceAdjustments;
      case 'salary_withdrawals': return registry.salaryWithdrawals;
      default:
        throw UnimplementedError('لا يوجد repository للكيان: $entity');
    }
  }

  /// معالجة التعارضات قبل التطبيق
  /// ترجع البيانات المراد تطبيقها (أو null لتخطي التطبيق)
  Future<Map<String, dynamic>?> _resolveConflict(
    String entity,
    String localUuid,
    Map<String, dynamic> remoteData,
  ) async {
    final repo = _getRepoForEntity(entity);
    final localData = await repo.getJsonByUuid(localUuid);

    // لا يوجد سجل محلي → إدراج جديد بدون تعارض
    if (localData == null) return remoteData;

    // استخراج الطوابع الزمنية
    final localTs = _asInt(localData['lastModified']) ??
        _asInt(localData['last_modified']) ??
        _asInt(localData['updated_at']) ?? 0;
    final remoteTs = _asInt(remoteData['lastModified']) ??
        _asInt(remoteData['last_modified']) ??
        _asInt(remoteData['updated_at']) ?? 0;

    // لا توجد طوابع زمنية صالحة → السماح بالتحديث
    if (localTs <= 0 || remoteTs <= 0) return remoteData;

    // البعيد أحدث → تحديث بدون تعارض
    if (remoteTs > localTs) return remoteData;

    // المحلي أحدث أو بنفس الوقت → تعارض!
    final resolution = _driveConflictResolver.resolve(
      ConflictContext(
        table: entity,
        uuid: localUuid,
        localData: localData,
        remoteData: remoteData,
        localTimestamp: DateTime.fromMillisecondsSinceEpoch(localTs * 1000),
        remoteTimestamp: DateTime.fromMillisecondsSinceEpoch(remoteTs * 1000),
        localDeviceId: _deviceId ?? 'local',
        remoteDeviceId: remoteData['deviceId'] ?? 'remote_drive',
      ),
    );

    if (resolution.winner == localData && resolution.mergedData == null) {
      // المحلي فاز → تخطي التحديث
      debugPrint('⚖️ تعارض $entity/$localUuid: المحلي أحدث، تخطي التحديث');
      return null;
    }

    if (resolution.mergedData != null) {
      // دمج على مستوى الحقل
      debugPrint('🔀 تعارض $entity/$localUuid: دمج على مستوى الحقل');
      return resolution.mergedData;
    }

    // البعيد فاز
    debugPrint('⚖️ تعارض $entity/$localUuid: البعيد فاز بالتعارض');
    return remoteData;
  }

  Future<void> _applyChange(
    String entity,
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (_database == null || _adapterRegistry == null) return;
    final db = _database!;
    final registry = _adapterRegistry!;
    final localUuid =
        _asString(data['local_uuid']) ?? _asString(data['localUuid']) ?? '';
    if (localUuid.isEmpty) return;

    debugPrint('🔄 تطبيق $operation على $entity/$localUuid');

    if (operation == 'delete') {
      await _deleteEntity(db, entity, localUuid);
      return;
    }

    final payload = Map<String, dynamic>.from(data);
    payload.putIfAbsent('localUuid', () => localUuid);

    // ✅ معالجة التعارضات قبل التطبيق
    final resolvedData = await _resolveConflict(entity, localUuid, payload);
    if (resolvedData == null) return; // تخطي: المحلي أحدث

    switch (entity) {
      case 'rooms':
        await registry.rooms.upsertFromJson(resolvedData, src: Source.drive);
      case 'bookings':
        await registry.bookings.upsertFromJson(resolvedData, src: Source.drive);
      case 'payments':
        await registry.payments.upsertFromJson(resolvedData, src: Source.drive);
      case 'expenses':
        await registry.expenses.upsertFromJson(resolvedData, src: Source.drive);
      case 'debts':
        await registry.debts.upsertFromJson(resolvedData, src: Source.drive);
      case 'employees':
        await registry.employees.upsertFromJson(resolvedData, src: Source.drive);
      case 'booking_notes':
        await registry.bookingNotes.upsertFromJson(resolvedData, src: Source.drive);
      case 'booking_nights':
        await registry.nights.upsertFromJson(resolvedData, src: Source.drive);
      case 'salary_cycles':
        await registry.salaryCycles.upsertFromJson(resolvedData, src: Source.drive);
      case 'salary_payments':
        await registry.salaryPayments.upsertFromJson(
          resolvedData,
          src: Source.drive,
        );
      case 'cash_transactions':
        await registry.cashTransactions.upsertFromJson(
          resolvedData,
          src: Source.drive,
        );
      case 'shift_notes':
        await registry.shiftNotes.upsertFromJson(resolvedData, src: Source.drive);
      case 'price_adjustments':
        await registry.priceAdjustments.upsertFromJson(
          resolvedData,
          src: Source.drive,
        );
      case 'audit_logs':
        await registry.auditLogs.upsertFromJson(resolvedData, src: Source.drive);
      case 'payment_voids':
        await registry.paymentVoids.upsertFromJson(resolvedData, src: Source.drive);
      case 'booking_price_adjustments':
        await registry.bookingPriceAdjustments.upsertFromJson(
          resolvedData,
          src: Source.drive,
        );
      case 'salary_withdrawals':
        await registry.salaryWithdrawals.upsertFromJson(
          resolvedData,
          src: Source.drive,
        );
    }
  }

  Future<void> _deleteEntity(
    AppDatabase db,
    String entity,
    String localUuid,
  ) async {
    switch (entity) {
      case 'rooms':
        await (db.delete(
          db.rooms,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'bookings':
        await (db.delete(
          db.bookings,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'payments':
        await (db.delete(
          db.payments,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'expenses':
        await (db.delete(
          db.expenses,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'debts':
        await (db.delete(
          db.debts,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'employees':
        await (db.delete(
          db.employees,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'booking_notes':
        await (db.delete(
          db.bookingNotes,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'booking_nights':
        await (db.delete(
          db.bookingNights,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'salary_cycles':
        await (db.delete(
          db.salaryCycles,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'salary_payments':
        await (db.delete(
          db.salaryPayments,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'cash_transactions':
        await (db.delete(
          db.cashTransactions,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'shift_notes':
        await (db.delete(
          db.shiftNotes,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'price_adjustments':
        await (db.delete(
          db.priceAdjustments,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'payment_voids':
        await (db.delete(
          db.paymentVoids,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'audit_logs':
        await (db.delete(
          db.auditLogs,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'booking_price_adjustments':
        await (db.delete(
          db.bookingPriceAdjustments,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
      case 'salary_withdrawals':
        await (db.delete(
          db.salaryWithdrawals,
        )..where((t) => t.localUuid.equals(localUuid))).go();
        return;
    }
  }

  // ignore: unused_element
  Future<void> _applyCashTransactionChange(
    AppDatabase db,
    String localUuid,
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (operation == 'delete') {
      await (db.delete(
        db.cashTransactions,
      )..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }

    final transactionType =
        _asString(data['transaction_type']) ??
        _asString(data['transactionType']);
    if (transactionType == null || transactionType.isEmpty) return;

    final transactionTime =
        _asString(data['transaction_time']) ??
        _asString(data['transactionTime']) ??
        Time.nowIso();

    final companion = CashTransactionsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
        _asInt(data['server_id']) ?? _asInt(data['serverId']),
      ),
      createdAt: d.Value(
        _asInt(data['created_at']) ??
            _asInt(data['createdAt']) ??
            Time.nowEpoch(),
      ),
      updatedAt: d.Value(
        _asInt(data['updated_at']) ??
            _asInt(data['updatedAt']) ??
            Time.nowEpoch(),
      ),
      deletedAt: _nullableValue<int>(
        _asInt(data['deleted_at']) ?? _asInt(data['deletedAt']),
      ),
      lastModified: d.Value(
        _asInt(data['last_modified']) ??
            _asInt(data['lastModified']) ??
            Time.nowEpoch(),
      ),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: const d.Value('google_drive_delta'),
      registerId: _nullableValue<int>(
        _asInt(data['register_id']) ?? _asInt(data['registerId']),
      ),
      transactionType: d.Value(transactionType),
      amount: d.Value(_asDouble(data['amount'])),
      referenceType: _nullableValue<String>(
        _asString(data['reference_type']) ?? _asString(data['referenceType']),
      ),
      referenceId: _nullableValue<int>(
        _asInt(data['reference_id']) ?? _asInt(data['referenceId']),
      ),
      description: _nullableValue<String>(_asString(data['description'])),
      transactionTime: d.Value(transactionTime),
      createdBy: _nullableValue<int>(
        _asInt(data['created_by']) ?? _asInt(data['createdBy']),
      ),
    );
    await db.into(db.cashTransactions).insertOnConflictUpdate(companion);
  }

  d.Value<T?> _nullableValue<T>(T? value) {
    return value == null ? const d.Value.absent() : d.Value(value);
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt();
    }
    return null;
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String && value.isNotEmpty) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    final result = value.toString();
    return result.isEmpty ? null : result;
  }

  Future<int> _getLastPushTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getInt(_prefsLastPushTsKey);
    if (cached != null) return cached;
    final legacy = prefs.getInt(_prefsLegacyLastDeltaSyncKey);
    if (legacy != null) {
      await prefs.setInt(_prefsLastPushTsKey, legacy);
      return legacy;
    }
    return 0;
  }

  Future<int> _getLastPullTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getInt(_prefsLastPullTsKey);
    if (cached != null) return cached;
    final legacy = prefs.getInt(_prefsLegacyLastDeltaSyncKey);
    if (legacy != null) {
      await prefs.setInt(_prefsLastPullTsKey, legacy);
      return legacy;
    }
    return 0;
  }

  Future<void> _updateLastPushTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastPushTsKey, Time.nowEpoch());
  }

  // ignore: unused_element
  Future<void> _updateLastPullTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastPullTsKey, Time.nowEpoch());
  }

  Future<void> cleanupOldDeltaFiles({int keepCount = 10}) async {
    if (_driveService?.isSignedIn != true) return;

    try {
      final deltaFiles = await _listDeltaSyncFiles();
      if (deltaFiles.length <= keepCount) return;

      deltaFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      final toDelete = deltaFiles.skip(keepCount).toList();

      for (final file in toDelete) {
        await _driveService!.deleteBackup(file.fileId);
        debugPrint('🗑️ حذف ملف مزامنة قديم: ${file.fileName}');
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تنظيف ملفات المزامنة: $e');
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    final lastPush = await _getLastPushTimestamp();
    final lastPull = await _getLastPullTimestamp();
    final lastActivity = lastPush > lastPull ? lastPush : lastPull;
    return {
      'initialized': isInitialized,
      'is_syncing': _isSyncing,
      'device_id': _deviceId,
      'last_push_epoch': lastPush,
      'last_pull_epoch': lastPull,
      'last_push_time': lastPush > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              lastPush * 1000,
            ).toIso8601String()
          : null,
      'last_pull_time': lastPull > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              lastPull * 1000,
            ).toIso8601String()
          : null,
      'last_sync_epoch': lastActivity,
      'last_sync_time': lastActivity > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              lastActivity * 1000,
            ).toIso8601String()
          : null,
      'signed_in': _driveService?.isSignedIn ?? false,
    };
  }
}

class DeltaSyncResult {
  DeltaSyncResult({
    required this.success,
    required this.message,
    this.changesCount = 0,
  });
  final bool success;
  final String message;
  final int changesCount;
}
