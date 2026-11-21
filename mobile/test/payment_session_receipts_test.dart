import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';

void main() {
  test(
    'current session payment total is isolated and excludes non-received rows',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';

      PaymentSessionContext.start(
        userId: 1,
        userName: 'User 1',
        sessionUuid: 'session-user-1',
      );
      await repository.create(
        amount: 100,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      PaymentSessionContext.start(
        userId: 2,
        userName: 'User 2',
        sessionUuid: 'session-user-2',
      );
      await repository.create(
        amount: 250,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      PaymentSessionContext.start(
        userId: 1,
        userName: 'User 1',
        sessionUuid: 'session-user-1',
      );
      final pendingId = await repository.create(
        amount: 40,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
        isPendingBalance: true,
      );
      final voidedId = await repository.create(
        amount: 60,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      await (db.update(db.payments)..where((p) => p.id.equals(voidedId))).write(
        const PaymentsCompanion(isVoided: Value(true)),
      );

      final total = await repository.watchTotalByCurrentPaymentSession().first;

      expect(total, 100);
      expect(pendingId, greaterThan(0));
    },
  );

  test(
    'current session total spans hotel-day boundary (no clip at 14:01)',
    () async {
      // ✅ (2026-09-05) النوبة قد تعبر حد 14:01 فتتوزع استلاماتها على
      // مفتاحي يوم فندقي — الإجمالي الصحيح «أثناء النوبة» = الكل.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      // مفتاحان فندقيان مختلفان (قبل وبعد حد 14:01) لنفس الجلسة.
      // نفس اليوم التقويمي حول حد 14:01: 13:00 ← مفتاح اليوم السابق
      // الفندقي، 15:00 ← مفتاح يومه الفندقي (نوبة تعبر الحد).
      const dayAPayment = '2026-08-20T13:00:00.000Z';
      const dayBPayment = '2026-08-20T15:00:00.000Z';
      final keyA = HotelTimeEngine.getHotelDayKeyFromIso(dayAPayment);
      final keyB = HotelTimeEngine.getHotelDayKeyFromIso(dayBPayment);
      expect(keyA, isNot(keyB), reason: 'يجب أن يكونا مفتاحين مختلفين');

      PaymentSessionContext.start(
        userId: 1,
        userName: 'User 1',
        sessionUuid: 'session-cross-boundary',
      );
      await repository.create(
        amount: 300,
        paymentDate: dayAPayment,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      await repository.create(
        amount: 450,
        paymentDate: dayBPayment,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final total = await repository.watchTotalByCurrentPaymentSession().first;
      expect(total, 750);
    },
  );

  test(
    'other users hotel-day receipts exclude the current system user',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'مدير النظام',
        sessionUuid: 'session-admin',
      );
      await repository.create(
        amount: 161500,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-employee',
      );
      await repository.create(
        amount: 250,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(hotelDay, excludedUserId: 1)
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 7);
      expect(summaries.single.userName, 'موظف الاستقبال');
      expect(summaries.single.totalAmount, 250);
    },
  );

  test(
    'hotel-day receipts clip a shift crossing 14:01 to the current hotel day',
    () async {
      // ✅ (2026-09-15) «بحسب اليوم الفندقي فقط»: النافذة لم تعد
      // يومين فندقيين — النوبة العابرة لحد 14:01 تُقتطع عمداً عند
      // حدود اليوم الفندقي: جزء 200 من أمس الفندقي يظهر في يومه،
      // والبطاقة هنا تعرض 500 فقط (ما استُلم في اليوم الفندقي الحالي).
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const yesterdayPortion = '2026-08-20T13:00:00.000Z';
      const todayPortion = '2026-08-20T15:00:00.000Z';
      final todayKey = HotelTimeEngine.getHotelDayKeyFromIso(todayPortion);
      expect(
        HotelTimeEngine.getHotelDayKeyFromIso(yesterdayPortion),
        isNot(todayKey),
      );

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        sessionUuid: 'session-admin',
      );

      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-night-shift',
      );
      await repository.create(
        amount: 200,
        paymentDate: yesterdayPortion,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      await repository.create(
        amount: 500,
        paymentDate: todayPortion,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(todayKey, excludedUserId: 1)
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 7);
      expect(summaries.single.totalAmount, 500);
      expect(summaries.single.paymentCount, 1);
    },
  );

  test(
    'hotel-day receipts exclude payments outside the current hotel day',
    () async {
      // ✅ (2026-09-15) لا نافذة يومين بعد: أمس الفندقي (2026-08-21)
      // والأقدم خارج اللوحة — لا تراكم تاريخي على لوحة اليوم.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const todayIso = '2026-08-22T20:00:00.000Z';
      const yesterdayIso = '2026-08-21T20:00:00.000Z';
      const ancientIso = '2026-08-19T09:00:00.000Z';
      final todayKey = HotelTimeEngine.getHotelDayKeyFromIso(todayIso);
      expect(
        HotelTimeEngine.getHotelDayKeyFromIso(yesterdayIso),
        HotelTimeEngine.previousHotelDayKey(todayKey),
        reason: 'أمس الفندقي كان داخل النافذة القديمة — صار خارجها',
      );

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        sessionUuid: 'session-admin',
      );
      PaymentSessionContext.start(
        userId: 9,
        userName: 'موظف قديم',
        sessionUuid: 'session-old',
      );
      await repository.create(
        amount: 300,
        paymentDate: yesterdayIso,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      await repository.create(
        amount: 999,
        paymentDate: ancientIso,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(todayKey, excludedUserId: 1)
          .first;
      expect(summaries, isEmpty);
    },
  );

  test(
    'hotel-day receipts keep another device user with the same local id',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        cloudUserId: 'cloud-manager',
        sessionUuid: 'session-manager',
      );
      await repository.create(
        amount: 100,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      // نفس المعرف المحلي قد يمثل مستخدماً مختلفاً على جهاز آخر.
      PaymentSessionContext.start(
        userId: 1,
        userName: 'المستخدم 1',
        cloudUserId: 'cloud-user-1',
        sessionUuid: 'session-user-1',
      );
      await repository.create(
        amount: 17000,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final savedPayments = await db.select(db.payments).get();
      expect(savedPayments.last.receivedByCloudId, 'cloud-user-1');

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(
            hotelDay,
            excludedUserName: 'المدير',
            excludedUserCloudId: 'cloud-manager',
          )
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 1);
      expect(summaries.single.userName, 'المستخدم 1');
      expect(summaries.single.totalAmount, 17000);
    },
  );

  test(
    'hotel-day receipts aggregate all sessions of a user into one row',
    () async {
      // ✅ (2026-09-14) عقد المستخدم الحرفي: سطر واحد لكل مستخدم =
      // إجمالي كل ما استلمه في اليوم الفندقي مهما كان عدد جلساته
      // (500 من جلسة صباحية + 500 من جلسة مسائية → سطر واحد 1000).
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        sessionUuid: 'session-admin',
      );

      // نفس الموظف بجلستين مختلفتين ضمن نفس اليوم الفندقي.
      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-morning',
      );
      await repository.create(
        amount: 500,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-evening',
      );
      await repository.create(
        amount: 500,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(hotelDay, excludedUserId: 1)
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 7);
      expect(summaries.single.userName, 'موظف الاستقبال');
      expect(summaries.single.totalAmount, 1000);
      expect(summaries.single.paymentCount, 2);
    },
  );

  test(
    'same cloud user with different name spellings appears as one row',
    () async {
      // ✅ (2026-09-14) تقرير التشخيص — «أحمد / أحمد / أحمد محمد»: نفس
      // الهوية السحابية باختلاف صياغة الاسم بين الجلسات = سطر واحد
      // (التجميع بالـ cloud_id الثابت لا بالاسم).
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        sessionUuid: 'session-admin',
      );

      PaymentSessionContext.start(
        userId: 7,
        userName: 'أحمد',
        cloudUserId: 'cloud-ahmad',
        sessionUuid: 'session-a',
      );
      await repository.create(
        amount: 300,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      PaymentSessionContext.start(
        userId: 7,
        userName: 'أحمد محمد',
        cloudUserId: 'cloud-ahmad',
        sessionUuid: 'session-b',
      );
      await repository.create(
        amount: 450,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(hotelDay, excludedUserId: 1)
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.totalAmount, 750);
      expect(summaries.single.paymentCount, 2);
    },
  );

  test(
    'another cloud user sharing the current user name is not excluded',
    () async {
      // ✅ (2026-09-14) تقرير التشخيص — «مستخدمان لهما الاسم نفسه»:
      // الاستبعاد بالاسم كان يُخفي استلامات الزميل الذي يشترك مع
      // المستخدم الحالي في الاسم. الآن الاسم لا يستبعد صفاً سحابياً —
      // cloud_id هو أساس الاستبعاد للصفوف السحابية.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        cloudUserId: 'cloud-admin',
        sessionUuid: 'session-admin',
      );
      await repository.create(
        amount: 900,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      // زميل آخر يحمل الاسم نفسه تماماً لكنه مستخدم سحابي مختلف.
      PaymentSessionContext.start(
        userId: 2,
        userName: 'المدير',
        cloudUserId: 'cloud-manager-2',
        sessionUuid: 'session-manager-2',
      );
      await repository.create(
        amount: 400,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(
            hotelDay,
            excludedUserId: 1,
            excludedUserName: 'المدير',
            excludedUserCloudId: 'cloud-admin',
          )
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 2);
      expect(summaries.single.totalAmount, 400);
    },
  );

  test(
    'legacy receipt without session uuid counts toward the hotel-day total',
    () async {
      // ✅ (2026-09-15) «بحسب اليوم الفندقي فقط»: الجلسة ليست بُعد
      // تجميع في البطاقة — الإرث بلا session UUID (وغالباً بلا
      // hotel_day_key، فيُشمل بـ LIKE على payment_date) يُحسب
      // لمستلمه في يومه الفندقي ويدمج مع جلساته في سطر واحد.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        sessionUuid: 'session-admin',
      );

      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-employee',
      );
      await repository.create(
        amount: 500,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      // سجل إرث مباشر بلا جلسة وبلا hotel_day_key (قبل تفعيل الخيار A)
      // في نفس اليوم الفندقي — يُشمل عبر payment_date LIKE.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              localUuid: 'legacy-receipt-no-session',
              createdAt: nowMs,
              updatedAt: nowMs,
              lastModified: nowMs,
              amount: 300,
              paymentDate: paymentDate,
              paymentMethod: 'نقدي',
              revenueType: 'room',
              receivedByUserId: const Value(7),
              receivedByName: const Value('موظف الاستقبال'),
            ),
          );

      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(hotelDay, excludedUserId: 1)
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 7);
      expect(summaries.single.userName, 'موظف الاستقبال');
      expect(summaries.single.totalAmount, 800);
      expect(summaries.single.paymentCount, 2);
    },
  );

  // ✅ يقابل إصلاح d30f005c (fix hotel-day payment reporting) من فرع
  // guest-adjustment-edit-end: السجلات القديمة بلا مفتاح يوم فندقي
  // تُحتسب وفق حدّ 14:01 لا ببادئة التاريخ.
  test(
    'legacy receipts respect the 14:01 hotel-day boundary in all totals',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      PaymentSessionContext.start(
        userId: 9,
        userName: 'موظف الاستقبال',
        sessionUuid: 'hotel-day-boundary-session',
      );

      Future<void> addLegacyPayment(
        double amount,
        String paymentDate, {
        bool pending = false,
      }) async {
        final id = await repository.create(
          amount: amount,
          paymentDate: paymentDate,
          paymentMethod: 'نقدي',
          revenueType: 'room',
          isPendingBalance: pending,
        );
        final created = await (db.select(
          db.payments,
        )..where((payment) => payment.id.equals(id))).getSingle();
        expect(
          created.hotelDayKey,
          HotelTimeEngine.resolvePaymentHotelDayKey(
            storedHotelDayKey: null,
            paymentDate: paymentDate,
          ),
        );
        await (db.update(db.payments)
              ..where((payment) => payment.id.equals(id)))
            .write(const PaymentsCompanion(hotelDayKey: Value(null)));
      }

      await addLegacyPayment(7, '2026-08-21T14:00:59');
      await addLegacyPayment(5, '2026-08-21');
      await addLegacyPayment(20, '2026-08-21T14:01:00');
      await addLegacyPayment(10, '2026-08-22T08:00:00');
      await addLegacyPayment(30, '2026-08-22 14:00:59');
      await addLegacyPayment(70, '2026-08-22T14:01:00');
      await addLegacyPayment(100, '2026-08-21T15:00:00', pending: true);

      const hotelDay = '2026-08-21';
      expect(await repository.getTotalByHotelDayKey(hotelDay), 65);
      expect(await repository.watchTotalByHotelDayKey(hotelDay).first, 65);
      expect(
        await repository.dao
            .listFilteredByHotelDay(
              fromHotelDay: hotelDay,
              toHotelDay: hotelDay,
              excludeVoided: true,
              excludePendingBalance: true,
            )
            .then(
              (payments) =>
                  payments.fold<double>(0, (sum, p) => sum + p.amount),
            ),
        65,
      );
      final summaries = await repository
          .watchPaymentUserHotelDaySummaries(hotelDay)
          .first;
      expect(summaries.single.totalAmount, 65);
      expect(summaries.single.paymentCount, 4);
    },
  );

  // ✅ يقابل إصلاح eb9984e9 (hotel-day room receipt card) من فرع
  // guest-adjustment-edit-end: أحدث دفعة فعلية لكل غرفة ضمن اليوم الفندقي.
  test(
    'latest room receipts show the latest valid amount, room, and timestamp',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);

      Future<int> addReceipt({
        required int userId,
        required String roomNumber,
        required double amount,
        required String date,
        bool pending = false,
      }) async {
        PaymentSessionContext.start(
          userId: userId,
          userName: 'موظف $userId',
          sessionUuid: 'receipt-session-$userId',
        );
        return repository.create(
          amount: amount,
          paymentDate: date,
          paymentMethod: 'نقدي',
          revenueType: 'room',
          roomNumber: roomNumber,
          isPendingBalance: pending,
        );
      }

      await addReceipt(
        userId: 1,
        roomNumber: '301',
        amount: 15000,
        date: '2026-08-21T06:00:00',
      );
      final voidedReceiptId = await addReceipt(
        userId: 2,
        roomNumber: '301',
        amount: 20000,
        date: '2026-08-21T07:00:00',
      );
      await addReceipt(
        userId: 3,
        roomNumber: '301',
        amount: 50000,
        date: '2026-08-21T08:00:00',
        pending: true,
      );
      final deletedReceiptId = await addReceipt(
        userId: 5,
        roomNumber: '301',
        amount: 60000,
        date: '2026-08-21T08:30:00',
      );
      await addReceipt(
        userId: 4,
        roomNumber: '302',
        amount: 9000,
        date: '2026-08-21T05:30:00',
      );
      await addReceipt(
        userId: 6,
        roomNumber: '303',
        amount: 5000,
        date: '2026-08-21T14:00:59',
      );
      await addReceipt(
        userId: 7,
        roomNumber: '303',
        amount: 7000,
        date: '2026-08-21T14:01:00',
      );
      await (db.update(db.payments)
            ..where((payment) => payment.id.equals(voidedReceiptId)))
          .write(const PaymentsCompanion(isVoided: Value(true)));
      await (db.update(
        db.payments,
      )..where((payment) => payment.id.equals(deletedReceiptId))).write(
        PaymentsCompanion(
          deletedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ),
      );

      final receipts = await repository
          .watchLatestRoomReceiptsByRoom('2026-08-20')
          .first;
      final room301 = receipts.singleWhere(
        (receipt) => receipt.roomNumber == '301',
      );
      final room302 = receipts.singleWhere(
        (receipt) => receipt.roomNumber == '302',
      );
      final room303 = receipts.singleWhere(
        (receipt) => receipt.roomNumber == '303',
      );

      expect(room301.amount, 15000);
      expect(room301.paymentDate, '2026-08-21T06:00:00');
      expect(room302.amount, 9000);
      expect(room302.paymentDate, '2026-08-21T05:30:00');
      expect(room303.amount, 5000);
      expect(room303.paymentDate, '2026-08-21T14:00:59');

      final followingHotelDay = await repository
          .watchLatestRoomReceiptsByRoom('2026-08-21')
          .first;
      expect(followingHotelDay, hasLength(1));
      expect(followingHotelDay.single.roomNumber, '303');
      expect(followingHotelDay.single.amount, 7000);
      expect(followingHotelDay.single.paymentDate, '2026-08-21T14:01:00');
    },
  );
}
