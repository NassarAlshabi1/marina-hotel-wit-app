// ============================================================================
// Marina Hotel - Supabase Realtime Service
// خدمة التحديثات الفورية باستخدام Supabase Realtime
// ============================================================================

import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_config.dart';
import '../utils/time.dart';
import 'daos/booking_notes_dao.dart';
import 'daos/bookings_dao.dart';
import 'daos/cash_transactions_dao.dart';
import 'daos/debts_dao.dart';
import 'daos/employees_dao.dart';
import 'daos/expenses_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/payments_dao.dart';
import 'daos/rooms_dao.dart';
import 'local_db.dart';

/// حالة Realtime
enum RealtimeStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// حدث Realtime
class RealtimeEvent {
  final String table;
  final String eventType; // INSERT, UPDATE, DELETE
  final Map<String, dynamic> newRecord;
  final Map<String, dynamic>? oldRecord;

  RealtimeEvent({
    required this.table,
    required this.eventType,
    required this.newRecord,
    this.oldRecord,
  });
}

/// تسجيل الإحصائيات الخاصة بـ Realtime
class RealtimeStats {
  int totalEvents = 0;
  int insertEvents = 0;
  int updateEvents = 0;
  int deleteEvents = 0;
  DateTime? lastEventTime;

  void recordEvent(String eventType) {
    totalEvents++;
    lastEventTime = DateTime.now();

    switch (eventType) {
      case 'INSERT':
        insertEvents++;
        break;
      case 'UPDATE':
        updateEvents++;
        break;
      case 'DELETE':
        deleteEvents++;
        break;
      default:
        break;
    }
  }

  Map<String, dynamic> toJson() => {
        'total_events': totalEvents,
        'insert_events': insertEvents,
        'update_events': updateEvents,
        'delete_events': deleteEvents,
        'last_event_time': lastEventTime?.toIso8601String(),
      };
}

/// خدمة Supabase Realtime
class SupabaseRealtimeService {
  SupabaseRealtimeService(this.db)
      : _roomsDao = RoomsDao(db, OutboxDao(db)),
        _bookingsDao = BookingsDao(db, OutboxDao(db)),
        _notesDao = BookingNotesDao(db, OutboxDao(db)),
        _employeesDao = EmployeesDao(db, OutboxDao(db)),
        _expensesDao = ExpensesDao(db, OutboxDao(db)),
        _cashDao = CashTransactionsDao(db, OutboxDao(db)),
        _paymentsDao = PaymentsDao(db, OutboxDao(db)),
        _debtsDao = DebtsDao(db, OutboxDao(db));

  final AppDatabase db;
  final RoomsDao _roomsDao;
  final BookingsDao _bookingsDao;
  final BookingNotesDao _notesDao;
  final EmployeesDao _employeesDao;
  final ExpensesDao _expensesDao;
  final CashTransactionsDao _cashDao;
  final PaymentsDao _paymentsDao;
  final DebtsDao _debtsDao;

  final List<RealtimeChannel> _channels = [];
  final _statusController = StreamController<RealtimeStatus>.broadcast();
  final _eventsController = StreamController<RealtimeEvent>.broadcast();
  final RealtimeStats _stats = RealtimeStats();

  Stream<RealtimeStatus> get statusStream => _statusController.stream;
  Stream<RealtimeEvent> get eventsStream => _eventsController.stream;
  RealtimeStatus _currentStatus = RealtimeStatus.disconnected;
  RealtimeStatus get currentStatus => _currentStatus;
  RealtimeStats get stats => _stats;

  SupabaseClient get _supabase => SupabaseConfig.client;

  bool _isSubscribing = false;
  bool _autoReconnectInitialized = false;
  StreamSubscription<AuthState>? _authSubscription;

