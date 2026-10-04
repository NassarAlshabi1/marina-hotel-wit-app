// ignore_for_file: lines_longer_than_80_chars
//
// ✅ (المرحلة 0 — تحصين الربط بين الموظفين والمصروفات ومسحوبات الرواتب)
// اختبارات انحدار للمخاطر المؤكَّدة من المسودة، بالكود الإنتاجي نفسه
// عبر جسور @visibleForTesting (نفس منهجية applyBookingNightsForTesting):
//
//   R1 — لا حذف نهائي لسجل مالي يتيم بعد فحص ما بعد المزامنة.
//   R2 — «الطريقة 2» (employeeId بعيد = id محلي) مُلغاة: الربط عبر
//        UUID → serverId فقط، ولا ربط خاطئ عند تصادم id محليين.
//   R3 — deleteByExpenseId/saveFromExpense لا يمسان مرآة جهاز آخر
//        تصادم expense_id/reason، مع بقاء إعادة تعيين الموظف تعمل.
//   R7 — Drive delta يطبّق salary_withdrawals/salary_carry_over_logs
//        بدل إسقاطهما صامتاً.
//   R8 — مصروف الرواتب (بما فيه «سلفة») لا يأخذ relatedId البعيد الخام؛
//        null عند فشل حل الـ UUID، وحلّ عبر UUID عند توفره.

