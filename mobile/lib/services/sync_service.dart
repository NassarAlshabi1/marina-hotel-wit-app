import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../utils/time.dart';
import '../utils/status_utils.dart';
import 'api_service.dart';
import 'local_db.dart';
import 'daos/outbox_dao.dart';
import 'daos/rooms_dao.dart';
import 'daos/bookings_dao.dart';
import 'daos/booking_notes_dao.dart';
import 'daos/employees_dao.dart';
import 'daos/expenses_dao.dart';
import 'daos/cash_transactions_dao.dart';
import 'daos/payments_dao.dart';
import '../providers/repository_providers.dart';
import 'sync_performance_optimizer.dart';
import 'delta_sync_service.dart';
import 'repositories/rooms_repository.dart';
import 'package:flutter/material.dart';
import 'sync_mutex.dart';
import 'sync_config.dart';

enum SyncStatus { idle, pushing, pulling, error }

class SyncService {
  SyncService(this.db)
      : roomsDao = RoomsDao(db, OutboxDao(db)),
        bookingsDao = BookingsDao(db, OutboxDao(db)),
        notesDao = BookingNotesDao(db, OutboxDao(db)),
        employeesDao = EmployeesDao(db, OutboxDao(db)),
        expensesDao = ExpensesDao(db, OutboxDao(db)),
        cashDao = CashTransactionsDao(db, OutboxDao(db)),
        paymentsDao = PaymentsDao(db, OutboxDao(db)),
        deltaSyncService = DeltaSyncService(db),
        _performanceOptimizer = SyncPerformanceOptimizer();

  final AppDatabase db;
  final RoomsDao roomsDao;
  final BookingsDao bookingsDao;
  final BookingNotesDao notesDao;
  final EmployeesDao employeesDao;
  final ExpensesDao expensesDao;
  final CashTransactionsDao cashDao;
  final PaymentsDao paymentsDao;
  final DeltaSyncService deltaSyncService;
  final SyncPerformanceOptimizer _performanceOptimizer;
  final SyncMutex _syncMutex = SyncMutex();

  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _status.stream;
  
  /// تهيئة محسن الأداء
  Future<void> initializePerformanceOptimizer() async {
    await _performanceOptimizer.initialize();
    debugPrint('🔧 تم تهيئة محسن أداء المزامنة');
  }
  
  /// الحصول على إحصائيات الأداء
  Map<String, dynamic> getPerformanceStats() {
    return _performanceOptimizer.getPerformanceStats();
  }
  
  /// تحديث إعدادات WiFi Only
  Future<void> setWifiOnlyMode(bool enabled) async {
    await _performanceOptimizer.setWifiOnlyMode(enabled);
  }
  
  /// تنظيف الموارد
  void dispose() {
    _performanceOptimizer.dispose();
    _status.close();
  }

  /// تشغيل المزامنة مع تحسين الأداء وحماية من التشغيل المتزامن
  Future<void> runSync() async {
    if (!await _syncMutex.acquire(timeout: SyncConfig.syncMutexTimeout)) {
      debugPrint('⏸️ المزامنة جارية بالفعل، تخطي المحاولة الجديدة');
      return;
    }
    
    try {
      if (await _performanceOptimizer.shouldSkipSync()) {
        debugPrint('⏭️ تم تخطي المزامنة حسب إعدادات محسن الأداء');
        return;
      }

      _status.add(SyncStatus.pushing);
      await _push();
      _status.add(SyncStatus.pulling);
      await _pull();
      
      _performanceOptimizer.recordSyncAttempt(success: true);
      _status.add(SyncStatus.idle);
      
      debugPrint('✅ تم إنجاز المزامنة بنجاح');
    } catch (e) {
      _performanceOptimizer.recordSyncAttempt(success: false);
      _status.add(SyncStatus.error);
      debugPrint('❌ فشل في المزامنة: $e');
      rethrow;
    } finally {
      _syncMutex.release();
    }
  }