  /// بدء الاستماع لجميع الجداول
  Future<void> subscribeToAll() async {
    if (_isSubscribing) {
      return;
    }
    if (!SupabaseConfig.isLoggedIn) {
      debugPrint('⚠️ يجب تسجيل الدخول إلى Supabase قبل تفعيل Realtime');
      return;
    }
    if (_channels.isNotEmpty) {
      // تم الاشتراك مسبقاً
      return;
    }

    _setupAutoReconnect();

    _isSubscribing = true;
    _updateStatus(RealtimeStatus.connecting);

    try {
      debugPrint('🔄 بدء الاشتراك في Realtime لجميع الجداول...');

      await _subscribeToTable('rooms', _handleRoomsChange);
      await _subscribeToTable('bookings', _handleBookingsChange);
      await _subscribeToTable('booking_notes', _handleBookingNotesChange);
      await _subscribeToTable('employees', _handleEmployeesChange);
      await _subscribeToTable('expenses', _handleExpensesChange);
      await _subscribeToTable('cash_transactions', _handleCashTransactionsChange);
      await _subscribeToTable('payments', _handlePaymentsChange);
      await _subscribeToTable('debts', _handleDebtsChange);

      _updateStatus(RealtimeStatus.connected);
      debugPrint('✅ تم الاشتراك في جميع الجداول بنجاح');
    } catch (e, st) {
      debugPrint('❌ خطأ في الاشتراك: $e');
      debugPrint('$st');
      _updateStatus(RealtimeStatus.error);
      rethrow;
    } finally {
      _isSubscribing = false;
    }
  }

  /// الاشتراك في جدول واحد
  Future<void> _subscribeToTable(
    String tableName,
    Future<void> Function(PostgresChangePayload) handler,
  ) async {
    final channel = _supabase.channel('public:$tableName');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tableName,
          callback: (payload) async {
            final eventType = _eventTypeString(payload.eventType);
            debugPrint('📥 تحديث من $tableName: $eventType');
            try {
              await handler(payload);
              _stats.recordEvent(eventType);
              _eventsController.add(
                RealtimeEvent(
                  table: tableName,
                  eventType: eventType,
                  newRecord: payload.newRecord ?? const {},
                  oldRecord: payload.oldRecord,
                ),
              );
            } catch (e, st) {
              debugPrint('❌ خطأ أثناء معالجة $tableName: $e');
              debugPrint('$st');
            }
          },
        )
        .subscribe();

