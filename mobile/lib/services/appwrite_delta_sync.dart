import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as d;
import 'package:appwrite/appwrite.dart';
import 'delta_sync_service.dart';
import 'appwrite_service.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'local_db.dart';
import '../utils/time.dart';
import '../utils/id.dart';
import 'sync_core/unified_lock_manager.dart';
import 'booking_derived_fields_service.dart';

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
      AppwriteService appwriteService, AppDatabase db) async {
    _appwriteService = appwriteService;
    _database = db;
    _deltaSyncService = DeltaSyncService(db);
    await _initializeDeviceId();
    _logger.info('تم تهيئة خدمة المزامنة التفاضلية لـ Appwrite',
        tag: 'DELTA_SYNC');
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
    final lockResult = await UnifiedLockManager.instance.acquire(
      category: LockCategory.deltaSync,
      holder: 'AppwriteDeltaSync.pushDeltaChanges',
      priority: LockPriority.high,
    );

    if (!lockResult.acquired) {
      return AppwriteDeltaSyncResult(
        success: false,
        message: 'فشل الحصول على القفل: ${lockResult.failureReason}',
      );
    }

    if (!isInitialized || _isSyncing) {
      UnifiedLockManager.instance.release(
        category: LockCategory.deltaSync,
        holder: 'AppwriteDeltaSync.pushDeltaChanges',
      );
      return AppwriteDeltaSyncResult(
        success: false,
        message: 'الخدمة غير جاهزة أو المزامنة جارية',
      );
    }

    _isSyncing = true;

    try {
      _logger.info('📤 بدء المزامنة التفاضلية إلى Appwrite...',
          tag: 'DELTA_SYNC');

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
              tag: 'DELTA_SYNC');
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
      _isSyncing = false;
      UnifiedLockManager.instance.release(
        category: LockCategory.deltaSync,
        holder: 'AppwriteDeltaSync.pushDeltaChanges',
      );
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
        await _appwriteService!.upsertDocument(
          collectionId: collectionId,
          documentId: change.localUuid,
          data: _sanitizePayload(payload),
        );
        break;
      case 'delete':
        try {
          await _appwriteService!.deleteDocument(
            collectionId: collectionId,
            documentId: change.localUuid,
          );
        } catch (e) {
          if (!e.toString().contains('404') &&
              !e.toString().contains('not_found')) {
            rethrow;
          }
        }
        break;
    }
  }

  Future<AppwriteDeltaSyncResult> pullDeltaChanges() async {
    final lockResult = await UnifiedLockManager.instance.acquire(
      category: LockCategory.deltaSync,
      holder: 'AppwriteDeltaSync.pullDeltaChanges',
      priority: LockPriority.high,
    );

    if (!lockResult.acquired) {
      return AppwriteDeltaSyncResult(
        success: false,
        message: 'فشل الحصول على القفل: ${lockResult.failureReason}',
      );
    }

    if (!isInitialized || _isSyncing) {
      UnifiedLockManager.instance.release(
        category: LockCategory.deltaSync,
        holder: 'AppwriteDeltaSync.pullDeltaChanges',
      );
      return AppwriteDeltaSyncResult(
        success: false,
        message: 'الخدمة غير جاهزة',
      );
    }

    _isSyncing = true;

    try {
      _logger.info('📥 فحص التغييرات من Appwrite...', tag: 'DELTA_SYNC');

      final lastPullTs = await _getLastDeltaSyncTimestamp();
      int pulledCount = 0;

      final entitiesToPull = {
        'rooms': AppwriteConfig.roomsCollectionId,
        'bookings': AppwriteConfig.bookingsCollectionId,
        'payments': AppwriteConfig.paymentsCollectionId,
        'expenses': AppwriteConfig.expensesCollectionId,
        'debts': AppwriteConfig.debtsCollectionId,
        'employees': AppwriteConfig.employeesCollectionId,
      };

      for (final entry in entitiesToPull.entries) {
        pulledCount +=
            await _pullEntityChanges(entry.key, entry.value, lastPullTs);
      }

      if (pulledCount > 0) {
        await _updateLastDeltaSyncTimestamp();

        // إعادة حساب جميع الحجوزات النشطة بعد تطبيق التغييرات
        await _recalculateAllActiveBookings();
      }

      _logger.info('✅ تم سحب $pulledCount تغيير من Appwrite',
          tag: 'DELTA_SYNC');

      return AppwriteDeltaSyncResult(
        success: true,
        message: 'تم سحب التغييرات بنجاح',
        pulledCount: pulledCount,
      );
    } catch (e) {
      _logger.error('❌ خطأ في سحب التغييرات: $e', tag: 'DELTA_SYNC');
      return AppwriteDeltaSyncResult(success: false, message: e.toString());
    } finally {
      _isSyncing = false;
      UnifiedLockManager.instance.release(
        category: LockCategory.deltaSync,
        holder: 'AppwriteDeltaSync.pullDeltaChanges',
      );
    }
  }

  Future<int> _pullEntityChanges(
      String entity, String collectionId, int lastPullTs) async {
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
          _logger.warning('فشل تطبيق تغيير: $entity/${doc.$id} - $e',
              tag: 'DELTA_SYNC');
        }
      }

      return applied;
    } catch (e) {
      _logger.warning('فشل سحب $entity: $e', tag: 'DELTA_SYNC');
      return 0;
    }
  }

  Future<void> _applyRemoteChange(
      String entity, String documentId, Map<String, dynamic> data) async {
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
    }
  }

  Future<void> _applyRoomChange(
      AppDatabase db, String localUuid, Map<String, dynamic> data) async {
    final roomNumber = _asString(data['roomNumber']);
    if (roomNumber == null || roomNumber.isEmpty) return;

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
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value('appwrite_delta'),
    );

    await db.into(db.rooms).insertOnConflictUpdate(companion);
  }

  Future<void> _applyBookingChange(
      AppDatabase db, String localUuid, Map<String, dynamic> data) async {
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
      guestIdIssueDate:
          _nullableValue<String>(_asString(data['guestIdIssueDate'])),
      guestIdIssuePlace:
          _nullableValue<String>(_asString(data['guestIdIssuePlace'])),
      guestNationality: d.Value(_asString(data['guestNationality']) ?? ''),
      guestEmail: _nullableValue<String>(_asString(data['guestEmail'])),
      guestAddress: _nullableValue<String>(_asString(data['guestAddress'])),
      checkinDate: d.Value(_asString(data['checkinDate']) ?? ''),
      checkoutDate: _nullableValue<String>(_asString(data['checkoutDate'])),
      actualCheckout: _nullableValue<String>(_asString(data['actualCheckout'])),
      status: d.Value(_asString(data['status']) ?? ''),
      notes: _nullableValue<String>(_asString(data['notes'])),
      // لا نحفظ expected_nights و calculated_nights من delta sync
      // سيتم حسابهم تلقائياً بعد الاستعادة
    );

    await db.into(db.bookings).insertOnConflictUpdate(companion);

    // إعادة حساب الحقول المشتقة (derived fields) بناءً على التواريخ
    final insertedBooking = await (db.select(db.bookings)
          ..where((b) => b.localUuid.equals(localUuid)))
        .getSingleOrNull();

    if (insertedBooking != null) {
      await _recalculateBookingFields(db, insertedBooking);
    }
  }

  Future<void> _applyPaymentChange(
      AppDatabase db, String localUuid, Map<String, dynamic> data) async {
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
      cashTransactionLocalId:
          _nullableValue<int>(_asInt(data['cashTransactionLocalId'])),
      cashTransactionServerId:
          _nullableValue<int>(_asInt(data['cashTransactionServerId'])),
      referenceNumber:
          _nullableValue<String>(_asString(data['referenceNumber'])),
    );

    await db.into(db.payments).insertOnConflictUpdate(companion);
  }

  Future<void> _applyExpenseChange(
      AppDatabase db, String localUuid, Map<String, dynamic> data) async {
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
      AppDatabase db, String localUuid, Map<String, dynamic> data) async {
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
      totalAmount:
          d.Value(_asDouble(data['totalAmount']) ?? _asDouble(data['amount'])),
      paidAmount: d.Value(_asDouble(data['paidAmount'])),
      remainingAmount: d.Value(_asDouble(data['remainingAmount'])),
      paymentDate: d.Value(_asString(data['paymentDate']) ?? ''),
      isSettled: d.Value(
          _asInt(data['isSettled']) ?? (data['status'] == 'settled' ? 1 : 0)),
      pledge: _nullableValue<String>(_asString(data['pledge'])),
      pledgeType: _nullableValue<String>(_asString(data['pledgeType'])),
      note: _nullableValue<String>(_asString(data['note'])),
    );

    await db.into(db.debts).insertOnConflictUpdate(companion);
  }

  Future<void> _applyEmployeeChange(
      AppDatabase db, String localUuid, Map<String, dynamic> data) async {
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

  String? _getCollectionId(String entity) {
    switch (entity) {
      case 'rooms':
        return AppwriteConfig.roomsCollectionId;
      case 'bookings':
        return AppwriteConfig.bookingsCollectionId;
      case 'payments':
        return AppwriteConfig.paymentsCollectionId;
      case 'expenses':
        return AppwriteConfig.expensesCollectionId;
      case 'debts':
        return AppwriteConfig.debtsCollectionId;
      case 'employees':
        return AppwriteConfig.employeesCollectionId;
      case 'booking_notes':
        return null;
      case 'cash_transactions':
        return null;
      case 'booking_nights':
        return null;
      case 'hotel_day_ledger':
        return null;
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
          ? DateTime.fromMillisecondsSinceEpoch(lastSync * 1000)
              .toIso8601String()
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

  /// إعادة حساب الحقول المشتقة للحجز (expected_nights, calculated_nights, إلخ)
  /// بناءً على التواريخ الفعلية بدلاً من الاعتماد على القيم المحفوظة
  Future<void> _recalculateBookingFields(
      AppDatabase db, Booking booking) async {
    try {
      final derivedFieldsService = BookingDerivedFieldsService(db);
      await derivedFieldsService.refreshForBooking(booking);
      _logger.info(
          '✅ تم إعادة حساب الحقول للحجز: ${booking.guestName} (${booking.roomNumber})');
    } catch (e) {
      _logger.warning('⚠️ خطأ في إعادة حساب الحقول للحجز ${booking.id}: $e');
    }
  }

  /// إعادة حساب جميع الحجوزات النشطة بعد استعادة البيانات
  Future<void> _recalculateAllActiveBookings() async {
    if (_database == null) return;

    try {
      debugPrint('🔄 إعادة حساب جميع الحجوزات النشطة...');

      final bookings = await (_database!.select(_database!.bookings)
            ..where((b) => b.deletedAt.isNull()))
          .get();

      final derivedFieldsService = BookingDerivedFieldsService(_database!);

      int recalculated = 0;
      for (final booking in bookings) {
        try {
          await derivedFieldsService.refreshForBooking(booking);
          recalculated++;
        } catch (e) {
          debugPrint('⚠️ خطأ في إعادة حساب الحجز ${booking.id}: $e');
        }
      }

      debugPrint('✅ تم إعادة حساب $recalculated حجز من أصل ${bookings.length}');
    } catch (e) {
      debugPrint('⚠️ خطأ في إعادة حساب الحجوزات: $e');
    }
  }
}