  Future<void> _push() async {
    final settings = _performanceOptimizer.getCurrentPerformanceSettings();
    final timeout = Duration(seconds: settings['timeout'] as int);
    final computation = await deltaSyncService.compute();
    if (computation.changes.isEmpty) {
      return;
    }
    final payload = computation.toPayload();
    try {
      final response = await ApiService.I.syncPush(payload).timeout(timeout);
      if (response['success'] != true) {
        return;
      }

      final results = List<Map<String, dynamic>>.from(response['data']['results']);
      await db.transaction(() async {
        var allSucceeded = true;

        for (var index = 0; index < computation.changes.length; index++) {
          if (index >= results.length) {
            allSucceeded = false;
            final missingChange = computation.changes[index];
            debugPrint('❌ Missing push result for ${missingChange.entity}/${missingChange.localUuid}');
            break;
          }

          final result = results[index];
          final change = computation.changes[index];
          if (result['success'] == true) {
            await _applyServerId(change.entity, change.localUuid, result['server_id']);
          } else {
            allSucceeded = false;
            debugPrint('❌ فشل إرسال ${change.entity}/${change.localUuid}: ${result['error']}');
          }
        }

        if (!allSucceeded) {
          throw StateError('Push response contained failures');
        }

        await deltaSyncService.persistMirror(
          computation,
          useExistingTransaction: true,
        );

        final now = Time.nowEpoch();
        final state = await (db.select(db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();
        await (db.into(db.syncState)).insertOnConflictUpdate(SyncStateCompanion(
          id: const d.Value(1),
          lastServerTs: d.Value(state?.lastServerTs ?? 0),
          lastPullTs: d.Value(state?.lastPullTs ?? 0),
          lastPushTs: d.Value(now),
          isSyncing: const d.Value(0),
        ));
      });
    } catch (e) {
      debugPrint('❌ فشل في إرسال بيانات المزامنة: $e');
      rethrow;
    }
  }

  Future<void> _pull() async {
    final pullSettings = _performanceOptimizer.getCurrentPerformanceSettings();
    final pullTimeoutSeconds = (() {
      final custom = pullSettings['pullTimeout'];
      if (custom is int && custom > 0) {
        return custom;
      }
      final fallback = pullSettings['timeout'];
      if (fallback is int && fallback > 0) {
        return fallback;
      }
      return 30;
    })();

    final state = await (db.select(db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();
    final since = state?.lastServerTs ?? 0;
    final res = await ApiService.I.syncPull(since).timeout(Duration(seconds: pullTimeoutSeconds));
    if (res['success'] != true) return;
    final data = List<Map<String, dynamic>>.from(res['data']['data']);
    
    await db.transaction(() async {
      int maxTs = since;
      for (final it in data) {
        final entity = it['entity'] as String;
        final op = it['op'] as String;
        final serverId = it['server_id'];
        final serverTs = (it['server_ts'] as num).toInt();
        final rawData = it['data'];
        final item = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
        
        try {
          await _applyIncoming(entity, op, serverId, serverTs, item);
          if (serverTs > maxTs) maxTs = serverTs;
        } catch (e) {
          debugPrint('❌ Failed to apply incoming change for $entity: $e');
          rethrow;
        }
      }
      
      final now = Time.nowEpoch();
      await (db.into(db.syncState)).insertOnConflictUpdate(SyncStateCompanion(
        id: const d.Value(1),
        lastServerTs: d.Value(maxTs),
        lastPullTs: d.Value(now),
        isSyncing: const d.Value(0),
      ));
    });
    
    await RoomsRepository(db).refreshAllRoomOccupancy();
  }

  Future<void> _applyServerId(String entity, String localUuid, dynamic serverId) async {
    final sid = _asInt(serverId);
    if (sid == null) return;
    
    final now = Time.nowEpoch();
    switch (entity) {
      case 'rooms':
        await (db.update(db.rooms)..where((t) => t.localUuid.equals(localUuid))).write(
          RoomsCompanion(serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
      case 'bookings':
        await (db.update(db.bookings)..where((t) => t.localUuid.equals(localUuid))).write(
          BookingsCompanion(serverBookingId: d.Value(sid), serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
      case 'booking_notes':
        await (db.update(db.bookingNotes)..where((t) => t.localUuid.equals(localUuid))).write(
          BookingNotesCompanion(serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
      case 'employees':
        await (db.update(db.employees)..where((t) => t.localUuid.equals(localUuid))).write(
          EmployeesCompanion(serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
      case 'expenses':
        await (db.update(db.expenses)..where((t) => t.localUuid.equals(localUuid))).write(
          ExpensesCompanion(serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
      case 'cash_transactions':
        await (db.update(db.cashTransactions)..where((t) => t.localUuid.equals(localUuid))).write(
          CashTransactionsCompanion(serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
      case 'payments':
        await (db.update(db.payments)..where((t) => t.localUuid.equals(localUuid))).write(
          PaymentsCompanion(serverPaymentId: d.Value(sid), serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
      case 'debts':
        await (db.update(db.debts)..where((t) => t.localUuid.equals(localUuid))).write(
          DebtsCompanion(serverId: d.Value(sid), lastModified: d.Value(now)),
        );
        break;
    }
  }

  Future<void> _applyIncoming(String entity, String op, dynamic serverId, int serverTs, Map<String, dynamic> data) async {
    switch (entity) {
      case 'rooms':
        final rn = data['room_number'] as String;
        final local = await (db.select(db.rooms)..where((t) => t.roomNumber.equals(rn))).getSingleOrNull();
        if (local != null) {
          if (serverTs >= local.lastModified) {
            await roomsDao.updateByNumber(
              rn,
              RoomsCompanion(
                type: data['type'] != null ? d.Value(data['type']) : const d.Value.absent(),
                price: data['price'] != null ? d.Value((data['price'] as num).toDouble()) : const d.Value.absent(),
                status: data['status'] != null ? d.Value(data['status']) : const d.Value.absent(),
                imageUrl: data['image_url'] != null ? d.Value(data['image_url']) : const d.Value.absent(),
                serverId: d.Value(serverId is int ? serverId : null),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await roomsDao.insertOne(
            RoomsCompanion(
              roomNumber: d.Value(rn),
              type: d.Value(data['type'] ?? ''),
              price: d.Value((data['price'] as num?)?.toDouble() ?? 0),
              status: d.Value(data['status'] ?? 'شاغرة'),
              imageUrl: d.Value(data['image_url']),
              serverId: d.Value(serverId is int ? serverId : null),
            ),
            originIsServer: true,
          );
        }
        if (op == 'delete' || data['deleted_at'] != null) {
          await roomsDao.softDelete(rn, originIsServer: true);
        }
        break;
      case 'bookings':
        final sbid = data['booking_id'] as int?;
        Booking? local;
        if (sbid != null) {
          local = await (db.select(db.bookings)..where((t) => t.serverBookingId.equals(sbid))).getSingleOrNull();
        }
        final room = data['room_number'] as String?;
        if (local != null) {
          if (serverTs >= local.lastModified) {
            await bookingsDao.updateById(
              local.id,
              BookingsCompanion(
                serverBookingId: d.Value(sbid),
                roomNumber: room != null ? d.Value(room) : const d.Value.absent(),
                guestName: data['guest_name'] != null ? d.Value(data['guest_name']) : const d.Value.absent(),
                guestPhone: data['guest_phone'] != null ? d.Value(data['guest_phone']) : const d.Value.absent(),
                checkinDate: data['checkin_date'] != null ? d.Value(data['checkin_date']) : const d.Value.absent(),
                checkoutDate: d.Value(data['checkout_date']),
                status: data['status'] != null ? d.Value(data['status']) : const d.Value.absent(),
                notes: d.Value(data['notes']),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await bookingsDao.insertOne(
            BookingsCompanion(
              serverBookingId: d.Value(sbid),
              roomNumber: d.Value(room ?? ''),
              guestName: d.Value(data['guest_name'] ?? ''),
              guestPhone: d.Value(data['guest_phone'] ?? ''),
              guestNationality: d.Value(data['guest_nationality'] ?? ''),
              guestEmail: d.Value(data['guest_email']),
              guestAddress: d.Value(data['guest_address']),
              checkinDate: d.Value(data['checkin_date'] ?? Time.nowIso()),
              checkoutDate: d.Value(data['checkout_date']),
              status: d.Value(data['status'] ?? 'محجوزة'),
              notes: d.Value(data['notes']),
              serverId: d.Value(sbid),
            ),
            originIsServer: true,
          );
        }
        if (op == 'delete' || data['deleted_at'] != null) {
          final target = local ?? await (db.select(db.bookings)..where((t) => t.serverBookingId.equals(sbid ?? -1))).getSingleOrNull();
          if (target != null) await bookingsDao.softDelete(target.id, originIsServer: true);
        }
        break;
      case 'booking_notes':
        final nid = data['note_id'] as int?;
        BookingNote? ln;
        if (nid != null) ln = await (db.select(db.bookingNotes)..where((t) => t.serverId.equals(nid))).getSingleOrNull();
        if (ln != null) {
          if (serverTs >= ln.lastModified) {
            await notesDao.updateById(
              ln.id,
              BookingNotesCompanion(
                bookingId: d.Value(ln.bookingId),
                noteText: d.Value(data['note_text'] ?? ln.noteText),
                alertType: d.Value(data['alert_type'] ?? ln.alertType),
                alertUntil: d.Value(data['alert_until']),
                isActive: d.Value((data['is_active'] as num? ?? 1).toInt()),
                serverId: d.Value(nid),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await notesDao.insertOne(
            BookingNotesCompanion(
              bookingId: d.Value(data['booking_id'] as int? ?? 0),
              noteText: d.Value(data['note_text'] ?? ''),
              alertType: d.Value(data['alert_type'] ?? 'low'),
              alertUntil: d.Value(data['alert_until']),
              isActive: d.Value((data['is_active'] as num? ?? 1).toInt()),
              serverId: d.Value(nid),
            ),
            originIsServer: true,
          );
        }
        if (op == 'delete' || data['deleted_at'] != null) {
          final target = ln ?? await (db.select(db.bookingNotes)..where((t) => t.serverId.equals(nid ?? -1))).getSingleOrNull();
          if (target != null) await notesDao.softDelete(target.id, originIsServer: true);
        }
        break;
      case 'employees':
        final sid = data['id'] as int?;
        Employee? le;
        if (sid != null) le = await (db.select(db.employees)..where((t) => t.serverId.equals(sid))).getSingleOrNull();
        if (le != null) {
          if (serverTs >= le.lastModified) {
            await employeesDao.updateById(
              le.id,
              EmployeesCompanion(
                name: d.Value(data['name'] ?? le.name),
                basicSalary: d.Value((data['basic_salary'] as num?)?.toDouble() ?? le.basicSalary),
                status: d.Value(data['status'] ?? le.status),
                serverId: d.Value(sid),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await employeesDao.insertOne(
            EmployeesCompanion(
              name: d.Value(data['name'] ?? ''),
              basicSalary: d.Value((data['basic_salary'] as num?)?.toDouble() ?? 0),
              status: d.Value(data['status'] ?? 'active'),
              serverId: d.Value(sid),
            ),
            originIsServer: true,
          );
        }
        if (op == 'delete' || data['deleted_at'] != null) {
          final target = le ?? await (db.select(db.employees)..where((t) => t.serverId.equals(sid ?? -1))).getSingleOrNull();
          if (target != null) await employeesDao.softDelete(target.id, originIsServer: true);
        }
        break;
      case 'expenses':
        final xid = data['id'] as int?;
        Expense? lx;
        if (xid != null) lx = await (db.select(db.expenses)..where((t) => t.serverId.equals(xid))).getSingleOrNull();
        if (lx != null) {
          if (serverTs >= lx.lastModified) {
            await expensesDao.updateById(
              lx.id,
              ExpensesCompanion(
                expenseType: d.Value(data['expense_type'] ?? lx.expenseType),
                relatedId: d.Value(data['related_id'] as int?),
                description: d.Value(data['description'] ?? lx.description),
                amount: d.Value((data['amount'] as num?)?.toDouble() ?? lx.amount),
                date: d.Value(data['date'] ?? lx.date),
                serverId: d.Value(xid),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await expensesDao.insertOne(
            ExpensesCompanion(
              expenseType: d.Value(data['expense_type'] ?? 'other'),
              relatedId: d.Value(data['related_id'] as int?),
              description: d.Value(data['description'] ?? ''),
              amount: d.Value((data['amount'] as num?)?.toDouble() ?? 0),
              date: d.Value(data['date'] ?? Time.safeIsoToDateString(Time.nowIso())),
              serverId: d.Value(xid),
            ),
            originIsServer: true,
          );
        }
        if (op == 'delete' || data['deleted_at'] != null) {
          final target = lx ?? await (db.select(db.expenses)..where((t) => t.serverId.equals(xid ?? -1))).getSingleOrNull();
          if (target != null) await expensesDao.softDelete(target.id, originIsServer: true);
        }
        break;
      case 'cash_transactions':
        final cid = data['id'] as int?;
        final lc = cid != null ? await (db.select(db.cashTransactions)..where((t) => t.serverId.equals(cid))).getSingleOrNull() : null;
        if (lc != null) {
          if (serverTs >= lc.lastModified) {
            await cashDao.updateById(
              lc.id,
              CashTransactionsCompanion(
                registerId: d.Value(data['register_id'] as int?),
                transactionType: d.Value(data['transaction_type'] ?? lc.transactionType),
                amount: d.Value((data['amount'] as num?)?.toDouble() ?? lc.amount),
                referenceType: d.Value(data['reference_type']),
                referenceId: d.Value(data['reference_id'] as int?),
                description: d.Value(data['description']),
                transactionTime: d.Value(data['transaction_time'] ?? lc.transactionTime),
                serverId: d.Value(cid),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await cashDao.insertOne(
            CashTransactionsCompanion(
              registerId: d.Value(data['register_id'] as int?),
              transactionType: d.Value(data['transaction_type'] ?? 'income'),
              amount: d.Value((data['amount'] as num?)?.toDouble() ?? 0),
              referenceType: d.Value(data['reference_type']),
              referenceId: d.Value(data['reference_id'] as int?),
              description: d.Value(data['description']),
              transactionTime: d.Value(data['transaction_time'] ?? Time.nowIso()),
              serverId: d.Value(cid),
            ),
            originIsServer: true,
          );
        }
        if (op == 'delete' || data['deleted_at'] != null) {
          final target = lc ?? await (db.select(db.cashTransactions)..where((t) => t.serverId.equals(cid ?? -1))).getSingleOrNull();
          if (target != null) await cashDao.softDelete(target.id, originIsServer: true);
        }
        break;
      case 'payments':
        final pid = data['payment_id'] as int?;
        final lp = pid != null ? await (db.select(db.payments)..where((t) => t.serverPaymentId.equals(pid))).getSingleOrNull() : null;
        if (lp != null) {
          if (serverTs >= lp.lastModified) {
            await paymentsDao.updateById(
              lp.id,
              PaymentsCompanion(
                serverPaymentId: d.Value(pid),
                serverBookingId: d.Value(data['booking_id'] as int?),
                roomNumber: d.Value(data['room_number'] as String?),
                amount: d.Value((data['amount'] as num?)?.toDouble() ?? lp.amount),
                paymentDate: d.Value(data['payment_date'] ?? lp.paymentDate),
                notes: d.Value(data['notes'] as String?),
                paymentMethod: d.Value(data['payment_method'] ?? lp.paymentMethod),
                revenueType: d.Value(data['revenue_type'] ?? lp.revenueType),
                cashTransactionServerId: d.Value(data['cash_transaction_id'] as int?),
                serverId: d.Value(pid),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await paymentsDao.insertOne(
            PaymentsCompanion(
              serverPaymentId: d.Value(pid),
              serverBookingId: d.Value(data['booking_id'] as int?),
              roomNumber: d.Value(data['room_number'] as String?),
              amount: d.Value((data['amount'] as num?)?.toDouble() ?? 0),
              paymentDate: d.Value(data['payment_date'] ?? Time.nowIso()),
              notes: d.Value(data['notes'] as String?),
              paymentMethod: d.Value(data['payment_method'] ?? 'نقدي'),
              revenueType: d.Value(data['revenue_type'] ?? 'room'),
              cashTransactionServerId: d.Value(data['cash_transaction_id'] as int?),
              serverId: d.Value(pid),
            ),
            originIsServer: true,
          );
        }
        if (op == 'delete' || data['deleted_at'] != null) {
          final target = lp ?? await (db.select(db.payments)..where((t) => t.serverPaymentId.equals(pid ?? -1))).getSingleOrNull();
          if (target != null) await paymentsDao.softDelete(target.id, originIsServer: true);
        }
        break;
      case 'booking_nights':
        await _applyBookingNight(op, serverTs, data);
        break;
      case 'hotel_day_ledger':
        await _applyHotelDayLedger(op, serverTs, data);
        break;
    }
  }

  Future<void> _applyBookingNight(String op, int serverTs, Map<String, dynamic> data) async {
    final localUuid = _asString(data['local_uuid']);
    if (localUuid == null || localUuid.isEmpty) {
      return;
    }

    final existing = await (db.select(db.bookingNights)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
    final bool isDelete = op == 'delete' || data['deleted_at'] != null;
    final int normalizedServerTs = _normalizeTimestampField(serverTs, fallback: Time.nowEpoch());
    final int createdAt = _normalizeTimestampField(data['created_at'], fallback: normalizedServerTs);
    final int updatedAt = _normalizeTimestampField(data['updated_at'], fallback: normalizedServerTs);
    final int lastModified = _normalizeTimestampField(data['last_modified'], fallback: updatedAt);
    final int createdEpoch = _normalizeTimestampField(data['created_at_epoch'], fallback: createdAt);
    final int lastModifiedEpoch = _normalizeTimestampField(data['last_modified_epoch'], fallback: lastModified);
    final int? deletedAt = data.containsKey('deleted_at')
        ? _normalizeTimestampField(data['deleted_at'], fallback: normalizedServerTs)
        : null;
    final String createdIso = _isoFromData(data['created_at_iso'], createdAt);
    final String updatedIso = _isoFromData(data['updated_at_iso'], updatedAt);
    final String? deletedIso = _maybeIsoFromData(data['deleted_at_iso'], deletedAt);

    if (isDelete) {
      if (existing != null) {
        await (db.update(db.bookingNights)..where((t) => t.id.equals(existing.id))).write(
          BookingNightsCompanion(
            deletedAt: deletedAt != null ? d.Value(deletedAt) : const d.Value.absent(),
            deletedAtIso: deletedIso != null ? d.Value(deletedIso) : const d.Value.absent(),
            updatedAt: d.Value(updatedAt),
            lastModified: d.Value(lastModified),
            updatedAtIso: d.Value(updatedIso),
            lastModifiedEpoch: d.Value(lastModifiedEpoch),
            origin: const d.Value('server'),
          ),
        );
      }
      return;
    }

    final bookingLocalId = _asInt(data['booking_local_id']);
    final hotelDayKey = _asString(data['hotel_day_key']);
    final nightStart = _asString(data['night_start']);
    final nightEnd = _asString(data['night_end']);

    if (bookingLocalId == null || hotelDayKey == null || nightStart == null || nightEnd == null) {
      debugPrint('⚠️ تخطي booking_nights/$localUuid لعدم اكتمال البيانات');
      return;
    }

    final companion = BookingNightsCompanion(
      localUuid: existing == null ? d.Value(localUuid) : const d.Value.absent(),
      bookingLocalId: d.Value(bookingLocalId),
      hotelDayKey: d.Value(hotelDayKey),
      nightStart: d.Value(nightStart),
      nightEnd: d.Value(nightEnd),
      nightlyRate: _doubleValue(data['nightly_rate']),
      sequence: _intValue(data['sequence']),
      isProcessedByAutoFix: _boolValue(data['is_processed_by_auto_fix']),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(updatedAt),
      deletedAt: deletedAt != null ? d.Value(deletedAt) : const d.Value.absent(),
      lastModified: d.Value(lastModified),
      createdAtIso: d.Value(createdIso),
      updatedAtIso: d.Value(updatedIso),
      deletedAtIso: deletedIso != null ? d.Value(deletedIso) : const d.Value.absent(),
      createdAtEpoch: d.Value(createdEpoch),
      lastModifiedEpoch: d.Value(lastModifiedEpoch),
      version: _intValue(data['version']),
      origin: const d.Value('server'),
    );

    if (existing == null) {
      await db.into(db.bookingNights).insert(companion);
    } else {
      await (db.update(db.bookingNights)..where((t) => t.id.equals(existing.id))).write(companion);
    }
  }

  Future<void> _applyHotelDayLedger(String op, int serverTs, Map<String, dynamic> data) async {
    final localUuid = _asString(data['local_uuid']);
    if (localUuid == null || localUuid.isEmpty) {
      return;
    }

    final existing = await (db.select(db.hotelDayLedger)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
    final bool isDelete = op == 'delete' || data['deleted_at'] != null;
    final int normalizedServerTs = _normalizeTimestampField(serverTs, fallback: Time.nowEpoch());
    final int createdAt = _normalizeTimestampField(data['created_at'], fallback: normalizedServerTs);
    final int updatedAt = _normalizeTimestampField(data['updated_at'], fallback: normalizedServerTs);
    final int lastModified = _normalizeTimestampField(data['last_modified'], fallback: updatedAt);
    final int createdEpoch = _normalizeTimestampField(data['created_at_epoch'], fallback: createdAt);
    final int lastModifiedEpoch = _normalizeTimestampField(data['last_modified_epoch'], fallback: lastModified);
    final int? deletedAt = data.containsKey('deleted_at')
        ? _normalizeTimestampField(data['deleted_at'], fallback: normalizedServerTs)
        : null;
    final String createdIso = _isoFromData(data['created_at_iso'], createdAt);
    final String updatedIso = _isoFromData(data['updated_at_iso'], updatedAt);
    final String? deletedIso = _maybeIsoFromData(data['deleted_at_iso'], deletedAt);

    if (isDelete) {
      if (existing != null) {
        await (db.update(db.hotelDayLedger)..where((t) => t.id.equals(existing.id))).write(
          HotelDayLedgerCompanion(
            deletedAt: deletedAt != null ? d.Value(deletedAt) : const d.Value.absent(),
            deletedAtIso: deletedIso != null ? d.Value(deletedIso) : const d.Value.absent(),
            updatedAt: d.Value(updatedAt),
            lastModified: d.Value(lastModified),
            updatedAtIso: d.Value(updatedIso),
            lastModifiedEpoch: d.Value(lastModifiedEpoch),
            origin: const d.Value('server'),
          ),
        );
      }
      return;
    }

    final hotelDayKey = _asString(data['hotel_day_key']);
    if (hotelDayKey == null || hotelDayKey.isEmpty) {
      debugPrint('⚠️ تخطي hotel_day_ledger/$localUuid لعدم اكتمال البيانات');
      return;
    }

    final companion = HotelDayLedgerCompanion(
      localUuid: existing == null ? d.Value(localUuid) : const d.Value.absent(),
      hotelDayKey: d.Value(hotelDayKey),
      totalIncome: _doubleValue(data['total_income']),
      totalExpenses: _doubleValue(data['total_expenses']),
      pendingBalances: _doubleValue(data['pending_balances']),
      occupancyRate: _doubleValue(data['occupancy_rate']),
      bookingsProcessed: _intValue(data['bookings_processed']),
      paymentsProcessed: _intValue(data['payments_processed']),
      debtsProcessed: _intValue(data['debts_processed']),
      expensesProcessed: _intValue(data['expenses_processed']),
      status: d.Value(_asString(data['status']) ?? 'draft'),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(updatedAt),
      deletedAt: deletedAt != null ? d.Value(deletedAt) : const d.Value.absent(),
      lastModified: d.Value(lastModified),
      createdAtIso: d.Value(createdIso),
      updatedAtIso: d.Value(updatedIso),
      deletedAtIso: deletedIso != null ? d.Value(deletedIso) : const d.Value.absent(),
      createdAtEpoch: d.Value(createdEpoch),
      lastModifiedEpoch: d.Value(lastModifiedEpoch),
      version: _intValue(data['version']),
      origin: const d.Value('server'),
    );

    if (existing == null) {
      await db.into(db.hotelDayLedger).insert(companion);
    } else {
      await (db.update(db.hotelDayLedger)..where((t) => t.id.equals(existing.id))).write(companion);
    }
  }

}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool? _asBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') return true;
    if (normalized == 'false' || normalized == '0' || normalized == 'no') return false;
  }
  return null;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  return value.toString();
}

DateTime? _parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    const int millisecondsThreshold = 1000000000000;
    if (value > millisecondsThreshold) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

int _normalizeTimestampField(dynamic value, {int? fallback}) {
  final parsed = _asInt(value);
  if (parsed == null) {
    return fallback ?? Time.nowEpoch();
  }
  return parsed >= 1000000000000 ? parsed ~/ 1000 : parsed;
}

String _isoFromData(dynamic value, int secondsFallback) {
  final iso = _asString(value);
  if (iso != null && iso.isNotEmpty) return iso;
  return _secondsToIso(secondsFallback);
}

String? _maybeIsoFromData(dynamic value, int? secondsFallback) {
  final iso = _asString(value);
  if (iso != null && iso.isNotEmpty) {
    return iso;
  }
  if (secondsFallback != null) {
    return _secondsToIso(secondsFallback);
  }
  return null;
}

String _secondsToIso(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toIso8601String();

d.Value<int> _intValue(dynamic value) {
  final parsed = _asInt(value);
  return parsed == null ? const d.Value.absent() : d.Value(parsed);
}

d.Value<double> _doubleValue(dynamic value) {
  final parsed = _asDouble(value);
  return parsed == null ? const d.Value.absent() : d.Value(parsed);
}

d.Value<bool> _boolValue(dynamic value) {
  final parsed = _asBool(value);
  return parsed == null ? const d.Value.absent() : d.Value(parsed);
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref.read(databaseProvider)));
final syncStatusProvider = StreamProvider<SyncStatus>((ref) => ref.read(syncServiceProvider).statusStream);
