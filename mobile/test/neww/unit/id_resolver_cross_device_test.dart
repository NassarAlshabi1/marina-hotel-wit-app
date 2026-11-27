// ✅ (2026-09-02) اختبارات حسم دلالات حل FK الموظف/الدورة عبر الأجهزة.
//
// الخلفية (تحذيرات salary_withdrawal "الموظف غير موجود محلياً" على جهاز
// جديد): المحلل كان يطابق employeeId البعيد (id جهاز المصدر) مع e.id
// المحلي (autoIncrement بترتيب عشوائي دلالياً بعد إزالة id في
// base_repository) — ربط خاطئ صامت أو تخطٍّ. القرار المعتمد في الكود
// (resolveBooking، expenses_adapter، توثيق _syncEmployees): عبر الأجهزة
// يُحل المرجع بـ UUID ثم serverId فقط.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late IdResolver resolver;

  setUp(() {
    db = TestDatabase.create();
    resolver = IdResolver(db);
  });

  tearDown(() async => db.close());

  Future<Employee> insertEmployee({
    required String localUuid,
    required String name,
    int? serverId,
    int? deletedAt,
  }) {
    return db
        .into(db.employees)
        .insertReturning(
          EmployeesCompanion.insert(
            localUuid: localUuid,
            name: name,
            basicSalary: 0,
            status: 'active',
            serverId: Value(serverId),
            deletedAt: Value(deletedAt),
            createdAt: 0,
            updatedAt: 0,
            lastModified: 0,
          ),
        );
  }

  group('resolveEmployee — من مصدر بعيد (fromRemote=true)', () {
    test('يحل عبر employeeUuid (الطريقة 1) بالصيغة القياسية', () async {
      final e = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001',
        name: 'موظف أول',
        serverId: 7,
      );
      final got = await resolver.resolveEmployee(
        uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001',
        serverId: 99,
        fromRemote: true,
      );
      expect(got, e.id);
    });

    test('يحل عبر employeeUuid بصيغة 32 حرفاً بدون شرطات', () async {
      final e = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0002',
        name: 'موظف ثانٍ',
        serverId: 8,
      );
      final got = await resolver.resolveEmployee(
        uuid: 'aaaaaaaabbbbccccddddeeeeffff0002',
        fromRemote: true,
      );
      expect(got, e.id);
    });

    test('يحل عبر serverId عندما لا يوجد uuid (payload قديم)', () async {
      final e = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0003',
        name: 'موظف ثالث',
        serverId: 12,
      );
      final got = await resolver.resolveEmployee(
        serverId: 12,
        fromRemote: true,
      );
      expect(got, e.id);
    });

    test(
      'لا يطابق employeeId البعيد مع e.id المحلي (منع الربط الخاطئ عبر الأجهزة)',
      () async {
        // موظف محلي id=1 لكن serverId=5 — مرجع بعيد employeeId=1 يشير
        // (دلالياً) إلى موظف آخر على جهاز المصدر وليس لهذا الموظف.
        await insertEmployee(
          localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0004',
          name: 'موظف محلي مختلف',
          serverId: 5,
        );
        final got = await resolver.resolveEmployee(
          localId: 1,
          employeeId: 1,
          fromRemote: true,
        );
        expect(
          got,
          isNull,
          reason: 'المطابقة بالـ id المحلي محظورة للمصادر البعيدة',
        );
      },
    );

    test('serverId مكرر (خطأ بيانات): يختار النشط أولاً بشكل حتمي', () async {
      final active = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0005',
        name: 'النشط',
        serverId: 1,
      );
      final deleted = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0006',
        name: 'المحذوف',
        serverId: 1,
        deletedAt: 1783994438,
      );
      final got = await resolver.resolveEmployee(serverId: 1, fromRemote: true);
      expect(got, active.id, reason: 'النشط (deletedAt NULL) يسبق المحذوف');
      expect(deleted.id, isNot(got));
    });

    test('serverId مكرر وكلاهما نشط: يختار الأصغر id حتماً', () async {
      final first = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0007',
        name: 'الأول',
        serverId: 2,
      );
      final second = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0008',
        name: 'الثاني',
        serverId: 2,
      );
      final got = await resolver.resolveEmployee(serverId: 2, fromRemote: true);
      expect(got, first.id < second.id ? first.id : second.id);
    });
  });

  group('resolveEmployee — من مصدر محلي (fromRemote=false)', () {
    test('يحل عبر localId (id المحلي صحيح الدلالة على نفس الجهاز)', () async {
      final e = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0009',
        name: 'محلي',
      );
      final got = await resolver.resolveEmployee(localId: e.id);
      expect(got, e.id);
    });
  });

  group('resolveSalaryCycle', () {
    Future<int> insertCycle({
      required String localUuid,
      required int employeeId,
      int? serverId,
      int? deletedAt,
    }) {
      return db
          .into(db.salaryCycles)
          .insert(
            SalaryCyclesCompanion.insert(
              localUuid: localUuid,
              employeeId: employeeId,
              cycleKey: '2026-08',
              serverId: Value(serverId),
              deletedAt: Value(deletedAt),
              createdAt: 0,
              updatedAt: 0,
              lastModified: 0,
            ),
          );
    }

    test(
      'fromRemote=true: يحل عبر serverId ولا يحل عبر localId البعيد',
      () async {
        final emp = await insertEmployee(
          localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff000a',
          name: 'دورات',
          serverId: 3,
        );
        final cycle = await insertCycle(
          localUuid: 'bbbbbbbb-cccc-dddd-eeee-ffff00000001',
          employeeId: emp.id,
          serverId: 42,
        );
        expect(
          await resolver.resolveSalaryCycle(serverId: 42, fromRemote: true),
          cycle,
        );
        expect(
          await resolver.resolveSalaryCycle(localId: cycle, fromRemote: true),
          isNull,
          reason: 'id الدورة المحلي قد يصادف cycleId جهازاً آخر — محظور',
        );
      },
    );

    test('fromRemote=false: يحل عبر localId', () async {
      final emp = await insertEmployee(
        localUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff000b',
        name: 'دورات ٢',
        serverId: 4,
      );
      final cycle = await insertCycle(
        localUuid: 'bbbbbbbb-cccc-dddd-eeee-ffff00000002',
        employeeId: emp.id,
      );
      expect(await resolver.resolveSalaryCycle(localId: cycle), cycle);
    });
  });

  group('buildFullSyncQueries + entityNeedsTombstoneParents', () {
    test(
      'includeTombstones=true يلغي فلتر tombstones (سحب الآباء المرجعية)',
      () {
        expect(
          SyncPullService.buildFullSyncQueries(includeTombstones: true),
          isEmpty,
        );
      },
    );

    test('employees كيان أب مرجعي — tombstones تُسحب', () {
      expect(SyncPullService.entityNeedsTombstoneParents('employees'), isTrue);
    });

    test('بقية الكيانات تبقى مع فلتر استبعاد tombstones', () {
      for (final entity in const [
        'salary_withdrawals',
        'salary_cycles',
        'salary_payments',
        'bookings',
        'rooms',
      ]) {
        expect(
          SyncPullService.entityNeedsTombstoneParents(entity),
          isFalse,
          reason: '$entity ليس كياناً أباً مرجعياً',
        );
      }
      final queries = SyncPullService.buildFullSyncQueries();
      expect(queries, hasLength(1));
      expect(queries.single, contains('deletedAt'));
    });
  });
}
