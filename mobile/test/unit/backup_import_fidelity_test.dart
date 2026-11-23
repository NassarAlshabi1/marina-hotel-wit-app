// ══════════════════════════════════════════════════════════════════
//  backup_import_fidelity_test.dart — عقد «الاستعادة لا تُسقط عموداً»
//
//  الجذر الذي يمنعه هذا الاختبار (تقرير 2026-11-23 / §14):
//    دوال `importFromJson` في `payments/debts/bookings/rooms` كانت تكتب
//    قائمة أعمدة **يدوية** بدل الصف كاملاً. المسقط كان:
//      • المدفوعات: isVoided/voidedAt/voidedBy/voidReason/isImmutable/
//        isPendingBalance/discountAmount/discountStartDate/referenceNumber…
//        ⇒ دفعة ملغاة تعود «مدفوعة» فرصيد الضيف ينقص، والخصم يضيع.
//      • الديون: amount/date/status/dueDate/isSettled/debtUuid/
//        bookingUuidCache/guestPhone… ⇒ ديون بمبلغ صفر وحالة فارغة.
//      • الغرف: cleaningStatus/lastOccupiedHotelDay/requiresMaintenance.
//      • الحجوزات: financialFrozenAt/financialHash/deviceId/idempotencyKey.
//      • الأربعة: `id` المحلي ⇒ إعادة ترقيم تُفكّك ربط الأبناء بالآباء.
//
//  الحل المنفَّذ: `insertOnConflictUpdate(entity.toCompanion(false))`
//  أي كل الأعمدة كما هي. الاختبار يثبت أن الجولة الكاملة
//  (صف ← toJson ← حذف ← importFromJson) تعيد **نفس** القيم الحسّاسة.
// ══════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/daos/bookings_dao.dart';
import 'package:marina_hotel_mobile/services/daos/debts_dao.dart';
import 'package:marina_hotel_mobile/services/daos/employees_dao.dart';
import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/payments_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  late AppDatabase db;
  late OutboxDao outbox;
  late AdapterRegistry adapters;
  late PaymentsDao paymentsDao;
  late DebtsDao debtsDao;
  late BookingsDao bookingsDao;
  late RoomsDao roomsDao;
  late ExpensesDao expensesDao;
  late EmployeesDao employeesDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxDao(db);
    adapters = AdapterRegistry(db);
    paymentsDao = PaymentsDao(db, outbox, adapters);
    debtsDao = DebtsDao(db, outbox, adapters);
    bookingsDao = BookingsDao(db, outbox, adapters);
    roomsDao = RoomsDao(db, outbox);
    expensesDao = ExpensesDao(db, outbox, adapters);
    employeesDao = EmployeesDao(db, outbox, adapters);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'المدفوعات: isVoided/voidReason/isPendingBalance/الخصم تنجو من الاستعادة',
    () async {
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              localUuid: 'pay-1',
              createdAt: 100,
              updatedAt: 200,
              lastModified: 200,
              amount: 500,
              paymentDate: '2026-11-20',
              paymentMethod: 'cash',
              revenueType: 'room',
              id: const d.Value(77),
              isVoided: const d.Value(true),
              voidedAt: const d.Value(1234),
              voidedBy: const d.Value('مدير'),
              voidReason: const d.Value('إدخال خاطئ'),
              isImmutable: const d.Value(true),
              isPendingBalance: const d.Value(true),
              discountAmount: const d.Value(25),
              discountStartDate: const d.Value('2026-11-01'),
              referenceNumber: const d.Value('REF-9'),
              receivedByCloudId: const d.Value('cloud-7'),
              version: const d.Value(9),
              serverId: const d.Value(321),
            ),
          );

      final row = await db.select(db.payments).getSingle();
      final snapshotJson = row.toJson();

      await db.delete(db.payments).go();
      await paymentsDao.importFromJson([snapshotJson]);

      final restored = await db.select(db.payments).getSingle();
      expect(restored.isVoided, isTrue, reason: 'الدفعة الملغاة عادت مدفوعة');
      expect(restored.voidReason, 'إدخال خاطئ');
      expect(restored.voidedBy, 'مدير');
      expect(restored.voidedAt, 1234);
      expect(restored.isImmutable, isTrue);
      expect(restored.isPendingBalance, isTrue);
      expect(restored.discountAmount, 25);
      expect(restored.discountStartDate, '2026-11-01');
      expect(restored.referenceNumber, 'REF-9');
      expect(restored.receivedByCloudId, 'cloud-7');
      expect(restored.version, 9);
      expect(restored.serverId, 321);
      expect(restored.id, 77, reason: 'إعادة الترقيم تفكّ ربط الأبناء بالآباء');
    },
  );

  test(
    'الديون: amount/status/dueDate/isSettled/bookingUuidCache تنجو',
    () async {
      await db
          .into(db.debts)
          .insert(
            DebtsCompanion.insert(
              localUuid: 'debt-1',
              createdAt: 100,
              updatedAt: 200,
              lastModified: 200,
              guestName: 'ضيف',
              checkinDate: '2026-11-20',
              checkoutDate: '2026-11-22',
              totalAmount: 900,
              paidAmount: 400,
              remainingAmount: 500,
              paymentDate: '2026-11-22',
              id: const d.Value(55),
              amount: const d.Value(500),
              date: const d.Value('2026-11-22'),
              status: const d.Value('متبقي'),
              dueDate: const d.Value('2026-12-01'),
              isSettled: const d.Value(0),
              settlementConfirmed: const d.Value(true),
              debtUuid: const d.Value('debt-uuid-9'),
              bookingUuidCache: const d.Value('booking-uuid-9'),
              guestPhone: const d.Value('0500000000'),
              description: const d.Value('باقي إقامة'),
              debtorName: const d.Value('المدين'),
              hotelDayOpened: const d.Value('2026-11-20'),
              hotelDayClosed: const d.Value('2026-11-22'),
              isFromAutoFix: const d.Value(true),
              debtReason: const d.Value('إقامة'),
              dateRecorded: const d.Value('2026-11-22'),
              version: const d.Value(4),
            ),
          );

      final snapshotJson = (await db.select(db.debts).getSingle()).toJson();
      await db.delete(db.debts).go();
      await debtsDao.importFromJson([snapshotJson]);

      final restored = await db.select(db.debts).getSingle();
      expect(restored.amount, 500, reason: 'الدين كان يُستعاد بمبلغ صفر');
      expect(restored.totalAmount, 900);
      expect(restored.paidAmount, 400);
      expect(restored.remainingAmount, 500);
      expect(restored.status, 'متبقي');
      expect(restored.dueDate, '2026-12-01');
      expect(restored.isSettled, 0);
      expect(restored.settlementConfirmed, isTrue);
      expect(restored.debtUuid, 'debt-uuid-9');
      expect(restored.bookingUuidCache, 'booking-uuid-9');
      expect(restored.guestPhone, '0500000000');
      expect(restored.description, 'باقي إقامة');
      expect(restored.debtorName, 'المدين');
      expect(restored.hotelDayOpened, '2026-11-20');
      expect(restored.hotelDayClosed, '2026-11-22');
      expect(restored.isFromAutoFix, isTrue);
      expect(restored.debtReason, 'إقامة');
      expect(restored.dateRecorded, '2026-11-22');
      expect(restored.version, 4);
      expect(restored.id, 55);
    },
  );

  test(
    'الغرف: cleaningStatus/آخر يوم إشغال/requiresMaintenance تنجو',
    () async {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-1',
              createdAt: 100,
              updatedAt: 200,
              lastModified: 200,
              roomNumber: '101',
              type: 'standard',
              price: 150,
              status: 'مشغولة',
              id: const d.Value(11),
              cleaningStatus: const d.Value('تحتاج تنظيف'),
              lastCleanedHotelDay: const d.Value('2026-11-19'),
              lastOccupiedHotelDay: const d.Value('2026-11-20'),
              requiresMaintenance: const d.Value(true),
              version: const d.Value(6),
            ),
          );

      final snapshotJson = (await db.select(db.rooms).getSingle()).toJson();
      await db.delete(db.rooms).go();
      await roomsDao.importFromJson([snapshotJson]);

      final restored = await db.select(db.rooms).getSingle();
      expect(restored.cleaningStatus, 'تحتاج تنظيف');
      expect(restored.lastCleanedHotelDay, '2026-11-19');
      expect(restored.lastOccupiedHotelDay, '2026-11-20');
      expect(restored.requiresMaintenance, isTrue);
      expect(restored.version, 6);
      expect(restored.id, 11);
    },
  );

  test(
    'الحجوزات: financialFrozenAt/financialHash/deviceId/idempotencyKey تنجو',
    () async {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-for-booking',
              createdAt: 100,
              updatedAt: 200,
              lastModified: 200,
              roomNumber: '101',
              type: 'standard',
              price: 150,
              status: 'مشغولة',
            ),
          );
      await db
          .into(db.bookings)
          .insert(
            BookingsCompanion.insert(
              localUuid: 'booking-1',
              createdAt: 100,
              updatedAt: 200,
              lastModified: 200,
              roomNumber: '101',
              guestName: 'ضيف',
              guestPhone: '0500000001',
              guestNationality: 'يمني',
              checkinDate: '2026-11-20T14:00:00.000Z',
              status: 'active',
              id: const d.Value(9),
              financialFrozenAt: const d.Value(1795341600000),
              financialHash: const d.Value('hash-abc'),
              deviceId: const d.Value('device-A'),
              idempotencyKey: const d.Value('idem-1'),
              totalPaidCached: const d.Value(300),
              remainingBalanceCached: const d.Value(700),
              version: const d.Value(12),
            ),
          );

      final snapshotJson = (await db.select(db.bookings).getSingle()).toJson();
      await db.delete(db.bookings).go();
      await bookingsDao.importFromJson([snapshotJson]);

      final restored = await db.select(db.bookings).getSingle();
      expect(restored.financialFrozenAt, 1795341600000);
      expect(restored.financialHash, 'hash-abc');
      expect(restored.deviceId, 'device-A');
      expect(restored.idempotencyKey, 'idem-1');
      expect(restored.totalPaidCached, 300);
      expect(restored.remainingBalanceCached, 700);
      expect(restored.version, 12);
      expect(restored.id, 9);
    },
  );

  test(
    'المصروفات: expenseKind/employeeUuid/withdrawalUuid/hotelDayKey تنجو',
    () async {
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              localUuid: 'expense-1',
              createdAt: 100,
              updatedAt: 200,
              lastModified: 200,
              expenseType: 'راتب',
              description: 'سحب راتب',
              amount: 250.5,
              date: '2026-11-20',
              id: const d.Value(33),
              expenseKind: const d.Value('salary'),
              employeeUuid: const d.Value('emp-uuid-1'),
              withdrawalUuid: const d.Value('withdrawal-uuid-1'),
              hotelDayKey: const d.Value('2026-11-20'),
              isAutoGenerated: const d.Value(true),
              employeeLinkCleared: const d.Value(1),
              categoryUuid: const d.Value('cat-1'),
              cashFlowUuid: const d.Value('flow-1'),
              version: const d.Value(3),
            ),
          );

      final snapshotJson = (await db.select(db.expenses).getSingle()).toJson();
      await db.delete(db.expenses).go();
      await expensesDao.importFromJson([snapshotJson]);

      final restored = await db.select(db.expenses).getSingle();
      expect(restored.expenseKind, 'salary');
      expect(
        restored.employeeUuid,
        'emp-uuid-1',
        reason: 'فقدان employeeUuid يفصل المصروف عن الموظف في كشف الرواتب',
      );
      expect(restored.withdrawalUuid, 'withdrawal-uuid-1');
      expect(restored.hotelDayKey, '2026-11-20');
      expect(restored.isAutoGenerated, isTrue);
      expect(restored.employeeLinkCleared, 1);
      expect(restored.categoryUuid, 'cat-1');
      expect(restored.cashFlowUuid, 'flow-1');
      expect(restored.version, 3);
      expect(restored.id, 33);
    },
  );

  test('الموظفون: employeeID والهوية العالمية تنجوان', () async {
    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            localUuid: 'emp-1',
            createdAt: 100,
            updatedAt: 200,
            lastModified: 200,
            name: 'موظف',
            basicSalary: 800,
            status: 'active',
            id: const d.Value(21),
            employeeID: const d.Value('EMP-007'),
            version: const d.Value(5),
          ),
        );

    final snapshotJson = (await db.select(db.employees).getSingle()).toJson();
    await db.delete(db.employees).go();
    await employeesDao.importFromJson([snapshotJson]);

    final restored = await db.select(db.employees).getSingle();
    expect(restored.employeeID, 'EMP-007');
    expect(restored.basicSalary, 800);
    expect(restored.version, 5);
    expect(restored.id, 21);
  });
}
