import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as d;

import 'delta_sync_service.dart';
import 'google_drive_backup_service.dart';
import 'local_db.dart';
import 'sync_constants.dart';
import '../utils/time.dart';
import 'device_identity.dart';
import 'sync_locks.dart';

const _kDeltaLogVersion = 1;
const _kDeltaLogFileName = 'marina_sync_delta_log.json';
const _kMaxLogEntries = 250;
const Duration _kLogRetention = Duration(days: 14);
const int _kLegacyCleanupIntervalSeconds = 6 * 3600;

enum _DeltaSyncStartResult {
  ok,
  notInitialized,
  alreadySyncing,
  notSignedIn,
}

class GoogleDriveDeltaSync {
  GoogleDriveDeltaSync._();
  static final instance = GoogleDriveDeltaSync._();

  GoogleDriveBackupService? _driveService;
  DeltaSyncService? _deltaSyncService;
  AppDatabase? _database;
  VectorClockDao? _vectorClockDao;
  String? _deviceId;
  String? _deltaLogFileId;
  bool _isSyncing = false;
  bool _mirrorReady = false;

  static const _prefsLegacyLastDeltaSyncKey = 'gd_last_delta_sync';
  static const _prefsLastPushTsKey = 'gd_last_push_ts';
  static const _prefsLastPullTsKey = 'gd_last_pull_ts';
  static const _prefsDeviceIdKey = 'gd_delta_device_id';
  static const _prefsDeltaLogFileIdKey = 'gd_delta_log_file_id';
  static const _prefsLastAppliedSeqKey = 'gd_last_applied_seq';
  static const _prefsLastCleanupTsKey = 'gd_legacy_delta_cleanup_ts';

  static const fullBackupPrefix = 'marina_backup_full_';
  static const deltaSyncPrefix = 'marina_sync_delta_';

