import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/blacklist_repository.dart';
import 'package:marina_hotel_mobile/services/search/global_search_service.dart';
import 'package:marina_hotel_mobile/utils/arabic_query.dart';

/// ✅ (2026-09-22) عقود خدمة البحث الشامل — كل عقد يطابق واقعة بيانات
/// حقيقية موثقة في تشخيص المراجعة:
/// - soft-delete: السجل المحذوف لا يظهر أبداً إلا بتدقيق المدير.
/// - الهمزات/التشكيل/ه-ة/ى-ي: التوسيع الأحادي الموضعي يغطيها.
/// - المبالغ: المدخل الرقمي المفرد يطابق بالمساواة.
/// - المدفوعات الملغاة/المعلقة: مستبعدة افتراضاضاً كعقد التقارير.
/// - نطاق اليوم الفندقي: hdk أولاً مع سقوط تاريخي ISO.
/// - الصلاحيات: النوع غير المسموح لا يُبحث إطلاقاً.
void main() {
  const nowSec = 1770000000;

  Future<AppDatabase> buildDb() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  GlobalSearchService serviceFor(AppDatabase db, {Set<String>? keys}) =>
      GlobalSearchService(db, allowedPermissionKeys: keys);

  /// ضامن وجود الغرفة — bookings.roomNumber يحمل FK إلى rooms
  Future<void> ensureRoom(AppDatabase db, String room) async {
    final existing = await (db.select(
      db.rooms,
    )..where((r) => r.roomNumber.equals(room))).getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-$room',
              createdAt: nowSec,
              updatedAt: nowSec,
              lastModified: nowSec,
              roomNumber: room,
              type: 'مزدوجة',
              price: 15000,
              status: 'شاغرة',
            ),
          );
    }
  }

  Future<int> insertBooking(
    AppDatabase db,
    String guestName, {
    String room = '101',
    String phone = '777123456',
    String idNumber = '010123456',
    String checkin = '2026-09-01',
    String? checkout,
    String status = 'محجوزة',
    String? notes,
    int? deletedAt,
  }) async {
    await ensureRoom(db, room);
    return db
        .into(db.bookings)
        .insert(
          BookingsCompanion.insert(
            localUuid: 'bk-${guestName.hashCode}-$room-$checkin',
            createdAt: nowSec,
            updatedAt: nowSec,
            lastModified: nowSec,
            roomNumber: room,
            guestName: guestName,
            guestPhone: phone,
            guestIdNumber: Value(idNumber),
            guestNationality: 'يمني',
            checkinDate: checkin,
            checkoutDate: Value(checkout),
            status: status,
            notes: Value(notes),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<int> insertExpense(
    AppDatabase db,
    String description,
    double amount, {
    String date = '2026-09-10',
    String? hotelDayKey,
    int? deletedAt,
  }) async {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            localUuid: 'exp-$description-$date-$amount',
            createdAt: nowSec,
            updatedAt: nowSec,
            lastModified: nowSec,
            expenseType: 'صيانة',
            description: description,
            amount: amount,
            date: date,
            hotelDayKey: Value(hotelDayKey ?? date),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<int> insertPayment(
    AppDatabase db,
    double amount, {
    String paymentDate = '2026-09-10T15:30:00',
    String? hotelDayKey,
    String room = '101',
    bool isVoided = false,
    bool isPendingBalance = false,
    int? deletedAt,
  }) async {
    return db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            localUuid: 'pay-$amount-$paymentDate-$room',
            createdAt: nowSec,
            updatedAt: nowSec,
            lastModified: nowSec,
            amount: amount,
            paymentDate: paymentDate,
            paymentMethod: 'نقدي',
            revenueType: 'room',
            hotelDayKey: Value(hotelDayKey ?? paymentDate.substring(0, 10)),
            roomNumber: Value(room),
            isVoided: Value(isVoided),
            isPendingBalance: Value(isPendingBalance),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<int> insertEmployee(
    AppDatabase db,
    String name, {
    String position = 'كهربائي',
    String status = 'نشط',
    int? deletedAt,
  }) async {
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            localUuid: 'emp-$name',
            createdAt: nowSec,
            updatedAt: nowSec,
            lastModified: nowSec,
            name: name,
            basicSalary: 80000,
            status: status,
            position: Value(position),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  group('عقود أداة الاستعلام العربي', () {
    test('التطبيع: تشكيل وتطويل وهمزات وة→ه', () {
      expect(normalizeArabicForSearch('أَحْـــمد'), 'احمد');
      expect(normalizeArabicForSearch('جميلة'), 'جميله');
      expect(normalizeArabicForSearch('يحيى'), 'يحيي');
      expect(normalizeArabicForSearch('مؤمن'), 'مومن');
    });

    test('التوسيع: كلمة بألف تشمل كل أشكال الهمزة والألف المقصورة', () {
      final variants = expandArabicVariants('احمد');
      expect(variants, containsAll(['احمد', 'أحمد', 'إحمد', 'آحمد', 'ىحمد']));
    });

    test('التوسيع: يحيي يغطي يحيى المحزنة فعلاً', () {
      expect(expandArabicVariants('يحيي'), contains('يحيى'));
    });

    test('قراءة المبالغ: أرقام عربية وفواصل، ورفض المختلط', () {
      expect(tryParseAmount('40000'), 40000);
      expect(tryParseAmount('40,000'), 40000);
      expect(tryParseAmount('٤٠٠٠٠'), 40000);
      expect(tryParseAmount('أحمد'), isNull);
      expect(tryParseAmount('123abc'), isNull);
    });
  });

  group('عقود خدمة البحث الشامل', () {
    test('عقد soft-delete: المحذوف لا يظهر إلا بتدقيق المدير', () async {
      final db = await buildDb();
      await insertExpense(db, 'صيانة مولد الفندق', 40000);
      await insertExpense(
        db,
        'صيانة مولد قديم',
        5000,
        deletedAt: nowSec,
      );
      final service = serviceFor(db);

      final alive = await service.search(
        const GlobalSearchQuery(text: 'مولد'),
      );
      expect(alive.totals[SearchEntityKind.expense], 1);

      final audited = await service.search(
        const GlobalSearchQuery(text: 'مولد', includeDeleted: true),
      );
      expect(audited.totals[SearchEntityKind.expense], 2);
    });

    test('عقد الهمزات: «احمد» تجد «أحمد» المخزنة', () async {
      final db = await buildDb();
      await insertBooking(db, 'أحمد الشرعبي');
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: 'احمد'),
      );
      expect(result.totals[SearchEntityKind.booking], 1);
      final hit = result.hits[SearchEntityKind.booking]!.single;
      expect(hit.matchedFields, contains('اسم النزيل'));
    });

    test('عقد الهمزات العكسي: «أحمد» تجد «احمد» المخزنة', () async {
      final db = await buildDb();
      await insertEmployee(db, 'احمد عبدالله');
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: 'أحمد'),
      );
      expect(result.totals[SearchEntityKind.employee], 1);
    });

    test('عقد ه/ة: «جميلة» تجد «جميله» المخزنة', () async {
      final db = await buildDb();
      await insertEmployee(db, 'جميله', position: 'عاملة نظافة');
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: 'جميلة'),
      );
      expect(result.totals[SearchEntityKind.employee], 1);
    });

    test('عقد ى/ي: «مصطفى» تجد «مصطفي» المخزنة', () async {
      final db = await buildDb();
      await insertBooking(db, 'مصطفي سعيد');
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: 'مصطفى'),
      );
      expect(result.totals[SearchEntityKind.booking], 1);
    });

    test('عقد الكلمات المتعددة: AND دلالي', () async {
      final db = await buildDb();
      await insertBooking(db, 'محمد احمد');
      final service = serviceFor(db);

      final both = await service.search(
        const GlobalSearchQuery(text: 'محمد احمد'),
      );
      expect(both.totals[SearchEntityKind.booking], 1);

      final absent = await service.search(
        const GlobalSearchQuery(text: 'محمد علي'),
      );
      expect(absent.totals[SearchEntityKind.booking] ?? 0, 0);
    });

    test('عقد المبلغ: «40000» يجد المصروف والدفعة والسحبية لا غيرها', () async {
      final db = await buildDb();
      await insertExpense(db, 'صيانة مولد', 40000);
      await insertExpense(db, 'قهوة الضيافة', 4000);
      await insertPayment(db, 40000);
      await insertPayment(db, 30000);
      final empId = await insertEmployee(db, 'عبدالله نصار');
      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: 'wd-40000',
              createdAt: nowSec,
              updatedAt: nowSec,
              lastModified: nowSec,
              employeeId: empId,
              amount: 40000,
              withdrawDate: '2026-09-10',
              hotelDayKey: const Value('2026-09-10'),
            ),
          );
      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: 'wd-9000',
              createdAt: nowSec,
              updatedAt: nowSec,
              lastModified: nowSec,
              employeeId: empId,
              amount: 9000,
              withdrawDate: '2026-09-11',
              hotelDayKey: const Value('2026-09-11'),
            ),
          );
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: '40000'),
      );
      expect(result.totals[SearchEntityKind.expense], 1);
      expect(result.totals[SearchEntityKind.payment], 1);
      expect(result.totals[SearchEntityKind.withdrawal], 1);
      expect(
        result.hits[SearchEntityKind.withdrawal]!.single.matchedFields,
        contains('المبلغ'),
      );
    });

    test('عقد رقم الحجز: «#3» و«000003» يجدان الحجز 3', () async {
      final db = await buildDb();
      final id = await insertBooking(db, 'سالم ناجي');
      final service = serviceFor(db);

      final byHash = await service.search(
        GlobalSearchQuery(text: '#$id'),
      );
      expect(byHash.totals[SearchEntityKind.booking], 1);
      expect(
        byHash.hits[SearchEntityKind.booking]!.single.matchedFields,
        contains('رقم الحجز'),
      );

      final byPadded = await service.search(
        GlobalSearchQuery(text: id.toString().padLeft(6, '0')),
      );
      expect(byPadded.totals[SearchEntityKind.booking], 1);
    });

    test('عقد الصلاحيات: النوع غير المسموح لا يُبحث', () async {
      final db = await buildDb();
      await insertBooking(db, 'أحمد الشرعبي');
      await insertExpense(db, 'صيانة مولد', 40000);
      await insertPayment(db, 50000);
      final service = serviceFor(db, keys: {'bookings'});

      expect(service.allowedKinds, contains(SearchEntityKind.booking));
      expect(
        service.allowedKinds,
        isNot(contains(SearchEntityKind.expense)),
      );

      final result = await service.search(
        const GlobalSearchQuery(text: 'مولد'),
      );
      expect(result.totals.isEmpty, isTrue);
      // وتصفية kinds بطلب غير مسموح لا تُنفَّذ
      final hijack = await service.search(
        const GlobalSearchQuery(
          text: 'مولد',
          kinds: {SearchEntityKind.expense},
        ),
      );
      expect(hijack.totals.isEmpty, isTrue);
    });

    test('عقد المدفوعات: الملغاة والمعلقة مستبعدة إلا بطلب المدير', () async {
      final db = await buildDb();
      await insertPayment(
        db,
        10000,
        isVoided: true,
        room: '201',
      );
      await insertPayment(
        db,
        20000,
        isPendingBalance: true,
        room: '202',
      );
      await insertPayment(db, 30000, room: '203');
      final service = serviceFor(db);

      // الملغاة (10000) مستبعدة افتراضياً كعقد التقارير المالية
      final byAmount = await service.search(
        const GlobalSearchQuery(text: '10000'),
      );
      expect(byAmount.totals[SearchEntityKind.payment] ?? 0, 0);

      // بتدقيق المدير تظهر
      final audited = await service.search(
        const GlobalSearchQuery(
          text: '10000',
          includeInactivePayments: true,
        ),
      );
      expect(audited.totals[SearchEntityKind.payment], 1);

      // والسليمة (30000) تظهر دائماً
      final healthy = await service.search(
        const GlobalSearchQuery(text: '30000'),
      );
      expect(healthy.totals[SearchEntityKind.payment], 1);
    });

    test('عقد النطاق الفندقي: hdk أولاً', () async {
      final db = await buildDb();
      await insertPayment(db, 1000, paymentDate: '2026-09-05T10:00:00');
      await insertPayment(db, 2000, paymentDate: '2026-08-15T10:00:00');
      final service = serviceFor(db);

      // البحث بطريقة الدفع (حقل فعلي) مع حصر سبتمبر
      final september = await service.search(
        const GlobalSearchQuery(
          text: 'نقدي',
          fromDay: '2026-09-01',
          toDay: '2026-09-30',
        ),
      );
      expect(september.totals[SearchEntityKind.payment], 1);
      expect(
        september.hits[SearchEntityKind.payment]!.single.amount,
        1000,
      );
    });

    test('عقد النطاق الفندقي: السقوط التاريخي لصفوف hdk=NULL', () async {
      final db = await buildDb();
      await insertPayment(
        db,
        3000,
        paymentDate: '2026-09-05T23:00:00',
        hotelDayKey: null,
      );
      await insertPayment(
        db,
        4000,
        paymentDate: '2026-08-05T10:00:00',
        hotelDayKey: null,
      );
      final service = serviceFor(db);

      final september = await service.search(
        const GlobalSearchQuery(
          text: '3000',
          fromDay: '2026-09-01',
          toDay: '2026-09-30',
        ),
      );
      expect(september.totals[SearchEntityKind.payment], 1);
    });

    test('عقد السحبيات: البحث باسم الموظف يجد سحبياته', () async {
      final db = await buildDb();
      final empId = await insertEmployee(db, 'عبدالله نصار');
      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: 'wd-nassar',
              createdAt: nowSec,
              updatedAt: nowSec,
              lastModified: nowSec,
              employeeId: empId,
              amount: 6000,
              withdrawDate: '2026-09-12',
              hotelDayKey: const Value('2026-09-12'),
            ),
          );
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: 'نصار'),
      );
      expect(result.totals[SearchEntityKind.withdrawal], 1);
      expect(
        result.hits[SearchEntityKind.withdrawal]!.single.title,
        'عبدالله نصار',
      );
      expect(
        result.hits[SearchEntityKind.withdrawal]!.single.matchedFields,
        contains('اسم الموظف'),
      );
    });

    test('عقد القائمة السوداء: بالاسم ورقم الهوية', () async {
      final db = await buildDb();
      await BlacklistRepository(db).addEntry(
        name: 'سالم مطلوب',
        nationalId: '9988776',
        reason: 'هارب',
      );
      final service = serviceFor(db);

      final byName = await service.search(
        const GlobalSearchQuery(text: 'سالم'),
      );
      expect(byName.totals[SearchEntityKind.blacklist], 1);

      final byId = await service.search(
        const GlobalSearchQuery(text: '9988776'),
      );
      expect(byId.totals[SearchEntityKind.blacklist], 1);
    });

    test('عقد السقف: العرض محدود والإجمالي صادق', () async {
      final db = await buildDb();
      for (var i = 0; i < 20; i++) {
        await insertExpense(db, 'قهوة ضيافة رقم $i', 1000.0 + i);
      }
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: 'قهوة'),
      );
      expect(
        result.hits[SearchEntityKind.expense]!.length,
        GlobalSearchService.maxHitsPerKind,
      );
      expect(result.totals[SearchEntityKind.expense], 20);
    });

    test('عقد بطاقات الضيوف: البحث برقم الهوية الجزئي', () async {
      final db = await buildDb();
      await db
          .into(db.guestInfos)
          .insert(
            GuestInfosCompanion.insert(
              localUuid: 'gi-1',
              createdAt: nowSec,
              updatedAt: nowSec,
              lastModified: nowSec,
              roomNumber: '105',
              guestName: 'فارس العولقي',
              nationality: 'يمني',
              idNumber: '0304556778',
            ),
          );
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: '455677'),
      );
      expect(result.totals[SearchEntityKind.guestInfo], 1);
      expect(
        result.hits[SearchEntityKind.guestInfo]!.single.matchedFields,
        contains('رقم الهوية'),
      );
    });

    test('عقد الاستعلام الفارغ: لا نتائج بلا أخطاء', () async {
      final db = await buildDb();
      await insertBooking(db, 'أحمد');
      final service = serviceFor(db);

      final result = await service.search(
        const GlobalSearchQuery(text: '   '),
      );
      expect(result.isEmpty, isTrue);
      expect(result.totalHits, 0);
    });
  });
}
