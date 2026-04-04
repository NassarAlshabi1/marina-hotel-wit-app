import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as d;
import 'package:appwrite/appwrite.dart';
import 'delta_sync_service.dart';
import 'appwrite_service.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'local_db.dart';
import 'booking_derived_fields_service.dart';
import '../utils/time.dart';
import '../utils/id.dart';
import 'sync_locks.dart';

class AppwriteDeltaSyncResult {
  final bool success;
  final String message;
  final int pushedCount;
  final int pulledCount;

  AppwriteDeltaSyncResult({
    required this.success,
    required this.message,
    this.pushedCount = 0,
    this.pulledCount = 0,
  });

  /// Alias getters for compatibility
  int get recordsPulled => pulledCount;
  int get recordsPushed => pushedCount;
  bool get hasConflicts => false; // TODO: Implement actual conflict detection
}

class AppwriteDeltaSync {
  AppwriteDeltaSync._();
  static final instance = AppwriteDeltaSync._();

  AppwriteService? _appwriteService;
  DeltaSyncService? _deltaSyncService;
  AppDatabase? _database;
  String? _deviceId;
  bool _isSyncing = false;

  final _logger = AppwriteLogger();

  static const _prefsLastDeltaSyncKey = 'appwrite_last_delta_sync';
  static const _prefsDeviceIdKey = 'appwrite_delta_device_id';
  static const _prefsDeltaSyncEnabledKey = 'appwrite_delta_sync_enabled';

  static const deltaSyncCollectionId = 'delta_sync_records';