  Future<void> initialize(GoogleDriveBackupService driveService, AppDatabase db) async {
    _driveService = driveService;
    _database = db;
    _deltaSyncService = DeltaSyncService(db);
    _vectorClockDao = VectorClockDao(db);
    await _initializeDeviceId();
    await _ensureMirrorTable();
    debugPrint('✅ تم تهيئة خدمة المزامنة التفاضلية لـ Google Drive');
  }

  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = await DeviceIdentity.ensure();
    await prefs.setString(_prefsDeviceIdKey, _deviceId!);
  }

  bool get isInitialized => _driveService != null && _deltaSyncService != null && _database != null;
  bool get isSyncing => _isSyncing;
  String? get deviceId => _deviceId;

  Future<DeltaSyncResult> pushDeltaChanges() async {
    final canStart = await SyncLocks.deltaSyncLock.synchronized(() async {
      if (!isInitialized) return _DeltaSyncStartResult.notInitialized;
      if (_isSyncing) return _DeltaSyncStartResult.alreadySyncing;
      if (_driveService?.isSignedIn != true) return _DeltaSyncStartResult.notSignedIn;
      _isSyncing = true;
      return _DeltaSyncStartResult.ok;
    });

    if (canStart == _DeltaSyncStartResult.notInitialized || canStart == _DeltaSyncStartResult.alreadySyncing) {
      return DeltaSyncResult(success: false, message: 'الخدمة غير جاهزة أو المزامنة جارية');
    }

    if (canStart == _DeltaSyncStartResult.notSignedIn) {
      return DeltaSyncResult(success: false, message: 'غير مسجل الدخول في Google Drive');
    }

    try {
      debugPrint('📤 بدء المزامنة التفاضلية إلى Google Drive...');
      final lastSyncTs = await _getLastPushTimestamp();
      final computation = await _deltaSyncService!.compute(since: lastSyncTs);

      if (computation.changes.isEmpty) {
        debugPrint('✅ لا توجد تغييرات للمزامنة');
        await _deltaSyncService!.persistMirror(computation);
        return DeltaSyncResult(success: true, message: 'لا توجد تغييرات', changesCount: 0);
      }

      final entry = _DeltaLogEntry(
        seq: -1,
        deviceId: _deviceId ?? 'unknown',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        changes: computation.toPayload(),
        fallbackTables: computation.fallbackTables.toList(),
        metadata: {
          'changes_count': computation.changes.length,
        },
      );

      final appendedSeq = await _appendEntryToLog(entry);
      await _deltaSyncService!.persistMirror(computation);
      await _updateLastPushTimestamp();
      await _cleanupLegacyDeltaFiles();

      debugPrint('✅ تم رفع ${computation.changes.length} تغيير (seq=$appendedSeq) إلى Google Drive');
      return DeltaSyncResult(
        success: true,
        message: 'تم رفع التغييرات بنجاح',
        changesCount: computation.changes.length,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في رفع التغييرات: $e');
      debugPrint('🔍 Stack trace: $stackTrace');
      return DeltaSyncResult(success: false, message: 'خطأ في رفع التغييرات: $e');
    } finally {
      await SyncLocks.deltaSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  Future<DeltaSyncResult> pullDeltaChanges() async {
    final canStart = await SyncLocks.deltaSyncLock.synchronized(() async {
      if (!isInitialized) return _DeltaSyncStartResult.notInitialized;
      if (_isSyncing) return _DeltaSyncStartResult.alreadySyncing;
      if (_driveService?.isSignedIn != true) return _DeltaSyncStartResult.notSignedIn;
      _isSyncing = true;
      return _DeltaSyncStartResult.ok;
    });

    if (canStart == _DeltaSyncStartResult.notInitialized || canStart == _DeltaSyncStartResult.alreadySyncing) {
      return DeltaSyncResult(success: false, message: 'الخدمة غير جاهزة');
    }

    if (canStart == _DeltaSyncStartResult.notSignedIn) {
      return DeltaSyncResult(success: false, message: 'غير مسجل الدخول');
    }

    try {
      debugPrint('📥 فحص التغييرات من سجل Google Drive...');
      final logState = await _loadDeltaLogState();
      final lastAppliedSeq = await _getLastAppliedSeq();

      if (lastAppliedSeq < logState.compactedUntil) {
        await _setLastAppliedSeq(logState.compactedUntil);
        throw DeltaLogGapException(logState.compactedUntil);
      }

      final pendingEntries = logState.entries
          .where((entry) => entry.seq > lastAppliedSeq && entry.deviceId != _deviceId)
          .toList()
        ..sort((a, b) => a.seq.compareTo(b.seq));

      if (pendingEntries.isEmpty) {
        return DeltaSyncResult(success: true, message: 'لا توجد تغييرات جديدة', changesCount: 0);
      }

      int appliedChanges = 0;
      for (final entry in pendingEntries) {
        final appliedFromEntry = await _applyDeltaEntry(entry);
        appliedChanges += appliedFromEntry;
        await _setLastAppliedSeq(entry.seq);
      }

      if (appliedChanges > 0) {
        await _updateLastPullTimestamp();
      }

      await _cleanupLegacyDeltaFiles();
      return DeltaSyncResult(
        success: true,
        message: 'تم تطبيق $appliedChanges تغيير',
        changesCount: appliedChanges,
      );
    } on DeltaLogGapException catch (gap) {
      final message = 'تم تنظيف سجل المزامنة قبل معالجة جميع التغييرات (seq <= ${gap.missingUntil}). يلزم تنفيذ مزامنة كاملة.';
      debugPrint('⚠️ $message');
      return DeltaSyncResult(success: false, message: message);
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');
      debugPrint('🔍 Stack trace: $stackTrace');
      return DeltaSyncResult(success: false, message: 'خطأ في سحب التغييرات: $e');
    } finally {
      await SyncLocks.deltaSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  Future<int> _appendEntryToLog(_DeltaLogEntry entry) async {
    return _mutateDeltaLog<int>((state) async {
      final nextSeq = state.nextSeq;
      entry.seq = nextSeq;
      state.entries.add(entry);
      state.nextSeq = nextSeq + 1;
      state.updatedAt = DateTime.now().toUtc();
      return entry.seq;
    });
  }

  Future<T> _mutateDeltaLog<T>(Future<T> Function(_DeltaLogState) mutator) async {
    var attempts = 0;
    while (attempts < 3) {
      final state = await _loadDeltaLogState();
      final result = await mutator(state);
      state.compact(maxEntries: _kMaxLogEntries, maxAge: _kLogRetention);
      final bytes = utf8.encode(jsonEncode(state.toJson()));
      try {
        await _driveService!.uploadJsonWithIfMatch(
          fileId: state.fileId,
          bytes: bytes,
          etag: state.etag,
        );
        return result;
      } on DrivePreconditionFailed {
        attempts += 1;
        await Future.delayed(Duration(milliseconds: 200 * attempts));
      } on DriveFileNotFound {
        await _forgetDeltaLogFileId();
        await _createDeltaLogFile();
      }
    }
    throw DrivePreconditionFailed('تعذر تحديث سجل المزامنة بعد عدة محاولات');
  }

  Future<_DeltaLogState> _loadDeltaLogState() async {
    final fileId = await _ensureDeltaLogFileId();
    DriveFileContent content;
    try {
      content = await _driveService!.downloadFileWithEtag(fileId);
    } on DriveFileNotFound {
      await _forgetDeltaLogFileId();
      await _createDeltaLogFile();
      return _loadDeltaLogState();
    }

    try {
      return _DeltaLogState.fromBytes(
        fileId: fileId,
        bytes: content.bytes,
        etag: content.etag,
      );
    } catch (_) {
      await _resetDeltaLogFile(fileId: fileId, etag: content.etag);
      return _loadDeltaLogState();
    }
  }

  Future<void> _resetDeltaLogFile({required String fileId, String? etag}) async {
    final payload = _buildEmptyLogPayload();
    final bytes = utf8.encode(jsonEncode(payload));
    await _driveService!.uploadJsonWithIfMatch(fileId: fileId, bytes: bytes, etag: etag);
  }

  Map<String, dynamic> _buildEmptyLogPayload() {
    return {
      'version': _kDeltaLogVersion,
      'next_seq': 1,
      'compacted_until': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'entries': <Map<String, dynamic>>[],
    };
  }

  Future<String> _ensureDeltaLogFileId() async {
    if (_deltaLogFileId != null) {
      return _deltaLogFileId!;
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsDeltaLogFileIdKey);
    if (cached != null) {
      try {
        await _driveService!.getFileById(cached);
        _deltaLogFileId = cached;
        return cached;
      } catch (_) {
        await prefs.remove(_prefsDeltaLogFileIdKey);
      }
    }

    final existing = await _driveService!.findFileByName(_kDeltaLogFileName);
    if (existing != null) {
      _deltaLogFileId = existing.fileId;
      await prefs.setString(_prefsDeltaLogFileIdKey, existing.fileId);
      return existing.fileId;
    }

    await _createDeltaLogFile();
    return _deltaLogFileId!;
  }

  Future<void> _createDeltaLogFile() async {
    final payload = _buildEmptyLogPayload();
    final bytes = utf8.encode(jsonEncode(payload));
    final fileId = await _driveService!.uploadBackupWithName(
      _kDeltaLogFileName,
      bytes,
      appProperties: {
        'type': 'delta_log',
        'version': _kDeltaLogVersion.toString(),
      },
    );
    _deltaLogFileId = fileId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeltaLogFileIdKey, fileId);
  }

  Future<void> _forgetDeltaLogFileId() async {
    _deltaLogFileId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsDeltaLogFileIdKey);
  }

  Future<int> _applyDeltaEntry(_DeltaLogEntry entry) async {
    final db = _database!;
    return await db.transaction(() async {
      await _ensureMirrorTable();
      final sortedChanges = _sortChangesByDependency(entry.changes);
      int applied = 0;

      for (final change in sortedChanges) {
        final entity = change['entity']?.toString();
        final op = change['op']?.toString() ?? 'update';
        if (entity == null || entity.isEmpty) continue;
        final rawData = change['data'];
        if (rawData is! Map) continue;
        final data = Map<String, dynamic>.from(rawData as Map);
        final localUuid = _asString(change['local_uuid']) ?? _asString(data['local_uuid']) ?? _asString(data['localUuid']) ?? '';
        if (localUuid.isEmpty) continue;

        await _applyChange(entity, op, data);
        await _syncVectorClock(entity, localUuid, op, data);

        final rowHash = _asString(change['row_hash']) ?? _asString(data['row_hash']) ?? _computePayloadHash(data);
        final payloadForMirror = Map<String, dynamic>.from(data)
          ..['local_uuid'] = localUuid
          ..['row_hash'] = rowHash;
        await _upsertMirrorRow(entity, localUuid, payloadForMirror, rowHash);
        applied++;
      }

      return applied;
    });
  }

  Future<void> _syncVectorClock(String entity, String localUuid, String operation, Map<String, dynamic> data) async {
    final dao = _vectorClockDao;
    if (dao == null) return;
    if (operation == 'delete') {
      await dao.deleteClock(entity, localUuid);
      return;
    }
    final vectorClock = data['vector_clock'];
    if (vectorClock == null) return;
    final clockString = vectorClock is String ? vectorClock : jsonEncode(vectorClock);
    if (clockString.isEmpty) return;
    await dao.upsertClock(entity, localUuid, clockString);
  }

  Future<void> _upsertMirrorRow(String entity, String localUuid, Map<String, dynamic> payload, String rowHash) async {
    if (_database == null) return;
    await _ensureMirrorTable();
    final db = _database!;
    await db.customStatement(
      'REPLACE INTO sync_mirror (table_name, local_uuid, row_hash, payload, last_seen_at) VALUES (?, ?, ?, ?, ?)',
      [
        entity,
        localUuid,
        rowHash,
        jsonEncode(payload),
        Time.nowEpoch(),
      ],
    );
  }

  Future<void> _ensureMirrorTable() async {
    if (_mirrorReady || _database == null) {
      if (_mirrorReady) return;
    }
    await _database!.customStatement(
      'CREATE TABLE IF NOT EXISTS sync_mirror (table_name TEXT NOT NULL, local_uuid TEXT NOT NULL, row_hash TEXT NOT NULL, payload TEXT NOT NULL, last_seen_at INTEGER NOT NULL, PRIMARY KEY(table_name, local_uuid))',
    );
    _mirrorReady = true;
  }

  Future<void> _cleanupLegacyDeltaFiles({bool force = false}) async {
    if (_driveService?.isSignedIn != true) return;
    final prefs = await SharedPreferences.getInstance();
    final now = Time.nowEpoch();
    final lastCleanup = prefs.getInt(_prefsLastCleanupTsKey) ?? 0;
    if (!force && (now - lastCleanup) < _kLegacyCleanupIntervalSeconds) {
      return;
    }

    try {
      final files = await _driveService!.listBackupFiles();
      final legacyFiles = files.where((f) => f.fileName.startsWith(deltaSyncPrefix)).toList();
      for (final file in legacyFiles) {
        await _driveService!.deleteBackup(file.fileId);
        debugPrint('🧹 حذف ملف دلتا قديم: ${file.fileName}');
      }
      await prefs.setInt(_prefsLastCleanupTsKey, now);
    } catch (e) {
      debugPrint('⚠️ فشل تنظيف ملفات الدلتا القديمة: $e');
    }
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

  Future<void> _updateLastPullTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastPullTsKey, Time.nowEpoch());
  }

  Future<int> _getLastAppliedSeq() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsLastAppliedSeqKey) ?? 0;
  }

  Future<void> _setLastAppliedSeq(int seq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastAppliedSeqKey, seq);
  }

  List<Map<String, dynamic>> _sortChangesByDependency(List<Map<String, dynamic>> changes) {
    final changesList = List<Map<String, dynamic>>.from(changes.map((c) => Map<String, dynamic>.from(c)));

    final deletes = <Map<String, dynamic>>[];
    final nonDeletes = <Map<String, dynamic>>[];

    for (final change in changesList) {
      final op = change['op'] as String?;
      if (op == 'delete') {
        deletes.add(change);
      } else {
        nonDeletes.add(change);
      }
    }

    nonDeletes.sort((a, b) {
      final aOrder = _getTableOrderIndex(a['entity'] as String? ?? '');
      final bOrder = _getTableOrderIndex(b['entity'] as String? ?? '');
      return aOrder.compareTo(bOrder);
    });

    deletes.sort((a, b) {
      final aOrder = _getTableOrderIndex(a['entity'] as String? ?? '');
      final bOrder = _getTableOrderIndex(b['entity'] as String? ?? '');
      return bOrder.compareTo(aOrder);
    });

    return [...nonDeletes, ...deletes];
  }

  int _getTableOrderIndex(String entity) {
    final index = SyncConstants.tableOrder.indexOf(entity);
    return index == -1 ? 999 : index;
  }

  Future<void> _applyChange(String entity, String operation, Map<String, dynamic> data) async {
    if (_database == null) return;
    final db = _database!;
    final localUuid = _asString(data['local_uuid']) ?? _asString(data['localUuid']) ?? '';
    if (localUuid.isEmpty) return;

    debugPrint('🔄 تطبيق $operation على $entity/$localUuid');

    switch (entity) {
      case 'rooms':
        await _applyRoomChange(db, localUuid, operation, data);
        break;
      case 'bookings':
        await _applyBookingChange(db, localUuid, operation, data);
        break;
      case 'payments':
        await _applyPaymentChange(db, localUuid, operation, data);
        break;
      case 'expenses':
        await _applyExpenseChange(db, localUuid, operation, data);
        break;
      case 'debts':
        await _applyDebtChange(db, localUuid, operation, data);
        break;
      case 'employees':
        await _applyEmployeeChange(db, localUuid, operation, data);
        break;
      case 'booking_notes':
        await _applyBookingNoteChange(db, localUuid, operation, data);
        break;
      case 'cash_transactions':
        await _applyCashTransactionChange(db, localUuid, operation, data);
        break;
    }
  }

  Future<void> _applyRoomChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.rooms)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }
    final roomNumber = _asString(data['room_number']) ?? _asString(data['roomNumber']);
    if (roomNumber == null || roomNumber.isEmpty) return;

    final companion = RoomsCompanion(
      roomNumber: d.Value(roomNumber),
      type: d.Value(_asString(data['type']) ?? ''),
      price: d.Value(_asDouble(data['price'])),
      status: d.Value(_asString(data['status']) ?? 'available'),
      imageUrl: _nullableValue<String>(_asString(data['image_url']) ?? _asString(data['imageUrl'])),
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
    );
    await db.into(db.rooms).insertOnConflictUpdate(companion);
  }

  Future<void> _applyBookingChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.bookings)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }
    final roomNumber = _asString(data['room_number']) ?? _asString(data['roomNumber']);
    if (roomNumber == null || roomNumber.isEmpty) return;

    final companion = BookingsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      serverBookingId: _nullableValue<int>(_asInt(data['server_booking_id']) ?? _asInt(data['serverBookingId'])),
      roomNumber: d.Value(roomNumber),
      guestName: d.Value(_asString(data['guest_name']) ?? _asString(data['guestName']) ?? ''),
      guestPhone: d.Value(_asString(data['guest_phone']) ?? _asString(data['guestPhone']) ?? ''),
      guestIdType: d.Value(_asString(data['guest_id_type']) ?? _asString(data['guestIdType']) ?? ''),
      guestIdNumber: d.Value(_asString(data['guest_id_number']) ?? _asString(data['guestIdNumber']) ?? ''),
      guestIdIssueDate: _nullableValue<String>(_asString(data['guest_id_issue_date']) ?? _asString(data['guestIdIssueDate'])),
      guestIdIssuePlace: _nullableValue<String>(_asString(data['guest_id_issue_place']) ?? _asString(data['guestIdIssuePlace'])),
      guestNationality: d.Value(_asString(data['guest_nationality']) ?? _asString(data['guestNationality']) ?? ''),
      guestEmail: _nullableValue<String>(_asString(data['guest_email']) ?? _asString(data['guestEmail'])),
      guestAddress: _nullableValue<String>(_asString(data['guest_address']) ?? _asString(data['guestAddress'])),
      checkinDate: d.Value(_asString(data['checkin_date']) ?? _asString(data['checkinDate']) ?? ''),
      checkoutDate: _nullableValue<String>(_asString(data['checkout_date']) ?? _asString(data['checkoutDate'])),
      actualCheckout: _nullableValue<String>(_asString(data['actual_checkout']) ?? _asString(data['actualCheckout'])),
      status: d.Value(_asString(data['status']) ?? ''),
      notes: _nullableValue<String>(_asString(data['notes'])),
      expectedNights: d.Value(_asInt(data['expected_nights']) ?? _asInt(data['expectedNights']) ?? 1),
      calculatedNights: d.Value(_asInt(data['calculated_nights']) ?? _asInt(data['calculatedNights']) ?? 1),
    );
    await db.into(db.bookings).insertOnConflictUpdate(companion);
  }

  Future<void> _applyPaymentChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.payments)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }

    final serverBookingId = _asInt(data['server_booking_id']) ?? _asInt(data['serverBookingId']);
    final incomingBookingUuid = _asString(data['booking_uuid_cache']) ??
        _asString(data['bookingUuidCache']) ??
        _asString(data['booking_uuid']) ??
        _asString(data['bookingUuid']);

    String? bookingUuidCache;
    int? resolvedBookingLocalId;

    if (incomingBookingUuid != null && incomingBookingUuid.isNotEmpty) {
      bookingUuidCache = incomingBookingUuid;
      final booking = await (db.select(db.bookings)..where((b) => b.localUuid.equals(incomingBookingUuid))).getSingleOrNull();
      resolvedBookingLocalId = booking?.id;
    }

    if (resolvedBookingLocalId == null && serverBookingId != null) {
      final booking = await (db.select(db.bookings)..where((b) => b.serverBookingId.equals(serverBookingId))).getSingleOrNull();
      resolvedBookingLocalId = booking?.id;
      bookingUuidCache = bookingUuidCache ?? booking?.localUuid;
    }

    dynamic pendingRaw = data['is_pending_balance'] ?? data['isPendingBalance'];
    bool? isPendingBalance;
    if (pendingRaw is bool) {
      isPendingBalance = pendingRaw;
    } else if (pendingRaw is num) {
      isPendingBalance = pendingRaw != 0;
    } else if (pendingRaw is String && pendingRaw.isNotEmpty) {
      final v = pendingRaw.toLowerCase();
      isPendingBalance = v == '1' || v == 'true' || v == 'yes';
    }

    final companion = PaymentsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      serverPaymentId: _nullableValue<int>(_asInt(data['server_payment_id']) ?? _asInt(data['serverPaymentId'])),
      serverBookingId: _nullableValue<int>(serverBookingId),
      bookingLocalId: resolvedBookingLocalId != null ? d.Value(resolvedBookingLocalId) : const d.Value.absent(),
      bookingUuidCache: bookingUuidCache != null && bookingUuidCache.isNotEmpty ? d.Value(bookingUuidCache) : const d.Value.absent(),
      roomNumber: _nullableValue<String>(_asString(data['room_number']) ?? _asString(data['roomNumber'])),
      amount: d.Value(_asDouble(data['amount'])),
      paymentDate: d.Value(_asString(data['payment_date']) ?? _asString(data['paymentDate']) ?? ''),
      notes: _nullableValue<String>(_asString(data['notes'])),
      paymentMethod: d.Value(_asString(data['payment_method']) ?? _asString(data['paymentMethod']) ?? ''),
      revenueType: d.Value(_asString(data['revenue_type']) ?? _asString(data['revenueType']) ?? ''),
      hotelDayKey: _nullableValue<String>(_asString(data['hotel_day_key']) ?? _asString(data['hotelDayKey'])),
      isPendingBalance: isPendingBalance != null ? d.Value(isPendingBalance) : const d.Value.absent(),
      linkedDebtUuid: _nullableValue<String>(_asString(data['linked_debt_uuid']) ?? _asString(data['linkedDebtUuid'])),
      cashTransactionLocalId: _nullableValue<int>(_asInt(data['cash_transaction_local_id']) ?? _asInt(data['cashTransactionLocalId'])),
      cashTransactionServerId: _nullableValue<int>(_asInt(data['cash_transaction_server_id']) ?? _asInt(data['cashTransactionServerId'])),
      referenceNumber: _nullableValue<String>(_asString(data['reference_number']) ?? _asString(data['referenceNumber'])),
    );
    await db.into(db.payments).insertOnConflictUpdate(companion);
  }

  Future<void> _applyExpenseChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.expenses)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }
    final expenseType = _asString(data['expense_type']) ?? _asString(data['expenseType']);
    if (expenseType == null || expenseType.isEmpty) return;

    final companion = ExpensesCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      expenseType: d.Value(expenseType),
      relatedId: _nullableValue<int>(_asInt(data['related_id']) ?? _asInt(data['relatedId'])),
      description: d.Value(_asString(data['description']) ?? ''),
      amount: d.Value(_asDouble(data['amount'])),
      date: d.Value(_asString(data['date']) ?? ''),
      cashTransactionId: _nullableValue<int>(_asInt(data['cash_transaction_id']) ?? _asInt(data['cashTransactionId'])),
    );
    await db.into(db.expenses).insertOnConflictUpdate(companion);
  }

  Future<void> _applyDebtChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.debts)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }
    final guestName = _asString(data['guest_name']) ??
        _asString(data['guestName']) ??
        _asString(data['debtor_name']) ??
        _asString(data['debtorName']);
    if (guestName == null || guestName.isEmpty) return;

    final companion = DebtsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      bookingLocalId: _nullableValue<int>(_asInt(data['booking_local_id']) ?? _asInt(data['bookingLocalId'])),
      guestName: d.Value(guestName),
      checkinDate: d.Value(_asString(data['checkin_date']) ?? _asString(data['checkinDate']) ?? ''),
      checkoutDate: d.Value(_asString(data['checkout_date']) ?? _asString(data['checkoutDate']) ?? ''),
      dateRecorded: d.Value(_asString(data['date_recorded']) ?? _asString(data['dateRecorded']) ?? ''),
      debtReason: d.Value(_asString(data['debt_reason']) ?? _asString(data['debtReason']) ?? ''),
      totalAmount: d.Value(_asDouble(data['total_amount']) ?? _asDouble(data['totalAmount']) ?? _asDouble(data['amount'])),
      paidAmount: d.Value(_asDouble(data['paid_amount']) ?? _asDouble(data['paidAmount'])),
      remainingAmount: d.Value(_asDouble(data['remaining_amount']) ?? _asDouble(data['remainingAmount'])),
      paymentDate: d.Value(_asString(data['payment_date']) ?? _asString(data['paymentDate']) ?? ''),
      isSettled: d.Value(_asInt(data['is_settled']) ?? _asInt(data['isSettled']) ?? (data['status'] == 'settled' ? 1 : 0)),
      pledge: _nullableValue<String>(_asString(data['pledge'])),
      pledgeType: _nullableValue<String>(_asString(data['pledge_type']) ?? _asString(data['pledgeType'])),
      note: _nullableValue<String>(_asString(data['note'])),
    );
    await db.into(db.debts).insertOnConflictUpdate(companion);
  }

  Future<void> _applyEmployeeChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.employees)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }
    final name = _asString(data['name']);
    if (name == null || name.isEmpty) return;

    final companion = EmployeesCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      name: d.Value(name),
      basicSalary: d.Value(_asDouble(data['basic_salary']) ?? _asDouble(data['basicSalary'])),
      position: d.Value(_asString(data['position']) ?? ''),
      phone: d.Value(_asString(data['phone']) ?? ''),
      hireDate: d.Value(_asString(data['hire_date']) ?? _asString(data['hireDate']) ?? ''),
      status: d.Value(_asString(data['status']) ?? ''),
    );
    await db.into(db.employees).insertOnConflictUpdate(companion);
  }

  Future<void> _applyBookingNoteChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.bookingNotes)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }

    final bookingId = _asInt(data['booking_id']) ?? _asInt(data['bookingId']);
    final noteText = _asString(data['note_text']) ?? _asString(data['noteText']);
    if (bookingId == null || noteText == null) return;

    final alertType = _asString(data['alert_type']) ?? _asString(data['alertType']) ?? 'general';
    final alertUntil = _asString(data['alert_until']) ?? _asString(data['alertUntil']);
    final isActive = _asInt(data['is_active']) ?? _asInt(data['isActive']) ?? 1;

    final companion = BookingNotesCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      bookingId: d.Value(bookingId),
      noteText: d.Value(noteText),
      alertType: d.Value(alertType),
      alertUntil: _nullableValue<String>(alertUntil),
      isActive: d.Value(isActive),
    );
    await db.into(db.bookingNotes).insertOnConflictUpdate(companion);
  }

  Future<void> _applyCashTransactionChange(AppDatabase db, String localUuid, String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.cashTransactions)..where((t) => t.localUuid.equals(localUuid))).go();
      return;
    }

    final transactionType = _asString(data['transaction_type']) ?? _asString(data['transactionType']);
    if (transactionType == null || transactionType.isEmpty) return;

    final transactionTime = _asString(data['transaction_time']) ?? _asString(data['transactionTime']) ?? Time.nowIso();

    final companion = CashTransactionsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ?? _asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ?? _asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ?? _asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      registerId: _nullableValue<int>(_asInt(data['register_id']) ?? _asInt(data['registerId'])),
      transactionType: d.Value(transactionType),
      amount: d.Value(_asDouble(data['amount'])),
      referenceType: _nullableValue<String>(_asString(data['reference_type']) ?? _asString(data['referenceType'])),
      referenceId: _nullableValue<int>(_asInt(data['reference_id']) ?? _asInt(data['referenceId'])),
      description: _nullableValue<String>(_asString(data['description'])),
      transactionTime: d.Value(transactionTime),
      createdBy: _nullableValue<int>(_asInt(data['created_by']) ?? _asInt(data['createdBy'])),
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

  String _computePayloadHash(Map<String, dynamic> payload) {
    final normalized = jsonEncode(payload);
    return crypto.md5.convert(utf8.encode(normalized)).toString();
  }

  Future<void> cleanupOldDeltaFiles({int keepCount = 10}) async {
    await _cleanupLegacyDeltaFiles(force: true);
  }

  Future<Map<String, dynamic>> getStatus() async {
    final lastPush = await _getLastPushTimestamp();
    final lastPull = await _getLastPullTimestamp();
    final lastSeq = await _getLastAppliedSeq();
    final lastActivity = lastPush > lastPull ? lastPush : lastPull;
    return {
      'initialized': isInitialized,
      'is_syncing': _isSyncing,
      'device_id': _deviceId,
      'last_push_epoch': lastPush,
      'last_pull_epoch': lastPull,
      'last_push_time': lastPush > 0 ? DateTime.fromMillisecondsSinceEpoch(lastPush * 1000).toIso8601String() : null,
      'last_pull_time': lastPull > 0 ? DateTime.fromMillisecondsSinceEpoch(lastPull * 1000).toIso8601String() : null,
      'last_sync_epoch': lastActivity,
      'last_sync_time': lastActivity > 0 ? DateTime.fromMillisecondsSinceEpoch(lastActivity * 1000).toIso8601String() : null,
      'last_applied_seq': lastSeq,
      'delta_log_file_id': _deltaLogFileId,
      'signed_in': _driveService?.isSignedIn ?? false,
    };
  }
}

