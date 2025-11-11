import 'dart:async';
import 'dart:convert';

import 'package:ditto_live/ditto_live.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/ditto_config.dart';
import '../utils/env.dart';
import 'daos/booking_notes_dao.dart';
import 'daos/bookings_dao.dart';
import 'daos/cash_transactions_dao.dart';
import 'daos/debts_dao.dart';
import 'daos/employees_dao.dart';
import 'daos/expenses_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/payments_dao.dart';
import 'daos/rooms_dao.dart';
import 'daos/shift_notes_dao.dart';
import 'ditto_schema_mapper.dart';
import 'local_db.dart';

class DittoLocalSyncService {
  DittoLocalSyncService._internal();

  static final DittoLocalSyncService _instance = DittoLocalSyncService._internal();

  factory DittoLocalSyncService() => _instance;

  Ditto? _ditto;
  AppDatabase? _database;
  static const _autoSyncPrefKey = 'ditto_auto_sync_enabled';
  static bool _dittoSdkInitialized = false;

  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _subscriptionsRegistered = false;
  bool _autoSyncAttempted = false;
  DateTime? _lastSyncTime;
  String? _lastError;

  OutboxDao? _outboxDao;
  RoomsDao? _roomsDao;
  BookingsDao? _bookingsDao;
  BookingNotesDao? _bookingNotesDao;
  EmployeesDao? _employeesDao;
  ExpensesDao? _expensesDao;
  CashTransactionsDao? _cashTransactionsDao;
  PaymentsDao? _paymentsDao;
  DebtsDao? _debtsDao;
  ShiftNotesDao? _shiftNotesDao;

  Future<bool> initialize(AppDatabase database) async {
    if (_isInitialized && _database == database && _ditto != null) {
      return true;
    }
    debugPrint('🔄 بدء تهيئة DittoLocalSyncService...');
    _database = database;
    _subscriptionsRegistered = false;
    _outboxDao = OutboxDao(database);
    _roomsDao = RoomsDao(database, _outboxDao!);
    _bookingsDao = BookingsDao(database, _outboxDao!);
    _bookingNotesDao = BookingNotesDao(database, _outboxDao!);
    _employeesDao = EmployeesDao(database, _outboxDao!);
    _expensesDao = ExpensesDao(database, _outboxDao!);
    _cashTransactionsDao = CashTransactionsDao(database, _outboxDao!);
    _paymentsDao = PaymentsDao(database, _outboxDao!);
    _debtsDao = DebtsDao(database);
    _shiftNotesDao = ShiftNotesDao(database);
    try {
      if (!_dittoSdkInitialized) {
        await Ditto.init();
        _dittoSdkInitialized = true;
      }
      final identity = await _buildIdentity();
      final instance = await Ditto.open(identity: identity);
      await instance.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
      instance.updateTransportConfig((config) {
        config.setAllPeerToPeerEnabled(false);
        config.connect.webSocketUrls
          ..clear()
          ..add('wss://${Env.dittoAppId}.cloud.ditto.live');
      });
      if (DittoConfig.enableCloudTransport && instance.deviceName.isNotEmpty) {
        instance.deviceName = DittoConfig.deviceName(instance.deviceName);
      }
      _ditto = instance;
      await _registerSubscriptions();
      _isInitialized = true;
      debugPrint('✅ تم تهيئة DittoLocalSyncService بنجاح');
      return true;
    } catch (error, stack) {
      _lastError = error.toString();
      debugPrint('❌ فشل تهيئة DittoLocalSyncService: $error');
      debugPrint(stack.toString());
      _isInitialized = false;
      _ditto = null;
      return false;
    }
  }

  Future<void> startSync() async {
    _ensureReady();
    _ditto!.startSync();
    debugPrint('🛰️ تم تشغيل المزامنة مع Ditto');
  }

  Future<void> stopSync() async {
    if (_ditto == null) {
      return;
    }
    _ditto!.stopSync();
    debugPrint('⏹️ تم إيقاف المزامنة مع Ditto');
  }

