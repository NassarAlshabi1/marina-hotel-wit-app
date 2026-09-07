// test/unit/cloudflare_push_contract_test.dart
//
// ✅ حارس عقد الدفع إلى Cloudflare D1 — AUDIT 2026-09-05
// (FIELD_TYPE_MATCH_AUDIT): «إضافة اختبار end-to-end يحرس العقد».
//
// يشغّل المنتجين الحقيقيين (DAOs/Repositories/Services) على قاعدة
// Drift في الذاكرة، ثم يمرّر كل صف outbox عبر buildPushOperation
// (نفس نقطة الدفع الوحيدة في _pushBatch) ويثبت لكل كيان:
//   1. الهوية: data.local_uuid نص غير فارغ (requireEntityId).
//   2. الصياغة: كل المفاتيح snake_case.
//   3. الأعمدة: كل مفتاح عموداً فعلياً في جدول D1 (worker/schema.sql)
//      — الـ worker يسقط المفاتيح الغريبة بصمت (database.ts:346).
//
// القائمة الملتحمة تغطي كل أنماط بناء الحمولات: adapter-based camel
// (bookings/payments/expenses/employees)، خرائط يدوية snake (rooms/
// debts/cash_transactions/shift_notes/booking_notes)، خرائط يدوية
// camel (guest_infos/inventory/salary_withdrawals/blacklist/
// payment_voids/price_adjustments/audit_logs)، وعقد app_users الثابت.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/auth_local_store.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';
import 'package:marina_hotel_mobile/services/daos/bookings_dao.dart';
import 'package:marina_hotel_mobile/services/daos/booking_notes_dao.dart';
import 'package:marina_hotel_mobile/services/daos/cash_transactions_dao.dart';
import 'package:marina_hotel_mobile/services/daos/debts_dao.dart';
import 'package:marina_hotel_mobile/services/daos/employees_dao.dart';
import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/payments_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/daos/shift_notes_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_void_service.dart';
import 'package:marina_hotel_mobile/services/price_adjustment_service.dart';
import 'package:marina_hotel_mobile/services/repositories/blacklist_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/guest_infos_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/inventory_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/sync/payload_normalizer.dart';

// الأعمدة المسموحة إضافةً لأعمدة جدول D1: عمود محلي بلا مرآة D1
// (مستبعد عمداً من العقد السحابي — يسقطه الـ worker بلا أثر).
const _droppableKeys = {'sync_timestamp'};

final RegExp _snakeKey = RegExp(r'^[a-z][a-z0-9_]*$');

Map<String, Set<String>>? _schemaColumns;