class _DeltaLogEntry {
  _DeltaLogEntry({
    required this.seq,
    required this.deviceId,
    required this.timestamp,
    required this.changes,
    required this.fallbackTables,
    this.metadata,
  });

  int seq;
  final String deviceId;
  final String timestamp;
  final List<Map<String, dynamic>> changes;
  final List<String> fallbackTables;
  final Map<String, dynamic>? metadata;

  factory _DeltaLogEntry.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'] as List<dynamic>? ?? const [];
    return _DeltaLogEntry(
      seq: json['seq'] is int ? json['seq'] as int : int.tryParse(json['seq']?.toString() ?? '') ?? 0,
      deviceId: json['device_id']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      changes: rawChanges.map((entry) => Map<String, dynamic>.from(entry as Map)).toList(),
      fallbackTables: List<String>.from((json['fallback_tables'] as List<dynamic>? ?? []).map((e) => e.toString())),
      metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seq': seq,
      'device_id': deviceId,
      'timestamp': timestamp,
      'changes': changes,
      if (fallbackTables.isNotEmpty) 'fallback_tables': fallbackTables,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    };
  }

  DateTime? get parsedTimestamp => DateTime.tryParse(timestamp);
}

class _DeltaLogState {
  _DeltaLogState({
    required this.fileId,
    required this.entries,
    required this.nextSeq,
    required this.compactedUntil,
    required this.updatedAt,
    required this.etag,
  });