  Future<Map<String, int>> pushLocalData() async {
    _ensureReady();
    debugPrint('🚀 بدء رفع البيانات المحلية إلى Ditto...');
    final summary = <String, int>{};
    Future<int> pushCollection<T>({
      required String label,
      required Future<List<T>> Function() fetch,
      required Map<String, dynamic> Function(T item) toDocument,
    }) async {
      int success = 0;
      try {
        final items = await fetch();
        if (items.isEmpty) {
          debugPrint('ℹ️ لا توجد عناصر لرفعها في $label');
          summary['${label}_pushed'] = 0;
          return 0;
        }
        for (final item in items) {
          try {
            final doc = toDocument(item);
            // استخدام DQL بدلاً من legacy API
            await _ditto!.store.execute(
              query: "INSERT INTO $label DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
              arguments: {"doc": doc},
            );
            success++;
          } catch (error) {
            debugPrint('❌ فشل رفع عنصر من $label: $error');
          }
        }
        debugPrint('✅ تم رفع $success سجل إلى $label');
      } catch (error) {
        debugPrint('❌ حدث خطأ أثناء رفع مجموعة $label: $error');
      }
      summary['${label}_pushed'] = success;
      return success;
    }

    await pushCollection<Room>(
      label: DittoSchemaMapper.roomsCollection,
      fetch: () => _roomsDao!.list(includeDeleted: false),
      toDocument: DittoSchemaMapper.roomToDitto,
    );
    await pushCollection<Booking>(
      label: DittoSchemaMapper.bookingsCollection,
      fetch: () => _bookingsDao!.list(includeDeleted: false),
      toDocument: DittoSchemaMapper.bookingToDitto,
    );
    await pushCollection<BookingNote>(
      label: DittoSchemaMapper.bookingNotesCollection,
      fetch: () => _bookingNotesDao!.list(includeDeleted: false),
      toDocument: DittoSchemaMapper.bookingNoteToDitto,
    );
    await pushCollection<Employee>(
      label: DittoSchemaMapper.employeesCollection,
      fetch: () => _employeesDao!.list(includeDeleted: false),
      toDocument: DittoSchemaMapper.employeeToDitto,
    );
    await pushCollection<Expense>(
      label: DittoSchemaMapper.expensesCollection,
      fetch: () => _expensesDao!.list(includeDeleted: false),
      toDocument: DittoSchemaMapper.expenseToDitto,
    );
    await pushCollection<CashTransaction>(
      label: DittoSchemaMapper.cashTransactionsCollection,
      fetch: () => _cashTransactionsDao!.list(includeDeleted: false),
      toDocument: DittoSchemaMapper.cashTransactionToDitto,
    );
    await pushCollection<Payment>(
      label: DittoSchemaMapper.paymentsCollection,
      fetch: () => _paymentsDao!.list(includeDeleted: false),
      toDocument: DittoSchemaMapper.paymentToDitto,
    );
    if (_debtsDao != null) {
      await pushCollection<Debt>(
        label: DittoSchemaMapper.debtsCollection,
        fetch: () => _debtsDao!.list(includeDeleted: false),
        toDocument: DittoSchemaMapper.debtToDitto,
      );
    }
    if (_shiftNotesDao != null) {
      await pushCollection<ShiftNote>(
        label: DittoSchemaMapper.shiftNotesCollection,
        fetch: () => _shiftNotesDao!.getAllNotes(),
        toDocument: DittoSchemaMapper.shiftNoteToDitto,
      );
    }
    debugPrint('📤 اكتمل رفع البيانات المحلية إلى Ditto');
    return summary;
  }

