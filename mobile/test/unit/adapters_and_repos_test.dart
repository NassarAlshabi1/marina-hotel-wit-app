import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AdapterRegistry adapters;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════
  // Helper: إدراج موظف للاختبار
  // ═══════════════════════════════════════════════════════════════
  Future<int> insertEmployee({
    String uuid = 'emp-1',
    String name = 'أحمد',
  }) async {
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            localUuid: d.Value(uuid),
            name: d.Value(name),
            position: d.Value('موظف'),
            status: d.Value('active'),
            basicSalary: d.Value(5000.0),
            createdAt: const d.Value(0),
            updatedAt: const d.Value(0),
            lastModified: const d.Value(0),
            createdAtEpoch: const d.Value(0),
            lastModifiedEpoch: const d.Value(0),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );
  }

  // ═══════════════════════════════════════════════════════════════
  // Helper: إدراج غرفة وحجز للاختبار
  // ═══════════════════════════════════════════════════════════════
  Future<int> insertRoomAndBooking({
    String roomUuid = 'room-1',
    String bookingUuid = 'booking-1',
  }) async {
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion(
            localUuid: d.Value(roomUuid),
            roomNumber: const d.Value('101'),
            type: const d.Value('single'),
            price: const d.Value(100.0),
            status: const d.Value('available'),
            createdAt: const d.Value(0),
            updatedAt: const d.Value(0),
            lastModified: const d.Value(0),
            createdAtEpoch: const d.Value(0),
            lastModifiedEpoch: const d.Value(0),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );
    return db
        .into(db.bookings)
        .insert(
          BookingsCompanion(
            localUuid: d.Value(bookingUuid),
            roomNumber: const d.Value('101'),
            guestName: const d.Value('ضيف'),
            guestPhone: const d.Value('123'),
            guestNationality: const d.Value('YEM'),
            checkinDate: const d.Value('2025-06-10'),
            status: const d.Value('active'),
            createdAt: const d.Value(0),
            updatedAt: const d.Value(0),
            lastModified: const d.Value(0),
            createdAtEpoch: const d.Value(0),
            lastModifiedEpoch: const d.Value(0),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );
  }

  // ═══════════════════════════════════════════════════════════════
  // SalaryCyclesAdapter — اختبار دوري كامل
  // ═══════════════════════════════════════════════════════════════
  group('SalaryCyclesAdapter — دوري كامل (appwrite)', () {
    test('resolveRefs يرجع shouldSkip=true عند عدم وجود الموظف', () async {
      final json = {
        'localUuid': 'sc-1',
        'employeeUuid': 'non-existent-uuid',
        'cycleKey': '2025-06',
        'hotelDayStart': '2025-06-01',
        'hotelDayEnd': '2025-06-30',
        'expectedAmount': 5000,
        'status': 'draft',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryCycles.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isTrue);
      expect(refs.skipReason, isNotNull);
      expect(refs.skipReason, contains('لا يمكن العثور'));
      expect(refs.employeeLocalId, isNull);
    });

    test('resolveRefs يرجع shouldSkip=false عند وجود الموظف', () async {
      await insertEmployee();

      final json = {
        'localUuid': 'sc-1',
        'employeeUuid': 'emp-1',
        'cycleKey': '2025-06',
        'hotelDayStart': '2025-06-01',
        'hotelDayEnd': '2025-06-30',
        'expectedAmount': 5000,
        'status': 'draft',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryCycles.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isFalse);
      expect(refs.skipReason, isNull);
      expect(refs.employeeLocalId, isNotNull);
    });

    test('fromJson + toJson دوري كامل (appwrite)', () async {
      await insertEmployee();

      final json = {
        'localUuid': 'sc-1',
        'employeeUuid': 'emp-1',
        'cycleKey': '2025-06',
        'hotelDayStart': '2025-06-01',
        'hotelDayEnd': '2025-06-30',
        'expectedAmount': 5000,
        'actualPaid': 3000,
        'remainingAmount': 2000,
        'status': 'active',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryCycles.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );
      final comp = adapters.salaryCycles.adapter.fromJson(
        json,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.salaryCycles).insert(comp);

      final row = await db.select(db.salaryCycles).getSingle();
      final out = adapters.salaryCycles.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(out['localUuid'], 'sc-1');
      expect(out['cycleKey'], '2025-06');
      expect(out['status'], 'active');
      expect(out['expectedAmount'], 5000);
      expect(out['origin'], 'server'); // appwrite → origin='server'
    });

    test('fromJson + toJson دوري كامل (drive)', () async {
      await insertEmployee();

      final json = {
        'local_uuid': 'sc-2',
        'employee_uuid': 'emp-1',
        'cycle_key': '2025-07',
        'hotel_day_start': '2025-07-01',
        'hotel_day_end': '2025-07-31',
        'expected_amount': 6000,
        'actual_paid': 0,
        'remaining_amount': 6000,
        'status': 'draft',
        'created_at': 100,
        'last_modified': 200,
      };

      final refs = await adapters.salaryCycles.adapter.resolveRefs(
        db,
        json,
        src: Source.drive,
      );
      final comp = adapters.salaryCycles.adapter.fromJson(
        json,
        src: Source.drive,
        refs: refs,
      );
      await db.into(db.salaryCycles).insert(comp);

      final row = await db.select(db.salaryCycles).getSingle();
      final out = adapters.salaryCycles.toJsonForSource(row, src: Source.drive);

      expect(out['local_uuid'], 'sc-2');
      expect(out['cycle_key'], '2025-07');
      expect(out['status'], 'draft');
      expect(out['expected_amount'], 6000);
      expect(out['origin'], 'server'); // drive → origin='server'
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SalaryWithdrawalsAdapter — اختبار دوري كامل
  // ═══════════════════════════════════════════════════════════════
  group('SalaryWithdrawalsAdapter — دوري كامل (appwrite)', () {
    test('resolveRefs يرجع shouldSkip=true عند عدم وجود الموظف', () async {
      final json = {
        'localUuid': 'sw-1',
        'employeeUuid': 'non-existent',
        'amount': 1000,
        'withdrawDate': '2025-06-15',
        'reason': 'exp_5',
        'hotelDayKey': '2025-06-15',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryWithdrawals.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isTrue);
      expect(refs.skipReason, contains('لا يمكن العثور'));
    });

    test('resolveRefs يرجع shouldSkip=false عند وجود الموظف', () async {
      await insertEmployee();

      final json = {
        'localUuid': 'sw-1',
        'employeeUuid': 'emp-1',
        'amount': 1000,
        'withdrawDate': '2025-06-15',
        'reason': 'exp_5',
        'hotelDayKey': '2025-06-15',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryWithdrawals.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isFalse);
      expect(refs.employeeLocalId, isNotNull);
    });

    test(
      'fromJson يتعامل مع الحقول القديمة (date, action, note, expenseId)',
      () async {
        await insertEmployee();

        final json = {
          'localUuid': 'sw-1',
          'employeeUuid': 'emp-1',
          'amount': 1000,
          'date': '2025-06-15',
          'action': 'سحب راتب',
          'note': 'ملاحظة',
          'expenseId': 5,
          'hotelDayKey': '2025-06-15',
          'createdAt': 100,
          'lastModified': 200,
        };

        final refs = await adapters.salaryWithdrawals.adapter.resolveRefs(
          db,
          json,
          src: Source.appwrite,
        );
        final comp = adapters.salaryWithdrawals.adapter.fromJson(
          json,
          src: Source.appwrite,
          refs: refs,
        );
        await db.into(db.salaryWithdrawals).insert(comp);

        final row = await db.select(db.salaryWithdrawals).getSingle();
        expect(row.withdrawDate, '2025-06-15');
        expect(row.withdrawalType, 'سحب راتب');
        expect(row.description, 'ملاحظة');
        expect(row.reason, 'exp_5'); // appwriteExpenseId → 'exp_5'
      },
    );

    test('toJson يستخرج expenseId من reason (exp_XX)', () async {
      await insertEmployee();

      final json = {
        'localUuid': 'sw-1',
        'employeeUuid': 'emp-1',
        'amount': 1000,
        'withdrawDate': '2025-06-15',
        'reason': 'exp_42',
        'hotelDayKey': '2025-06-15',
        'withdrawalType': 'سحب',
        'description': 'test',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryWithdrawals.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );
      final comp = adapters.salaryWithdrawals.adapter.fromJson(
        json,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.salaryWithdrawals).insert(comp);

      final row = await db.select(db.salaryWithdrawals).getSingle();
      final out = adapters.salaryWithdrawals.toJsonForSource(
        row,
        src: Source.appwrite,
      );

      expect(out['expenseId'], 42);
      expect(out['date'], '2025-06-15'); // Appwrite required field
      expect(out['action'], 'سحب'); // Appwrite required field
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // NightsAdapter — اختبار دوري كامل مع shouldSkip
  // ═══════════════════════════════════════════════════════════════
  group('NightsAdapter — دوري كامل مع shouldSkip', () {
    test('resolveRefs يرجع shouldSkip=true عند عدم وجود الحجز', () async {
      final json = {
        'localUuid': 'bn-1',
        'bookingUuidCache': 'non-existent-booking',
        'hotelDayKey': '2025-06-15',
        'nightStart': '2025-06-15T14:01:00',
        'nightEnd': '2025-06-16T14:00:00',
        'nightlyRate': 100,
        'sequence': 1,
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.nights.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isTrue);
      expect(refs.skipReason, contains('لا يمكن العثور على الحجز'));
    });

    test('resolveRefs يرجع shouldSkip=false عند وجود الحجز', () async {
      await insertRoomAndBooking();

      final json = {
        'localUuid': 'bn-1',
        'bookingUuidCache': 'booking-1',
        'hotelDayKey': '2025-06-15',
        'nightStart': '2025-06-15T14:01:00',
        'nightEnd': '2025-06-16T14:00:00',
        'nightlyRate': 100,
        'sequence': 1,
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.nights.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isFalse);
      expect(refs.bookingLocalId, isNotNull);
    });

    test('fromJson + toJson دوري كامل (appwrite)', () async {
      await insertRoomAndBooking();

      final json = {
        'localUuid': 'bn-1',
        'bookingUuidCache': 'booking-1',
        'hotelDayKey': '2025-06-15',
        'nightStart': '2025-06-15T14:01:00',
        'nightEnd': '2025-06-16T14:00:00',
        'nightlyRate': 100,
        'baseRate': 80,
        'adjustment': 20,
        'finalRate': 100,
        'sequence': 1,
        'isProcessedByAutoFix': false,
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.nights.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );
      final comp = adapters.nights.adapter.fromJson(
        json,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.bookingNights).insert(comp);

      final row = await db.select(db.bookingNights).getSingle();
      final out = adapters.nights.toJsonForSource(row, src: Source.appwrite);

      expect(out['localUuid'], 'bn-1');
      expect(out['hotelDayKey'], '2025-06-15');
      expect(out['nightlyRate'], 100);
      expect(out['origin'], 'server');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SalaryPaymentsAdapter — اختبار دوري كامل مع shouldSkip
  // ═══════════════════════════════════════════════════════════════
  group('SalaryPaymentsAdapter — دوري كامل مع shouldSkip', () {
    test('resolveRefs يرجع shouldSkip=true عند عدم وجود الدورة', () async {
      final json = {
        'localUuid': 'sp-1',
        'cycleLocalUuid': 'non-existent-cycle',
        'amount': 5000,
        'hotelDayKey': '2025-06-15',
        'paymentDateIso': '2025-06-15',
        'method': 'cash',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryPayments.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isTrue);
      expect(refs.skipReason, contains('لا يمكن العثور على دورة الراتب'));
    });

    test('resolveRefs يرجع shouldSkip=false عند وجود الدورة', () async {
      final empId = await insertEmployee();
      await db
          .into(db.salaryCycles)
          .insert(
            SalaryCyclesCompanion(
              localUuid: const d.Value('cycle-1'),
              employeeId: d.Value(empId),
              cycleKey: const d.Value('2025-06'),
              hotelDayStart: const d.Value('2025-06-01'),
              hotelDayEnd: const d.Value('2025-06-30'),
              expectedAmount: const d.Value(5000),
              actualPaid: const d.Value(0),
              remainingAmount: const d.Value(5000),
              status: const d.Value('active'),
              createdAt: const d.Value(0),
              updatedAt: const d.Value(0),
              lastModified: const d.Value(0),
              createdAtEpoch: const d.Value(0),
              lastModifiedEpoch: const d.Value(0),
              version: const d.Value(1),
              origin: const d.Value('local'),
              vectorClock: const d.Value('{}'),
            ),
          );

      final json = {
        'localUuid': 'sp-1',
        'cycleLocalUuid': 'cycle-1',
        'amount': 5000,
        'hotelDayKey': '2025-06-15',
        'paymentDateIso': '2025-06-15',
        'method': 'cash',
        'createdAt': 100,
        'lastModified': 200,
      };

      final refs = await adapters.salaryPayments.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      expect(refs.shouldSkip, isFalse);
      expect(refs.salaryCycleLocalId, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // BaseRepository — upsertFromJson مع shouldSkip
  // ═══════════════════════════════════════════════════════════════
  group('BaseRepository — upsertFromJson مع shouldSkip', () {
    test(
      'upsertFromJson يرجع -1 عند shouldSkip=true (موظف غير موجود)',
      () async {
        final json = {
          'localUuid': 'sc-orphan',
          'employeeUuid': 'non-existent-uuid',
          'cycleKey': '2025-06',
          'hotelDayStart': '2025-06-01',
          'hotelDayEnd': '2025-06-30',
          'expectedAmount': 5000,
          'status': 'draft',
          'createdAt': 100,
          'lastModified': 200,
        };

        final result = await adapters.salaryCycles.upsertFromJson(
          json,
          src: Source.appwrite,
        );

        expect(result, -1); // تم التخطي
      },
    );

    test('upsertFromJson ينجح عند وجود الموظف', () async {
      await insertEmployee();

      final json = {
        'localUuid': 'sc-1',
        'employeeUuid': 'emp-1',
        'cycleKey': '2025-06',
        'hotelDayStart': '2025-06-01',
        'hotelDayEnd': '2025-06-30',
        'expectedAmount': 5000,
        'status': 'draft',
        'createdAt': 100,
        'lastModified': 200,
      };

      final result = await adapters.salaryCycles.upsertFromJson(
        json,
        src: Source.appwrite,
      );

      expect(result, greaterThan(0)); // تم الإدراج بنجاح
    });

    test('upsertFromJson يزيل id البعيد لمنع تصادم UNIQUE', () async {
      await insertEmployee();

      final json = {
        'id': 999, // id بعيد — يجب إزالته
        'localUuid': 'sc-remote',
        'employeeUuid': 'emp-1',
        'cycleKey': '2025-06',
        'hotelDayStart': '2025-06-01',
        'hotelDayEnd': '2025-06-30',
        'expectedAmount': 5000,
        'status': 'draft',
        'createdAt': 100,
        'lastModified': 200,
      };

      final result = await adapters.salaryCycles.upsertFromJson(
        json,
        src: Source.appwrite,
      );

      // تم الإدراج بنجاح رغم وجود id بعيد
      expect(result, greaterThan(0));
      // id المحلي يجب أن يكون 1 وليس 999
      final row = await db.select(db.salaryCycles).getSingle();
      expect(row.id, isNot(999));
    });

    test('upsertFromJson يحدث السجل الموجود بدلاً من إدراج جديد', () async {
      await insertEmployee();

      // إدراج أول
      final json1 = {
        'localUuid': 'sc-upsert',
        'employeeUuid': 'emp-1',
        'cycleKey': '2025-06',
        'hotelDayStart': '2025-06-01',
        'hotelDayEnd': '2025-06-30',
        'expectedAmount': 5000,
        'status': 'draft',
        'createdAt': 100,
        'lastModified': 200,
      };
      await adapters.salaryCycles.upsertFromJson(json1, src: Source.appwrite);

      // إدراج ثاني بنفس localUuid = تحديث
      final json2 = {
        'localUuid': 'sc-upsert',
        'employeeUuid': 'emp-1',
        'cycleKey': '2025-06',
        'hotelDayStart': '2025-06-01',
        'hotelDayEnd': '2025-06-30',
        'expectedAmount': 7000, // قيمة مختلفة
        'status': 'active',
        'createdAt': 100,
        'lastModified': 300,
      };
      await adapters.salaryCycles.upsertFromJson(json2, src: Source.appwrite);

      final rows = await db.select(db.salaryCycles).get();
      expect(rows.length, 1); // سجل واحد فقط (تم التحديث)
      expect(rows.first.expectedAmount, 7000);
      expect(rows.first.status, 'active');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SalaryWithdrawalsRepository — اختبار CRUD
  // ═══════════════════════════════════════════════════════════════
  group('SalaryWithdrawalsRepository — CRUD', () {
    test('createFromExpense ينشئ سجل سحب راتب', () async {
      final empId = await insertEmployee();
      final repo = SalaryWithdrawalsRepository(db);

      final id = await repo.createFromExpense(
        expenseId: 1,
        employeeId: empId,
        reason: 'exp_1',
        amount: 1000,
        date: '2025-06-15',
      );

      expect(id, greaterThan(0));

      final rows = await repo.listActive();
      expect(rows.length, 1);
      expect(rows.first.amount, 1000);
      expect(rows.first.reason, 'exp_1');
      expect(rows.first.employeeId, empId);
    });

    test('saveFromExpense ينشئ سجل جديد إذا لم يوجد', () async {
      final empId = await insertEmployee();
      final repo = SalaryWithdrawalsRepository(db);

      await repo.saveFromExpense(
        expenseId: 5,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 2000,
        date: '2025-06-15',
        note: 'ملاحظة',
      );

      final rows = await repo.listActive();
      expect(rows.length, 1);
      expect(rows.first.reason, 'exp_5');
      expect(rows.first.amount, 2000);
    });

    test('saveFromExpense يحدث السجل الموجود', () async {
      final empId = await insertEmployee();
      final repo = SalaryWithdrawalsRepository(db);

      // إنشاء أول
      await repo.saveFromExpense(
        expenseId: 5,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 2000,
        date: '2025-06-15',
      );

      // تحديث بنفس expenseId
      await repo.saveFromExpense(
        expenseId: 5,
        employeeId: empId,
        action: 'سحب راتب معدّل',
        amount: 3000,
        date: '2025-06-15',
        note: 'تعديل',
      );

      final rows = await repo.listActive();
      expect(rows.length, 1); // سجل واحد فقط
      expect(rows.first.amount, 3000);
      expect(rows.first.description, 'تعديل');
    });

    test('deleteByExpenseId يحذف ناعماً', () async {
      final empId = await insertEmployee();
      final repo = SalaryWithdrawalsRepository(db);

      await repo.createFromExpense(
        expenseId: 10,
        employeeId: empId,
        reason: 'exp_10',
        amount: 500,
        date: '2025-06-15',
      );

      // قبل الحذف
      expect((await repo.listActive()).length, 1);

      // حذف ناعم
      await repo.deleteByExpenseId(10);

      // بعد الحذف
      expect((await repo.listActive()).length, 0);

      // لكن السجل لا يزال موجود في قاعدة البيانات
      final allRows = await repo.listAll();
      expect(allRows.length, 1);
      expect(allRows.first.deletedAt, isNotNull);
    });

    test('listByEmployeeId يرجع سحوبات الموظف المحدد فقط', () async {
      final empId1 = await insertEmployee(uuid: 'emp-1', name: 'أحمد');
      final empId2 = await insertEmployee(uuid: 'emp-2', name: 'محمد');
      final repo = SalaryWithdrawalsRepository(db);

      await repo.createFromExpense(
        expenseId: 1,
        employeeId: empId1,
        reason: 'exp_1',
        amount: 1000,
        date: '2025-06-15',
      );
      await repo.createFromExpense(
        expenseId: 2,
        employeeId: empId2,
        reason: 'exp_2',
        amount: 2000,
        date: '2025-06-15',
      );

      final emp1Withdrawals = await repo.listByEmployeeId(empId1);
      expect(emp1Withdrawals.length, 1);
      expect(emp1Withdrawals.first.amount, 1000);

      final emp2Withdrawals = await repo.listByEmployeeId(empId2);
      expect(emp2Withdrawals.length, 1);
      expect(emp2Withdrawals.first.amount, 2000);
    });
  });
}