  Future<void> initialize(
    AppwriteService appwriteService,
    AppDatabase db,
  ) async {
    _appwriteService = appwriteService;
    _database = db;
    _deltaSyncService = DeltaSyncService(db);
    await _initializeDeviceId();
    _logger.info(
      'تم تهيئة خدمة المزامنة التفاضلية لـ Appwrite',
      tag: 'DELTA_SYNC',
    );
  }

  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_prefsDeviceIdKey);
    if (_deviceId == null) {
      _deviceId = IdGen.uuid();
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
    }
  }

  bool get isInitialized =>
      _appwriteService != null && _deltaSyncService != null;
  bool get isSyncing => _isSyncing;
  String? get deviceId => _deviceId;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsDeltaSyncEnabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDeltaSyncEnabledKey, enabled);
  }

  Future<AppwriteDeltaSyncResult> pushDeltaChanges() async {
    final canStart = await SyncLocks.appwriteSyncLock.synchronized(() async {
      if (!isInitialized || _isSyncing) {
        return false;
      }
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      return AppwriteDeltaSyncResult(
        success: false,
        message: 'الخدمة غير جاهزة أو المزامنة جارية',
      );
    }

    try {
      _logger.info(
        '📤 بدء المزامنة التفاضلية إلى Appwrite...',
        tag: 'DELTA_SYNC',
      );

      final lastSyncTs = await _getLastDeltaSyncTimestamp();
      final computation = await _deltaSyncService!.compute(since: lastSyncTs);

      if (computation.changes.isEmpty) {
        _logger.info('✅ لا توجد تغييرات للمزامنة', tag: 'DELTA_SYNC');
        return AppwriteDeltaSyncResult(
          success: true,
          message: 'لا توجد تغييرات',
          pushedCount: 0,
        );
      }

      final failedChanges = <DeltaSyncChange>[];
      final successfulChanges = <DeltaSyncChange>[];

      for (final change in computation.changes) {
        try {
          await _pushSingleChange(change);
          successfulChanges.add(change);
        } catch (e) {
          failedChanges.add(change);
          _logger.warning(
            'فشل رفع تغيير: ${change.entity}/${change.localUuid} - $e',
            tag: 'DELTA_SYNC',
          );
        }
      }

      if (successfulChanges.isNotEmpty) {
        await _persistSuccessfulChanges(computation, successfulChanges);
        await _updateLastDeltaSyncTimestamp();
      }

      final hasFailures = failedChanges.isNotEmpty;
      final message = hasFailures
          ? 'تم رفع ${successfulChanges.length} تغيير وفشل ${failedChanges.length}'
          : 'تم رفع ${successfulChanges.length} تغيير بنجاح';

      _logger.info('✅ $message', tag: 'DELTA_SYNC');

      return AppwriteDeltaSyncResult(
        success: !hasFailures,
        message: message,
        pushedCount: successfulChanges.length,
      );
    } catch (e) {
      _logger.error('❌ خطأ في المزامنة التفاضلية: $e', tag: 'DELTA_SYNC');
      return AppwriteDeltaSyncResult(success: false, message: e.toString());
    } finally {
      await SyncLocks.appwriteSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  Future<void> _persistSuccessfulChanges(
    DeltaSyncComputation computation,
    List<DeltaSyncChange> successfulChanges,
  ) async {
    final successfulUuids = successfulChanges.map((c) => c.localUuid).toSet();
    final allChangeUuids = computation.changes.map((c) => c.localUuid).toSet();
    final filteredSnapshot = <String, Map<String, MirrorRow>>{};

    for (final entry in computation.mirrorSnapshot.entries) {
      final filteredRows = <String, MirrorRow>{};
      for (final rowEntry in entry.value.entries) {
        if (successfulUuids.contains(rowEntry.key) ||
            !allChangeUuids.contains(rowEntry.key)) {
          filteredRows[rowEntry.key] = rowEntry.value;
        }
      }
      filteredSnapshot[entry.key] = filteredRows;
    }

    final filteredComputation = DeltaSyncComputation(
      changes: successfulChanges,
      mirrorSnapshot: filteredSnapshot,
      fallbackTables: computation.fallbackTables,
    );

    await _deltaSyncService!.persistMirror(filteredComputation);
  }

  Future<void> _pushSingleChange(DeltaSyncChange change) async {
    final collectionId = _getCollectionId(change.entity);
    if (collectionId == null) {
      _logger.warning('مجموعة غير معروفة: ${change.entity}', tag: 'DELTA_SYNC');
      return;
    }

    final payload = Map<String, dynamic>.from(change.data);
    payload['deviceId'] = _deviceId;
    payload['syncTimestamp'] = Time.nowEpoch();

    switch (change.operation) {
      case 'insert':
      case 'update':
        final sanitized = _sanitizePayload(payload);
        final converted = _convertAmountTypesForAppwrite(collectionId, sanitized);
        await _appwriteService!.upsertDocument(
          collectionId: collectionId,
          documentId: change.localUuid,
          data: converted,
        );
        break;
      case 'delete':
        try {
          await _appwriteService!.deleteDocument(
            collectionId: collectionId,
            documentId: change.localUuid,
          );
        } on AppwriteException catch (e) {
          if (e.code != 404) rethrow;
        } catch (e) {
          rethrow;
        }
        break;
    }
  }

  Future<AppwriteDeltaSyncResult> pullDeltaChanges() async {
    final canStart = await SyncLocks.appwriteSyncLock.synchronized(() async {
      if (!isInitialized || _isSyncing) {
        return false;
      }
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      return AppwriteDeltaSyncResult(
        success: false,
        message: 'الخدمة غير جاهزة',
      );
    }

    try {
      _logger.info('📥 فحص التغييرات من Appwrite...', tag: 'DELTA_SYNC');

      final lastPullTs = await _getLastDeltaSyncTimestamp();
      int pulledCount = 0;

      final entitiesToPull = {
        'rooms': AppwriteConfig.roomsCollectionId,
        'bookings': AppwriteConfig.bookingsCollectionId,
        // ✅ بعد bookings مباشرة لأنه يعتمد عليها (bookingLocalId)
        'booking_price_adjustments': AppwriteConfig.bookingPriceAdjustmentsCollectionId,
        'booking_notes': AppwriteConfig.bookingNotesCollectionId,
        'booking_nights': AppwriteConfig.bookingNightsCollectionId,
        'payments': AppwriteConfig.paymentsCollectionId,
        'expenses': AppwriteConfig.expensesCollectionId,
        'cash_transactions': AppwriteConfig.cashTransactionsCollectionId,
        'debts': AppwriteConfig.debtsCollectionId,
        'employees': AppwriteConfig.employeesCollectionId,
        // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته
        'salary_cycles': AppwriteConfig.salaryCyclesCollectionId,
        'salary_payments': AppwriteConfig.salaryPaymentsCollectionId,
        'salary_withdrawals': AppwriteConfig.salaryWithdrawalsCollectionId,
        'shift_notes': AppwriteConfig.shiftNotesCollectionId,
        'price_adjustments': AppwriteConfig.priceAdjustmentsCollectionId,
        'audit_logs': AppwriteConfig.auditLogsCollectionId,
        'payment_voids': AppwriteConfig.paymentVoidsCollectionId,
        'guest_infos': AppwriteConfig.guestInfosCollectionId,
      };

      for (final entry in entitiesToPull.entries) {
        pulledCount += await _pullEntityChanges(
          entry.key,
          entry.value,
          lastPullTs,
        );
      }

      if (pulledCount > 0) {
        await _updateLastDeltaSyncTimestamp();
      }

      _logger.info(
        '✅ تم سحب $pulledCount تغيير من Appwrite',
        tag: 'DELTA_SYNC',
      );

      return AppwriteDeltaSyncResult(
        success: true,
        message: 'تم سحب التغييرات بنجاح',
        pulledCount: pulledCount,
      );
    } catch (e) {
      _logger.error('❌ خطأ في سحب التغييرات: $e', tag: 'DELTA_SYNC');
      return AppwriteDeltaSyncResult(success: false, message: e.toString());
    } finally {
      await SyncLocks.appwriteSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  Future<int> _pullEntityChanges(
    String entity,
    String collectionId,
    int lastPullTs,
  ) async {
    try {
      final documents = await _appwriteService!.listDocuments(
        collectionId: collectionId,
        queries: lastPullTs > 0
            ? [Query.greaterThan('syncTimestamp', lastPullTs)]
            : null,
        useCache: false,
      );

      int applied = 0;
      for (final doc in documents) {
        final data = Map<String, dynamic>.from(doc.data);
        final sourceDeviceId = data['deviceId'] as String?;

        if (sourceDeviceId == _deviceId) continue;

        try {
          await _applyRemoteChange(entity, doc.$id, data);
          applied++;
        } catch (e) {
          _logger.warning(
            'فشل تطبيق تغيير: $entity/${doc.$id} - $e',
            tag: 'DELTA_SYNC',
          );
        }
      }

      return applied;
    } catch (e) {
      _logger.warning('فشل سحب $entity: $e', tag: 'DELTA_SYNC');
      return 0;
    }
  }

  Future<void> _applyRemoteChange(
    String entity,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    final db = _database!;

    switch (entity) {
      case 'rooms':
        await _applyRoomChange(db, documentId, data);
        break;
      case 'bookings':
        await _applyBookingChange(db, documentId, data);
        break;
      case 'payments':
        await _applyPaymentChange(db, documentId, data);
        break;
      case 'expenses':
        await _applyExpenseChange(db, documentId, data);
        break;
      case 'debts':
        await _applyDebtChange(db, documentId, data);
        break;
      case 'employees':
        await _applyEmployeeChange(db, documentId, data);
        break;
      case 'booking_nights':
        await _applyBookingNightChange(db, documentId, data);
        break;
      case 'booking_notes':
        await _applyBookingNoteChange(db, documentId, data);
        break;
      case 'cash_transactions':
        await _applyCashTransactionChange(db, documentId, data);
        break;
      case 'shift_notes':
        await _applyShiftNoteChange(db, documentId, data);
        break;
      case 'salary_cycles':
        await _applySalaryCycleChange(db, documentId, data);
        break;
      case 'salary_payments':
        await _applySalaryPaymentChange(db, documentId, data);
        break;
      // ❌ hotel_day_ledger - محلي فقط
      case 'price_adjustments':
        await _applyPriceAdjustmentChange(db, documentId, data);
        break;
      case 'booking_price_adjustments':
        await _applyBookingPriceAdjustmentChange(db, documentId, data);
        break;
      case 'audit_logs':
        await _applyAuditLogChange(db, documentId, data);
        break;
      case 'payment_voids':
        await _applyPaymentVoidChange(db, documentId, data);
        break;
      case 'guest_infos':
        await _applyGuestInfoChange(db, documentId, data);
        break;
      case 'salary_withdrawals':
        await _applySalaryWithdrawalChange(db, documentId, data);
        break;
    }
  }

  Future<void> _applyRoomChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final roomNumber = _asString(data['roomNumber']);
    if (roomNumber == null || roomNumber.isEmpty) return;

    final incomingLastModified =
        _asInt(data['lastModified']) ?? Time.nowEpoch();

    final companion = RoomsCompanion(
      roomNumber: d.Value(roomNumber),
      type: d.Value(_asString(data['type']) ?? ''),
      price: d.Value(_asDouble(data['price'])),
      status: d.Value(_asString(data['status']) ?? 'available'),
      imageUrl: _nullableValue<String>(_asString(data['imageUrl'])),
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(incomingLastModified),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
    );

    final existingByUuid =
        await (db.select(db.rooms)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();

    if (existingByUuid != null) {
      await (db.update(
        db.rooms,
      )..where((t) => t.localUuid.equals(localUuid))).write(companion);
      return;
    }

    final existingByNumber =
        await (db.select(db.rooms)
              ..where((t) => t.roomNumber.equals(roomNumber))
              ..limit(1))
            .getSingleOrNull();

    if (existingByNumber != null) {
      if (incomingLastModified >= existingByNumber.lastModified) {
        await (db.update(
          db.rooms,
        )..where((t) => t.roomNumber.equals(roomNumber))).write(companion);
      }
      return;
    }

    await db.into(db.rooms).insert(companion);
  }

  Future<void> _applyBookingChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final roomNumber = _asString(data['roomNumber']);
    if (roomNumber == null || roomNumber.isEmpty) return;

    final companion = BookingsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      serverBookingId: _nullableValue<int>(_asInt(data['serverBookingId'])),
      roomNumber: d.Value(roomNumber),
      guestName: d.Value(_asString(data['guestName']) ?? ''),
      guestPhone: d.Value(_asString(data['guestPhone']) ?? ''),
      guestIdType: d.Value(_asString(data['guestIdType']) ?? ''),
      guestIdNumber: d.Value(_asString(data['guestIdNumber']) ?? ''),
      guestIdIssueDate: _nullableValue<String>(
        _asString(data['guestIdIssueDate']),
      ),
      guestIdIssuePlace: _nullableValue<String>(
        _asString(data['guestIdIssuePlace']),
      ),
      guestNationality: d.Value(_asString(data['guestNationality']) ?? ''),
      guestEmail: _nullableValue<String>(_asString(data['guestEmail'])),
      guestAddress: _nullableValue<String>(_asString(data['guestAddress'])),
      checkinDate: d.Value(_asString(data['checkinDate']) ?? ''),
      checkoutDate: _nullableValue<String>(_asString(data['checkoutDate'])),
      actualCheckout: _nullableValue<String>(_asString(data['actualCheckout'])),
      status: d.Value(_asString(data['status']) ?? ''),
      notes: _nullableValue<String>(_asString(data['notes'])),
      expectedNights: d.Value(_asInt(data['expectedNights']) ?? 1),
      calculatedNights: d.Value(_asInt(data['calculatedNights']) ?? 1),
      discount: d.Value(_asDouble(data['discount'])),
      discountType: d.Value(_asString(data['discountType']) ?? 'per_night'),
      discountStartDate: _nullableValue<String>(_asString(data['discountStartDate'])),
    );

    await db.into(db.bookings).insertOnConflictUpdate(companion);
  }

  Future<void> _applyPaymentChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final companion = PaymentsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      serverPaymentId: _nullableValue<int>(_asInt(data['serverPaymentId'])),
      bookingLocalId: _nullableValue<int>(_asInt(data['bookingLocalId'])),
      serverBookingId: _nullableValue<int>(_asInt(data['serverBookingId'])),
      roomNumber: _nullableValue<String>(_asString(data['roomNumber'])),
      amount: d.Value(_asDouble(data['amount'])),
      paymentDate: d.Value(_asString(data['paymentDate']) ?? ''),
      notes: _nullableValue<String>(_asString(data['notes'])),
      paymentMethod: d.Value(_asString(data['paymentMethod']) ?? ''),
      revenueType: d.Value(_asString(data['revenueType']) ?? ''),
      cashTransactionLocalId: _nullableValue<int>(
        _asInt(data['cashTransactionLocalId']),
      ),
      cashTransactionServerId: _nullableValue<int>(
        _asInt(data['cashTransactionServerId']),
      ),
      referenceNumber: _nullableValue<String>(
        _asString(data['referenceNumber']),
      ),
    );

    await db.into(db.payments).insertOnConflictUpdate(companion);
  }

  Future<void> _applyExpenseChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final expenseType = _asString(data['expenseType']);
    if (expenseType == null || expenseType.isEmpty) return;

    final companion = ExpensesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      expenseType: d.Value(expenseType),
      relatedId: _nullableValue<int>(_asInt(data['relatedId'])),
      description: d.Value(_asString(data['description']) ?? ''),
      amount: d.Value(_asDouble(data['amount'])),
      date: d.Value(_asString(data['date']) ?? ''),
      cashTransactionId: _nullableValue<int>(_asInt(data['cashTransactionId'])),
    );

    await db.into(db.expenses).insertOnConflictUpdate(companion);
  }

  Future<void> _applyDebtChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final guestName =
        _asString(data['guestName']) ?? _asString(data['debtorName']);
    if (guestName == null || guestName.isEmpty) return;

    final companion = DebtsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      bookingLocalId: _nullableValue<int>(_asInt(data['bookingLocalId'])),
      guestName: d.Value(guestName),
      checkinDate: d.Value(_asString(data['checkinDate']) ?? ''),
      checkoutDate: d.Value(_asString(data['checkoutDate']) ?? ''),
      dateRecorded: d.Value(_asString(data['dateRecorded']) ?? ''),
      debtReason: d.Value(_asString(data['debtReason']) ?? ''),
      totalAmount: d.Value(
        _asDouble(data['totalAmount'] ?? data['amount']),
      ),
      paidAmount: d.Value(_asDouble(data['paidAmount'])),
      remainingAmount: d.Value(_asDouble(data['remainingAmount'])),
      paymentDate: d.Value(_asString(data['paymentDate']) ?? ''),
      isSettled: d.Value(
        _asInt(data['isSettled']) ?? (data['status'] == 'settled' ? 1 : 0),
      ),
      pledge: _nullableValue<String>(_asString(data['pledge'])),
      pledgeType: _nullableValue<String>(_asString(data['pledgeType'])),
      note: _nullableValue<String>(_asString(data['note'])),
    );

    await db.into(db.debts).insertOnConflictUpdate(companion);
  }

  Future<void> _applyEmployeeChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final name = _asString(data['name']);
    if (name == null || name.isEmpty) return;

    final companion = EmployeesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      name: d.Value(name),
      basicSalary: d.Value(_asDouble(data['basicSalary'])),
      position: d.Value(_asString(data['position']) ?? ''),
      phone: d.Value(_asString(data['phone']) ?? ''),
      hireDate: d.Value(_asString(data['hireDate']) ?? ''),
      status: d.Value(_asString(data['status']) ?? ''),
    );

    await db.into(db.employees).insertOnConflictUpdate(companion);
  }

  Future<void> _applyPriceAdjustmentChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final targetType = _asString(data['targetType']);
    final targetUuid = _asString(data['targetUuid']);
    if (targetType == null || targetUuid == null) return;

    final companion = PriceAdjustmentsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      targetType: d.Value(targetType),
      targetUuid: d.Value(targetUuid),
      adjustmentType: d.Value(_asString(data['adjustmentType']) ?? ''),
      previousValue: d.Value(_asInt(data['previousValue']) ?? 0),
      newValue: d.Value(_asInt(data['newValue']) ?? 0),
      reason: _nullableValue<String>(_asString(data['reason'])),
      effectiveDate: d.Value(_asString(data['effectiveDate']) ?? ''),
      appliedBy: d.Value(_asString(data['appliedBy']) ?? ''),
      hotelDayKey: d.Value(_asString(data['hotelDayKey']) ?? ''),
      isReversed: d.Value(_asBool(data['isReversed']) ?? false),
      reversedAt: _nullableValue<String>(_asString(data['reversedAt'])),
      reversedBy: _nullableValue<String>(_asString(data['reversedBy'])),
    );

    await db.into(db.priceAdjustments).insertOnConflictUpdate(companion);
    if (targetType == 'room') {
      await _recalculateBookingsForRoomUuid(db, targetUuid);
    } else if (targetType == 'booking') {
      await _recalculateBookingByUuid(db, targetUuid);
    }
  }

  Future<void> _applyAuditLogChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final operationType = _asString(data['operationType']);
    final entityType = _asString(data['entityType']);
    if (operationType == null || entityType == null) return;

    final timestamp = _asInt(data['timestamp']) ?? Time.nowEpoch();

    final companion = AuditLogsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      operationType: d.Value(operationType),
      entityType: d.Value(entityType),
      entityUuid: d.Value(_asString(data['entityUuid']) ?? ''),
      entityId: _nullableValue<int>(_asInt(data['entityId'])),
      previousState: _nullableValue<String>(_asString(data['previousState'])),
      newState: _nullableValue<String>(_asString(data['newState'])),
      changedFields: _nullableValue<String>(_asString(data['changedFields'])),
      performedBy: d.Value(_asString(data['performedBy']) ?? ''),
      deviceId: d.Value(_asString(data['deviceId']) ?? ''),
      ipAddress: _nullableValue<String>(_asString(data['ipAddress'])),
      hotelDayKey: d.Value(_asString(data['hotelDayKey']) ?? ''),
      timestamp: d.Value(timestamp),
      timestampIso: d.Value(
        _asString(data['timestampIso']) ??
            DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toIso8601String(),
      ),
      isFinancial: d.Value(_asBool(data['isFinancial']) ?? false),
      amountImpact: _nullableValue<int>(_asInt(data['amountImpact'])),
    );

    await db.into(db.auditLogs).insertOnConflictUpdate(companion);
  }

  Future<void> _applyPaymentVoidChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final originalPaymentUuid = _asString(data['originalPaymentUuid']);
    if (originalPaymentUuid == null) return;

    final voidedAt = _asInt(data['voidedAt']) ?? Time.nowEpoch();

    final companion = PaymentVoidsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      originalPaymentUuid: d.Value(originalPaymentUuid),
      originalPaymentId: d.Value(_asInt(data['originalPaymentId']) ?? 0),
      bookingUuid: d.Value(_asString(data['bookingUuid']) ?? ''),
      voidedAmount: d.Value(_asInt(data['voidedAmount']) ?? 0),
      voidReason: d.Value(_asString(data['voidReason']) ?? ''),
      voidedBy: d.Value(_asString(data['voidedBy']) ?? ''),
      voidedAt: d.Value(voidedAt),
      voidedAtIso: d.Value(
        _asString(data['voidedAtIso']) ??
            DateTime.fromMillisecondsSinceEpoch(voidedAt * 1000).toIso8601String(),
      ),
      hotelDayKey: d.Value(_asString(data['hotelDayKey']) ?? ''),
      reversalPaymentUuid: _nullableValue<String>(_asString(data['reversalPaymentUuid'])),
      approvedBy: _nullableValue<String>(_asString(data['approvedBy'])),
    );

    await db.into(db.paymentVoids).insertOnConflictUpdate(companion);
  }

  Future<void> _applyGuestInfoChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final guestName = _asString(data['guestName']);
    if (guestName == null || guestName.isEmpty) return;

    final incomingLastModified =
        _asInt(data['lastModified']) ?? Time.nowEpoch();

    final companion = GuestInfosCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      roomNumber: d.Value(_asString(data['roomNumber']) ?? ''),
      guestName: d.Value(guestName),
      nationality: d.Value(_asString(data['nationality']) ?? ''),
      idNumber: d.Value(_asString(data['idNumber']) ?? ''),
      idType: d.Value(_asString(data['idType']) ?? 'بطاقة شخصية'),
      issueDate: _nullableValue<String>(_asString(data['issueDate'])),
      issuePlace: _nullableValue<String>(_asString(data['issuePlace'])),
      governorate: _nullableValue<String>(_asString(data['governorate'])),
      notes: _nullableValue<String>(_asString(data['notes'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(incomingLastModified),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
    );

    await db.into(db.guestInfos).insertOnConflictUpdate(companion);
  }

  Future<void> _applySalaryWithdrawalChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final employeeId = _asInt(data['employeeId']);
    if (employeeId == null) return;

    final incomingLastModified =
        _asInt(data['lastModified']) ?? Time.nowEpoch();

    final companion = SalaryWithdrawalsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      employeeId: d.Value(employeeId),
      amount: d.Value(_asDouble(data['amount']) ?? 0),
      withdrawDate: d.Value(_asString(data['withdrawDate']) ?? ''),
      reason: _nullableValue<String>(_asString(data['reason'])),
      hotelDayKey: _nullableValue<String>(_asString(data['hotelDayKey'])),
      withdrawalType: _nullableValue<String>(_asString(data['withdrawalType'])),
      description: _nullableValue<String>(_asString(data['description'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(incomingLastModified),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
    );

    await db.into(db.salaryWithdrawals).insertOnConflictUpdate(companion);
  }

  Future<void> _applyBookingNightChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final bookingLocalId = _asInt(data['bookingLocalId']);
    if (bookingLocalId == null) return;

    final companion = BookingNightsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      bookingLocalId: d.Value(bookingLocalId),
      hotelDayKey: d.Value(_asString(data['hotelDayKey']) ?? ''),
      nightStart: d.Value(_asString(data['nightStart']) ?? ''),
      nightEnd: d.Value(_asString(data['nightEnd']) ?? ''),
      nightlyRate: d.Value(_asDouble(data['nightlyRate'])),
      sequence: d.Value(_asInt(data['sequence']) ?? 0),
      isProcessedByAutoFix: d.Value(_asBool(data['isProcessedByAutoFix']) ?? false),
      baseRate: d.Value(_asDouble(data['baseRate'])),
      adjustment: d.Value(_asDouble(data['adjustment'])),
      finalRate: d.Value(_asDouble(data['finalRate'])),
      appliedAdjustmentUuid: _nullableValue<String>(_asString(data['appliedAdjustmentUuid'])),
      appliedAdjustmentsJson: _nullableValue<String>(_asString(data['appliedAdjustmentsJson'])),
    );

    await db.into(db.bookingNights).insertOnConflictUpdate(companion);
  }

  Future<void> _applyBookingNoteChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final bookingId = _asInt(data['bookingId']);
    if (bookingId == null) return;

    final companion = BookingNotesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      bookingId: d.Value(bookingId),
      noteText: d.Value(_asString(data['noteText']) ?? ''),
      alertType: d.Value(_asString(data['alertType']) ?? ''),
      alertUntil: _nullableValue<String>(_asString(data['alertUntil'])),
      isActive: d.Value(_asInt(data['isActive']) ?? 1),
    );

    await db.into(db.bookingNotes).insertOnConflictUpdate(companion);
  }

  Future<void> _applyCashTransactionChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final companion = CashTransactionsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      registerId: _nullableValue<int>(_asInt(data['registerId'])),
      transactionType: d.Value(_asString(data['transactionType']) ?? ''),
      amount: d.Value(_asDouble(data['amount'])),
      referenceType: _nullableValue<String>(_asString(data['referenceType'])),
      referenceId: _nullableValue<int>(_asInt(data['referenceId'])),
      description: _nullableValue<String>(_asString(data['description'])),
      transactionTime: d.Value(_asString(data['transactionTime']) ?? ''),
      createdBy: _nullableValue<int>(_asInt(data['createdBy'])),
    );

    await db.into(db.cashTransactions).insertOnConflictUpdate(companion);
  }

  Future<void> _applyShiftNoteChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final companion = ShiftNotesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      title: d.Value(_asString(data['title']) ?? ''),
      content: d.Value(_asString(data['content']) ?? ''),
      priority: d.Value(_asString(data['priority']) ?? 'medium'),
      shiftType: d.Value(_asString(data['shiftType']) ?? 'all'),
      isRead: d.Value(_asInt(data['isRead']) ?? 0),
      expiresAt: _nullableValue<String>(_asString(data['expiresAt'])),
      createdBy: d.Value(_asString(data['createdBy']) ?? 'user'),
    );

    await db.into(db.shiftNotes).insertOnConflictUpdate(companion);
  }

  Future<void> _applySalaryCycleChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final employeeId = _asInt(data['employeeId']);
    if (employeeId == null) return;

    final companion = SalaryCyclesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      employeeId: d.Value(employeeId),
      cycleKey: d.Value(_asString(data['cycleKey']) ?? ''),
      hotelDayStart: _nullableValue<String>(_asString(data['hotelDayStart'])),
      hotelDayEnd: _nullableValue<String>(_asString(data['hotelDayEnd'])),
      expectedAmount: d.Value(_asInt(data['expectedAmount']) ?? 0),
      actualPaid: d.Value(_asInt(data['actualPaid']) ?? 0),
      remainingAmount: d.Value(_asInt(data['remainingAmount']) ?? 0),
      status: d.Value(_asString(data['status']) ?? 'draft'),
    );

    await db.into(db.salaryCycles).insertOnConflictUpdate(companion);
  }

  Future<void> _applySalaryPaymentChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final cycleId = _asInt(data['cycleId']);
    if (cycleId == null) return;

    final companion = SalaryPaymentsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      cycleId: d.Value(cycleId),
      amount: d.Value(_asInt(data['amount']) ?? 0),
      hotelDayKey: _nullableValue<String>(_asString(data['hotelDayKey'])),
      paymentDateIso: d.Value(_asString(data['paymentDateIso']) ?? ''),
      method: _nullableValue<String>(_asString(data['method'])),
      isAutoGenerated: d.Value(_asBool(data['isAutoGenerated']) ?? false),
    );

    await db.into(db.salaryPayments).insertOnConflictUpdate(companion);
  }


  bool? _asBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final t = value.toLowerCase();
      if (t == 'true' || t == '1') return true;
      if (t == 'false' || t == '0') return false;
    }
    return null;
  }

  String? _getCollectionId(String entity) {
    switch (entity) {
      case 'rooms':
        return AppwriteConfig.roomsCollectionId;
      case 'bookings':
        return AppwriteConfig.bookingsCollectionId;
      case 'booking_notes':
        return AppwriteConfig.bookingNotesCollectionId;
      case 'booking_nights':
        return AppwriteConfig.bookingNightsCollectionId;
      case 'payments':
        return AppwriteConfig.paymentsCollectionId;
      case 'expenses':
        return AppwriteConfig.expensesCollectionId;
      case 'cash_transactions':
        return AppwriteConfig.cashTransactionsCollectionId;
      case 'debts':
        return AppwriteConfig.debtsCollectionId;
      case 'employees':
        return AppwriteConfig.employeesCollectionId;
      // ❌ hotel_day_ledger - محلي فقط
      case 'salary_cycles':
        return AppwriteConfig.salaryCyclesCollectionId;
      case 'salary_payments':
        return AppwriteConfig.salaryPaymentsCollectionId;
      case 'shift_notes':
        return AppwriteConfig.shiftNotesCollectionId;
      case 'price_adjustments':
        return AppwriteConfig.priceAdjustmentsCollectionId;
      case 'booking_price_adjustments':
        return AppwriteConfig.bookingPriceAdjustmentsCollectionId;
      case 'audit_logs':
        return AppwriteConfig.auditLogsCollectionId;
      case 'payment_voids':
        return AppwriteConfig.paymentVoidsCollectionId;
      case 'guest_infos':
        return AppwriteConfig.guestInfosCollectionId;
      case 'salary_withdrawals':
        return AppwriteConfig.salaryWithdrawalsCollectionId;
      default:
        return null;
    }
  }

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> payload) {
    final result = <String, dynamic>{};
    payload.forEach((key, value) {
      final camelKey = _toCamelCase(key);
      if (value != null) {
        result[camelKey] = value;
      }
    });
    return result;
  }

  /// تحويل حقول amount من double إلى int للمجموعات التي تتطلب integer في Appwrite
  static const _intAmountFields = <String, Set<String>>{
    'booking_price_adjustments': {'amount'},
    'cash_transactions': {'amount'},
    'salary_withdrawals': {'amount'},
    'debts': {'amount', 'remainingAmount'},
  };

  Map<String, dynamic> _convertAmountTypesForAppwrite(
    String collectionId,
    Map<String, dynamic> payload,
  ) {
    final intFields = _intAmountFields[collectionId];
    if (intFields == null || intFields.isEmpty) return payload;

    final result = Map<String, dynamic>.from(payload);
    for (final field in intFields) {
      if (result.containsKey(field) && result[field] is num) {
        result[field] = (result[field] as num).round();
      }
    }
    return result;
  }

  String _toCamelCase(String input) {
    if (!input.contains('_')) return input;
    final parts = input.split('_');
    final first = parts.first;
    final rest = parts
        .skip(1)
        .map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}');
    return '$first${rest.join()}';
  }

  Future<int> _getLastDeltaSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsLastDeltaSyncKey) ?? 0;
  }

  Future<void> _updateLastDeltaSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastDeltaSyncKey, Time.nowEpoch());
  }

  Future<Map<String, dynamic>> getStatus() async {
    final lastSync = await _getLastDeltaSyncTimestamp();
    final enabled = await isEnabled();
    return {
      'initialized': isInitialized,
      'enabled': enabled,
      'is_syncing': _isSyncing,
      'device_id': _deviceId,
      'last_sync_epoch': lastSync,
      'last_sync_time': lastSync > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              lastSync * 1000,
            ).toIso8601String()
          : null,
    };
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

  Future<void> _applyBookingPriceAdjustmentChange(
    AppDatabase db,
    String localUuid,
    Map<String, dynamic> data,
  ) async {
    final bookingUuid = _asString(data['bookingLocalUuid']) ?? _asString(data['booking_local_uuid']);
    if (bookingUuid == null || bookingUuid.isEmpty) return;

    final companion = BookingPriceAdjustmentsCompanion(
      localUuid: d.Value(localUuid),
      serverId: _nullableValue<int>(_asInt(data['serverId']) ?? _asInt(data['server_id'])),
      bookingLocalUuid: d.Value(bookingUuid),
      bookingLocalId: _nullableValue<int>(_asInt(data['bookingLocalId']) ?? _asInt(data['booking_local_id'])),
      adjustmentType: d.Value(_asInt(data['adjustmentType']) ?? _asInt(data['adjustment_type']) ?? 0),
      adjustmentMode: d.Value(_asString(data['adjustmentMode']) ?? _asString(data['adjustment_mode']) ?? 'per_night'),
      amount: d.Value(_asDouble(data['amount'])),
      effectiveHotelDay: d.Value(_asString(data['effectiveHotelDay']) ?? _asString(data['effective_hotel_day']) ?? ''),
      endHotelDay: _nullableValue<String>(_asString(data['endHotelDay']) ?? _asString(data['end_hotel_day'])),
      isActive: d.Value(_asBool(data['isActive']) ?? _asBool(data['is_active']) ?? true),
      reason: _nullableValue<String>(_asString(data['reason'])),
      appliedBy: _nullableValue<String>(_asString(data['appliedBy']) ?? _asString(data['applied_by'])),
      cancelledAt: _nullableValue<String>(_asString(data['cancelledAt']) ?? _asString(data['cancelled_at'])),
      cancelledBy: _nullableValue<String>(_asString(data['cancelledBy']) ?? _asString(data['cancelled_by'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? _asInt(data['created_at']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? _asInt(data['updated_at']) ?? Time.nowEpoch()),
      deletedAt: _nullableValue<int>(_asInt(data['deletedAt']) ?? _asInt(data['deleted_at'])),
      lastModified: d.Value(_asInt(data['lastModified']) ?? _asInt(data['last_modified']) ?? Time.nowEpoch()),
      createdAtIso: _nullableValue<String>(_asString(data['createdAtIso']) ?? _asString(data['created_at_iso'])),
      updatedAtIso: _nullableValue<String>(_asString(data['updatedAtIso']) ?? _asString(data['updated_at_iso'])),
      deletedAtIso: _nullableValue<String>(_asString(data['deletedAtIso']) ?? _asString(data['deleted_at_iso'])),
      createdAtEpoch: d.Value(_asInt(data['createdAtEpoch']) ?? 0),
      lastModifiedEpoch: d.Value(_asInt(data['lastModifiedEpoch']) ?? 0),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
      vectorClock: d.Value(_asString(data['vectorClock']) ?? _asString(data['vector_clock']) ?? '{}'),
    );

    await db.into(db.bookingPriceAdjustments).insertOnConflictUpdate(companion);
    final bookingId =
        _asInt(data['bookingLocalId']) ?? _asInt(data['booking_local_id']);
    if (bookingId != null) {
      await _recalculateBookingById(db, bookingId);
    } else {
      await _recalculateBookingByUuid(db, bookingUuid);
    }
  }

  Future<void> _recalculateBookingById(AppDatabase db, int bookingId) async {
    await BookingDerivedFieldsService(db).refreshForBookingId(
      bookingId,
      forceRebuild: true,
    );
  }

  Future<void> _recalculateBookingByUuid(
    AppDatabase db,
    String bookingUuid,
  ) async {
    final booking = await (db.select(db.bookings)
          ..where((b) => b.localUuid.equals(bookingUuid)))
        .getSingleOrNull();
    if (booking == null) return;
    await _recalculateBookingById(db, booking.id);
  }

  Future<void> _recalculateBookingsForRoomUuid(
    AppDatabase db,
    String roomUuid,
  ) async {
    final room = await (db.select(db.rooms)
          ..where((r) => r.localUuid.equals(roomUuid)))
        .getSingleOrNull();
    if (room == null) return;
    final activeStatuses = [
      'مؤكد',
      'confirmed',
      'نشط',
      'active',
      'مسجل دخول',
      'checked_in',
    ];
    final bookings = await (db.select(db.bookings)
          ..where((b) => b.roomNumber.equals(room.roomNumber))
          ..where((b) => b.deletedAt.isNull())
          ..where((b) => b.actualCheckout.isNull())
          ..where((b) => b.status.isIn(activeStatuses)))
        .get();
    for (final booking in bookings) {
      await _recalculateBookingById(db, booking.id);
    }
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
}