  Future<Map<String, int>> pullRemoteData() async {
    _ensureReady();
    debugPrint('📥 بدء سحب البيانات من Ditto إلى القاعدة المحلية...');
    final summary = <String, int>{};
    final db = _database!;
    Future<int> pullCollection({
      required String label,
      required Future<void> Function(Map<String, dynamic> value) apply,
    }) async {
      int success = 0;
      try {
        // استخدام DQL بدلاً من legacy API
        final results = await _ditto!.store.execute(
          query: "SELECT * FROM $label WHERE !DELETED",
          arguments: {},
        );
        for (final item in results.items) {
          if (item.value is! Map<String, dynamic>) {
            continue;
          }
          final data = Map<String, dynamic>.from(item.value as Map);
          try {
            await apply(data);
            success++;
          } catch (error) {
            debugPrint('❌ فشل حفظ مستند من $label: $error');
          }
        }
        debugPrint('✅ تم سحب $success سجل من $label');
      } catch (error) {
        debugPrint('❌ حدث خطأ أثناء سحب مجموعة $label: $error');
      }
      summary['${label}_pulled'] = success;
      return success;
    }

    await pullCollection(
      label: DittoSchemaMapper.roomsCollection,
      apply: (doc) async {
        final companion = DittoSchemaMapper.dittoToRoomCompanion(doc).copyWith(origin: const Value('server'));
        await db.into(db.rooms).insertOnConflictUpdate(companion);
      },
    );
    await pullCollection(
      label: DittoSchemaMapper.bookingsCollection,
      apply: (doc) async {
        final companion = DittoSchemaMapper.dittoToBookingCompanion(doc).copyWith(origin: const Value('server'));
        await db.into(db.bookings).insertOnConflictUpdate(companion);
      },
    );
    await pullCollection(
      label: DittoSchemaMapper.bookingNotesCollection,
      apply: (doc) async {
        final companion = DittoSchemaMapper.dittoToBookingNoteCompanion(doc).copyWith(origin: const Value('server'));
        await db.into(db.bookingNotes).insertOnConflictUpdate(companion);
      },
    );
    await pullCollection(
      label: DittoSchemaMapper.employeesCollection,
      apply: (doc) async {
        final companion = DittoSchemaMapper.dittoToEmployeeCompanion(doc).copyWith(origin: const Value('server'));
        await db.into(db.employees).insertOnConflictUpdate(companion);
      },
    );
    await pullCollection(
      label: DittoSchemaMapper.expensesCollection,
      apply: (doc) async {
        final companion = DittoSchemaMapper.dittoToExpenseCompanion(doc).copyWith(origin: const Value('server'));
        await db.into(db.expenses).insertOnConflictUpdate(companion);
      },
    );
    await pullCollection(
      label: DittoSchemaMapper.cashTransactionsCollection,
      apply: (doc) async {
        final companion = DittoSchemaMapper.dittoToCashTransactionCompanion(doc).copyWith(origin: const Value('server'));
        await db.into(db.cashTransactions).insertOnConflictUpdate(companion);
      },
    );
    await pullCollection(
      label: DittoSchemaMapper.paymentsCollection,
      apply: (doc) async {
        final companion = DittoSchemaMapper.dittoToPaymentCompanion(doc).copyWith(origin: const Value('server'));
        await db.into(db.payments).insertOnConflictUpdate(companion);
      },
    );
    if (_debtsDao != null) {
      await pullCollection(
        label: DittoSchemaMapper.debtsCollection,
        apply: (doc) async {
          final companion = DittoSchemaMapper.dittoToDebtCompanion(doc).copyWith(origin: const Value('server'));
          await db.into(db.debts).insertOnConflictUpdate(companion);
        },
      );
    }
    if (_shiftNotesDao != null) {
      await pullCollection(
        label: DittoSchemaMapper.shiftNotesCollection,
        apply: (doc) async {
          final companion = DittoSchemaMapper.dittoToShiftNoteCompanion(doc);
          await db.into(db.shiftNotes).insertOnConflictUpdate(companion);
        },
      );
    }
    debugPrint('📥 اكتمل سحب البيانات من Ditto');
    return summary;
  }