  final String fileId;
  List<_DeltaLogEntry> entries;
  int nextSeq;
  int compactedUntil;
  DateTime updatedAt;
  final String? etag;

  factory _DeltaLogState.fromBytes({required String fileId, required List<int> bytes, String? etag}) {
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final rawEntries = decoded['entries'] as List<dynamic>? ?? const [];
    final entries = rawEntries
        .map((entry) => _DeltaLogEntry.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));

    final nextSeqRaw = decoded['next_seq'];
    final compactedRaw = decoded['compacted_until'];
    final updatedRaw = decoded['updated_at']?.toString();

    return _DeltaLogState(
      fileId: fileId,
      entries: entries,
      nextSeq: nextSeqRaw is int
          ? nextSeqRaw
          : int.tryParse(nextSeqRaw?.toString() ?? '') ?? (entries.isEmpty ? 1 : entries.last.seq + 1),
      compactedUntil: compactedRaw is int ? compactedRaw : int.tryParse(compactedRaw?.toString() ?? '') ?? 0,
      updatedAt: DateTime.tryParse(updatedRaw ?? '') ?? DateTime.now().toUtc(),
      etag: etag,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': _kDeltaLogVersion,
      'next_seq': nextSeq,
      'compacted_until': compactedUntil,
      'updated_at': updatedAt.toIso8601String(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  void compact({required int maxEntries, required Duration maxAge}) {
    entries.sort((a, b) => a.seq.compareTo(b.seq));
    final cutoff = DateTime.now().toUtc().subtract(maxAge);
    var trimmedSeq = compactedUntil;
    final retained = <_DeltaLogEntry>[];

    for (final entry in entries) {
      final ts = entry.parsedTimestamp;
      if (ts != null && ts.isBefore(cutoff)) {
        trimmedSeq = entry.seq;
        continue;
      }
      retained.add(entry);
    }

    entries = retained;

    if (entries.length > maxEntries) {
      final dropCount = entries.length - maxEntries;
      final dropped = entries.sublist(0, dropCount);
      if (dropped.isNotEmpty) {
        trimmedSeq = dropped.last.seq;
      }
      entries = entries.sublist(dropCount);
    }

    if (trimmedSeq > compactedUntil) {
      compactedUntil = trimmedSeq;
    }

    updatedAt = DateTime.now().toUtc();
  }
}

class DeltaLogGapException implements Exception {
  DeltaLogGapException(this.missingUntil);
  final int missingUntil;
  @override
  String toString() => 'DeltaLogGapException: missing entries up to seq $missingUntil';
}

class DeltaSyncResult {
  final bool success;
  final String message;
  final int changesCount;

  DeltaSyncResult({
    required this.success,
    required this.message,
    this.changesCount = 0,
  });
}