Map<String, Set<String>> _loadSchemaColumns() {
  if (_schemaColumns != null) return _schemaColumns!;
  final candidates = [
    File('../worker/schema.sql'),
    File('worker/schema.sql'),
    File('../../worker/schema.sql'),
  ];
  final file = candidates.firstWhere(
    (f) => f.existsSync(),
    orElse: () => throw StateError(
      'worker/schema.sql غير موجود — اختبار عقد الأعمدة يحتاجه',
    ),
  );
  final tables = <String, Set<String>>{};
  String? current;
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    final create = RegExp(
      r'^CREATE TABLE (IF NOT EXISTS )?(\w+) \($',
    ).firstMatch(line);
    if (create != null) {
      current = create.group(2)!;
      tables.putIfAbsent(current, () => <String>{});
      continue;
    }
    if (current == null) continue;
    if (line == ');' || line.startsWith(')')) {
      current = null;
      continue;
    }
    if (line.isEmpty || line.startsWith('--')) continue;
    final col = RegExp(r'^"?\w+"? \w').firstMatch(line);
    if (col == null) continue; // UNIQUE(...), FOREIGN KEY, PRIMARY KEY…
    final name = line.split(' ').first.replaceAll('"', '');
    if (['UNIQUE', 'PRIMARY', 'FOREIGN', 'CHECK', 'CONSTRAINT'].contains(
      name,
    )) {
      continue;
    }
    tables[current]!.add(name);
  }
  return _schemaColumns = tables;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outboxDao;
  late RoomsDao roomsDao;
  late BookingsDao bookingsDao;
  late BookingNotesDao bookingNotesDao;
  late PaymentsDao paymentsDao;
  late ExpensesDao expensesDao;
  late EmployeesDao employeesDao;
  late DebtsDao debtsDao;
  late CashTransactionsDao cashTransactionsDao;
  late ShiftNotesDao shiftNotesDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
    roomsDao = RoomsDao(db, outboxDao);
    bookingsDao = BookingsDao(db, outboxDao);
    bookingNotesDao = BookingNotesDao(db, outboxDao);
    paymentsDao = PaymentsDao(db, outboxDao);
    expensesDao = ExpensesDao(db, outboxDao);
    employeesDao = EmployeesDao(db, outboxDao);
    debtsDao = DebtsDao(db, outboxDao);
    cashTransactionsDao = CashTransactionsDao(db, outboxDao);
    shiftNotesDao = ShiftNotesDao(db, outboxDao);
    _schemaColumns = null;
  });

  tearDown(() async {
    await db.close();
  });

  /// يفرغ outbox — لفصل عملية عن أخرى عند اختبار القبور الصافية
  Future<void> clearOutbox() async {
    await (outboxDao.delete(outboxDao.outbox)).go();
  }

  /// يمرر كل صفوف outbox الحالية عبر buildPushOperation ويطابق العقد.
  Future<List<Map<String, dynamic>>> pushedOperations() async {
    final rows = await (outboxDao.select(
      outboxDao.outbox,
    )..orderBy([(t) => d.OrderingTerm.asc(t.id)])).get();
    expect(rows, isNotEmpty, reason: 'المنتج لم يكتب في outbox');
    final schema = _loadSchemaColumns();
    final ops = <Map<String, dynamic>>[];
    for (final row in rows) {
      final op = await buildPushOperation(
        row,
        resolveRowVectorClock: (_, __) async => null,
      );
      final entity = op['entity'] as String;
      final table = CloudflareConfig.tableNameFor(entity);
      expect(table, isNotNull, reason: 'كيان بلا جدول D1: $entity');
      final data = op['data'] as Map<String, dynamic>;
      final allowed = schema[table]!.union(_droppableKeys).union({
        'local_uuid',
        'id',
      });

      // 1) الهوية
      expect(
        data['local_uuid'],
        allOf(isA<String>(), isNotEmpty),
        reason: '$entity: requireEntityId يحتاج local_uuid نصاً',
      );
      // 2) الصياغة snake_case
      for (final key in data.keys) {
        expect(
          _snakeKey.hasMatch(key),
          isTrue,
          reason: '$entity: مفتاح camelCase كان سيُسقط صمتاً: $key',
        );
      }
      // 3) أعمدة D1 الفعلية
      for (final key in data.keys) {
        expect(
          allowed.contains(key),
          isTrue,
          reason:
              '$entity/$table: العمود $key غير موجود في D1 — '
              'كان سيُسقط صمتاً (فقدان بيانات)',
        );
      }
      ops.add(op);
    }
    return ops;
  }

  Future<int> seedBooking() async {
    final now = DateTime.now();
    // FK: bookings.room_number → rooms.room_number
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            roomNumber: '101',
            type: 'standard',
            price: 100,
            status: 'شاغرة',
            localUuid: 'room-contract-101',
            createdAt: 1720000000,
            updatedAt: 1720000000,
            lastModified: 1720000000,
          ),
        );
    return bookingsDao.insertOne(
      BookingsCompanion(
        roomNumber: const d.Value('101'),
        guestName: const d.Value('ضيف العقد'),
        guestPhone: const d.Value('0500000000'),
        guestIdType: const d.Value('هوية'),
        guestNationality: const d.Value('يمني'),
        checkinDate: d.Value(now.toIso8601String()),
        status: const d.Value('checked_in'),
        discountType: const d.Value('none'),
        needsCheckoutReview: const d.Value(false),
        remainingBalanceCached: const d.Value(0),
      ),
    );
  }

  group('عقد الدفع لكل نمط بناء حمولة', () {
    test('rooms — DAO snake + قبورة softDelete', () async {
      final roomUuid = await roomsDao.insertOne(
        RoomsCompanion(
          roomNumber: const d.Value('201'),
          type: const d.Value('standard'),
          price: const d.Value(100.0),
          status: const d.Value('شاغرة'),
        ),
      );
      expect(roomUuid, '201');
      // 1) إنشاء — DAO snake
      final createOps = await pushedOperations();
      expect(createOps.length, 1);
      expect(createOps.single['operation'], 'create');
      expect(
        (createOps.single['data'] as Map)['room_number'],
        '201',
      );
      // 2) قبورة صافية — softDelete يحمل deleted_at وإلا لن يرى الجهاز
      //    الآخر الحذف أبداً (كانت الحمولة {room_number} فقط)
      await clearOutbox();
      await roomsDao.softDelete('201');
      final tombOps = await pushedOperations();
      expect(tombOps.single['operation'], 'update');
      final tomb = tombOps.single['data'] as Map<String, dynamic>;
      expect(
        tomb['deleted_at'],
        isNotNull,
        reason: 'softDelete بلا deleted_at = الحذف لا يصل للأجهزة الأخرى',
      );
    });

    test('bookings — adapter camelCase (كان مكسوراً)', () async {
      final bookingId = await seedBooking();
      expect(bookingId, greaterThan(0));
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'bookings').single['data']
              as Map<String, dynamic>;
      expect(data['guest_name'], 'ضيف العقد');
      expect(data['room_number'], '101');
      expect(data.containsKey('guestName'), isFalse);
    });

    test(
      'booking_notes — إنشاء + قبرة حذف (كانت برمي validation_error)',
      () async {
        final bookingId = await seedBooking();
        final noteId = await bookingNotesDao.insertOne(
          BookingNotesCompanion(
            bookingId: d.Value(bookingId),
            noteText: const d.Value('ملاحظة العقد'),
            alertType: const d.Value('info'),
          ),
        );
        // إنشاء منفصل ثم قبورة صافية (الاندماج يدمج create+update لنفس uuid)
        final afterCreate = await pushedOperations();
        expect(
          afterCreate.where((o) => o['entity'] == 'booking_notes').length,
          1,
        );
        await clearOutbox();
        await bookingNotesDao.softDelete(noteId);
        final ops = await pushedOperations();
        final tomb = ops.single['data'] as Map<String, dynamic>;
        expect(ops.single['operation'], 'update');
        expect(
          tomb['deleted_at'],
          isNotNull,
          reason: 'قبرة الحذف كانت {id: رقم} — requireEntityId يرميها',
        );
      },
    );

    test('payments — adapter camelCase (كان مكسوراً)', () async {
      final bookingId = await seedBooking();
      await paymentsDao.insertOne(
        PaymentsCompanion(
          bookingLocalId: d.Value(bookingId),
          amount: const d.Value(500.0),
          paymentDate: d.Value(DateTime.now().toIso8601String()),
          paymentMethod: const d.Value('cash'),
          revenueType: const d.Value('room'),
          isPendingBalance: const d.Value(false),
        ),
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'payments').single['data']
              as Map<String, dynamic>;
      expect(data['amount'], 500.0);
      expect(data['payment_method'], 'cash');
      expect(data.containsKey('paymentMethod'), isFalse);
    });

    test('expenses — adapter camelCase', () async {
      await expensesDao.insertOne(
        ExpensesCompanion(
          expenseType: const d.Value('صيانة'),
          description: const d.Value('اصلاح مكيف'),
          amount: const d.Value(120.0),
          date: d.Value(DateTime.now().toIso8601String()),
          isAutoGenerated: const d.Value(false),
        ),
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'expenses').single['data']
              as Map<String, dynamic>;
      expect(data['expense_type'], 'صيانة');
      expect(data['amount'], 120.0);
    });

    test('employees — adapter camelCase', () async {
      await employeesDao.insertOne(
        EmployeesCompanion(
          name: const d.Value('موظف العقد'),
          basicSalary: const d.Value(3000.0),
          status: const d.Value('active'),
        ),
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'employees').single['data']
              as Map<String, dynamic>;
      expect(data['basic_salary'], 3000.0);
      expect(data.containsKey('basicSalary'), isFalse);
    });

    test('debts — DAO snake', () async {
      final bookingId = await seedBooking();
      final nowIso = DateTime.now().toIso8601String();
      await debtsDao.insertOne(
        DebtsCompanion(
          bookingLocalId: d.Value(bookingId),
          guestName: const d.Value('مدين العقد'),
          checkinDate: d.Value(nowIso),
          checkoutDate: d.Value(nowIso),
          totalAmount: const d.Value(1000.0),
          paidAmount: const d.Value(400.0),
          remainingAmount: const d.Value(600.0),
          paymentDate: d.Value(nowIso),
          isFromAutoFix: const d.Value(false),
          settlementConfirmed: const d.Value(false),
        ),
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'debts').single['data']
              as Map<String, dynamic>;
      expect(data['remaining_amount'], 600.0);
    });

    test('cash_transactions — DAO snake', () async {
      await cashTransactionsDao.insertOne(
        CashTransactionsCompanion(
          transactionType: const d.Value('income'),
          amount: const d.Value(300.0),
          transactionTime: d.Value(DateTime.now().toIso8601String()),
        ),
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'cash_transactions').single['data']
              as Map<String, dynamic>;
      expect(data['transaction_type'], 'income');
    });

    test('shift_notes — DAO snake', () async {
      await shiftNotesDao.addNote(
        title: 'ملاحظة وردية',
        content: 'تفاصيل',
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'shift_notes').single['data']
              as Map<String, dynamic>;
      expect(data['title'], 'ملاحظة وردية');
    });

    test('guest_infos — خرائط يدوية camelCase (كانت مكسورة)', () async {
      await GuestInfosRepository(db).create(
        roomNumber: '101',
        guestName: 'نزيل العقد',
        nationality: 'يمني',
        idNumber: '12345',
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'guest_infos').single['data']
              as Map<String, dynamic>;
      expect(data['guest_name'], 'نزيل العقد');
      expect(data['id_number'], '12345');
      expect(data.containsKey('guestName'), isFalse);
    });

    test(
      'inventory_items + inventory_transactions — camelCase (كانت مكسورة)',
      () async {
        await InventoryRepository(db).createItem(
          name: 'منشفة',
          unit: 'قطعة',
          initialQuantity: 10,
          minimumQuantity: 2,
        );
        final ops = await pushedOperations();
        final itemOps = ops
            .where((o) => o['entity'] == 'inventory_items')
            .toList();
        expect(itemOps, isNotEmpty);
        final data = itemOps.first['data'] as Map<String, dynamic>;
        expect(data['name'], 'منشفة');
        expect(data['minimum_quantity'], 2);
        expect(data.containsKey('minimumQuantity'), isFalse);
        final txOps = ops
            .where((o) => o['entity'] == 'inventory_transactions')
            .toList();
        expect(txOps, isNotEmpty, reason: 'إنشاء صنف يولّد حركة رصيد افتتاحية');
      },
    );

    test('salary_withdrawals — خرائط يدوية camelCase (كانت مكسورة)', () async {
      await employeesDao.insertOne(
        EmployeesCompanion(
          name: const d.Value('موظف السحب'),
          basicSalary: const d.Value(2000.0),
          status: const d.Value('active'),
        ),
      );
      await SalaryWithdrawalsRepository(db).createFromExpense(
        expenseId: 0,
        employeeId: 1,
        reason: 'سلفة',
        amount: 100.0,
        date: DateTime.now().toIso8601String(),
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'salary_withdrawals').single['data']
              as Map<String, dynamic>;
      expect(data['amount'], 100.0);
      expect(data['employee_id'], 1);
      expect(data.containsKey('employeeId'), isFalse);
    });

    test('blacklist — تجسيد افتراضي من shift_notes الموسومة', () async {
      await BlacklistRepository(db).addEntry(
        name: 'محظور العقد',
        nationality: 'يمني',
        reason: 'تجربة',
      );
      final ops = await pushedOperations();
      final data =
          ops.where((o) => o['entity'] == 'blacklist').single['data']
              as Map<String, dynamic>;
      expect(data['name'], 'محظور العقد');
      expect(data['reported_by'], 'police');
      expect(data['active'], anyOf(0, 1));
      expect(data.containsKey('nationalId'), isFalse);
    });

    test('price_adjustments + audit_logs — خدمة تعديل الأسعار', () async {
      await roomsDao.insertOne(
        RoomsCompanion(
          roomNumber: const d.Value('301'),
          type: const d.Value('standard'),
          price: const d.Value(100.0),
          status: const d.Value('شاغرة'),
        ),
      );
      // حجز نشط ليولد سجل تدقيق (auditEntries تتطلب ليلًا متأثرة)
      final now = DateTime.now();
      final bookingId = await bookingsDao.insertOne(
        BookingsCompanion(
          roomNumber: const d.Value('301'),
          guestName: const d.Value('ضيف سعر'),
          guestPhone: const d.Value('0500000000'),
          guestIdType: const d.Value('هوية'),
          guestNationality: const d.Value('يمني'),
          checkinDate: d.Value(
            now.subtract(const Duration(days: 1)).toIso8601String(),
          ),
          checkoutDate: d.Value(
            now.add(const Duration(days: 1)).toIso8601String(),
          ),
          status: const d.Value('نشط'),
          discountType: const d.Value('none'),
          needsCheckoutReview: const d.Value(false),
          remainingBalanceCached: const d.Value(0),
        ),
      );
      // ليالٍ حالية قبل تغيير السعر — شرط توليد سجلات التدقيق
      // (nightsAffected > 0 قبل إعادة الحساب) — مفاتيح أيام فريدة
      for (final offset in [0, 1]) {
        final dayKey = now
            .add(Duration(days: offset))
            .toIso8601String()
            .substring(0, 10);
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion.insert(
                bookingLocalId: bookingId,
                hotelDayKey: dayKey,
                nightStart: now.toIso8601String(),
                nightEnd: now.add(const Duration(days: 1)).toIso8601String(),
                localUuid: 'night-$offset-uuid',
                createdAt: 1720000000,
                updatedAt: 1720000000,
                lastModified: 1720000000,
              ),
            );
      }
      await PriceAdjustmentService(db).applyRoomPriceChange(
        roomNumber: '301',
        oldPrice: 100,
        newPrice: 150.75,
        appliedBy: 'tester',
        reason: 'عقد الدفع',
      );
      final ops = await pushedOperations();
      final adj =
          ops.where((o) => o['entity'] == 'price_adjustments').single['data']
              as Map<String, dynamic>;
      expect(adj['previous_value'], 100);
      expect(adj['new_value'], 150.75);
      expect(adj.containsKey('previousValue'), isFalse);
      // audit_logs: الكاتب المحلي الوحيد أصبح يكتب في outbox أيضاً
      final audit =
          ops.where((o) => o['entity'] == 'audit_logs').single['data']
              as Map<String, dynamic>;
      expect(audit['operation_type'], 'price_adjustment_applied');
    });

    test('payment_voids + payments update — خدمة الإبطال', () async {
      final bookingId = await seedBooking();
      const paymentUuid = 'pay-uuid-contract';
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              bookingLocalId: d.Value(bookingId),
              amount: 700,
              paymentDate: DateTime.now().toIso8601String(),
              paymentMethod: 'cash',
              revenueType: 'room',
              isPendingBalance: const d.Value(false),
              localUuid: paymentUuid,
              createdAt: 1720000000,
              updatedAt: 1720000000,
              lastModified: 1720000000,
            ),
          );
      await PaymentVoidService(db).voidPayment(
        paymentUuid: paymentUuid,
        voidReason: 'عقد الدفع',
        voidedBy: 'tester',
      );
      final ops = await pushedOperations();
      final voids =
          ops.where((o) => o['entity'] == 'payment_voids').single['data']
              as Map<String, dynamic>;
      expect(voids['original_payment_uuid'], paymentUuid);
      expect(voids['voided_by'], 'tester');
      expect(voids.containsKey('originalPaymentUuid'), isFalse);
      // الدفعة الأصلية تحمل is_voided=1 عبر outbox أيضاً
      final payOps = ops
          .where((o) => o['entity'] == 'payments')
          .map((o) => o['data'] as Map<String, dynamic>);
      expect(
        payOps.where((p) => p['is_voided'] == 1),
        isNotEmpty,
        reason: 'إبطال الدفعة يجب أن يصل للأجهزة الأخرى',
      );
    });

    test('app_users — العقد المرجعي snake_case يمر كما هو', () async {
      final payload = AuthLocalStore.appUsersSyncPayload(
        localUuid: 'user-contract-1',
        username: 'tester',
        fullName: 'مستخدم العقد',
        active: true,
        now: 1720000000,
        deviceId: 'dev-test',
      );
      await outboxDao.merge(
        entity: 'app_users',
        op: 'create',
        localUuid: 'user-contract-1',
        payload: payload,
        clientTs: 1720000000,
      );
      final ops = await pushedOperations();
      final data = ops.single['data'] as Map<String, dynamic>;
      expect(data['username'], 'tester');
      expect(data['active'], 1);
      expect(data['device_id'], 'dev-test');
    });
  });
}
