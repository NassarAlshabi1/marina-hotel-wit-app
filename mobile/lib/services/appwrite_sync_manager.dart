import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as d;
import 'package:appwrite/models.dart' as models;
import '../utils/id.dart';
import '../utils/time.dart';
import 'appwrite_service.dart';
import 'appwrite_logger.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_models.dart';
import 'appwrite_config.dart';
import 'local_db.dart';

/// حالة المزامنة
enum SyncStatus {
  idle,
  syncing,
  success,
  failed,
  partial,
}

/// نتيجة المزامنة
class SyncResult {
  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;

  SyncResult({
    required this.status,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
    required this.timestamp,
    required this.duration,
  });

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
}

/// مدير المزامنة الثنائية
class AppwriteSyncManager {
  final AppwriteService appwriteService;
  final AppDatabase database;
  
  AppwriteSyncManager({required this.appwriteService, required this.database});

  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();
  
  Timer? _syncTimer;
  SyncStatus _currentStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _currentDeviceId;
  String? _deviceLocalUuid;
  int? _deviceVersion;
  int? _deviceCreatedAtEpoch;
  
  final _syncController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncController.stream;

  /// تهيئة المزامنة
  Future<void> initialize() async {
    try {
      await appwriteService.initialize();
      await _loadSettings();
      _logger.info('Sync manager initialized', tag: 'SYNC');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize sync manager', 
        error: e, 
        stackTrace: stackTrace, 
        tag: 'SYNC'
      );
    }
  }

  /// تحميل الإعدادات
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentDeviceId = prefs.getString('appwrite_device_id');

    final lastSyncEpoch = prefs.getInt('appwrite_last_sync_time');
    _lastSyncTime = lastSyncEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncEpoch)
        : null;

    _deviceLocalUuid = prefs.getString('appwrite_device_local_uuid');
    _deviceVersion = prefs.getInt('appwrite_device_version');
    _deviceCreatedAtEpoch = prefs.getInt('appwrite_device_created_at');
  }

  /// حفظ الإعدادات
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentDeviceId != null) {
      await prefs.setString('appwrite_device_id', _currentDeviceId!);
    }
    if (_lastSyncTime != null) {
      await prefs.setInt('appwrite_last_sync_time', _lastSyncTime!.millisecondsSinceEpoch);
    }
    if (_deviceLocalUuid != null) {
      await prefs.setString('appwrite_device_local_uuid', _deviceLocalUuid!);
    }
    if (_deviceVersion != null) {
      await prefs.setInt('appwrite_device_version', _deviceVersion!);
    }
    if (_deviceCreatedAtEpoch != null) {
      await prefs.setInt('appwrite_device_created_at', _deviceCreatedAtEpoch!);
    }
  }

  /// تسجيل الجهاز
  Future<String> registerDevice({
    required String deviceName,
    required String deviceModel,
    required String osVersion,
  }) async {
    try {
      _logger.info('Registering device: $deviceName', tag: 'SYNC');
      final deviceType = _resolveDeviceType();
      final nowIso = Time.nowIso();
      final nowEpoch = Time.nowEpoch();

      _deviceLocalUuid ??= IdGen.uuid();
      _deviceCreatedAtEpoch ??= nowEpoch;

      if (_currentDeviceId != null) {
        _deviceVersion = (_deviceVersion ?? 1) + 1;

        await appwriteService.updateDocument(
          collectionId: AppwriteConfig.devicesCollectionId,
          documentId: _currentDeviceId!,
          data: {
            'deviceName': deviceName,
            'deviceModel': deviceModel,
            'osVersion': osVersion,
            'deviceType': deviceType,
            'status': 'active',
            'localUuid': _deviceLocalUuid,
            'lastSeen': nowIso,
            'lastActive': nowEpoch,
            'createdAt': _deviceCreatedAtEpoch,
            'updatedAt': nowEpoch,
            'lastModified': nowEpoch,
            'version': _deviceVersion,
            'origin': 'mobile',
          },
        );

        await _saveSettings();
        _logger.info('Device updated: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      } else {
        _deviceVersion = 1;
        _deviceCreatedAtEpoch = nowEpoch;

        final device = await appwriteService.createDevice({
          'deviceName': deviceName,
          'deviceModel': deviceModel,
          'osVersion': osVersion,
          'deviceType': deviceType,
          'status': 'active',
          'localUuid': _deviceLocalUuid,
          'lastSeen': nowIso,
          'lastActive': nowEpoch,
          'createdAt': _deviceCreatedAtEpoch,
          'updatedAt': nowEpoch,
          'lastModified': nowEpoch,
          'version': _deviceVersion,
          'origin': 'mobile',
        });
        
        _currentDeviceId = device.$id;
        await _saveSettings();
        
        _logger.info('Device registered: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to register device', 
        error: e, 
        stackTrace: stackTrace, 
        tag: 'SYNC'
      );
      rethrow;
    }
  }

  /// بدء المزامنة التلقائية
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (timer) async {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('appwrite_sync_enabled') ?? false;
      
      if (enabled) {
        await sync();
      }
    });
    _logger.info('Auto sync started (interval: ${interval.inMinutes} min)', tag: 'SYNC');
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _logger.info('Auto sync stopped', tag: 'SYNC');
  }

  /// تنفيذ المزامنة
  Future<SyncResult> sync() async {
    if (_currentStatus == SyncStatus.syncing) {
      _logger.warning('Sync already in progress', tag: 'SYNC');
      return SyncResult(
        status: SyncStatus.failed,
        errorMessage: 'Sync already in progress',
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
    }

    _currentStatus = SyncStatus.syncing;
    _syncController.add(_currentStatus);
    
    final startTime = DateTime.now();
    int recordsPushed = 0;
    int recordsPulled = 0;
    int conflicts = 0;
    String? errorMessage;
    SyncStatus finalStatus = SyncStatus.success;
    String? syncLogId;
    String? syncLogLocalUuid;
    int syncLogVersion = 1;
    int? syncLogCreatedEpoch;

    try {
      _logger.info('Starting sync...', tag: 'SYNC');

      // التحقق من الاتصال
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        throw Exception('No internet connection');
      }

      // إنشاء سجل مزامنة
      syncLogLocalUuid = IdGen.uuid();
      syncLogCreatedEpoch = Time.nowEpoch();

      final syncLog = await appwriteService.createSyncLog({
        'deviceId': _currentDeviceId ?? 'unknown',
        'syncType': 'full',
        'startTime': startTime.toIso8601String(),
        'status': 'in_progress',
        'action': 'sync_start',
        'details': '{"recordsPushed":0,"recordsPulled":0,"conflicts":0}',
        'timestamp': syncLogCreatedEpoch,
        'localUuid': syncLogLocalUuid,
        'createdAt': syncLogCreatedEpoch,
        'updatedAt': syncLogCreatedEpoch,
        'lastModified': syncLogCreatedEpoch,
        'version': syncLogVersion,
        'origin': 'mobile',
      });
      syncLogId = syncLog.$id;

      final pushedCount = await _pushAllEntities();
      recordsPushed += pushedCount;

      // مزامنة الغرف
      final rooms = await appwriteService.listRooms(useCache: false);
      final roomsSynced = await _syncRooms(rooms);
      recordsPulled += roomsSynced;
      _logger.debug('Synced $roomsSynced rooms', tag: 'SYNC');

      // مزامنة الحجوزات
      final bookings = await appwriteService.listBookings(useCache: false);
      final bookingsSynced = await _syncBookings(bookings);
      recordsPulled += bookingsSynced;
      _logger.debug('Synced $bookingsSynced bookings', tag: 'SYNC');

      // مزامنة الموظفين
      final employees = await appwriteService.listEmployees(useCache: false);
      final employeesSynced = await _syncEmployees(employees);
      recordsPulled += employeesSynced;
      _logger.debug('Synced $employeesSynced employees', tag: 'SYNC');

      // مزامنة المصروفات
      final expenses = await appwriteService.listExpenses(useCache: false);
      final expensesSynced = await _syncExpenses(expenses);
      recordsPulled += expensesSynced;
      _logger.debug('Synced $expensesSynced expenses', tag: 'SYNC');

      // مزامنة المدفوعات
      final payments = await appwriteService.listPayments(useCache: false);
      final paymentsSynced = await _syncPayments(payments);
      recordsPulled += paymentsSynced;
      _logger.debug('Synced $paymentsSynced payments', tag: 'SYNC');

      // مزامنة الديون
      final debts = await appwriteService.listDebts(useCache: false);
      final debtsSynced = await _syncDebts(debts);
      recordsPulled += debtsSynced;
      _logger.debug('Synced $debtsSynced debts', tag: 'SYNC');

      // تحديث سجل المزامنة
      final endTime = DateTime.now();
      final endEpoch = Time.nowEpoch();
      syncLogVersion += 1;

      await appwriteService.updateDocument(
        collectionId: AppwriteConfig.syncLogsCollectionId,
        documentId: syncLogId!,
        data: {
          'endTime': endTime.toIso8601String(),
          'status': 'completed',
          'action': 'sync_complete',
          'details': '{"recordsPushed":$recordsPushed,"recordsPulled":$recordsPulled,"conflicts":$conflicts}',
          'updatedAt': endEpoch,
          'lastModified': endEpoch,
          'timestamp': endEpoch,
          'version': syncLogVersion,
          if (syncLogLocalUuid != null) 'localUuid': syncLogLocalUuid,
          'origin': 'mobile',
        },
      );

      _lastSyncTime = endTime;
      await _saveSettings();

      _logger.info('Sync completed successfully (pushed: $recordsPushed, pulled: $recordsPulled)', 
        tag: 'SYNC'
      );

    } catch (e, stackTrace) {
      errorMessage = e.toString();
      finalStatus = SyncStatus.failed;

      if (syncLogId != null) {
        final failEpoch = Time.nowEpoch();
        syncLogVersion += 1;
        try {
          await appwriteService.updateDocument(
            collectionId: AppwriteConfig.syncLogsCollectionId,
            documentId: syncLogId!,
            data: {
              'status': 'failed',
              'action': 'sync_failed',
              'errorMessage': errorMessage,
              'details': '{"recordsPushed":$recordsPushed,"recordsPulled":$recordsPulled,"conflicts":$conflicts}',
              'updatedAt': failEpoch,
              'lastModified': failEpoch,
              'timestamp': failEpoch,
              if (syncLogLocalUuid != null) 'localUuid': syncLogLocalUuid,
              'origin': 'mobile',
            },
          );
        } catch (_) {}
      }
      
      _errorHandler.handleError(e, 
        context: 'sync()', 
        stackTrace: stackTrace
      );
      
      _logger.error('Sync failed', error: e, stackTrace: stackTrace, tag: 'SYNC');
    }

    _currentStatus = finalStatus;
    _syncController.add(_currentStatus);

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    return SyncResult(
      status: finalStatus,
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      conflicts: conflicts,
      errorMessage: errorMessage,
      timestamp: endTime,
      duration: duration,
    );
  }

  /// الحصول على إحصائيات المزامنة
  Future<Map<String, dynamic>> getSyncStatistics() async {
    try {
      final syncLogs = await appwriteService.listSyncLogs(useCache: false);

      int extractCount(Map<String, dynamic> data, String key) {
        final value = data[key];
        if (value is num) {
          return value.toInt();
        }

        final details = data['details'];
        if (details is String && details.isNotEmpty) {
          try {
            final decoded = jsonDecode(details);
            if (decoded is Map<String, dynamic>) {
              final detailValue = decoded[key];
              if (detailValue is num) {
                return detailValue.toInt();
              }
            }
          } catch (_) {}
        }

        return 0;
      }
      
      int totalSyncs = syncLogs.length;
      int successfulSyncs = syncLogs.where((log) => 
        log.data['status'] == 'completed'
      ).length;
      int failedSyncs = syncLogs.where((log) => 
        log.data['status'] == 'failed'
      ).length;
      
      int totalRecordsPushed = syncLogs.fold<int>(0, (sum, log) => 
        sum + extractCount(Map<String, dynamic>.from(log.data), 'recordsPushed')
      );
      int totalRecordsPulled = syncLogs.fold<int>(0, (sum, log) => 
        sum + extractCount(Map<String, dynamic>.from(log.data), 'recordsPulled')
      );
      int totalConflicts = syncLogs.fold<int>(0, (sum, log) => 
        sum + extractCount(Map<String, dynamic>.from(log.data), 'conflicts')
      );

      return {
        'totalSyncs': totalSyncs,
        'successfulSyncs': successfulSyncs,
        'failedSyncs': failedSyncs,
        'successRate': totalSyncs > 0 ? (successfulSyncs / totalSyncs * 100) : 0.0,
        'totalRecordsPushed': totalRecordsPushed,
        'totalRecordsPulled': totalRecordsPulled,
        'totalConflicts': totalConflicts,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
      };
    } catch (e) {
      _logger.error('Failed to get sync statistics', error: e, tag: 'SYNC');
      return {
        'totalSyncs': 0,
        'successfulSyncs': 0,
        'failedSyncs': 0,
        'successRate': 0.0,
        'totalRecordsPushed': 0,
        'totalRecordsPulled': 0,
        'totalConflicts': 0,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
      };
    }
  }

  Future<int> _syncRooms(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    await database.transaction(() async {
      await database.batch((batch) {
        for (final doc in documents) {
          final data = Map<String, dynamic>.from(doc.data);
          final roomNumber = _asString(data['roomNumber']);
          if (roomNumber == null || roomNumber.isEmpty) {
            continue;
          }
          final localUuid = _asString(data['localUuid']) ?? doc.$id;
          final companion = RoomsCompanion(
            roomNumber: d.Value(roomNumber),
            type: d.Value(_asString(data['type']) ?? ''),
            price: d.Value(_asDouble(data['price'])),
            status: d.Value(_asString(data['status']) ?? 'available'),
            imageUrl: _nullableValue<String>(_asString(data['imageUrl'])),
            localUuid: d.Value(localUuid),
            serverId: _nullableValue<int>(_asIntNullable(data['serverId'])),
            createdAt: d.Value(_normalizeEpoch(data['createdAt'])),
            updatedAt: d.Value(_normalizeEpoch(data['updatedAt'])),
            deletedAt: _nullableValue<int>(_normalizeEpochNullable(data['deletedAt'])),
            lastModified: d.Value(_normalizeEpoch(data['lastModified'])),
            version: d.Value(_asInt(data['version'], fallback: 1)),
            origin: d.Value(_asString(data['origin']) ?? 'server'),
          );
          batch.insert(database.rooms, companion, mode: d.InsertMode.insertOrReplace);
          processed++;
        }
      });
    });
    return processed;
  }

  Future<int> _syncBookings(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    await database.transaction(() async {
      await database.batch((batch) {
        for (final doc in documents) {
          final data = Map<String, dynamic>.from(doc.data);
          final localUuid = _asString(data['localUuid']) ?? doc.$id;
          final roomNumber = _asString(data['roomNumber']) ?? '';
          if (localUuid.isEmpty || roomNumber.isEmpty) {
            continue;
          }
          final companion = BookingsCompanion(
            localUuid: d.Value(localUuid),
            serverId: _nullableValue<int>(_asIntNullable(data['serverId'])),
            createdAt: d.Value(_normalizeEpoch(data['createdAt'])),
            updatedAt: d.Value(_normalizeEpoch(data['updatedAt'])),
            deletedAt: _nullableValue<int>(_normalizeEpochNullable(data['deletedAt'])),
            lastModified: d.Value(_normalizeEpoch(data['lastModified'])),
            version: d.Value(_asInt(data['version'], fallback: 1)),
            origin: d.Value(_asString(data['origin']) ?? 'server'),
            serverBookingId: _nullableValue<int>(_asIntNullable(data['serverBookingId'])),
            roomNumber: d.Value(roomNumber),
            guestName: d.Value(_asString(data['guestName']) ?? ''),
            guestPhone: d.Value(_asString(data['guestPhone']) ?? ''),
            guestIdType: d.Value(_asString(data['guestIdType']) ?? ''),
            guestIdNumber: d.Value(_asString(data['guestIdNumber']) ?? ''),
            guestIdIssueDate: _nullableValue<String>(_asString(data['guestIdIssueDate'])),
            guestIdIssuePlace: _nullableValue<String>(_asString(data['guestIdIssuePlace'])),
            guestNationality: d.Value(_asString(data['guestNationality']) ?? ''),
            guestEmail: _nullableValue<String>(_asString(data['guestEmail'])),
            guestAddress: _nullableValue<String>(_asString(data['guestAddress'])),
            checkinDate: d.Value(_asString(data['checkinDate']) ?? ''),
            checkoutDate: _nullableValue<String>(_asString(data['checkoutDate'])),
            actualCheckout: _nullableValue<String>(_asString(data['actualCheckout'])),
            status: d.Value(_asString(data['status']) ?? ''),
            notes: _nullableValue<String>(_asString(data['notes'])),
            expectedNights: d.Value(_asInt(data['expectedNights'], fallback: 1)),
            calculatedNights: d.Value(_asInt(data['calculatedNights'], fallback: 1)),
          );
          batch.insert(database.bookings, companion, mode: d.InsertMode.insertOrReplace);
          processed++;
        }
      });
    });
    return processed;
  }

  Future<int> _syncEmployees(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    await database.transaction(() async {
      await database.batch((batch) {
        for (final doc in documents) {
          final data = Map<String, dynamic>.from(doc.data);
          final localUuid = _asString(data['localUuid']) ?? doc.$id;
          final name = _asString(data['name']);
          if (localUuid.isEmpty || name == null || name.isEmpty) {
            continue;
          }
          final companion = EmployeesCompanion(
            localUuid: d.Value(localUuid),
            serverId: _nullableValue<int>(_asIntNullable(data['serverId'])),
            createdAt: d.Value(_normalizeEpoch(data['createdAt'])),
            updatedAt: d.Value(_normalizeEpoch(data['updatedAt'])),
            deletedAt: _nullableValue<int>(_normalizeEpochNullable(data['deletedAt'])),
            lastModified: d.Value(_normalizeEpoch(data['lastModified'])),
            version: d.Value(_asInt(data['version'], fallback: 1)),
            origin: d.Value(_asString(data['origin']) ?? 'server'),
            name: d.Value(name),
            basicSalary: d.Value(_asDouble(data['basicSalary'])),
            position: d.Value(_asString(data['position']) ?? ''),
            phone: d.Value(_asString(data['phone']) ?? ''),
            hireDate: d.Value(_asString(data['hireDate']) ?? ''),
            status: d.Value(_asString(data['status']) ?? ''),
          );
          batch.insert(database.employees, companion, mode: d.InsertMode.insertOrReplace);
          processed++;
        }
      });
    });
    return processed;
  }

  Future<int> _syncExpenses(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    await database.transaction(() async {
      await database.batch((batch) {
        for (final doc in documents) {
          final data = Map<String, dynamic>.from(doc.data);
          final localUuid = _asString(data['localUuid']) ?? doc.$id;
          final expenseType = _asString(data['expenseType']);
          if (localUuid.isEmpty || expenseType == null || expenseType.isEmpty) {
            continue;
          }
          final companion = ExpensesCompanion(
            localUuid: d.Value(localUuid),
            serverId: _nullableValue<int>(_asIntNullable(data['serverId'])),
            createdAt: d.Value(_normalizeEpoch(data['createdAt'])),
            updatedAt: d.Value(_normalizeEpoch(data['updatedAt'])),
            deletedAt: _nullableValue<int>(_normalizeEpochNullable(data['deletedAt'])),
            lastModified: d.Value(_normalizeEpoch(data['lastModified'])),
            version: d.Value(_asInt(data['version'], fallback: 1)),
            origin: d.Value(_asString(data['origin']) ?? 'server'),
            expenseType: d.Value(expenseType),
            relatedId: _nullableValue<int>(_asIntNullable(data['relatedId'])),
            description: d.Value(_asString(data['description']) ?? ''),
            amount: d.Value(_asDouble(data['amount'])),
            date: d.Value(_asString(data['date']) ?? ''),
            cashTransactionId: _nullableValue<int>(_asIntNullable(data['cashTransactionId'])),
          );
          batch.insert(database.expenses, companion, mode: d.InsertMode.insertOrReplace);
          processed++;
        }
      });
    });
    return processed;
  }

  Future<int> _syncPayments(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    await database.transaction(() async {
      await database.batch((batch) {
        for (final doc in documents) {
          final data = Map<String, dynamic>.from(doc.data);
          final localUuid = _asString(data['localUuid']) ?? doc.$id;
          if (localUuid.isEmpty) {
            continue;
          }
          final companion = PaymentsCompanion(
            localUuid: d.Value(localUuid),
            serverId: _nullableValue<int>(_asIntNullable(data['serverId'])),
            createdAt: d.Value(_normalizeEpoch(data['createdAt'])),
            updatedAt: d.Value(_normalizeEpoch(data['updatedAt'])),
            deletedAt: _nullableValue<int>(_normalizeEpochNullable(data['deletedAt'])),
            lastModified: d.Value(_normalizeEpoch(data['lastModified'])),
            version: d.Value(_asInt(data['version'], fallback: 1)),
            origin: d.Value(_asString(data['origin']) ?? 'server'),
            serverPaymentId: _nullableValue<int>(_asIntNullable(data['serverPaymentId'])),
            bookingLocalId: _nullableValue<int>(_asIntNullable(data['bookingLocalId'])),
            serverBookingId: _nullableValue<int>(_asIntNullable(data['serverBookingId'])),
            roomNumber: _nullableValue<String>(_asString(data['roomNumber'])),
            amount: d.Value(_asDouble(data['amount'])),
            paymentDate: d.Value(_asString(data['paymentDate']) ?? ''),
            notes: _nullableValue<String>(_asString(data['notes'])),
            paymentMethod: d.Value(_asString(data['paymentMethod']) ?? ''),
            revenueType: d.Value(_asString(data['revenueType']) ?? ''),
            cashTransactionLocalId: _nullableValue<int>(_asIntNullable(data['cashTransactionLocalId'])),
            cashTransactionServerId: _nullableValue<int>(_asIntNullable(data['cashTransactionServerId'])),
            referenceNumber: _nullableValue<String>(_asString(data['referenceNumber'])),
          );
          batch.insert(database.payments, companion, mode: d.InsertMode.insertOrReplace);
          processed++;
        }
      });
    });
    return processed;
  }

  Future<int> _syncDebts(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    await database.transaction(() async {
      await database.batch((batch) {
        for (final doc in documents) {
          final data = Map<String, dynamic>.from(doc.data);
          final localUuid = _asString(data['localUuid']) ?? doc.$id;
          final guestName = _asString(data['guestName']);
          if (localUuid.isEmpty || guestName == null || guestName.isEmpty) {
            continue;
          }
          final companion = DebtsCompanion(
            localUuid: d.Value(localUuid),
            serverId: _nullableValue<int>(_asIntNullable(data['serverId'])),
            createdAt: d.Value(_normalizeEpoch(data['createdAt'])),
            updatedAt: d.Value(_normalizeEpoch(data['updatedAt'])),
            deletedAt: _nullableValue<int>(_normalizeEpochNullable(data['deletedAt'])),
            lastModified: d.Value(_normalizeEpoch(data['lastModified'])),
            version: d.Value(_asInt(data['version'], fallback: 1)),
            origin: d.Value(_asString(data['origin']) ?? 'server'),
            bookingLocalId: _nullableValue<int>(_asIntNullable(data['bookingLocalId'])),
            guestName: d.Value(guestName),
            checkinDate: d.Value(_asString(data['checkinDate']) ?? ''),
            checkoutDate: d.Value(_asString(data['checkoutDate']) ?? ''),
            dateRecorded: d.Value(_asString(data['dateRecorded']) ?? ''),
            debtReason: d.Value(_asString(data['debtReason']) ?? ''),
            totalAmount: d.Value(_asDouble(data['totalAmount'])),
            paidAmount: d.Value(_asDouble(data['paidAmount'])),
            remainingAmount: d.Value(_asDouble(data['remainingAmount'])),
            paymentDate: d.Value(_asString(data['paymentDate']) ?? ''),
            isSettled: d.Value(_asInt(data['isSettled'], fallback: 0)),
            pledge: _nullableValue<String>(_asString(data['pledge'])),
            pledgeType: _nullableValue<String>(_asString(data['pledgeType'])),
            note: _nullableValue<String>(_asString(data['note'])),
          );
          batch.insert(database.debts, companion, mode: d.InsertMode.insertOrReplace);
          processed++;
        }
      });
    });
    return processed;
  }

  d.Value<T?> _nullableValue<T>(T? value) {
    return value == null ? const d.Value.absent() : d.Value(value);
  }

  int _normalizeEpoch(dynamic value, {int? fallback}) {
    if (value == null) {
      return fallback ?? Time.nowEpoch();
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is DateTime) {
      return value.toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    if (value is String && value.isNotEmpty) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        return parsedInt;
      }
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) {
        return parsedDouble.toInt();
      }
      final parsedDate = DateTime.tryParse(value);
      if (parsedDate != null) {
        return parsedDate.toUtc().millisecondsSinceEpoch ~/ 1000;
      }
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback ?? Time.nowEpoch();
  }

  int? _normalizeEpochNullable(dynamic value) {
    if (value == null) {
      return null;
    }
    return _normalizeEpoch(value);
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    final result = _asIntNullable(value);
    return result ?? fallback;
  }

  int? _asIntNullable(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String && value.isNotEmpty) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        return parsedInt;
      }
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) {
        return parsedDouble.toInt();
      }
    }
    return null;
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) {
      return fallback;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String && value.isNotEmpty) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return fallback;
  }

  String? _asString(dynamic value) {
    if (value == null) {
      return null;
    }
    final result = value.toString();
    if (result.isEmpty) {
      return null;
    }
    return result;
  }

  Future<int> _pushAllEntities() async {
    var total = 0;
    total += await _pushRooms();
    total += await _pushBookings();
    total += await _pushExpenses();
    total += await _pushPayments();
    total += await _pushDebts();
    return total;
  }

  Future<int> _pushRooms() async {
    final roomsList = await (database.select(database.rooms)).get();
    var processed = 0;
    for (final room in roomsList) {
      final payload = _roomToRemote(room);
      try {
        await appwriteService.upsertRoom(room.localUuid, payload);
        processed++;
      } catch (error, stackTrace) {
        _logger.error('Failed to push room ${room.roomNumber}', error: error, stackTrace: stackTrace, tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _pushBookings() async {
    final bookingsList = await (database.select(database.bookings)).get();
    var processed = 0;
    for (final booking in bookingsList) {
      final payload = _bookingToRemote(booking);
      try {
        await appwriteService.upsertBooking(booking.localUuid, payload);
        processed++;
      } catch (error, stackTrace) {
        _logger.error('Failed to push booking ${booking.localUuid}', error: error, stackTrace: stackTrace, tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _pushExpenses() async {
    final expensesList = await (database.select(database.expenses)).get();
    var processed = 0;
    for (final expense in expensesList) {
      final payload = _expenseToRemote(expense);
      try {
        await appwriteService.upsertExpense(expense.localUuid, payload);
        processed++;
      } catch (error, stackTrace) {
        _logger.error('Failed to push expense ${expense.localUuid}', error: error, stackTrace: stackTrace, tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _pushPayments() async {
    final paymentsList = await (database.select(database.payments)).get();
    var processed = 0;
    for (final payment in paymentsList) {
      final payload = _paymentToRemote(payment);
      try {
        await appwriteService.upsertPayment(payment.localUuid, payload);
        processed++;
      } catch (error, stackTrace) {
        _logger.error('Failed to push payment ${payment.localUuid}', error: error, stackTrace: stackTrace, tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _pushDebts() async {
    final debtsList = await (database.select(database.debts)).get();
    var processed = 0;
    for (final debt in debtsList) {
      final payload = _debtToRemote(debt);
      try {
        await appwriteService.upsertDebt(debt.localUuid, payload);
        processed++;
      } catch (error, stackTrace) {
        _logger.error('Failed to push debt ${debt.localUuid}', error: error, stackTrace: stackTrace, tag: 'SYNC');
      }
    }
    return processed;
  }

  Map<String, dynamic> _roomToRemote(Room room) {
    final data = <String, dynamic>{
      'roomNumber': room.roomNumber,
      'type': room.type,
      'price': room.price,
      'status': room.status,
      'localUuid': room.localUuid,
      'createdAt': room.createdAt,
      'updatedAt': room.updatedAt,
      'lastModified': room.lastModified,
      'version': room.version,
      'origin': room.origin,
    };
    _putIfNotNull(data, 'serverId', room.serverId);
    _putIfNotNull(data, 'deletedAt', room.deletedAt);
    _putIfStringNotEmpty(data, 'imageUrl', room.imageUrl);
    return data;
  }

  Map<String, dynamic> _bookingToRemote(Booking booking) {
    final data = <String, dynamic>{
      'roomNumber': booking.roomNumber,
      'guestName': booking.guestName,
      'guestPhone': booking.guestPhone,
      'guestIdType': booking.guestIdType,
      'guestIdNumber': booking.guestIdNumber,
      'guestNationality': booking.guestNationality,
      'checkinDate': booking.checkinDate,
      'status': booking.status,
      'expectedNights': booking.expectedNights,
      'calculatedNights': booking.calculatedNights,
      'localUuid': booking.localUuid,
      'createdAt': booking.createdAt,
      'updatedAt': booking.updatedAt,
      'lastModified': booking.lastModified,
      'version': booking.version,
      'origin': booking.origin,
    };
    _putIfNotNull(data, 'serverBookingId', booking.serverBookingId);
    _putIfNotNull(data, 'serverId', booking.serverId);
    _putIfNotNull(data, 'deletedAt', booking.deletedAt);
    _putIfStringNotEmpty(data, 'guestIdIssueDate', booking.guestIdIssueDate);
    _putIfStringNotEmpty(data, 'guestIdIssuePlace', booking.guestIdIssuePlace);
    _putIfStringNotEmpty(data, 'guestEmail', booking.guestEmail);
    _putIfStringNotEmpty(data, 'guestAddress', booking.guestAddress);
    _putIfStringNotEmpty(data, 'checkoutDate', booking.checkoutDate);
    _putIfStringNotEmpty(data, 'actualCheckout', booking.actualCheckout);
    _putIfStringNotEmpty(data, 'notes', booking.notes);
    return data;
  }

  Map<String, dynamic> _expenseToRemote(Expense expense) {
    final data = <String, dynamic>{
      'expenseType': expense.expenseType,
      'description': expense.description,
      'amount': expense.amount,
      'date': expense.date,
      'localUuid': expense.localUuid,
      'createdAt': expense.createdAt,
      'updatedAt': expense.updatedAt,
      'lastModified': expense.lastModified,
      'version': expense.version,
      'origin': expense.origin,
    };
    _putIfNotNull(data, 'relatedId', expense.relatedId);
    _putIfNotNull(data, 'cashTransactionId', expense.cashTransactionId);
    _putIfNotNull(data, 'serverId', expense.serverId);
    _putIfNotNull(data, 'deletedAt', expense.deletedAt);
    return data;
  }

  Map<String, dynamic> _paymentToRemote(Payment payment) {
    final data = <String, dynamic>{
      'amount': payment.amount,
      'paymentDate': payment.paymentDate,
      'paymentMethod': payment.paymentMethod,
      'revenueType': payment.revenueType,
      'localUuid': payment.localUuid,
      'createdAt': payment.createdAt,
      'updatedAt': payment.updatedAt,
      'lastModified': payment.lastModified,
      'version': payment.version,
      'origin': payment.origin,
    };
    _putIfNotNull(data, 'serverPaymentId', payment.serverPaymentId);
    _putIfNotNull(data, 'bookingLocalId', payment.bookingLocalId);
    _putIfNotNull(data, 'serverBookingId', payment.serverBookingId);
    _putIfStringNotEmpty(data, 'roomNumber', payment.roomNumber);
    _putIfStringNotEmpty(data, 'notes', payment.notes);
    _putIfNotNull(data, 'cashTransactionLocalId', payment.cashTransactionLocalId);
    _putIfNotNull(data, 'cashTransactionServerId', payment.cashTransactionServerId);
    _putIfStringNotEmpty(data, 'referenceNumber', payment.referenceNumber);
    _putIfNotNull(data, 'serverId', payment.serverId);
    _putIfNotNull(data, 'deletedAt', payment.deletedAt);
    return data;
  }

  Map<String, dynamic> _debtToRemote(Debt debt) {
    final data = <String, dynamic>{
      'amount': debt.totalAmount,
      'debtorName': debt.guestName,
      'dueDate': _resolveDebtDueDate(debt),
      'status': debt.isSettled == 1 ? 'settled' : 'pending',
      'localUuid': debt.localUuid,
      'createdAt': debt.createdAt,
      'updatedAt': debt.updatedAt,
      'lastModified': debt.lastModified,
      'version': debt.version,
      'origin': debt.origin,
    };
    _putIfNotNull(data, 'serverId', debt.serverId);
    _putIfNotNull(data, 'deletedAt', debt.deletedAt);
    return data;
  }

  String _resolveDebtDueDate(Debt debt) {
    final candidates = [debt.checkoutDate, debt.paymentDate, debt.dateRecorded];
    for (final value in candidates) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '1970-01-01';
  }

  void _putIfNotNull<T>(Map<String, dynamic> map, String key, T? value) {
    if (value != null) {
      map[key] = value;
    }
  }

  void _putIfStringNotEmpty(Map<String, dynamic> map, String key, String? value) {
    if (value != null && value.isNotEmpty) {
      map[key] = value;
    }
  }

  /// الحصول على قائمة الأجهزة المسجلة
  Future<List<AppwriteDevice>> getRegisteredDevices() async {
    try {
      final devices = await appwriteService.listDevices(useCache: false);
      return devices.map((doc) => AppwriteDevice.fromJson(doc.data)).toList();
    } catch (e) {
      _logger.error('Failed to get registered devices', error: e, tag: 'SYNC');
      return [];
    }
  }

  /// رفع جميع البيانات المحلية
  Future<void> pushAllLocalData() async {
    _logger.info('Pushing all local data...', tag: 'SYNC');
    // TODO: تنفيذ رفع البيانات من قاعدة البيانات المحلية
    throw UnimplementedError('Push all local data not implemented yet');
  }

  /// تحميل جميع البيانات من الخادم
  Future<void> pullAllRemoteData() async {
    _logger.info('Pulling all remote data...', tag: 'SYNC');
    // TODO: تنفيذ تحميل البيانات وحفظها في قاعدة البيانات المحلية
    throw UnimplementedError('Pull all remote data not implemented yet');
  }

  /// إعادة تعيين حالة المزامنة
  Future<void> resetSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('appwrite_last_sync_time');
    _lastSyncTime = null;
    _logger.info('Sync state reset', tag: 'SYNC');
  }

  // Getters
  SyncStatus get currentStatus => _currentStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get currentDeviceId => _currentDeviceId;
  bool get isSyncing => _currentStatus == SyncStatus.syncing;

  String _resolveDeviceType() {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
      default:
        return 'unknown';
    }
  }

  /// التخلص من الموارد
  void dispose() {
    stopAutoSync();
    _syncController.close();
  }
}
