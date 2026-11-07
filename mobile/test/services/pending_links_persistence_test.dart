// اختبارات PR-5 (وثيقة الربط §8.1): السجل غير المحلول لا يُفقد.
//  1) تخطّي سجل مالي لأن أباه غير موجود ⇒ الحمولة تُحفظ في pending_links
//     وتعود النتيجة -2 (تخطٍّ بحفظ دائم) لا -1.
//  2) بعد وصول الأب: retryPendingLinks يُدخل السجل من الحمولة المحفوظة
//     (لا صف موجود ليُحدَّث) ويحذف صف المعلّق.
//  3) بلا reapply: لا نجاح كاذب — يبقى الصف المعلّق.

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/local_link_resolver.dart';
import 'package:marina_hotel_mobile/services/repositories/base_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AdapterRegistry registry;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registry = AdapterRegistry.testing(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> withdrawalJson({String employeeUuid = 'emp-missing'}) =>
      {
        'localUuid': 'sw-1',
        'employeeUuid': employeeUuid,
        'employeeId': 42,
        'amount': 1200,
        'withdrawDate': '2026-11-01',
        'reason': 'سحب راتب',
        'createdAt': 1000,
        'lastModified': 1000,
        'version': 1,
      };

  Future<List<Map<String, Object?>>> pendingRows() async {
    final rows = await db
        .customSelect(
          'SELECT entity, local_uuid, missing_kind, missing_uuid, '
          'payload_json FROM pending_links',
          readsFrom: const {},
        )
        .get();
    return rows.map((r) => r.data).toList();
  }

  test('تخطّي الأب المفقود يحفظ الحمولة ويعيد -2 (لا -1)', () async {
    final result = await registry.salaryWithdrawals.upsertFromJson(
      withdrawalJson(),
      src: Source.appwrite,
    );

    expect(result, BaseRepository.deferredPersisted);
    expect(result, isNot(-1));

    final rows = await pendingRows();
    expect(rows, hasLength(1));
    expect(rows.single['entity'], 'salary_withdrawal');
    expect(rows.single['local_uuid'], 'sw-1');
    expect(rows.single['missing_kind'], 'employee_uuid');
    expect(rows.single['missing_uuid'], 'emp-missing');
    expect('${rows.single['payload_json']}', contains('"amount":1200'));
  });

  test('سجل غير قابل للحل لاحقاً يبقى -1 (لا صف معلّق بلا مفتاح)', () async {
    // بلا employeeUuid: لا يمكن معرفة الأب المفقود ⇒ لا pending link.
    final json = withdrawalJson()..remove('employeeUuid');
    final result = await registry.salaryWithdrawals.upsertFromJson(
      json,
      src: Source.appwrite,
    );
    expect(result, -1);
    expect(await pendingRows(), isEmpty);
  });

  test('بعد وصول الموظف: retry يُدخل السجل من الحمولة المحفوظة', () async {
    await registry.salaryWithdrawals.upsertFromJson(
      withdrawalJson(),
      src: Source.appwrite,
    );
    expect(await pendingRows(), hasLength(1));

    // الموظف يصل لاحقاً (كما في سحب الموظفين قبل السحوبات).
    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: 'موظف',
            basicSalary: 5000,
            status: 'active',
            localUuid: 'emp-missing',
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
          ),
        );

    final resolver = LocalLinkResolver(db);
    final resolved = await resolver.retryPendingLinks(
      reapply: (entity, payload) async {
        expect(entity, 'salary_withdrawal');
        final id = await registry.salaryWithdrawals.upsertFromJson(
          Map<String, dynamic>.from(payload),
          src: Source.appwrite,
        );
        return id >= 0;
      },
    );

    expect(resolved, 1);
    expect(await pendingRows(), isEmpty);

    final inserted = await db
        .customSelect(
          'SELECT employee_uuid, amount FROM salary_withdrawals '
          'WHERE local_uuid = ?',
          variables: [Variable.withString('sw-1')],
          readsFrom: const {},
        )
        .get();
    expect(inserted, hasLength(1));
    expect(inserted.single.data['employee_uuid'], 'emp-missing');
    expect(inserted.single.data['amount'], 1200.0);
  });

  test('بلا reapply لا يُعلن الربط نجاحاً كاذباً', () async {
    await registry.salaryWithdrawals.upsertFromJson(
      withdrawalJson(),
      src: Source.appwrite,
    );

    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: 'موظف',
            basicSalary: 5000,
            status: 'active',
            localUuid: 'emp-missing',
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
          ),
        );

    final resolved = await LocalLinkResolver(db).retryPendingLinks();
    expect(resolved, 0);
    expect(await pendingRows(), hasLength(1), reason: 'يبقى للمراجعة');
  });
}
