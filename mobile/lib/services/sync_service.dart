import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as d;
import 'api_service.dart';
import 'local_db.dart';

class SyncService {
  SyncService(this.db);
  final AppDatabase db;
  final _uuid = const Uuid();

  Future<void> queueChange({
    required String entity,
    required String op,
    required String localUuid,
    int? serverId,
    required Map<String, dynamic> data,
  }) async {
    await db.into(db.outbox).insert(OutboxCompanion(
      entity: d.Value(entity),
      op: d.Value(op),
      localUuid: d.Value(localUuid),
      serverId: d.Value(serverId),
      dataJson: d.Value(jsonEncode(data)),
      clientTs: d.Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    ));
  }

  Future<void> runSync() async {
    await _push();
    await _pull();
  }

  Future<void> _push() async {
    final items = await (db.select(db.outbox)
          ..orderBy([(t) => d.OrderingTerm(expression: t.id, mode: d.OrderingMode.asc)])
          ..limit(50))
        .get();
    if (items.isEmpty) return;

    final payload = items
        .map((e) => {
              'entity': e.entity,
              'op': e.op,
              'uuid': e.localUuid,
              'server_id': e.serverId,
              'data': jsonDecode(e.dataJson),
              'client_ts': e.clientTs,
            })
        .toList();

    final res = await ApiService.I.syncPush(payload);
    if (res['success'] == true) {
      final results = List<Map<String, dynamic>>.from(res['data']['results']);
      // handle mapping
      for (final r in results) {
        final uuid = r['uuid'] as String?;
        final ok = r['success'] == true;
        final sid = r['server_id'];
        if (uuid == null) continue;
        final item = items.firstWhere((i) => i.localUuid == uuid, orElse: () => throw Exception('uuid not found'));
        if (ok) {
          // TODO: update local row with serverId if necessary
          await (db.delete(db.outbox)..where((t) => t.id.equals(item.id))).go();
        } else if (r['conflict'] == true) {
          // mark conflict and drop for now
          await (db.delete(db.outbox)..where((t) => t.id.equals(item.id))).go();
        } else {
          // increment attempts
          await (db.update(db.outbox)..where((t) => t.id.equals(item.id))).write(
            OutboxCompanion(attempts: d.Value(item.attempts + 1), lastError: d.Value(r['error']?.toString() ?? 'error')),
          );
        }
      }
    }
  }

  Future<void> _pull() async {
    final lastSince = int.tryParse((await db.getKv('last_server_ts')) ?? '0') ?? 0;
    final res = await ApiService.I.syncPull(lastSince);
    if (res['success'] == true) {
      final serverTime = res['data']['server_time'] as int? ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final items = List<Map<String, dynamic>>.from(res['data']['data']);
      for (final it in items) {
        final entity = it['entity'] as String;
        final op = it['op'] as String;
        final data = Map<String, dynamic>.from(it['data']);
        await _applyServerChange(entity, op, data);
      }
      await db.setKv('last_server_ts', '$serverTime');
    }
  }