    _channels.add(channel);
    debugPrint('✓ اشتراك في جدول: $tableName');
  }

  /// إلغاء الاشتراك من جميع القنوات
  Future<void> unsubscribeAll() async {
    if (_channels.isEmpty) {
      _updateStatus(RealtimeStatus.disconnected);
      return;
    }

    debugPrint('🔌 إلغاء الاشتراك من جميع قنوات Realtime...');
    for (final channel in List<RealtimeChannel>.from(_channels)) {
      try {
        await _supabase.removeChannel(channel);
      } catch (e) {
        debugPrint('⚠️ تعذر إزالة القناة ${channel.topic}: $e');
      }
    }

    _channels.clear();
    _updateStatus(RealtimeStatus.disconnected);
  }

  /// تنظيف الموارد
  void dispose() {
    unsubscribeAll();
    _authSubscription?.cancel();
    _statusController.close();
    _eventsController.close();
  }

  void _updateStatus(RealtimeStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _setupAutoReconnect() {
    if (_autoReconnectInitialized) {
      return;
    }
    _autoReconnectInitialized = true;

    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
          debugPrint('🔄 تم تسجيل الدخول مجدداً - إعادة تفعيل Realtime');
          // إعادة الاشتراك عند إعادة تسجيل الدخول
          () async {
            await unsubscribeAll();
            await subscribeToAll();
          }();
          break;
        case AuthChangeEvent.signedOut:
          debugPrint('⚠️ تم تسجيل الخروج - إلغاء اشتراكات Realtime');
          unsubscribeAll();
          break;
        default:
          break;
      }
    });
  }

  // --------------------------------------------------------------------------
  // معالجات الجداول
  // --------------------------------------------------------------------------

  Future<void> _handleRoomsChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final roomNumber = (oldData?['room_number'] ?? oldData?['roomNumber']) as String?;
        if (roomNumber != null) {
          await _roomsDao.softDelete(roomNumber, originIsServer: true);
        }
        return;
      }

      if (newData == null) return;

      final roomNumber = newData['room_number'] as String?;
      if (roomNumber == null) return;

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      final existing = await (db.select(db.rooms)
            ..where((t) => t.roomNumber.equals(roomNumber)))
          .getSingleOrNull();

      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('rooms', newData, existing);
      }

      if (existing == null) {
        await _roomsDao.insertOne(
          RoomsCompanion(
            roomNumber: d.Value(roomNumber),
            type: d.Value(_stringOr(newData['type'], '')),
            price: d.Value(_toDouble(newData['price'])),
            status: d.Value(_stringOr(newData['status'], 'شاغرة')),
            imageUrl: newData['image_url'] != null
                ? d.Value(newData['image_url'] as String?)
                : const d.Value.absent(),
            serverId: d.Value(_toIntNullable(newData['server_id'])),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _roomsDao.updateByNumber(
            roomNumber,
            RoomsCompanion(
              type: newData['type'] != null ? d.Value(newData['type'] as String) : const d.Value.absent(),
              price: newData['price'] != null ? d.Value(_toDouble(newData['price'])) : const d.Value.absent(),
              status: newData['status'] != null ? d.Value(newData['status'] as String) : const d.Value.absent(),
              imageUrl: newData['image_url'] != null
                  ? d.Value(newData['image_url'] as String?)
                  : const d.Value.absent(),
              serverId: d.Value(_toIntNullable(newData['server_id'])),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _roomsDao.softDelete(roomNumber, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول rooms (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير الغرف: $e');
    }
  }

  Future<void> _handleBookingsChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final serverBookingId = oldData?['server_booking_id'] as int?;
        if (serverBookingId != null) {
          final existing = await (db.select(db.bookings)
                ..where((t) => t.serverBookingId.equals(serverBookingId)))
              .getSingleOrNull();
          if (existing != null) {
            await _bookingsDao.softDelete(existing.id, originIsServer: true);
          }
        }
        return;
      }

      if (newData == null) return;

      final serverBookingId = newData['server_booking_id'] as int?;
      Booking? existing;
      if (serverBookingId != null) {
        existing = await (db.select(db.bookings)
              ..where((t) => t.serverBookingId.equals(serverBookingId)))
            .getSingleOrNull();
      }

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('bookings', newData, existing);
      }

      if (existing == null) {
        await _bookingsDao.insertOne(
          BookingsCompanion(
            serverBookingId: d.Value(serverBookingId),
            roomNumber: d.Value(_stringOr(newData['room_number'], '')),
            guestName: d.Value(_stringOr(newData['guest_name'], '')),
            guestPhone: d.Value(_stringOr(newData['guest_phone'], '')),
            guestNationality: d.Value(_stringOr(newData['guest_nationality'], '')),
            guestEmail: newData['guest_email'] != null
                ? d.Value(newData['guest_email'] as String?)
                : const d.Value.absent(),
            guestAddress: newData['guest_address'] != null
                ? d.Value(newData['guest_address'] as String?)
                : const d.Value.absent(),
            guestIdType: newData['guest_id_type'] != null
                ? d.Value(newData['guest_id_type'] as String)
                : const d.Value.absent(),
            guestIdNumber: newData['guest_id_number'] != null
                ? d.Value(newData['guest_id_number'] as String)
                : const d.Value.absent(),
            checkinDate: d.Value(_stringOr(newData['checkin_date'], Time.nowIso())),
            checkoutDate: newData['checkout_date'] != null
                ? d.Value(newData['checkout_date'] as String?)
                : const d.Value.absent(),
            status: d.Value(_stringOr(newData['status'], 'محجوزة')),
            notes: newData['notes'] != null
                ? d.Value(newData['notes'] as String?)
                : const d.Value.absent(),
            expectedNights: newData['expected_nights'] != null
                ? d.Value(_toInt(newData['expected_nights']))
                : const d.Value.absent(),
            calculatedNights: newData['calculated_nights'] != null
                ? d.Value(_toInt(newData['calculated_nights']))
                : const d.Value.absent(),
            serverId: d.Value(serverBookingId),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _bookingsDao.updateById(
            existing.id,
            BookingsCompanion(
              serverBookingId: d.Value(serverBookingId),
              roomNumber: newData['room_number'] != null
                  ? d.Value(newData['room_number'] as String)
                  : const d.Value.absent(),
              guestName: newData['guest_name'] != null
                  ? d.Value(newData['guest_name'] as String)
                  : const d.Value.absent(),
              guestPhone: newData['guest_phone'] != null
                  ? d.Value(newData['guest_phone'] as String)
                  : const d.Value.absent(),
              guestNationality: newData['guest_nationality'] != null
                  ? d.Value(newData['guest_nationality'] as String)
                  : const d.Value.absent(),
              guestEmail: newData['guest_email'] != null
                  ? d.Value(newData['guest_email'] as String?)
                  : const d.Value.absent(),
              guestAddress: newData['guest_address'] != null
                  ? d.Value(newData['guest_address'] as String?)
                  : const d.Value.absent(),
              status: newData['status'] != null
                  ? d.Value(newData['status'] as String)
                  : const d.Value.absent(),
              notes: newData['notes'] != null
                  ? d.Value(newData['notes'] as String?)
                  : const d.Value.absent(),
              checkoutDate: newData['checkout_date'] != null
                  ? d.Value(newData['checkout_date'] as String?)
                  : const d.Value.absent(),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _bookingsDao.softDelete(existing.id, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول bookings (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير الحجوزات: $e');
    }
  }

  Future<void> _handleBookingNotesChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final serverId = oldData?['server_id'] as int?;
        if (serverId != null) {
          final existing = await (db.select(db.bookingNotes)
                ..where((t) => t.serverId.equals(serverId)))
              .getSingleOrNull();
          if (existing != null) {
            await _notesDao.softDelete(existing.id, originIsServer: true);
          }
        }
        return;
      }

      if (newData == null) return;

      final serverId = newData['server_id'] as int?;
      BookingNote? existing;
      if (serverId != null) {
        existing = await (db.select(db.bookingNotes)
              ..where((t) => t.serverId.equals(serverId)))
            .getSingleOrNull();
      }

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('booking_notes', newData, existing);
      }

      if (existing == null) {
        await _notesDao.insertOne(
          BookingNotesCompanion(
            bookingId: d.Value(_toInt(newData['booking_id'], fallback: 0)),
            noteText: d.Value(_stringOr(newData['note_text'], '')),
            alertType: d.Value(_stringOr(newData['alert_type'], 'low')),
            alertUntil: newData['alert_until'] != null
                ? d.Value(newData['alert_until'] as String?)
                : const d.Value.absent(),
            isActive: d.Value(_toInt(newData['is_active'], fallback: 1)),
            serverId: d.Value(serverId),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _notesDao.updateById(
            existing.id,
            BookingNotesCompanion(
              bookingId: d.Value(_toInt(newData['booking_id'], fallback: existing.bookingId)),
              noteText: newData['note_text'] != null
                  ? d.Value(newData['note_text'] as String)
                  : const d.Value.absent(),
              alertType: newData['alert_type'] != null
                  ? d.Value(newData['alert_type'] as String)
                  : const d.Value.absent(),
              alertUntil: newData['alert_until'] != null
                  ? d.Value(newData['alert_until'] as String?)
                  : const d.Value.absent(),
              isActive: newData['is_active'] != null
                  ? d.Value(_toInt(newData['is_active']))
                  : const d.Value.absent(),
              serverId: d.Value(serverId),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _notesDao.softDelete(existing.id, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول booking_notes (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير ملاحظات الحجوزات: $e');
    }
  }

  Future<void> _handleEmployeesChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final serverId = oldData?['server_id'] as int?;
        if (serverId != null) {
          final existing = await (db.select(db.employees)
                ..where((t) => t.serverId.equals(serverId)))
              .getSingleOrNull();
          if (existing != null) {
            await _employeesDao.softDelete(existing.id, originIsServer: true);
          }
        }
        return;
      }

      if (newData == null) return;

      final serverId = newData['server_id'] as int? ?? newData['id'] as int?;
      Employee? existing;
      if (serverId != null) {
        existing = await (db.select(db.employees)
              ..where((t) => t.serverId.equals(serverId)))
            .getSingleOrNull();
      }

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('employees', newData, existing);
      }

      if (existing == null) {
        await _employeesDao.insertOne(
          EmployeesCompanion(
            name: d.Value(_stringOr(newData['name'], '')),
            basicSalary: d.Value(_toDouble(newData['basic_salary'])),
            status: d.Value(_stringOr(newData['status'], 'active')),
            position: newData['position'] != null
                ? d.Value(newData['position'] as String)
                : const d.Value.absent(),
            phone: newData['phone'] != null
                ? d.Value(newData['phone'] as String)
                : const d.Value.absent(),
            hireDate: newData['hire_date'] != null
                ? d.Value(newData['hire_date'] as String)
                : const d.Value.absent(),
            serverId: d.Value(serverId),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _employeesDao.updateById(
            existing.id,
            EmployeesCompanion(
              name: newData['name'] != null
                  ? d.Value(newData['name'] as String)
                  : const d.Value.absent(),
              basicSalary: newData['basic_salary'] != null
                  ? d.Value(_toDouble(newData['basic_salary']))
                  : const d.Value.absent(),
              status: newData['status'] != null
                  ? d.Value(newData['status'] as String)
                  : const d.Value.absent(),
              position: newData['position'] != null
                  ? d.Value(newData['position'] as String)
                  : const d.Value.absent(),
              phone: newData['phone'] != null
                  ? d.Value(newData['phone'] as String)
                  : const d.Value.absent(),
              hireDate: newData['hire_date'] != null
                  ? d.Value(newData['hire_date'] as String)
                  : const d.Value.absent(),
              serverId: d.Value(serverId),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _employeesDao.softDelete(existing.id, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول employees (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير الموظفين: $e');
    }
  }

  Future<void> _handleExpensesChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final serverId = oldData?['server_id'] as int? ?? oldData?['id'] as int?;
        if (serverId != null) {
          final existing = await (db.select(db.expenses)
                ..where((t) => t.serverId.equals(serverId)))
              .getSingleOrNull();
          if (existing != null) {
            await _expensesDao.softDelete(existing.id, originIsServer: true);
          }
        }
        return;
      }

      if (newData == null) return;

      final serverId = newData['server_id'] as int? ?? newData['id'] as int?;
      Expense? existing;
      if (serverId != null) {
        existing = await (db.select(db.expenses)
              ..where((t) => t.serverId.equals(serverId)))
            .getSingleOrNull();
      }

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('expenses', newData, existing);
      }

      if (existing == null) {
        await _expensesDao.insertOne(
          ExpensesCompanion(
            expenseType: d.Value(_stringOr(newData['expense_type'], 'other')),
            relatedId: newData['related_id'] != null
                ? d.Value(_toIntNullable(newData['related_id']))
                : const d.Value.absent(),
            description: d.Value(_stringOr(newData['description'], '')),
            amount: d.Value(_toDouble(newData['amount'])),
            date: d.Value(_stringOr(newData['date'], Time.safeIsoToDateString(Time.nowIso()))),
            cashTransactionId: newData['cash_transaction_id'] != null
                ? d.Value(_toIntNullable(newData['cash_transaction_id']))
                : const d.Value.absent(),
            serverId: d.Value(serverId),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _expensesDao.updateById(
            existing.id,
            ExpensesCompanion(
              expenseType: newData['expense_type'] != null
                  ? d.Value(newData['expense_type'] as String)
                  : const d.Value.absent(),
              relatedId: newData['related_id'] != null
                  ? d.Value(_toIntNullable(newData['related_id']))
                  : const d.Value.absent(),
              description: newData['description'] != null
                  ? d.Value(newData['description'] as String)
                  : const d.Value.absent(),
              amount: newData['amount'] != null
                  ? d.Value(_toDouble(newData['amount']))
                  : const d.Value.absent(),
              date: newData['date'] != null
                  ? d.Value(newData['date'] as String)
                  : const d.Value.absent(),
              cashTransactionId: newData['cash_transaction_id'] != null
                  ? d.Value(_toIntNullable(newData['cash_transaction_id']))
                  : const d.Value.absent(),
              serverId: d.Value(serverId),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _expensesDao.softDelete(existing.id, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول expenses (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير المصروفات: $e');
    }
  }

  Future<void> _handleCashTransactionsChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final serverId = oldData?['server_id'] as int? ?? oldData?['id'] as int?;
        if (serverId != null) {
          final existing = await (db.select(db.cashTransactions)
                ..where((t) => t.serverId.equals(serverId)))
              .getSingleOrNull();
          if (existing != null) {
            await _cashDao.softDelete(existing.id, originIsServer: true);
          }
        }
        return;
      }

      if (newData == null) return;

      final serverId = newData['server_id'] as int? ?? newData['id'] as int?;
      CashTransaction? existing;
      if (serverId != null) {
        existing = await (db.select(db.cashTransactions)
              ..where((t) => t.serverId.equals(serverId)))
            .getSingleOrNull();
      }

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('cash_transactions', newData, existing);
      }

      if (existing == null) {
        await _cashDao.insertOne(
          CashTransactionsCompanion(
            registerId: newData['register_id'] != null
                ? d.Value(_toIntNullable(newData['register_id']))
                : const d.Value.absent(),
            transactionType: d.Value(_stringOr(newData['transaction_type'], 'income')),
            amount: d.Value(_toDouble(newData['amount'])),
            referenceType: newData['reference_type'] != null
                ? d.Value(newData['reference_type'] as String?)
                : const d.Value.absent(),
            referenceId: newData['reference_id'] != null
                ? d.Value(_toIntNullable(newData['reference_id']))
                : const d.Value.absent(),
            description: newData['description'] != null
                ? d.Value(newData['description'] as String?)
                : const d.Value.absent(),
            transactionTime: d.Value(_stringOr(newData['transaction_time'], Time.nowIso())),
            serverId: d.Value(serverId),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _cashDao.updateById(
            existing.id,
            CashTransactionsCompanion(
              registerId: newData['register_id'] != null
                  ? d.Value(_toIntNullable(newData['register_id']))
                  : const d.Value.absent(),
              transactionType: newData['transaction_type'] != null
                  ? d.Value(newData['transaction_type'] as String)
                  : const d.Value.absent(),
              amount: newData['amount'] != null
                  ? d.Value(_toDouble(newData['amount']))
                  : const d.Value.absent(),
              referenceType: newData['reference_type'] != null
                  ? d.Value(newData['reference_type'] as String?)
                  : const d.Value.absent(),
              referenceId: newData['reference_id'] != null
                  ? d.Value(_toIntNullable(newData['reference_id']))
                  : const d.Value.absent(),
              description: newData['description'] != null
                  ? d.Value(newData['description'] as String?)
                  : const d.Value.absent(),
              transactionTime: newData['transaction_time'] != null
                  ? d.Value(newData['transaction_time'] as String)
                  : const d.Value.absent(),
              serverId: d.Value(serverId),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _cashDao.softDelete(existing.id, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول cash_transactions (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير المعاملات النقدية: $e');
    }
  }

  Future<void> _handlePaymentsChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final serverPaymentId = oldData?['server_payment_id'] as int? ?? oldData?['payment_id'] as int?;
        if (serverPaymentId != null) {
          final existing = await (db.select(db.payments)
                ..where((t) => t.serverPaymentId.equals(serverPaymentId)))
              .getSingleOrNull();
          if (existing != null) {
            await _paymentsDao.softDelete(existing.id, originIsServer: true);
          }
        }
        return;
      }

      if (newData == null) return;

      final serverPaymentId = newData['server_payment_id'] as int? ?? newData['payment_id'] as int?;
      Payment? existing;
      if (serverPaymentId != null) {
        existing = await (db.select(db.payments)
              ..where((t) => t.serverPaymentId.equals(serverPaymentId)))
            .getSingleOrNull();
      }

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('payments', newData, existing);
      }

      if (existing == null) {
        await _paymentsDao.insertOne(
          PaymentsCompanion(
            serverPaymentId: d.Value(serverPaymentId),
            serverBookingId: newData['server_booking_id'] != null
                ? d.Value(_toIntNullable(newData['server_booking_id']))
                : const d.Value.absent(),
            roomNumber: newData['room_number'] != null
                ? d.Value(newData['room_number'] as String?)
                : const d.Value.absent(),
            amount: d.Value(_toDouble(newData['amount'])),
            paymentDate: d.Value(_stringOr(newData['payment_date'], Time.nowIso())),
            notes: newData['notes'] != null
                ? d.Value(newData['notes'] as String?)
                : const d.Value.absent(),
            paymentMethod: d.Value(_stringOr(newData['payment_method'], 'نقدي')),
            revenueType: newData['revenue_type'] != null
                ? d.Value(newData['revenue_type'] as String)
                : const d.Value.absent(),
            cashTransactionServerId: newData['cash_transaction_id'] != null
                ? d.Value(_toIntNullable(newData['cash_transaction_id']))
                : const d.Value.absent(),
            serverId: d.Value(serverPaymentId),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _paymentsDao.updateById(
            existing.id,
            PaymentsCompanion(
              serverPaymentId: d.Value(serverPaymentId),
              serverBookingId: newData['server_booking_id'] != null
                  ? d.Value(_toIntNullable(newData['server_booking_id']))
                  : const d.Value.absent(),
              roomNumber: newData['room_number'] != null
                  ? d.Value(newData['room_number'] as String?)
                  : const d.Value.absent(),
              amount: newData['amount'] != null
                  ? d.Value(_toDouble(newData['amount']))
                  : const d.Value.absent(),
              paymentDate: newData['payment_date'] != null
                  ? d.Value(newData['payment_date'] as String)
                  : const d.Value.absent(),
              notes: newData['notes'] != null
                  ? d.Value(newData['notes'] as String?)
                  : const d.Value.absent(),
              paymentMethod: newData['payment_method'] != null
                  ? d.Value(newData['payment_method'] as String)
                  : const d.Value.absent(),
              revenueType: newData['revenue_type'] != null
                  ? d.Value(newData['revenue_type'] as String)
                  : const d.Value.absent(),
              cashTransactionServerId: newData['cash_transaction_id'] != null
                  ? d.Value(_toIntNullable(newData['cash_transaction_id']))
                  : const d.Value.absent(),
              serverId: d.Value(serverPaymentId),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _paymentsDao.softDelete(existing.id, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول payments (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير المدفوعات: $e');
    }
  }

  Future<void> _handleDebtsChange(PostgresChangePayload payload) async {
    final event = payload.eventType;
    final newData = payload.newRecord;
    final oldData = payload.oldRecord;

    try {
      if (event == PostgresChangeEvent.delete) {
        final serverId = oldData?['server_id'] as int? ?? oldData?['id'] as int?;
        if (serverId != null) {
          final existing = await (db.select(db.debts)
                ..where((t) => t.serverId.equals(serverId)))
              .getSingleOrNull();
          if (existing != null) {
            await _debtsDao.softDelete(existing.id, originIsServer: true);
          }
        }
        return;
      }

      if (newData == null) return;

      final serverId = newData['server_id'] as int? ?? newData['id'] as int?;
      Debt? existing;
      if (serverId != null) {
        existing = await (db.select(db.debts)
              ..where((t) => t.serverId.equals(serverId)))
            .getSingleOrNull();
      }

      final serverTs = _parseTimestamp(newData['last_modified'] ?? newData['updated_at']);
      if (existing != null && _hasConflict(existing.lastModified, serverTs)) {
        await _resolveConflict('debts', newData, existing);
      }

      if (existing == null) {
        await _debtsDao.insertOne(
          DebtsCompanion(
            bookingLocalId: newData['booking_local_id'] != null
                ? d.Value(_toIntNullable(newData['booking_local_id']))
                : const d.Value.absent(),
            guestName: d.Value(_stringOr(newData['guest_name'], '')),
            checkinDate: d.Value(_stringOr(newData['checkin_date'], Time.nowIso())),
            checkoutDate: d.Value(_stringOr(newData['checkout_date'], Time.nowIso())),
            dateRecorded: newData['date_recorded'] != null
                ? d.Value(newData['date_recorded'] as String)
                : const d.Value.absent(),
            debtReason: newData['debt_reason'] != null
                ? d.Value(newData['debt_reason'] as String)
                : const d.Value.absent(),
            totalAmount: d.Value(_toDouble(newData['total_amount'])),
            paidAmount: d.Value(_toDouble(newData['paid_amount'])),
            remainingAmount: d.Value(_toDouble(newData['remaining_amount'])),
            paymentDate: d.Value(_stringOr(newData['payment_date'], Time.nowIso())),
            isSettled: d.Value(_toInt(newData['is_settled'], fallback: 0)),
            pledge: newData['pledge'] != null
                ? d.Value(newData['pledge'] as String?)
                : const d.Value.absent(),
            pledgeType: newData['pledge_type'] != null
                ? d.Value(newData['pledge_type'] as String?)
                : const d.Value.absent(),
            note: newData['note'] != null
                ? d.Value(newData['note'] as String?)
                : const d.Value.absent(),
            serverId: d.Value(serverId),
          ),
          originIsServer: true,
        );
      } else {
        if (serverTs >= existing.lastModified) {
          await _debtsDao.updateById(
            existing.id,
            DebtsCompanion(
              bookingLocalId: newData['booking_local_id'] != null
                  ? d.Value(_toIntNullable(newData['booking_local_id']))
                  : const d.Value.absent(),
              guestName: newData['guest_name'] != null
                  ? d.Value(newData['guest_name'] as String)
                  : const d.Value.absent(),
              checkinDate: newData['checkin_date'] != null
                  ? d.Value(newData['checkin_date'] as String)
                  : const d.Value.absent(),
              checkoutDate: newData['checkout_date'] != null
                  ? d.Value(newData['checkout_date'] as String)
                  : const d.Value.absent(),
              dateRecorded: newData['date_recorded'] != null
                  ? d.Value(newData['date_recorded'] as String)
                  : const d.Value.absent(),
              debtReason: newData['debt_reason'] != null
                  ? d.Value(newData['debt_reason'] as String)
                  : const d.Value.absent(),
              totalAmount: newData['total_amount'] != null
                  ? d.Value(_toDouble(newData['total_amount']))
                  : const d.Value.absent(),
              paidAmount: newData['paid_amount'] != null
                  ? d.Value(_toDouble(newData['paid_amount']))
                  : const d.Value.absent(),
              remainingAmount: newData['remaining_amount'] != null
                  ? d.Value(_toDouble(newData['remaining_amount']))
                  : const d.Value.absent(),
              paymentDate: newData['payment_date'] != null
                  ? d.Value(newData['payment_date'] as String)
                  : const d.Value.absent(),
              isSettled: newData['is_settled'] != null
                  ? d.Value(_toInt(newData['is_settled']))
                  : const d.Value.absent(),
              pledge: newData['pledge'] != null
                  ? d.Value(newData['pledge'] as String?)
                  : const d.Value.absent(),
              pledgeType: newData['pledge_type'] != null
                  ? d.Value(newData['pledge_type'] as String?)
                  : const d.Value.absent(),
              note: newData['note'] != null
                  ? d.Value(newData['note'] as String?)
                  : const d.Value.absent(),
              serverId: d.Value(serverId),
              origin: const d.Value('server'),
            ),
            originIsServer: true,
          );
          if (newData['deleted_at'] != null) {
            await _debtsDao.softDelete(existing.id, originIsServer: true);
          }
        } else {
          debugPrint('⚠️ تجاهل تحديث أقدم لجدول debts (serverTs=$serverTs, local=${existing.lastModified})');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير الديون: $e');
    }
  }

  // --------------------------------------------------------------------------
  // أدوات مساعدة
  // --------------------------------------------------------------------------

  bool _hasConflict(int localLastModified, int serverLastModified) {
    return localLastModified > serverLastModified;
  }

  Future<void> _resolveConflict(
    String tableName,
    Map<String, dynamic> serverData,
    dynamic localData,
  ) async {
    debugPrint('⚠️ تضارب في $tableName - سيتم اعتماد بيانات السيرفر');
    // استراتيجية: بيانات السيرفر لها الأولوية
    // يمكن لاحقاً إضافة منطق أكثر تقدماً لإبلاغ المستخدم أو حفظ سجل التضارب
  }

  int _parseTimestamp(dynamic value) {
    if (value == null) {
      return Time.nowEpoch();
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
      try {
        return DateTime.parse(value).millisecondsSinceEpoch ~/ 1000;
      } catch (_) {
        return Time.nowEpoch();
      }
    }
    return Time.nowEpoch();
  }

  String _eventTypeString(PostgresChangeEvent event) {
    final raw = event.toString();
    final value = raw.contains('.') ? raw.split('.').last : raw;
    return value.toUpperCase();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  int? _toIntNullable(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) {
      return int.tryParse(value);
    }
    return null;
  }

  String _stringOr(dynamic value, String fallback) {
    if (value == null) return fallback;
    final str = value.toString();
    return str.isEmpty ? fallback : str;
  }
}
