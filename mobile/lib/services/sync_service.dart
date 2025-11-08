import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import 'package:pocketbase/pocketbase.dart';
import '../utils/time.dart';
import 'pocketbase_service.dart';
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
        paymentsDao = PaymentsDao(db, OutboxDao(db)) {
    _subscribeToRealtimeUpdates();
  }

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

  final _subs = <Future<dynamic>>[];

  void _subscribeToRealtimeUpdates() {
    final pb = PocketBaseService.I.client;
    final collections = [
      'rooms', 'bookings', 'booking_notes', 'employees',
      'expenses', 'cash_transactions', 'payments'
    ];
    for (final c in collections) {
      try {
        final sub = pb.collection(c).subscribe('*', (e) async {
          await _pullCollection(c);
        });
        _subs.add(sub);
      } catch (_) {}
    }
  }

  Future<void> runSync() async {
    try {
      _status.add(SyncStatus.pushing);
      await _push();
      _status.add(SyncStatus.pulling);
      await _pull();
      _status.add(SyncStatus.idle);
    } catch (_) {
      _status.add(SyncStatus.error);
      rethrow;
    }
  }

  Future<void> _push() async {
    final batch = await outboxDao.takeBatch(50);
    if (batch.isEmpty) return;
    final pb = PocketBaseService.I.client;

    for (final item in batch) {
      try {
        final entity = item.entity;
        final collection = _getCollectionName(entity);
        final payload = Map<String, dynamic>.from(jsonDecode(item.payload));
        final body = await _augmentPayloadForEntity(entity, item.localUuid, payload, isCreate: item.op == 'create');

        if (item.op == 'create') {
          final record = await pb.collection(collection).create(body: body);
          await _updateLocalServerId(entity, item.localUuid, record.id);
          await outboxDao.removeById(item.id);
        } else if (item.op == 'update') {
          final list = await pb.collection(collection).getList(filter: 'local_uuid = "${item.localUuid}"');
          if (list.items.isNotEmpty) {
            await pb.collection(collection).update(list.items.first.id, body: body);
            await outboxDao.removeById(item.id);
          } else {
            final record = await pb.collection(collection).create(body: body);
            await _updateLocalServerId(entity, item.localUuid, record.id);
            await outboxDao.removeById(item.id);
          }
        } else if (item.op == 'delete') {
          final list = await pb.collection(collection).getList(filter: 'local_uuid = "${item.localUuid}"');
          if (list.items.isNotEmpty) {
            await pb.collection(collection).update(list.items.first.id, body: {'deleted_at_ts': Time.nowEpoch(), 'last_modified': Time.nowEpoch()});
          }
          await outboxDao.removeById(item.id);
        }
      } catch (e) {
        final attempts = item.attempts + 1;
        await outboxDao.setError(item.id, e.toString(), attempts);
      }
    }
  }

  Future<Map<String, dynamic>> _augmentPayloadForEntity(String entity, String localUuid, Map<String, dynamic> payload, {required bool isCreate}) async {
    final now = Time.nowEpoch();
    Map<String, dynamic> body = Map<String, dynamic>.from(payload);

    switch (entity) {
      case 'rooms':
        final row = await (db.select(db.rooms)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (isCreate && row != null) {
          body.addAll({
            'local_uuid': localUuid,
            'created_at_ts': row.createdAt,
            'updated_at_ts': row.updatedAt,
            'last_modified': row.lastModified,
            'version': row.version,
            'origin': row.origin,
          });
        } else {
          body['last_modified'] = now;
        }
        break;
      case 'bookings':
        final row = await (db.select(db.bookings)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (isCreate && row != null) {
          body.addAll({
            'local_uuid': localUuid,
            'created_at_ts': row.createdAt,
            'updated_at_ts': row.updatedAt,
            'last_modified': row.lastModified,
            'version': row.version,
            'origin': row.origin,
          });
        } else {
          body['last_modified'] = now;
        }
        break;
      case 'booking_notes':
        final row = await (db.select(db.bookingNotes)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (body.containsKey('booking_id')) {
          final bid = body['booking_id'] as int?;
          if (bid != null) {
            final b = await (db.select(db.bookings)..where((t) => t.id.equals(bid))).getSingleOrNull();
            if (b != null) body['booking_local_uuid'] = b.localUuid;
          }
          body.remove('booking_id');
        }
        if (isCreate && row != null) {
          body.addAll({
            'local_uuid': localUuid,
            'created_at_ts': row.createdAt,
            'updated_at_ts': row.updatedAt,
            'last_modified': row.lastModified,
            'version': row.version,
            'origin': row.origin,
          });
        } else {
          body['last_modified'] = now;
        }
        break;
      case 'employees':
        final row = await (db.select(db.employees)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (isCreate && row != null) {
          body.addAll({
            'local_uuid': localUuid,
            'created_at_ts': row.createdAt,
            'updated_at_ts': row.updatedAt,
            'last_modified': row.lastModified,
            'version': row.version,
            'origin': row.origin,
          });
        } else {
          body['last_modified'] = now;
        }
        break;
      case 'expenses':
        final row = await (db.select(db.expenses)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (isCreate && row != null) {
          body.addAll({
            'local_uuid': localUuid,
            'created_at_ts': row.createdAt,
            'updated_at_ts': row.updatedAt,
            'last_modified': row.lastModified,
            'version': row.version,
            'origin': row.origin,
          });
        } else {
          body['last_modified'] = now;
        }
        break;
      case 'cash_transactions':
        final row = await (db.select(db.cashTransactions)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (isCreate && row != null) {
          body.addAll({
            'local_uuid': localUuid,
            'created_at_ts': row.createdAt,
            'updated_at_ts': row.updatedAt,
            'last_modified': row.lastModified,
            'version': row.version,
            'origin': row.origin,
          });
        } else {
          body['last_modified'] = now;
        }
        break;
      case 'payments':
        final row = await (db.select(db.payments)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (body.containsKey('booking_local_id')) {
          final lid = body['booking_local_id'] as int?;
          if (lid != null) {
            final b = await (db.select(db.bookings)..where((t) => t.id.equals(lid))).getSingleOrNull();
            if (b != null) body['booking_local_uuid'] = b.localUuid;
          }
          body.remove('booking_local_id');
        }
        if (body.containsKey('cash_transaction_local_id')) {
          final cid = body['cash_transaction_local_id'] as int?;
          if (cid != null) {
            final c = await (db.select(db.cashTransactions)..where((t) => t.id.equals(cid))).getSingleOrNull();
            if (c != null) body['cash_transaction_local_uuid'] = c.localUuid;
          }
          body.remove('cash_transaction_local_id');
        }
        if (isCreate && row != null) {
          body.addAll({
            'local_uuid': localUuid,
            'created_at_ts': row.createdAt,
            'updated_at_ts': row.updatedAt,
            'last_modified': row.lastModified,
            'version': row.version,
            'origin': row.origin,
          });
        } else {
          body['last_modified'] = now;
        }
        break;
    }

    return body;
  }

  int _pbIdHash(String id) => id.hashCode;

  Future<void> _updateLocalServerId(String entity, String localUuid, String pbId) async {
    final sid = _pbIdHash(pbId);
    switch (entity) {
      case 'rooms':
        final row = await (db.select(db.rooms)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) {
          await (db.update(db.rooms)..where((t) => t.roomNumber.equals(row.roomNumber))).write(RoomsCompanion(serverId: d.Value(sid)));
        }
        break;
      case 'bookings':
        final row = await (db.select(db.bookings)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) {
          await (db.update(db.bookings)..where((t) => t.id.equals(row.id))).write(BookingsCompanion(serverId: d.Value(sid)));
        }
        break;
      case 'booking_notes':
        final row = await (db.select(db.bookingNotes)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) {
          await (db.update(db.bookingNotes)..where((t) => t.id.equals(row.id))).write(BookingNotesCompanion(serverId: d.Value(sid)));
        }
        break;
      case 'employees':
        final row = await (db.select(db.employees)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) {
          await (db.update(db.employees)..where((t) => t.id.equals(row.id))).write(EmployeesCompanion(serverId: d.Value(sid)));
        }
        break;
      case 'expenses':
        final row = await (db.select(db.expenses)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) {
          await (db.update(db.expenses)..where((t) => t.id.equals(row.id))).write(ExpensesCompanion(serverId: d.Value(sid)));
        }
        break;
      case 'cash_transactions':
        final row = await (db.select(db.cashTransactions)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) {
          await (db.update(db.cashTransactions)..where((t) => t.id.equals(row.id))).write(CashTransactionsCompanion(serverId: d.Value(sid)));
        }
        break;
      case 'payments':
        final row = await (db.select(db.payments)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (row != null) {
          await (db.update(db.payments)..where((t) => t.id.equals(row.id))).write(PaymentsCompanion(serverId: d.Value(sid)));
        }
        break;
    }
  }

  Future<void> _pull() async {
    await _pullCollection('rooms');
    await _pullCollection('bookings');
    await _pullCollection('booking_notes');
    await _pullCollection('employees');
    await _pullCollection('expenses');
    await _pullCollection('cash_transactions');
    await _pullCollection('payments');

    final now = Time.nowEpoch();
    await (db.into(db.syncState)).insertOnConflictUpdate(SyncStateCompanion(
      id: const d.Value(1),
      lastPullTs: d.Value(now),
      isSyncing: const d.Value(0),
    ));
  }

  Future<void> _pullCollection(String entity) async {
    final pb = PocketBaseService.I.client;
    final collection = _getCollectionName(entity);
    final state = await (db.select(db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();
    final sinceTs = state?.lastPullTs ?? 0;
    try {
      final records = await pb.collection(collection).getFullList(filter: 'last_modified > $sinceTs', sort: '+last_modified');
      for (final r in records) {
        await _applyRemoteRecord(entity, r.toJson());
      }
    } catch (_) {}
  }

  Future<void> _applyRemoteRecord(String entity, Map<String, dynamic> data) async {
    final localUuid = data['local_uuid'] as String?;
    final lastModified = (data['last_modified'] as num?)?.toInt() ?? 0;
    final deletedAtTs = (data['deleted_at_ts'] as num?)?.toInt();
    final pbId = (data['id']?.toString() ?? '');
    final sid = pbId.isNotEmpty ? _pbIdHash(pbId) : null;

    switch (entity) {
      case 'rooms':
        if (localUuid == null) return;
        final local = await (db.select(db.rooms)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (deletedAtTs != null) {
          if (local != null) await roomsDao.softDelete(local.roomNumber, originIsServer: true);
          return;
        }
        if (local != null) {
          if (lastModified >= local.lastModified) {
            await roomsDao.updateByNumber(
              local.roomNumber,
              RoomsCompanion(
                type: data['type'] != null ? d.Value(data['type']) : const d.Value.absent(),
                price: data['price'] != null ? d.Value((data['price'] as num).toDouble()) : const d.Value.absent(),
                status: data['status'] != null ? d.Value(data['status']) : const d.Value.absent(),
                imageUrl: d.Value(data['image_url'] as String?),
                serverId: d.Value(sid),
                lastModified: d.Value(lastModified),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await roomsDao.insertOne(
            RoomsCompanion(
              localUuid: d.Value(localUuid),
              roomNumber: d.Value(data['room_number'] as String),
              type: d.Value(data['type'] as String),
              price: d.Value((data['price'] as num).toDouble()),
              status: d.Value(data['status'] as String),
              imageUrl: d.Value(data['image_url'] as String?),
              serverId: d.Value(sid),
              createdAt: d.Value((data['created_at_ts'] as num).toInt()),
              updatedAt: d.Value((data['updated_at_ts'] as num).toInt()),
              lastModified: d.Value(lastModified),
              version: d.Value((data['version'] as num).toInt()),
              origin: d.Value(data['origin'] as String),
            ),
            originIsServer: true,
          );
        }
        break;
      case 'bookings':
        if (localUuid == null) return;
        final local = await (db.select(db.bookings)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (deletedAtTs != null) {
          if (local != null) await bookingsDao.softDelete(local.id, originIsServer: true);
          return;
        }
        if (local != null) {
          if (lastModified >= local.lastModified) {
            await bookingsDao.updateById(
              local.id,
              BookingsCompanion(
                roomNumber: data['room_number'] != null ? d.Value(data['room_number']) : const d.Value.absent(),
                guestName: data['guest_name'] != null ? d.Value(data['guest_name']) : const d.Value.absent(),
                guestPhone: data['guest_phone'] != null ? d.Value(data['guest_phone']) : const d.Value.absent(),
                guestIdType: data['guest_id_type'] != null ? d.Value(data['guest_id_type']) : const d.Value.absent(),
                guestIdNumber: data['guest_id_number'] != null ? d.Value(data['guest_id_number']) : const d.Value.absent(),
                guestIdIssueDate: d.Value(data['guest_id_issue_date'] as String?),
                guestIdIssuePlace: d.Value(data['guest_id_issue_place'] as String?),
                guestNationality: data['guest_nationality'] != null ? d.Value(data['guest_nationality']) : const d.Value.absent(),
                guestEmail: d.Value(data['guest_email'] as String?),
                guestAddress: d.Value(data['guest_address'] as String?),
                checkinDate: data['checkin_date'] != null ? d.Value(data['checkin_date']) : const d.Value.absent(),
                checkoutDate: d.Value(data['checkout_date'] as String?),
                actualCheckout: d.Value(data['actual_checkout'] as String?),
                status: data['status'] != null ? d.Value(data['status']) : const d.Value.absent(),
                notes: d.Value(data['notes'] as String?),
                expectedNights: data['expected_nights'] != null ? d.Value((data['expected_nights'] as num).toInt()) : const d.Value.absent(),
                calculatedNights: data['calculated_nights'] != null ? d.Value((data['calculated_nights'] as num).toInt()) : const d.Value.absent(),
                serverBookingId: d.Value(data['server_booking_id'] as int?),
                serverId: d.Value(sid),
                lastModified: d.Value(lastModified),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await bookingsDao.insertOne(
            BookingsCompanion(
              localUuid: d.Value(localUuid),
              roomNumber: d.Value(data['room_number'] as String),
              guestName: d.Value(data['guest_name'] as String),
              guestPhone: d.Value(data['guest_phone'] as String),
              guestIdType: d.Value(data['guest_id_type'] as String),
              guestIdNumber: d.Value(data['guest_id_number'] as String),
              guestIdIssueDate: d.Value(data['guest_id_issue_date'] as String?),
              guestIdIssuePlace: d.Value(data['guest_id_issue_place'] as String?),
              guestNationality: d.Value(data['guest_nationality'] as String),
              guestEmail: d.Value(data['guest_email'] as String?),
              guestAddress: d.Value(data['guest_address'] as String?),
              checkinDate: d.Value(data['checkin_date'] as String),
              checkoutDate: d.Value(data['checkout_date'] as String?),
              actualCheckout: d.Value(data['actual_checkout'] as String?),
              status: d.Value(data['status'] as String),
              notes: d.Value(data['notes'] as String?),
              expectedNights: d.Value((data['expected_nights'] as num).toInt()),
              calculatedNights: d.Value((data['calculated_nights'] as num).toInt()),
              serverBookingId: d.Value(data['server_booking_id'] as int?),
              serverId: d.Value(sid),
              createdAt: d.Value((data['created_at_ts'] as num).toInt()),
              updatedAt: d.Value((data['updated_at_ts'] as num).toInt()),
              lastModified: d.Value(lastModified),
              version: d.Value((data['version'] as num).toInt()),
              origin: d.Value(data['origin'] as String),
            ),
            originIsServer: true,
          );
        }
        break;
      case 'booking_notes':
        if (localUuid == null) return;
        final local = await (db.select(db.bookingNotes)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        final bookingLocalUuid = data['booking_local_uuid'] as String?;
        int? bookingLocalId;
        if (bookingLocalUuid != null) {
          final b = await (db.select(db.bookings)..where((t) => t.localUuid.equals(bookingLocalUuid))).getSingleOrNull();
          bookingLocalId = b?.id;
        }
        if (deletedAtTs != null) {
          if (local != null) await notesDao.softDelete(local.id, originIsServer: true);
          return;
        }
        if (local != null) {
          if (lastModified >= local.lastModified) {
            await notesDao.updateById(
              local.id,
              BookingNotesCompanion(
                bookingId: bookingLocalId != null ? d.Value(bookingLocalId) : const d.Value.absent(),
                noteText: data['note_text'] != null ? d.Value(data['note_text']) : const d.Value.absent(),
                alertType: data['alert_type'] != null ? d.Value(data['alert_type']) : const d.Value.absent(),
                alertUntil: d.Value(data['alert_until'] as String?),
                isActive: data['is_active'] != null ? d.Value((data['is_active'] as num).toInt()) : const d.Value.absent(),
                serverId: d.Value(sid),
                lastModified: d.Value(lastModified),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await notesDao.insertOne(
            BookingNotesCompanion(
              localUuid: d.Value(localUuid),
              bookingId: d.Value(bookingLocalId ?? 0),
              noteText: d.Value(data['note_text'] as String),
              alertType: d.Value(data['alert_type'] as String),
              alertUntil: d.Value(data['alert_until'] as String?),
              isActive: d.Value((data['is_active'] as num).toInt()),
              serverId: d.Value(sid),
              createdAt: d.Value((data['created_at_ts'] as num).toInt()),
              updatedAt: d.Value((data['updated_at_ts'] as num).toInt()),
              lastModified: d.Value(lastModified),
              version: d.Value((data['version'] as num).toInt()),
              origin: d.Value(data['origin'] as String),
            ),
            originIsServer: true,
          );
        }
        break;
      case 'employees':
        if (localUuid == null) return;
        final local = await (db.select(db.employees)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (deletedAtTs != null) {
          if (local != null) await employeesDao.softDelete(local.id, originIsServer: true);
          return;
        }
        if (local != null) {
          if (lastModified >= local.lastModified) {
            await employeesDao.updateById(
              local.id,
              EmployeesCompanion(
                name: data['name'] != null ? d.Value(data['name']) : const d.Value.absent(),
                basicSalary: data['basic_salary'] != null ? d.Value((data['basic_salary'] as num).toDouble()) : const d.Value.absent(),
                position: data['position'] != null ? d.Value(data['position']) : const d.Value.absent(),
                phone: data['phone'] != null ? d.Value(data['phone']) : const d.Value.absent(),
                hireDate: data['hire_date'] != null ? d.Value(data['hire_date']) : const d.Value.absent(),
                status: data['status'] != null ? d.Value(data['status']) : const d.Value.absent(),
                serverId: d.Value(sid),
                lastModified: d.Value(lastModified),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await employeesDao.insertOne(
            EmployeesCompanion(
              localUuid: d.Value(localUuid),
              name: d.Value(data['name'] as String),
              basicSalary: d.Value((data['basic_salary'] as num).toDouble()),
              position: d.Value(data['position'] as String),
              phone: d.Value(data['phone'] as String),
              hireDate: d.Value(data['hire_date'] as String),
              status: d.Value(data['status'] as String),
              serverId: d.Value(sid),
              createdAt: d.Value((data['created_at_ts'] as num).toInt()),
              updatedAt: d.Value((data['updated_at_ts'] as num).toInt()),
              lastModified: d.Value(lastModified),
              version: d.Value((data['version'] as num).toInt()),
              origin: d.Value(data['origin'] as String),
            ),
            originIsServer: true,
          );
        }
        break;
      case 'expenses':
        if (localUuid == null) return;
        final local = await (db.select(db.expenses)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (deletedAtTs != null) {
          if (local != null) await expensesDao.softDelete(local.id, originIsServer: true);
          return;
        }
        if (local != null) {
          if (lastModified >= local.lastModified) {
            await expensesDao.updateById(
              local.id,
              ExpensesCompanion(
                expenseType: data['expense_type'] != null ? d.Value(data['expense_type']) : const d.Value.absent(),
                relatedId: d.Value(data['related_id'] as int?),
                description: data['description'] != null ? d.Value(data['description']) : const d.Value.absent(),
                amount: data['amount'] != null ? d.Value((data['amount'] as num).toDouble()) : const d.Value.absent(),
                date: data['date'] != null ? d.Value(data['date']) : const d.Value.absent(),
                serverId: d.Value(sid),
                lastModified: d.Value(lastModified),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await expensesDao.insertOne(
            ExpensesCompanion(
              localUuid: d.Value(localUuid),
              expenseType: d.Value(data['expense_type'] as String),
              relatedId: d.Value(data['related_id'] as int?),
              description: d.Value(data['description'] as String),
              amount: d.Value((data['amount'] as num).toDouble()),
              date: d.Value(data['date'] as String),
              serverId: d.Value(sid),
              createdAt: d.Value((data['created_at_ts'] as num).toInt()),
              updatedAt: d.Value((data['updated_at_ts'] as num).toInt()),
              lastModified: d.Value(lastModified),
              version: d.Value((data['version'] as num).toInt()),
              origin: d.Value(data['origin'] as String),
            ),
            originIsServer: true,
          );
        }
        break;
      case 'cash_transactions':
        if (localUuid == null) return;
        final local = await (db.select(db.cashTransactions)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        if (deletedAtTs != null) {
          if (local != null) await cashDao.softDelete(local.id, originIsServer: true);
          return;
        }
        if (local != null) {
          if (lastModified >= local.lastModified) {
            await cashDao.updateById(
              local.id,
              CashTransactionsCompanion(
                registerId: d.Value(data['register_id'] as int?),
                transactionType: data['transaction_type'] != null ? d.Value(data['transaction_type']) : const d.Value.absent(),
                amount: data['amount'] != null ? d.Value((data['amount'] as num).toDouble()) : const d.Value.absent(),
                referenceType: d.Value(data['reference_type'] as String?),
                referenceId: d.Value(data['reference_id'] as int?),
                description: d.Value(data['description'] as String?),
                transactionTime: data['transaction_time'] != null ? d.Value(data['transaction_time']) : const d.Value.absent(),
                serverId: d.Value(sid),
                lastModified: d.Value(lastModified),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await cashDao.insertOne(
            CashTransactionsCompanion(
              localUuid: d.Value(localUuid),
              registerId: d.Value(data['register_id'] as int?),
              transactionType: d.Value(data['transaction_type'] as String),
              amount: d.Value((data['amount'] as num).toDouble()),
              referenceType: d.Value(data['reference_type'] as String?),
              referenceId: d.Value(data['reference_id'] as int?),
              description: d.Value(data['description'] as String?),
              transactionTime: d.Value(data['transaction_time'] as String),
              serverId: d.Value(sid),
              createdAt: d.Value((data['created_at_ts'] as num).toInt()),
              updatedAt: d.Value((data['updated_at_ts'] as num).toInt()),
              lastModified: d.Value(lastModified),
              version: d.Value((data['version'] as num).toInt()),
              origin: d.Value(data['origin'] as String),
            ),
            originIsServer: true,
          );
        }
        break;
      case 'payments':
        if (localUuid == null) return;
        final local = await (db.select(db.payments)..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        final bookingLocalUuid = data['booking_local_uuid'] as String?;
        final cashTrxLocalUuid = data['cash_transaction_local_uuid'] as String?;
        int? bookingLocalId;
        int? cashLocalId;
        if (bookingLocalUuid != null) {
          final b = await (db.select(db.bookings)..where((t) => t.localUuid.equals(bookingLocalUuid))).getSingleOrNull();
          bookingLocalId = b?.id;
        }
        if (cashTrxLocalUuid != null) {
          final c = await (db.select(db.cashTransactions)..where((t) => t.localUuid.equals(cashTrxLocalUuid))).getSingleOrNull();
          cashLocalId = c?.id;
        }
        if (deletedAtTs != null) {
          if (local != null) await paymentsDao.softDelete(local.id, originIsServer: true);
          return;
        }
        if (local != null) {
          if (lastModified >= local.lastModified) {
            await paymentsDao.updateById(
              local.id,
              PaymentsCompanion(
                serverPaymentId: d.Value(data['server_payment_id'] as int?),
                bookingLocalId: bookingLocalId != null ? d.Value(bookingLocalId) : const d.Value.absent(),
                serverBookingId: d.Value(data['server_booking_id'] as int?),
                roomNumber: d.Value(data['room_number'] as String?),
                amount: data['amount'] != null ? d.Value((data['amount'] as num).toDouble()) : const d.Value.absent(),
                paymentDate: data['payment_date'] != null ? d.Value(data['payment_date']) : const d.Value.absent(),
                notes: d.Value(data['notes'] as String?),
                paymentMethod: data['payment_method'] != null ? d.Value(data['payment_method']) : const d.Value.absent(),
                revenueType: data['revenue_type'] != null ? d.Value(data['revenue_type']) : const d.Value.absent(),
                cashTransactionLocalId: cashLocalId != null ? d.Value(cashLocalId) : const d.Value.absent(),
                cashTransactionServerId: d.Value(data['cash_transaction_server_id'] as int?),
                serverId: d.Value(sid),
                lastModified: d.Value(lastModified),
                origin: const d.Value('server'),
              ),
              originIsServer: true,
            );
          }
        } else {
          await paymentsDao.insertOne(
            PaymentsCompanion(
              localUuid: d.Value(localUuid),
              serverPaymentId: d.Value(data['server_payment_id'] as int?),
              bookingLocalId: d.Value(bookingLocalId ?? 0),
              serverBookingId: d.Value(data['server_booking_id'] as int?),
              roomNumber: d.Value(data['room_number'] as String?),
              amount: d.Value((data['amount'] as num).toDouble()),
              paymentDate: d.Value(data['payment_date'] as String),
              notes: d.Value(data['notes'] as String?),
              paymentMethod: d.Value(data['payment_method'] as String),
              revenueType: d.Value(data['revenue_type'] as String),
              cashTransactionLocalId: d.Value(cashLocalId ?? 0),
              cashTransactionServerId: d.Value(data['cash_transaction_server_id'] as int?),
              serverId: d.Value(sid),
              createdAt: d.Value((data['created_at_ts'] as num).toInt()),
              updatedAt: d.Value((data['updated_at_ts'] as num).toInt()),
              lastModified: d.Value(lastModified),
              version: d.Value((data['version'] as num).toInt()),
              origin: d.Value(data['origin'] as String),
            ),
            originIsServer: true,
          );
        }
        break;
    }
  }

  String _getCollectionName(String entity) {
    switch (entity) {
      case 'rooms':
        return 'rooms';
      case 'bookings':
        return 'bookings';
      case 'booking_notes':
        return 'booking_notes';
      case 'employees':
        return 'employees';
      case 'expenses':
        return 'expenses';
      case 'cash_transactions':
        return 'cash_transactions';
      case 'payments':
        return 'payments';
      default:
        return entity;
    }
  }

  void dispose() {
    _status.close();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref.read(databaseProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) => ref.read(syncServiceProvider).statusStream);
