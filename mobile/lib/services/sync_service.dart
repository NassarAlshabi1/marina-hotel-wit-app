import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../utils/time.dart';
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
import 'providers.dart';

enum SyncStatus { idle, pushing, pulling, error }

class SyncService {
  SyncService(this.db)
      : outboxDao = OutboxDao(db),
        roomsDao = RoomsDao(db, OutboxDao(db)),
        bookingsDao = BookingsDao(db, OutboxDao(db)),
        notesDao = BookingNotesDao(db, OutboxDao(db)),
        employeesDao = EmployeesDao(db, OutboxDao(db)),
        expensesDao = ExpensesDao(db, OutboxDao(db)),
        cashDao = CashTransactionsDao(db, OutboxDao(db)),
        paymentsDao = PaymentsDao(db, OutboxDao(db));

  final AppDatabase db;
  final OutboxDao outboxDao;
  final RoomsDao roomsDao;
  final BookingsDao bookingsDao;
  final BookingNotesDao notesDao;
  final EmployeesDao employeesDao;
  final ExpensesDao expensesDao;
  final CashTransactionsDao cashDao;
  final PaymentsDao paymentsDao;

  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _status.stream;

  Future<void> runSync() async {
    try {
      _status.add(SyncStatus.pushing);
      await _push();
      _status.add(SyncStatus.pulling);
      await _pull();
      _status.add(SyncStatus.idle);
    } catch (_) {
      _status.add(SyncStatus.error);
    }
  }

  Future<void> _push() async {
    final batch = await outboxDao.takeBatch(50);
    if (batch.isEmpty) return;
    final changes = batch
        .map((o) => {
              'entity': o.entity,
              'op': o.op,
              'uuid': o.localUuid,
              'server_id': o.serverId,
              'data': jsonDecode(o.payload),
              'client_ts': o.clientTs,
            })
        .toList();
    try {
      final res = await ApiService.I.syncPush(changes);
      if (res['success'] == true) {
        final results = List<Map<String, dynamic>>.from(res['data']['results']);
        for (var i = 0; i < batch.length; i++) {
          final o = batch[i];
          final r = results[i];
          if (r['success'] == true) {
            final sid = r['server_id'];
            await _applyServerId(o.entity, o.localUuid, sid);
            await outboxDao.removeById(o.id);
          } else {
            final attempts = o.attempts + 1;
            await outboxDao.setError(o.id, r['error']?.toString() ?? 'error', attempts);
          }
        }
      }
    } catch (e) {
      for (final o in batch) {
        final attempts = o.attempts + 1;
        await outboxDao.setError(o.id, e.toString(), attempts);
      }
      rethrow;
    }
  }

  Future<void> _pull() async {
    final state = await (db.select(db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();
    final since = state?.lastServerTs ?? 0;
    final res = await ApiService.I.syncPull(since);
    if (res['success'] != true) return;
    final data = List<Map<String, dynamic>>.from(res['data']['data']);
    int maxTs = since;
    for (final it in data) {
      final entity = it['entity'] as String;
      final op = it['op'] as String;
      final serverId = it['server_id'];
      final serverTs = (it['server_ts'] as num).toInt();
      final item = Map<String, dynamic>.from(it['data']);
      await _applyIncoming(entity, op, serverId, serverTs, item);
      if (serverTs > maxTs) maxTs = serverTs;
    }
    final now = Time.nowEpoch();
    await (db.into(db.syncState)).insertOnConflictUpdate(SyncStateCompanion(
      id: const d.Value(1),
      lastServerTs: d.Value(maxTs),
      lastPullTs: d.Value(now),
      isSyncing: const d.Value(0),
    ));
  }

  Future<void> _applyServerId(String entity, String localUuid, dynamic serverId) async {
    switch (entity) {
      case 'rooms':
        final row = await (db.select(db.rooms)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) await (db.update(db.rooms)..where((t) => t.roomNumber.equals(row.roomNumber))).write(RoomsCompanion(serverId: d.Value(serverId is int ? serverId : null), lastModified: d.Value(Time.nowEpoch())));
        break;
      case 'bookings':
        final row = await (db.select(db.bookings)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) await (db.update(db.bookings)..where((t) => t.id.equals(row.id))).write(BookingsCompanion(serverBookingId: d.Value(serverId is int ? serverId : null), serverId: d.Value(serverId is int ? serverId : null), lastModified: d.Value(Time.nowEpoch())));
        break;
      case 'booking_notes':
        final rowN = await (db.select(db.bookingNotes)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (rowN != null) await (db.update(db.bookingNotes)..where((t) => t.id.equals(rowN.id))).write(BookingNotesCompanion(serverId: d.Value(serverId is int ? serverId : null), lastModified: d.Value(Time.nowEpoch())));
        break;
      case 'employees':
        final rowE = await (db.select(db.employees)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (rowE != null) await (db.update(db.employees)..where((t) => t.id.equals(rowE.id))).write(EmployeesCompanion(serverId: d.Value(serverId is int ? serverId : null), lastModified: d.Value(Time.nowEpoch())));
        break;
      case 'expenses':
        final rowX = await (db.select(db.expenses)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (rowX != null) await (db.update(db.expenses)..where((t) => t.id.equals(rowX.id))).write(ExpensesCompanion(serverId: d.Value(serverId is int ? serverId : null), lastModified: d.Value(Time.nowEpoch())));
        break;
      case 'cash_transactions':
        final rowC = await (db.select(db.cashTransactions)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (rowC != null) await (db.update(db.cashTransactions)..where((t) => t.id.equals(rowC.id))).write(CashTransactionsCompanion(serverId: d.Value(serverId is int ? serverId : null), lastModified: d.Value(Time.nowEpoch())));
        break;
      case 'payments':
        final rowP = await (db.select(db.payments)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (rowP != null) await (db.update(db.payments)..where((t) => t.id.equals(rowP.id))).write(PaymentsCompanion(serverPaymentId: d.Value(serverId is int ? serverId : null), serverId: d.Value(serverId is int ? serverId : null), lastModified: d.Value(Time.nowEpoch())));
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
    }
  }
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref.read(databaseProvider)));
final syncStatusProvider = StreamProvider<SyncStatus>((ref) => ref.read(syncServiceProvider).statusStream);
