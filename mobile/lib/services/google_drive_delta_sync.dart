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

enum SyncFileType {
  fullBackup,
  deltaSync,
}

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
  String? _deviceId;
  bool _isSyncing = false;

  static const _prefsLegacyLastDeltaSyncKey = 'gd_last_delta_sync';
  static const _prefsLastPushTsKey = 'gd_last_push_ts';
  static const _prefsLastPullTsKey = 'gd_last_pull_ts';
  static const _prefsDeviceIdKey = 'gd_delta_device_id';

  static const fullBackupPrefix = 'marina_backup_full_';
  static const deltaSyncPrefix = 'marina_sync_delta_';

  Future<void> initialize(
      GoogleDriveBackupService driveService, AppDatabase db) async {
    _driveService = driveService;
    _database = db;
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
          success: false, message: 'الخدمة غير جاهزة أو المزامنة جارية');
    }

    if (canStart == _DeltaSyncStartResult.notSignedIn) {
      return DeltaSyncResult(
          success: false, message: 'غير مسجل الدخول في Google Drive');
    }

    try {
      debugPrint('📤 بدء المزامنة التفاضلية إلى Google Drive...');

      final lastSyncTs = await _getLastPushTimestamp();
      final computation = await _deltaSyncService!.compute(since: lastSyncTs);

      if (computation.changes.isEmpty) {
        debugPrint('✅ لا توجد تغييرات للمزامنة');
        return DeltaSyncResult(
            success: true, message: 'لا توجد تغييرات', changesCount: 0);
      }

      final deltaPayload = _buildDeltaPayload(computation);
      final fileName = _generateDeltaSyncFileName();

      await _uploadDeltaFile(fileName, deltaPayload);
      await _deltaSyncService!.persistMirror(computation);
      await _updateLastPushTimestamp(Time.nowEpoch());

      debugPrint(
          '✅ تم رفع ${computation.changes.length} تغيير إلى Google Drive');

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
            success: true, message: 'لا توجد ملفات مزامنة', changesCount: 0);
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

          final payloadTs = _asInt(deltaData['epoch']) ??
              _asInt(deltaData['syncTimestamp']) ??
              fileTsSec;
          if (payloadTs > maxProcessedTsSec) {
            maxProcessedTsSec = payloadTs;
          } else if (fileTsSec > maxProcessedTsSec) {
            maxProcessedTsSec = fileTsSec;
          }
        } else {
          if (fileTsSec > maxProcessedTsSec) {
            maxProcessedTsSec = fileTsSec;
          }
        }
      }

      await _updateLastPullTimestamp(maxProcessedTsSec);

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
    return '${deltaSyncPrefix}${dateStr}_$timeStr.json';
  }

  Future<void> _uploadDeltaFile(
      String fileName, Map<String, dynamic> payload) async {
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

    return await _database!.transaction(() async {
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
        changes.map((c) => Map<String, dynamic>.from(c as Map)));

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

  Future<void> _applyChange(
      String entity, String operation, Map<String, dynamic> data) async {
    if (_database == null) return;
    final db = _database!;
    final localUuid =
        _asString(data['local_uuid']) ?? _asString(data['localUuid']) ?? '';
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

  Future<void> _applyRoomChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.rooms)..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }
    final roomNumber = _asString(data['room_number']);
    if (roomNumber == null || roomNumber.isEmpty) return;

    final companion = RoomsCompanion(
      roomNumber: d.Value(roomNumber),
      type: d.Value(_asString(data['type']) ?? ''),
      price: data.containsKey('price')
          ? d.Value(_asDouble(data['price']))
          : const d.Value.absent(),
      status: d.Value(_asString(data['status']) ?? 'available'),
      imageUrl: _nullableValue<String>(
          _asString(data['image_url']) ?? _asString(data['imageUrl'])),
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
    );

    final existingByUuid = await (db.select(db.rooms)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();

    if (existingByUuid != null) {
      await (db.update(db.rooms)..where((t) => t.localUuid.equals(localUuid)))
          .write(companion);
      return;
    }

    final existingByNumber = await (db.select(db.rooms)
          ..where((t) => t.roomNumber.equals(roomNumber))
          ..limit(1))
        .getSingleOrNull();

    if (existingByNumber != null) {
      await (db.update(db.rooms)..where((t) => t.roomNumber.equals(roomNumber)))
          .write(companion);
      return;
    }

    try {
      await db.into(db.rooms).insert(companion);
    } catch (_) {
      await (db.update(db.rooms)..where((t) => t.roomNumber.equals(roomNumber)))
          .write(companion);
    }
  }

  Future<void> _applyBookingChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.bookings)
            ..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }
    final roomNumber =
        _asString(data['room_number']) ?? _asString(data['roomNumber']);
    if (roomNumber == null || roomNumber.isEmpty) return;

    final existingRoom = await (db.select(db.rooms)
          ..where((r) => r.roomNumber.equals(roomNumber))
          ..limit(1))
        .getSingleOrNull();

    if (existingRoom == null) {
      final now = Time.nowEpoch();
      await db.into(db.rooms).insertOnConflictUpdate(RoomsCompanion(
        roomNumber: d.Value(roomNumber),
        type: const d.Value(''),
        price: const d.Value(0),
        status: const d.Value('available'),
        localUuid: d.Value(IdGen.uuid()),
        createdAt: d.Value(now),
        updatedAt: d.Value(now),
        lastModified: d.Value(now),
        origin: const d.Value('google_drive_delta'),
      ));
    }

    final companion = BookingsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      serverBookingId: _nullableValue<int>(
          _asInt(data['server_booking_id']) ?? _asInt(data['serverBookingId'])),
      roomNumber: d.Value(roomNumber),
      guestName: d.Value(
          _asString(data['guest_name']) ?? _asString(data['guestName']) ?? ''),
      guestPhone: d.Value(_asString(data['guest_phone']) ??
          _asString(data['guestPhone']) ??
          ''),
      guestIdType: d.Value(_asString(data['guest_id_type']) ??
          _asString(data['guestIdType']) ??
          ''),
      guestIdNumber: d.Value(_asString(data['guest_id_number']) ??
          _asString(data['guestIdNumber']) ??
          ''),
      guestIdIssueDate: _nullableValue<String>(
          _asString(data['guest_id_issue_date']) ??
              _asString(data['guestIdIssueDate'])),
      guestIdIssuePlace: _nullableValue<String>(
          _asString(data['guest_id_issue_place']) ??
              _asString(data['guestIdIssuePlace'])),
      guestNationality: d.Value(_asString(data['guest_nationality']) ??
          _asString(data['guestNationality']) ??
          ''),
      guestEmail: _nullableValue<String>(
          _asString(data['guest_email']) ?? _asString(data['guestEmail'])),
      guestAddress: _nullableValue<String>(
          _asString(data['guest_address']) ?? _asString(data['guestAddress'])),
      checkinDate: d.Value(_asString(data['checkin_date']) ??
          _asString(data['checkinDate']) ??
          ''),
      checkoutDate: _nullableValue<String>(
          _asString(data['checkout_date']) ?? _asString(data['checkoutDate'])),
      actualCheckout: _nullableValue<String>(
          _asString(data['actual_checkout']) ??
              _asString(data['actualCheckout'])),
      status: d.Value(_asString(data['status']) ?? ''),
      notes: _nullableValue<String>(_asString(data['notes'])),
      expectedNights: (data.containsKey('expected_nights') ||
              data.containsKey('expectedNights'))
          ? d.Value(_asInt(data['expected_nights']) ??
              _asInt(data['expectedNights']) ??
              1)
          : const d.Value.absent(),
      calculatedNights: (data.containsKey('calculated_nights') ||
              data.containsKey('calculatedNights'))
          ? d.Value(_asInt(data['calculated_nights']) ??
              _asInt(data['calculatedNights']) ??
              1)
          : const d.Value.absent(),
    );
    await db.into(db.bookings).insertOnConflictUpdate(companion);
  }

  Future<void> _applyPaymentChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.payments)
            ..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }

    final serverBookingId =
        _asInt(data['server_booking_id']) ?? _asInt(data['serverBookingId']);
    final incomingBookingUuid = _asString(data['booking_uuid_cache']) ??
        _asString(data['bookingUuidCache']) ??
        _asString(data['booking_uuid']) ??
        _asString(data['bookingUuid']);

    String? bookingUuidCache;
    int? resolvedBookingLocalId;

    if (incomingBookingUuid != null && incomingBookingUuid.isNotEmpty) {
      bookingUuidCache = incomingBookingUuid;
      final booking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(incomingBookingUuid)))
          .getSingleOrNull();
      resolvedBookingLocalId = booking?.id;
    }

    if (resolvedBookingLocalId == null && serverBookingId != null) {
      final booking = await (db.select(db.bookings)
            ..where((b) => b.serverBookingId.equals(serverBookingId)))
          .getSingleOrNull();
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
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      serverPaymentId: _nullableValue<int>(
          _asInt(data['server_payment_id']) ?? _asInt(data['serverPaymentId'])),
      serverBookingId: _nullableValue<int>(serverBookingId),
      bookingLocalId: resolvedBookingLocalId != null
          ? d.Value(resolvedBookingLocalId)
          : const d.Value.absent(),
      bookingUuidCache: bookingUuidCache != null && bookingUuidCache.isNotEmpty
          ? d.Value(bookingUuidCache)
          : const d.Value.absent(),
      roomNumber: _nullableValue<String>(
          _asString(data['room_number']) ?? _asString(data['roomNumber'])),
      amount: d.Value(_asDouble(data['amount'])),
      paymentDate: d.Value(_asString(data['payment_date']) ??
          _asString(data['paymentDate']) ??
          ''),
      notes: _nullableValue<String>(_asString(data['notes'])),
      paymentMethod: d.Value(_asString(data['payment_method']) ??
          _asString(data['paymentMethod']) ??
          ''),
      revenueType: d.Value(_asString(data['revenue_type']) ??
          _asString(data['revenueType']) ??
          ''),
      hotelDayKey: _nullableValue<String>(
          _asString(data['hotel_day_key']) ?? _asString(data['hotelDayKey'])),
      isPendingBalance: isPendingBalance != null
          ? d.Value(isPendingBalance)
          : const d.Value.absent(),
      linkedDebtUuid: _nullableValue<String>(
          _asString(data['linked_debt_uuid']) ??
              _asString(data['linkedDebtUuid'])),
      cashTransactionLocalId: _nullableValue<int>(
          _asInt(data['cash_transaction_local_id']) ??
              _asInt(data['cashTransactionLocalId'])),
      cashTransactionServerId: _nullableValue<int>(
          _asInt(data['cash_transaction_server_id']) ??
              _asInt(data['cashTransactionServerId'])),
      referenceNumber: _nullableValue<String>(
          _asString(data['reference_number']) ??
              _asString(data['referenceNumber'])),
    );
    await db.into(db.payments).insertOnConflictUpdate(companion);
  }

  Future<void> _applyExpenseChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.expenses)
            ..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }
    final expenseType =
        _asString(data['expense_type']) ?? _asString(data['expenseType']);
    if (expenseType == null || expenseType.isEmpty) return;

    final companion = ExpensesCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      expenseType: d.Value(expenseType),
      relatedId: _nullableValue<int>(
          _asInt(data['related_id']) ?? _asInt(data['relatedId'])),
      description: d.Value(_asString(data['description']) ?? ''),
      amount: d.Value(_asDouble(data['amount'])),
      date: d.Value(_asString(data['date']) ?? ''),
      cashTransactionId: _nullableValue<int>(
          _asInt(data['cash_transaction_id']) ??
              _asInt(data['cashTransactionId'])),
    );
    await db.into(db.expenses).insertOnConflictUpdate(companion);
  }

  Future<void> _applyDebtChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.debts)..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }
    final guestName = _asString(data['guest_name']) ??
        _asString(data['guestName']) ??
        _asString(data['debtor_name']) ??
        _asString(data['debtorName']);
    if (guestName == null || guestName.isEmpty) return;

    final companion = DebtsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      bookingLocalId: _nullableValue<int>(
          _asInt(data['booking_local_id']) ?? _asInt(data['bookingLocalId'])),
      guestName: d.Value(guestName),
      checkinDate: d.Value(_asString(data['checkin_date']) ??
          _asString(data['checkinDate']) ??
          ''),
      checkoutDate: d.Value(_asString(data['checkout_date']) ??
          _asString(data['checkoutDate']) ??
          ''),
      dateRecorded: d.Value(_asString(data['date_recorded']) ??
          _asString(data['dateRecorded']) ??
          ''),
      debtReason: d.Value(_asString(data['debt_reason']) ??
          _asString(data['debtReason']) ??
          ''),
      totalAmount: d.Value(_asDouble(data['total_amount']) ??
          _asDouble(data['totalAmount']) ??
          _asDouble(data['amount'])),
      paidAmount: d.Value(
          _asDouble(data['paid_amount']) ?? _asDouble(data['paidAmount'])),
      remainingAmount: d.Value(_asDouble(data['remaining_amount']) ??
          _asDouble(data['remainingAmount'])),
      paymentDate: d.Value(_asString(data['payment_date']) ??
          _asString(data['paymentDate']) ??
          ''),
      isSettled: d.Value(_asInt(data['is_settled']) ??
          _asInt(data['isSettled']) ??
          (data['status'] == 'settled' ? 1 : 0)),
      pledge: _nullableValue<String>(_asString(data['pledge'])),
      pledgeType: _nullableValue<String>(
          _asString(data['pledge_type']) ?? _asString(data['pledgeType'])),
      note: _nullableValue<String>(_asString(data['note'])),
    );
    await db.into(db.debts).insertOnConflictUpdate(companion);
  }

  Future<void> _applyEmployeeChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.employees)
            ..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }
    final name = _asString(data['name']);
    if (name == null || name.isEmpty) return;

    final companion = EmployeesCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      name: d.Value(name),
      basicSalary: d.Value(
          _asDouble(data['basic_salary']) ?? _asDouble(data['basicSalary'])),
      position: d.Value(_asString(data['position']) ?? ''),
      phone: d.Value(_asString(data['phone']) ?? ''),
      hireDate: d.Value(
          _asString(data['hire_date']) ?? _asString(data['hireDate']) ?? ''),
      status: d.Value(_asString(data['status']) ?? ''),
    );
    await db.into(db.employees).insertOnConflictUpdate(companion);
  }

  Future<void> _applyBookingNoteChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.bookingNotes)
            ..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }

    final bookingId = _asInt(data['booking_id']) ?? _asInt(data['bookingId']);
    final noteText =
        _asString(data['note_text']) ?? _asString(data['noteText']);
    if (bookingId == null || noteText == null) return;

    final alertType = _asString(data['alert_type']) ??
        _asString(data['alertType']) ??
        'general';
    final alertUntil =
        _asString(data['alert_until']) ?? _asString(data['alertUntil']);
    final isActive = _asInt(data['is_active']) ?? _asInt(data['isActive']) ?? 1;

    final companion = BookingNotesCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
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

  Future<void> _applyCashTransactionChange(AppDatabase db, String localUuid,
      String operation, Map<String, dynamic> data) async {
    if (operation == 'delete') {
      await (db.delete(db.cashTransactions)
            ..where((t) => t.localUuid.equals(localUuid)))
          .go();
      return;
    }

    final transactionType = _asString(data['transaction_type']) ??
        _asString(data['transactionType']);
    if (transactionType == null || transactionType.isEmpty) return;

    final transactionTime = _asString(data['transaction_time']) ??
        _asString(data['transactionTime']) ??
        Time.nowIso();

    final companion = CashTransactionsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(
          _asInt(data['server_id']) ?? _asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['created_at']) ??
          _asInt(data['createdAt']) ??
          Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updated_at']) ??
          _asInt(data['updatedAt']) ??
          Time.nowEpoch()),
      deletedAt: _nullableValue<int>(
          _asInt(data['deleted_at']) ?? _asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['last_modified']) ??
          _asInt(data['lastModified']) ??
          Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('google_drive_delta'),
      registerId: _nullableValue<int>(
          _asInt(data['register_id']) ?? _asInt(data['registerId'])),
      transactionType: d.Value(transactionType),
      amount: d.Value(_asDouble(data['amount'])),
      referenceType: _nullableValue<String>(_asString(data['reference_type']) ??
          _asString(data['referenceType'])),
      referenceId: _nullableValue<int>(
          _asInt(data['reference_id']) ?? _asInt(data['referenceId'])),
      description: _nullableValue<String>(_asString(data['description'])),
      transactionTime: d.Value(transactionTime),
      createdBy: _nullableValue<int>(
          _asInt(data['created_by']) ?? _asInt(data['createdBy'])),
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

  Future<void> _updateLastPushTimestamp(int timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastPushTsKey, timestamp);
    await prefs.setInt(_prefsLegacyLastDeltaSyncKey, timestamp);
  }

  Future<void> _updateLastPullTimestamp(int timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastPullTsKey, timestamp);
    await prefs.setInt(_prefsLegacyLastDeltaSyncKey, timestamp);
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
          ? DateTime.fromMillisecondsSinceEpoch(lastPush * 1000)
              .toIso8601String()
          : null,
      'last_pull_time': lastPull > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastPull * 1000)
              .toIso8601String()
          : null,
      'last_sync_epoch': lastActivity,
      'last_sync_time': lastActivity > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastActivity * 1000)
              .toIso8601String()
          : null,
      'signed_in': _driveService?.isSignedIn ?? false,
    };
  }
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