  Future<void> _applyServerChange(String entity, String op, Map<String, dynamic> data) async {
    switch (entity) {
      case 'rooms':
        await _applyGeneric(data, db.rooms, (c) => RoomsCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: const d.Value(null),
              lastModified: d.Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              roomNumber: d.Value(data['room_number'] as String),
              type: d.Value(data['type'] as String),
              price: d.Value((data['price'] is num) ? (data['price'] as num).toDouble() : double.tryParse(data['price'].toString()) ?? 0),
              status: d.Value(data['status'] as String),
            ));
        break;
      case 'bookings':
        await _applyGeneric(data, db.bookings, (c) => BookingsCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: d.Value((data['booking_id'] as num?)?.toInt()),
              lastModified: d.Value(_ts(data['updated_at'] ?? data['created_at'])),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              bookingId: d.Value((data['booking_id'] as num?)?.toInt()),
              guestName: d.Value((data['guest_name'] ?? '') as String),
              guestPhone: d.Value((data['guest_phone'] ?? '') as String),
              guestIdType: d.Value((data['guest_id_type'] ?? '') as String),
              guestIdNumber: d.Value((data['guest_id_number'] ?? '') as String),
              roomNumber: d.Value((data['room_number'] ?? '') as String),
              checkinDate: d.Value(data['checkin_date'] as String),
              checkoutDate: d.Value(data['checkout_date'] as String?),
              status: d.Value((data['status'] ?? 'محجوزة') as String),
              notes: d.Value(data['notes'] as String?),
              expectedNights: d.Value((data['expected_nights'] as num?)?.toInt()),
              calculatedNights: d.Value((data['calculated_nights'] as num?)?.toInt()),
            ));
        break;
      case 'booking_notes':
        await _applyGeneric(data, db.bookingNotes, (c) => BookingNotesCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: d.Value((data['note_id'] as num?)?.toInt()),
              lastModified: d.Value(_ts(data['updated_at'] ?? data['created_at'])),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              noteId: d.Value((data['note_id'] as num?)?.toInt()),
              bookingId: d.Value((data['booking_id'] as num?)!.toInt()),
              noteText: d.Value((data['note_text'] ?? '') as String),
              alertType: d.Value((data['alert_type'] ?? '') as String),
              alertUntil: d.Value(data['alert_until'] as String?),
              isActive: d.Value(((data['is_active'] as num?) ?? 1).toInt()),
            ));
        break;
      case 'employees':
        await _applyGeneric(data, db.employees, (c) => EmployeesCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: d.Value((data['id'] as num?)?.toInt()),
              lastModified: d.Value(_ts(data['updated_at'] ?? data['created_at'])),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              employeeId: d.Value((data['id'] as num?)?.toInt()),
              name: d.Value((data['name'] ?? '') as String),
              basicSalary: d.Value((data['basic_salary'] is num) ? (data['basic_salary'] as num).toDouble() : double.tryParse(data['basic_salary'].toString()) ?? 0),
              status: d.Value((data['status'] ?? 'active') as String),
            ));
        break;
      case 'expenses':
        await _applyGeneric(data, db.expenses, (c) => ExpensesCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: d.Value((data['id'] as num?)?.toInt()),
              lastModified: d.Value(_ts(data['updated_at'] ?? data['created_at'])),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              expenseId: d.Value((data['id'] as num?)?.toInt()),
              expenseType: d.Value((data['expense_type'] ?? '') as String),
              relatedId: d.Value((data['related_id'] as num?)?.toInt()),
              description: d.Value((data['description'] ?? '') as String),
              amount: d.Value((data['amount'] is num) ? (data['amount'] as num).toDouble() : double.tryParse(data['amount'].toString()) ?? 0),
              date: d.Value((data['date'] ?? '') as String),
            ));
        break;
      case 'cash_transactions':
        await _applyGeneric(data, db.cashTransactions, (c) => CashTransactionsCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: d.Value((data['id'] as num?)?.toInt()),
              lastModified: d.Value(_ts(data['updated_at'] ?? data['created_at'])),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              cashId: d.Value((data['id'] as num?)?.toInt()),
              registerId: d.Value((data['register_id'] as num?)!.toInt()),
              transactionType: d.Value((data['transaction_type'] ?? '') as String),
              amount: d.Value((data['amount'] is num) ? (data['amount'] as num).toDouble() : double.tryParse(data['amount'].toString()) ?? 0),
              referenceType: d.Value((data['reference_type'] ?? '') as String),
              referenceId: d.Value((data['reference_id'] as num?)!.toInt()),
              description: d.Value(data['description'] as String?),
              transactionTime: d.Value((data['transaction_time'] ?? '') as String),
            ));
        break;
      case 'suppliers':
        await _applyGeneric(data, db.suppliers, (c) => SuppliersCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: d.Value((data['id'] as num?)?.toInt()),
              lastModified: d.Value(_ts(data['updated_at'] ?? data['created_at'])),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              supplierId: d.Value((data['id'] as num?)?.toInt()),
              name: d.Value((data['name'] ?? '') as String),
            ));
        break;
      case 'users':
        await _applyGeneric(data, db.users, (c) => UsersCompanion(
              localUuid: d.Value(_uuid.v4()),
              serverId: d.Value((data['user_id'] as num?)?.toInt()),
              lastModified: d.Value(_ts(data['updated_at'] ?? data['created_at'])),
              deletedAt: d.Value(data['deleted_at'] == null ? null : _ts(data['deleted_at'])),
              version: const d.Value(1),
              origin: const d.Value('server'),
              userId: d.Value((data['user_id'] as num?)?.toInt()),
              username: d.Value((data['username'] ?? '') as String),
              fullName: d.Value((data['full_name'] ?? '') as String),
              email: d.Value((data['email'] ?? '') as String),
              phone: d.Value((data['phone'] ?? '') as String),
              userType: d.Value((data['user_type'] ?? '') as String),
              isActive: d.Value(((data['is_active'] as num?) ?? 1).toInt()),
            ));
        break;
    }
  }

  int _ts(dynamic s) {
    if (s == null) return 0;
    if (s is int) return s;
    // expect server returns timestamp as string datetime, convert to seconds
    try {
      return DateTime.parse(s.toString()).millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
  }

  Future<void> _applyGeneric<T extends d.Table, C>(
      Map<String, dynamic> data, T table, C Function(T) buildCompanion) async {
    final comp = buildCompanion(table);
    await (db.into(table as dynamic)).insert(comp as d.Insertable, mode: d.InsertMode.insertOrReplace);
  }
}
