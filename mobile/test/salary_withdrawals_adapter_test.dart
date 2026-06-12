import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

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

  group('SalaryWithdrawalsAdapter', () {
    test('round-trip from Appwrite with existing employee', () async {
      // ترتيب: إنشاء موظف في القاعدة
      final empUuid = 'emp-uuid-sw-1';
      await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: d.Value(empUuid),
        name: const d.Value('أحمد موظف'),
        phone: const d.Value('0500000010'),
        jobTitle: const d.Value('موظف استقبال'),
        salary: const d.Value(3000.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      // تنفيذ: محاكاة سحب سحب راتب من Appwrite
      final json = {
        'localUuid': 'sw-1',
        'employeeId': 1,
        'amount': 500.0,
        'withdrawalDate': '2025-06-10',
        'reason': 'سحب عاجل',
        'createdAt': 2000,
        'lastModified': 2000,
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

      // التحقق: تم إدراج سحب الراتب بنجاح
      final row = await db.select(db.salaryWithdrawals).getSingle();
      expect(row.localUuid, equals('sw-1'));
      expect(row.amount, equals(500.0));
      expect(row.reason, equals('سحب عاجل'));
    });

    test('resolveRefs with employeeUuid resolves correctly', () async {
      final empUuid = 'emp-uuid-sw-2';
      await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: d.Value(empUuid),
        name: const d.Value('محمد موظف'),
        phone: const d.Value('0500000011'),
        jobTitle: const d.Value('مدير'),
        salary: const d.Value(5000.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final json = {
        'localUuid': 'sw-2',
        'employeeUuid': empUuid,
        'amount': 1000.0,
        'withdrawalDate': '2025-06-15',
        'reason': 'راتب',
        'createdAt': 3000,
        'lastModified': 3000,
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
      expect(row.localUuid, equals('sw-2'));
      expect(row.amount, equals(1000.0));
    });

    test('round-trip to Appwrite (camelCase keys)', () async {
      final empUuid = 'emp-uuid-sw-3';
      await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: d.Value(empUuid),
        name: const d.Value('علي موظف'),
        phone: const d.Value('0500000012'),
        jobTitle: const d.Value('موظف صيانة'),
        salary: const d.Value(2500.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      // إدراج سحب راتب أولاً
      final json = {
        'localUuid': 'sw-3',
        'employeeId': 1,
        'amount': 750.0,
        'withdrawalDate': '2025-06-20',
        'reason': 'مستعجل',
        'createdAt': 4000,
        'lastModified': 4000,
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

      // round-trip: تحويل إلى JSON للتطبيق
      final row = await db.select(db.salaryWithdrawals).getSingle();
      final out = adapters.salaryWithdrawals.toJsonForSource(row, src: Source.appwrite);

      expect(out['localUuid'], equals('sw-3'));
      expect(out.containsKey('employeeUuid') || out.containsKey('employeeLocalUuid'), isTrue);
    });

    test('drive source uses snake_case keys', () async {
      final empUuid = 'emp-uuid-sw-4';
      await db.into(db.employees).insert(EmployeesCompanion(
        localUuid: d.Value(empUuid),
        name: const d.Value('سامي موظف'),
        phone: const d.Value('0500000013'),
        jobTitle: const d.Value('موظف'),
        salary: const d.Value(3000.0),
        status: const d.Value('active'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final json = {
        'local_uuid': 'sw-4',
        'employee_id': 1,
        'amount': 2000.0,
        'withdrawal_date': '2025-06-25',
        'reason': 'دفعة',
        'created_at': 5000,
        'last_modified': 5000,
      };

      final refs = await adapters.salaryWithdrawals.adapter.resolveRefs(
        db,
        json,
        src: Source.drive,
      );
      final comp = adapters.salaryWithdrawals.adapter.fromJson(
        json,
        src: Source.drive,
        refs: refs,
      );
      await db.into(db.salaryWithdrawals).insert(comp);

      final row = await db.select(db.salaryWithdrawals).getSingle();
      final out = adapters.salaryWithdrawals.toJsonForSource(row, src: Source.drive);

      expect(out['local_uuid'], equals('sw-4'));
      expect(out['amount'], equals(2000.0));
    });
  });
}