  Future<bool> fullSync() async {
    _ensureReady();
    if (_isSyncing) {
      debugPrint('⚠️ توجد عملية مزامنة قيد التنفيذ بالفعل');
      return false;
    }
    _isSyncing = true;
    debugPrint('🔁 بدء مزامنة كاملة (Push ثم Pull)...');
    try {
      final pushSummary = await pushLocalData();
      final pullSummary = await pullRemoteData();
      _lastSyncTime = DateTime.now();
      debugPrint('📊 ملخص الرفع: $pushSummary');
      debugPrint('📊 ملخص السحب: $pullSummary');
      debugPrint('✅ تم إكمال المزامنة الثنائية بنجاح');
      return true;
    } catch (error, stack) {
      _lastError = error.toString();
      debugPrint('❌ فشل المزامنة الكاملة: $error');
      debugPrint(stack.toString());
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  Future<Map<String, dynamic>> getSyncStats() async {
    _ensureReady();
    final roomsCount = await _roomsDao!.list(includeDeleted: false).then((value) => value.length);
    final bookingsCount = await _bookingsDao!.list(includeDeleted: false).then((value) => value.length);
    final employeesCount = await _employeesDao!.list(includeDeleted: false).then((value) => value.length);
    final paymentsCount = await _paymentsDao!.list(includeDeleted: false).then((value) => value.length);
    return {
      'rooms_in_local': roomsCount,
      'bookings_in_local': bookingsCount,
      'employees_in_local': employeesCount,
      'payments_in_local': paymentsCount,
      'is_syncing': _isSyncing,
      'last_sync': _lastSyncTime,
      'last_error': _lastError,
    };
  }

  Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSyncPrefKey) ?? DittoConfig.autoStartSync;
  }

  Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncPrefKey, enabled);
    _autoSyncAttempted = false;
  }

  Future<void> maybeAutoSync(AppDatabase database) async {
    if (_autoSyncAttempted) return;
    _autoSyncAttempted = true;
    final enabled = await isAutoSyncEnabled();
    if (!enabled) return;
    final ok = await initialize(database);
    if (!ok) return;
    try {
      await startSync();
    } catch (_) {}
    await fullSync();
  }

  Future<void> dispose() async {
    _subscriptionsRegistered = false;
    if (_ditto != null) {
      try {
        _ditto!.stopSync();
      } catch (_) {}
      await _ditto!.close();
    }
    _ditto = null;
    _database = null;
    _outboxDao = null;
    _roomsDao = null;
    _bookingsDao = null;
    _bookingNotesDao = null;
    _employeesDao = null;
    _expensesDao = null;
    _cashTransactionsDao = null;
    _paymentsDao = null;
    _debtsDao = null;
    _shiftNotesDao = null;
    _isInitialized = false;
    _isSyncing = false;
    _subscriptionsRegistered = false;
    _autoSyncAttempted = false;
    debugPrint('🧹 تم تحرير موارد DittoLocalSyncService');
  }

  bool get isInitialized => _isInitialized;

  bool get isSyncing => _isSyncing;

  DateTime? get lastSyncTime => _lastSyncTime;

  String? get lastError => _lastError;

  Ditto? get dittoInstance => _ditto;

  void _ensureReady() {
    if (!_isInitialized || _ditto == null || _database == null) {
      throw StateError('DittoLocalSyncService غير مهيأ');
    }
  }

  Future<void> _registerSubscriptions() async {
    if (_subscriptionsRegistered || _ditto == null) {
      return;
    }
    debugPrint('📡 تسجيل اشتراكات Ditto للمجموعات...');
    for (final collection in DittoSchemaMapper.allCollections) {
      try {
        _ditto!.sync.registerSubscription('SELECT * FROM COLLECTION $collection');
      } catch (error) {
        debugPrint('⚠️ تعذر تسجيل الاشتراك للمجموعة $collection: $error');
      }
    }
    _subscriptionsRegistered = true;
  }

  Future<Identity> _buildIdentity() async {
    if (Env.dittoAppId.isEmpty) {
      throw StateError('DITTO_APP_ID غير مُعرّف');
    }
    if (Env.dittoUsePlayground) {
      if (Env.dittoPlaygroundToken.isEmpty) {
        throw StateError('DITTO_PLAYGROUND_TOKEN غير مُعرّف');
      }
      return OnlinePlaygroundIdentity(appID: Env.dittoAppId, token: Env.dittoPlaygroundToken);
    }
    if (Env.dittoPlaygroundToken.isEmpty) {
      throw StateError('يتطلب الوضع الإنتاجي رمز مصادقة');
    }
    if (Env.dittoApiToken.isEmpty || Env.dittoCloudWebhook.isEmpty) {
      throw StateError('DITTO_API_TOKEN أو DITTO_CLOUD_WEBHOOK غير مُعرّف');
    }
    return OnlineWithAuthenticationIdentity(
      appID: Env.dittoAppId,
      authenticationHandler: AuthenticationHandler(
        authenticationRequired: (authenticator) async {
          final token = await _fetchAuthToken();
          await authenticator.login(token: token, provider: 'api-token');
        },
        authenticationExpiringSoon: (authenticator, _) async {
          final token = await _fetchAuthToken();
          await authenticator.login(token: token, provider: 'api-token');
        },
      ),
    );
  }

  Future<String> _fetchAuthToken() async {
    final uri = Uri.parse(Env.dittoCloudWebhook);
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${Env.dittoApiToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'app_id': Env.dittoAppId}),
    );
    if (response.statusCode != 200) {
      throw StateError('فشل طلب المصادقة من Ditto (${response.statusCode}): ${response.body}');
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final token = payload['token'] ?? payload['access_token'];
      if (token is String && token.isNotEmpty) {
        return token;
      }
      throw StateError('استجابة المصادقة لا تحتوي token صالح');
    } catch (error) {
      throw StateError('تعذر تحليل استجابة المصادقة: $error');
    }
  }
}