import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/expenses_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/google_drive_delta_sync.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/sync/payload_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2026-09-25';
  const currentDevice = 'device-B';

  late AppDatabase db;
  late SalaryWithdrawalsRepository repo;

  // ⚠️ قاعدة واحدة لكل الملف: AppwriteSyncManager و AdapterRegistry
  // singleton بمُنشئ factory يتجاهل المعامل بعد أول إنشاء (نفس قيد
  // pull_commit_visibility_test) — إقفال القاعدة لكل اختبار يترك المدير
  // يشير لقاعدة مُغلقة.
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
    repo = SalaryWithdrawalsRepository(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    // نظافة قبل كل اختبار (الأبناء قبل الآباء لقيود FK).
    await db.delete(db.salaryWithdrawals).go();
    await db.delete(db.salaryCarryOverLogs).go();
    await db.delete(db.expenses).go();
    await db.delete(db.outbox).go();
    await db.delete(db.employees).go();
    // ✅ (ت1 المكملة) جداول مسار الدلتا الجديدة (أبناء قبل آباء).
    await db.delete(db.bookingPriceAdjustments).go();
    await db.delete(db.inventoryTransactions).go();
    await db.delete(db.inventoryItems).go();
    await db.delete(db.guestInfos).go();
    await db.delete(db.bookings).go();
    await db.delete(db.rooms).go();
    // هوية الجهاز الحالية — حارس الملكية في P0.3 يعتمد عليها.
    AppwriteSyncManager.updateStaticDeviceId(currentDevice);
  });

  tearDown(() async {
    AppwriteSyncManager.updateStaticDeviceId(null);
  });

  /// إضافة موظف بمعرف محلي وUUID معلومين.
  Future<int> addEmployee({
    int? id,
    required String uuid,
    int? serverId,
    String name = 'موظف',
  }) {
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            id: id != null ? d.Value(id) : const d.Value.absent(),
            name: d.Value(name),
            basicSalary: const d.Value(10000),
            status: const d.Value('active'),
            hireDate: const d.Value('2026-01-01'),
            localUuid: d.Value(uuid),
            serverId: serverId != null
                ? d.Value(serverId)
                : const d.Value.absent(),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  /// مرآة «قادمة من جهاز آخر»: origin=server + deviceId أجنبي + رابط
  /// expense_id/رقم الجهاز المصدر (رقم autoincrement غير محمول).
  Future<int> addForeignMirror({
    required int employeeId,
    required int foreignExpenseId,
    required double amount,
    String date = '2026-01-01',
    String uuid = 'sw-foreign',
  }) {
    return db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            withdrawalType: const d.Value('سحب راتب'),
            reason: d.Value('exp_$foreignExpenseId'),
            expenseId: d.Value(foreignExpenseId),
            hotelDayKey: d.Value(date),
            localUuid: d.Value(uuid),
            origin: const d.Value('server'),
            deviceId: const d.Value('device-A'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  Future<SalaryWithdrawal?> activeByUuid(String uuid) {
    return (db.select(db.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(uuid)))
        .getSingleOrNull();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // R3 — حارس deleteByExpenseId / saveFromExpense
  // ═══════════════════════════════════════════════════════════════════════
  group('R3: حارس expense_id/reason لا يمس مسحوب جهاز آخر', () {
    test('حذف مصروف بلا نطاق موظف لا يحذف مرآة أجنبية متصادمة', () async {
      final x = await addEmployee(uuid: 'uuid-x', name: 'أحمد');
      await addForeignMirror(
        employeeId: x,
        foreignExpenseId: 5,
        amount: 999,
        uuid: 'sw-foreign-5',
      );

      // كما تفعل الشاشة لغير-R موظف: بدون نطاق (relatedId null).
      await repo.deleteByExpenseId(5);

      final row = await activeByUuid('sw-foreign-5');
      expect(row, isNotNull, reason: 'مرآة جهاز آخر يجب ألا تُحذف');
      expect(row!.deletedAt, isNull);
    });

    test('حذف بنطاق موظف آخر لا يحذف المرآة الأجنبية', () async {
      final x = await addEmployee(uuid: 'uuid-x', name: 'أحمد');
      final other = await addEmployee(uuid: 'uuid-other', name: 'آخر');
      await addForeignMirror(
        employeeId: x,
        foreignExpenseId: 5,
        amount: 999,
        uuid: 'sw-foreign-5',
      );

      await repo.deleteByExpenseId(
        5,
        employeeId: other,
        employeeUuid: 'uuid-other',
      );

      final row = await activeByUuid('sw-foreign-5');
      expect(row, isNotNull);
      expect(row!.deletedAt, isNull);
    });

    test(
      'الحذف بموظف المصروف يحذف مرآته المحلية ويُبقي المرآة الأجنبية',
      () async {
        final x = await addEmployee(uuid: 'uuid-x', name: 'أحمد');
        // مرآة محلية لنفس المبلغ (origin=local) — تُنشأ عبر saveFromExpense.
        await repo.saveFromExpense(
          expenseId: 5,
          employeeId: x,
          action: 'سحب راتب',
          amount: 500,
          date: day,
          hotelDayKey: day,
        );
        await addForeignMirror(
          employeeId: x,
          foreignExpenseId: 5,
          amount: 500,
          uuid: 'sw-foreign-5',
        );

        await repo.deleteByExpenseId(
          5,
          employeeId: x,
          employeeUuid: 'uuid-x',
        );

        final all = await db.select(db.salaryWithdrawals).get();
        final local = all.where((w) => w.localUuid != 'sw-foreign-5');
        final foreign = all.where((w) => w.localUuid == 'sw-foreign-5');
        expect(local.single.deletedAt, isNotNull, reason: 'المرآة المحلية تحذف');
        expect(
          foreign.single.deletedAt,
          isNull,
          reason: 'المرآة الأجنبية تبقى — رابطها ليس لهذا الجهاز',
        );
      },
    );

    test('saveFromExpense لا يعدّل مسحوب جهاز آخر المتصادق الرقماً', () async {
      final x = await addEmployee(uuid: 'uuid-x', name: 'أحمد');
      await addForeignMirror(
        employeeId: x,
        foreignExpenseId: 5,
        amount: 999,
        date: '2026-01-01',
        uuid: 'sw-foreign-5',
      );

      // تعديل مبلغ المصروف المحلي id=5 — الطريقة 1/2 يجدان المرآة
      // الأجنبية برقمها المتطابق، والحارس يجب أن يمنع تعديلها.
      await repo.saveFromExpense(
        expenseId: 5,
        employeeId: x,
        action: 'سحب راتب',
        amount: 500,
        date: day,
        hotelDayKey: day,
      );

      final foreign = await activeByUuid('sw-foreign-5');
      expect(foreign, isNotNull);
      expect(foreign!.amount, 999, reason: 'مبلغ المرآة الأجنبية لم يتغير');
      expect(foreign.version, 1, reason: 'لم تُحدَّث نسخة المرآة الأجنبية');
      expect(foreign.employeeId, x);

      // وأُنشئت مرآة محلية جديدة لهذا المصروف.
      final locals = await (db.select(db.salaryWithdrawals)
            ..where(
              (t) =>
                  t.expenseId.equals(5) &
                  t.origin.equals('local') &
                  t.deletedAt.isNull(),
            ))
          .get();
      expect(locals, hasLength(1));
      expect(locals.first.amount, 500);
    });

    test('إعادة تعيين موظف المصروف تحدّث المرآة القديمة بلا تكرار', () async {
      final x = await addEmployee(uuid: 'uuid-x', name: 'أحمد');
      final y = await addEmployee(uuid: 'uuid-y', name: 'سامح');

      await repo.saveFromExpense(
        expenseId: 7,
        employeeId: x,
        action: 'سحب راتب',
        amount: 300,
        date: day,
        hotelDayKey: day,
      );

      // كما تفعل الشاشة: previousEmployeeId = الموظف السابق للمصروف.
      await repo.saveFromExpense(
        expenseId: 7,
        employeeId: y,
        action: 'سحب راتب',
        amount: 300,
        date: day,
        hotelDayKey: day,
        previousEmployeeId: x,
      );

      final active = await (db.select(db.salaryWithdrawals)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      expect(active, hasLength(1), reason: 'مرآة واحدة فقط — بلا تكرار');
      expect(active.first.employeeId, y, reason: 'المرآة انتقلت للموظف الجديد');
      expect(
        active.first.employeeUuid,
        'uuid-y',
        reason: 'employeeUuid حُدِّث مع إعادة التعيين (R12)',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R8 — expenses_adapter: لا relatedId بعيد خام + شمول «سلفة»
  // ═══════════════════════════════════════════════════════════════════════
  group('R8: relatedId لمصروف الراتب يُحل عبر UUID ولا يُؤخذ خاماً', () {
    test('isSalaryExpenseType تشمل «سلفة» وأشباهها', () {
      expect(PayloadMapper.isSalaryExpenseType('سلفة'), isTrue);
      expect(PayloadMapper.isSalaryExpenseType('سلفة عاجلة'), isTrue);
      expect(PayloadMapper.isSalaryExpenseType('سحب راتب'), isTrue);
      expect(PayloadMapper.isSalaryExpenseType('خصم من الراتب'), isTrue);
      expect(PayloadMapper.isSalaryExpenseType('ضيافة'), isFalse);
      expect(PayloadMapper.isSalaryExpenseType(''),
          isFalse);
    });

    test('سلفة من مصدر بعيد بلا uuid → relatedId null لا الرقم الخام', () async {
      final adapter = ExpensesAdapter(IdResolver(db));
      const json = {'expenseType': 'سلفة', 'relatedId': 7};

      final refs = await adapter.resolveRefs(db, json, src: Source.appwrite);
      final companion = adapter.fromJson(json, src: Source.appwrite, refs: refs);

      expect(refs.employeeRelatedId, isNull);
      expect(
        companion.relatedId.value,
        isNull,
        reason: 'لا relatedId بعيد خام — يُربط لاحقاً عبر employeeUuid',
      );
    });

    test('سلفة من مصدر بعيد بـ uuid حاضر → relatedId محلول', () async {
      final empId = await addEmployee(uuid: 'emp-1', name: 'أحمد');
      final adapter = ExpensesAdapter(IdResolver(db));
      const json = {
        'expenseType': 'سلفة',
        'relatedId': 7,
        'employeeUuid': 'emp-1',
      };

      final refs = await adapter.resolveRefs(db, json, src: Source.appwrite);
      final companion = adapter.fromJson(json, src: Source.appwrite, refs: refs);

      expect(refs.employeeRelatedId, empId);
      expect(companion.relatedId.value, empId);
    });

    test('غير-R راتب (حجز) يبقى relatedId كما هو', () async {
      final adapter = ExpensesAdapter(IdResolver(db));
      const json = {'expenseType': 'ضيافة', 'relatedId': 9};

      final refs = await adapter.resolveRefs(db, json, src: Source.appwrite);
      final companion = adapter.fromJson(json, src: Source.appwrite, refs: refs);

      expect(companion.relatedId.value, 9, reason: 'سلوك محفوظ لغير الرواتب');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R2 — _syncSalaryWithdrawals: لا «طريقة 2» (id بعيد = id محلي)
  // ═══════════════════════════════════════════════════════════════════════
  group('R2: سحب المسحوبات يربط عبر UUID/serverId لا id المحلي', () {
    models.Document withdrawalDoc({
      required String uuid,
      required int remoteEmployeeId,
    }) {
      return models.Document(
        $id: uuid,
        $sequence: 1,
        $collectionId: 'salary_withdrawals',
        $databaseId: 'marina',
        $createdAt: '2026-10-01T00:00:00.000Z',
        $updatedAt: '2026-10-01T12:00:00.000Z',
        $permissions: const <String>[],
        data: <String, dynamic>{
          'localUuid': uuid,
          'employeeId': remoteEmployeeId,
          'amount': 5000.0,
          'withdrawDate': '2026-10-01',
          'withdrawalType': 'سحب راتب',
          'reason': 'exp_$remoteEmployeeId',
          'createdAt': 1760000000,
          'lastModified': 1760000100,
          'version': 1,
          'deviceId': 'device-A',
        },
      );
    }

    test(
      'employeeId بعيد=3 مع موظفين (id=3 بلا serverId و id=7 بـ serverId=3) '
      '→ يرتبط بالصاحب serverId لا بمصادفة الـ id',
      () async {
        final a = await addEmployee(
          id: 3,
          uuid: 'uuid-a',
          name: 'موظف id=3 محلياً',
        );
        final b = await addEmployee(
          id: 7,
          uuid: 'uuid-b',
          serverId: 3,
          name: 'صاحب الـ id الأصلي',
        );

        final manager = AppwriteSyncManager(
          appwriteService: AppwriteService(),
          database: db,
        );
        final applied = await manager.syncSalaryWithdrawalsForTesting([
          withdrawalDoc(uuid: 'sw-r2', remoteEmployeeId: 3),
        ]);

        expect(applied, 1);
        final row = await activeByUuid('sw-r2');
        expect(row, isNotNull);
        expect(
          row!.employeeId,
          b,
          reason: 'الربط عبر serverId=3 (جهاز المصدر) — لا عبر id المحلي 3',
        );
        expect(row.employeeId, isNot(a), reason: 'لا ربط بمصادفة الـ id');
        expect(row.employeeUuid, 'uuid-b', reason: 'ختم employeeUuid القياسي');
      },
    );

    test('موظف بلا uuid وبلا serverId مطابق → يتيم لا يُربط ولا يُدرج', () async {
      await addEmployee(id: 3, uuid: 'uuid-a', name: 'أحمد');

      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );
      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(uuid: 'sw-orphan', remoteEmployeeId: 99),
      ]);

      expect(applied, 0, reason: 'السجل اليتيم لا يُعالج كنجاح');
      expect(await activeByUuid('sw-orphan'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R7 — Drive delta: تطبيق جدولي الرواتب المفقودين
  // ═══════════════════════════════════════════════════════════════════════
  group('R7: Drive delta يطبّق salary_withdrawals و carry_over_logs', () {
    test('تغيّرَان للجدولين يُطبَّقان ويُنشئان السجلات', () async {
      await addEmployee(uuid: 'uuid-a', name: 'أحمد');

      final applied =
          await GoogleDriveDeltaSync.instance.applyChangesForTesting(
        db,
        AdapterRegistry.instance,
        {
          'changes': [
            {
              'entity': 'salary_withdrawals',
              'op': 'update',
              'data': {
                'localUuid': 'sw-delta-1',
                'employeeUuid': 'uuid-a',
                'amount': 1500.0,
                'withdrawDate': '2026-10-02',
                'withdrawalType': 'سحب راتب',
                'reason': 'exp_9',
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 3,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
            {
              'entity': 'salary_carry_over_logs',
              'op': 'update',
              'data': {
                'localUuid': 'col-delta-1',
                'employeeUuid': 'uuid-a',
                'amount': 250.0,
                'previousCycleStart': '2026-09-01',
                'previousCycleEnd': '2026-09-30',
                'newCycleStart': '2026-10-01',
                'newCycleEnd': '2026-10-31',
                'reason': 'ترحيل تلقائي',
                'carriedAt': 5000,
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 1,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
          ],
        },
      );

      expect(applied, 2, reason: 'الجدولان يُطبَّقان لا يُسقطان صامتاً');

      final sw = await activeByUuid('sw-delta-1');
      expect(sw, isNotNull, reason: 'salary_withdrawals وصل عبر Delta');
      expect(sw!.amount, 1500.0);

      final col = await (db.select(db.salaryCarryOverLogs)
            ..where((t) => t.localUuid.equals('col-delta-1')))
          .getSingleOrNull();
      expect(col, isNotNull, reason: 'salary_carry_over_logs يصل عبر Delta');
      expect(col!.amount, 250.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ت1 المكملة — Drive delta يطبّق الكيانات الأربعة المتبقية (كانت تُسقط
  // بصمت رغم أن المُنتِج يصدّرها)، ويعلن أي إسقاط ويستثنيه من العدّ.
  // ═══════════════════════════════════════════════════════════════════════
  group('ت1: Drive delta يطبّق guest_infos/inventory/booking_price_adjustments', () {
    test('الكيانات الأربعة تُطبَّق والكيان غير المدعوم لا يُحصى applied', () async {
      final applied =
          await GoogleDriveDeltaSync.instance.applyChangesForTesting(
        db,
        AdapterRegistry.instance,
        {
          'changes': [
            // غرفة ثم حجز ثم تعديل سعر مرتبط به (الترتيب التبعي في الدفعة).
            {
              'entity': 'rooms',
              'op': 'update',
              'data': {
                'localUuid': 'room-delta-1',
                'roomNumber': '701',
                'type': 'double',
                'price': 100.0,
                'status': 'available',
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 1,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
            {
              'entity': 'bookings',
              'op': 'update',
              'data': {
                'localUuid': 'booking-delta-1',
                'roomNumber': '701',
                'guestName': 'ضيف دلتا',
                'guestPhone': '777000',
                'guestNationality': 'يمني',
                'checkinDate': day,
                'status': 'checked_in',
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 1,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
            {
              'entity': 'booking_price_adjustments',
              'op': 'update',
              'data': {
                'localUuid': 'bpa-delta-1',
                'bookingLocalUuid': 'booking-delta-1',
                'roomNumber': '701',
                'amount': 25.0,
                'effectiveHotelDay': day,
                'reason': 'اختبار دلتا',
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 1,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
            {
              'entity': 'guest_infos',
              'op': 'update',
              'data': {
                'localUuid': 'gi-delta-1',
                'roomNumber': '701',
                'guestName': 'ضيف دلتا',
                'nationality': 'يمني',
                'idNumber': 'ID-1',
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 1,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
            {
              'entity': 'inventory_items',
              'op': 'update',
              'data': {
                'localUuid': 'item-delta-1',
                'name': 'منشفة دلتا',
                'quantity': 10,
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 1,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
            {
              'entity': 'inventory_transactions',
              'op': 'update',
              'data': {
                'localUuid': 'txn-delta-1',
                'itemLocalUuid': 'item-delta-1',
                'movementType': 'in',
                'quantity': 10,
                'balanceAfter': 10,
                'createdAt': 1000,
                'lastModified': 2000,
                'version': 1,
                'deviceId': 'device-A',
                'origin': 'server',
              },
            },
            // كيان غير مدعوم — إسقاط معلن لا يُحصى applied (ت1: العدّ
            // بعد التطبيق الفعلي لا قبله).
            {
              'entity': 'not_a_real_entity',
              'op': 'update',
              'data': {'localUuid': 'ghost-1'},
            },
          ],
        },
      );

      expect(applied, 6, reason: 'الكيان غير المدعوم لا يُحصى applied');

      final bpa = await (db.select(db.bookingPriceAdjustments)
            ..where((t) => t.localUuid.equals('bpa-delta-1')))
          .getSingleOrNull();
      expect(bpa, isNotNull, reason: 'booking_price_adjustments يصل عبر Delta');
      expect(bpa!.amount, 25.0);

      final gi = await (db.select(db.guestInfos)
            ..where((t) => t.localUuid.equals('gi-delta-1')))
          .getSingleOrNull();
      expect(gi, isNotNull, reason: 'guest_infos يصل عبر Delta');

      final item = await (db.select(db.inventoryItems)
            ..where((t) => t.localUuid.equals('item-delta-1')))
          .getSingleOrNull();
      expect(item, isNotNull, reason: 'inventory_items يصل عبر Delta');
      expect(item!.quantity, 10);

      final txn = await (db.select(db.inventoryTransactions)
            ..where((t) => t.localUuid.equals('txn-delta-1')))
          .getSingleOrNull();
      expect(txn, isNotNull, reason: 'inventory_transactions يصل عبر Delta');
      expect(
        txn!.itemId,
        item!.id,
        reason: 'رابط البند يُحل محلياً عبر itemLocalUuid',
      );
    });

    test('delete عبر delta لكيان غير مالي (guest_infos) يُطبَّق ويُحصى', () async {
      await db.into(db.guestInfos).insert(
            GuestInfosCompanion(
              roomNumber: const d.Value('702'),
              guestName: const d.Value('حذف دلتا'),
              nationality: const d.Value(''),
              idNumber: const d.Value('ID-2'),
              localUuid: const d.Value('gi-del-1'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );

      final applied =
          await GoogleDriveDeltaSync.instance.applyChangesForTesting(
        db,
        AdapterRegistry.instance,
        {
          'changes': [
            {
              'entity': 'guest_infos',
              'op': 'delete',
              'data': {'local_uuid': 'gi-del-1'},
            },
          ],
        },
      );

      expect(applied, 1, reason: 'delete لكيان غير مالي يُنفَّذ ويُحصى');
      final gi = await (db.select(db.guestInfos)
            ..where((t) => t.localUuid.equals('gi-del-1')))
          .getSingleOrNull();
      expect(gi, isNull, reason: 'الصف غير المالي حُذف نهائياً عبر Delta');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // R1 — فحص ما بعد المزامنة لا يحذف السجلات المالية اليتيمة
  // ═══════════════════════════════════════════════════════════════════════
  group('R1: لا حذف نهائي لسجل مالي يتيم بعد المزامنة', () {
    test('انتهاك FK على salary_withdrawals → السجل يبقى ويُسجَّل', () async {
      await addEmployee(uuid: 'uuid-x', name: 'أحمد');

      // إنشاء انتهاك مقصود: موظف غير موجود (999).
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              employeeId: const d.Value(999),
              amount: const d.Value(777),
              withdrawDate: const d.Value('2026-10-03'),
              reason: const d.Value('exp_999'),
              localUuid: const d.Value('sw-orphan-fk'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );

      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );
      await manager.performPostSyncIntegrityCheckForTesting();

      final row = await activeByUuid('sw-orphan-fk');
      expect(
        row,
        isNotNull,
        reason: 'لا DELETE نهائي — السجل اليتيم محفوظ للمراجعة (P0.1)',
      );
      expect(row!.employeeId, 999);
      expect(row.amount, 777);
    });
  });
}
