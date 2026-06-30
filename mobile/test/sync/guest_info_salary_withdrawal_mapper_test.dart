// ignore_for_file: avoid_dynamic_calls, prefer_const_declarations, prefer_const_constructors, directives_ordering, no_leading_underscores_for_local_identifiers

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/payload_mapper.dart';

/// اختبارات PayloadMapper لـ guest_infos و salary_withdrawals
///
/// تستخدم Drift database في الذاكرة (NativeDatabase.memory()) لإنشاء
/// كائنات GuestInfo و SalaryWithdrawal حقيقية واختبار الـ mappers عليها.

void main() {
  late AppDatabase database;
  late PayloadMapper mapper;

  setUpAll(() {
    // إنشاء قاعدة بيانات في الذاكرة للاختبارات
    database = AppDatabase.forTesting(NativeDatabase.memory());
    mapper = const PayloadMapper();
  });

  tearDownAll(() async {
    await database.close();
  });

  // Helper: إنشاء موظف للربط مع salary_withdrawals
  Future<int> _createEmployee(String uuid, String name, int id) async {
    return database.into(database.employees).insert(
          EmployeesCompanion.insert(
            localUuid: uuid,
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
            version: drift.Value(1),
            origin: drift.Value('mobile'),
            vectorClock: drift.Value('{}'),
            deviceId: drift.Value('device-test'),
            id: drift.Value(id),
            name: name,
            basicSalary: 5000.0,
            status: 'active',
          ),
        );
  }

  group('guestInfoToRemote', () {
    test('returns all required sync fields', () async {
      final uuid = 'test-guest-uuid-001';
      final insertedId = await database.into(database.guestInfos).insert(
            GuestInfosCompanion.insert(
              localUuid: uuid,
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000100,
              version: drift.Value(1),
              origin: drift.Value('mobile'),
              vectorClock: drift.Value('{}'),
              deviceId: drift.Value('device-001'),
              roomNumber: '101',
              guestName: 'أحمد محمد',
              nationality: 'مصري',
              idNumber: '29801011234567',
              idType: drift.Value('بطاقة شخصية'),
            ),
          );
      final info = await (database.select(database.guestInfos)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.guestInfoToRemote(info);

      // ── Sync fields ──
      expect(payload['localUuid'], uuid);
      expect(payload['createdAt'], 1700000000);
      expect(payload['updatedAt'], 1700000000);
      expect(payload['lastModified'], 1700000100);
      expect(payload['version'], 1);
      expect(payload['origin'], 'mobile');
      expect(payload['sync_origin'], 'mobile');
      expect(payload['syncTimestamp'], isNotNull);
      expect(payload['vectorClock'], '{}');
      expect(payload['deviceId'], 'device-001');

      // ── Business fields ──
      expect(payload['roomNumber'], '101');
      expect(payload['guestName'], 'أحمد محمد');
      expect(payload['nationality'], 'مصري');
      expect(payload['idNumber'], '29801011234567');
      expect(payload['idType'], 'بطاقة شخصية');

      // serverId should be absent (null)
      expect(payload.containsKey('serverId'), isFalse);
    });

    test('includes optional fields when present', () async {
      final uuid = 'test-guest-uuid-002';
      final insertedId = await database.into(database.guestInfos).insert(
            GuestInfosCompanion.insert(
              localUuid: uuid,
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000100,
              version: drift.Value(1),
              origin: drift.Value('mobile'),
              vectorClock: drift.Value('{}'),
              deviceId: drift.Value('device-002'),
              roomNumber: '202',
              guestName: 'سامي علي',
              nationality: 'سعودي',
              idNumber: '1234567890',
              idType: drift.Value('إقامة'),
              issueDate: drift.Value('2020-01-15'),
              issuePlace: drift.Value('الرياض'),
              governorate: drift.Value('الرياض'),
              notes: drift.Value('ضيف VIP'),
            ),
          );
      final info = await (database.select(database.guestInfos)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.guestInfoToRemote(info);

      expect(payload['issueDate'], '2020-01-15');
      expect(payload['issuePlace'], 'الرياض');
      expect(payload['governorate'], 'الرياض');
      expect(payload['notes'], 'ضيف VIP');
    });

    test('omits optional fields when null', () async {
      final uuid = 'test-guest-uuid-003';
      final insertedId = await database.into(database.guestInfos).insert(
            GuestInfosCompanion.insert(
              localUuid: uuid,
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000100,
              version: drift.Value(1),
              origin: drift.Value('mobile'),
              vectorClock: drift.Value('{}'),
              deviceId: drift.Value('device-003'),
              roomNumber: '303',
              guestName: 'محمد أحمد',
              nationality: 'أردني',
              idNumber: '9876543210',
              idType: drift.Value('بطاقة شخصية'),
              // issueDate, issuePlace, governorate, notes = null
            ),
          );
      final info = await (database.select(database.guestInfos)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.guestInfoToRemote(info);

      // null optional fields should NOT be in the payload
      expect(payload.containsKey('issueDate'), isFalse);
      expect(payload.containsKey('issuePlace'), isFalse);
      expect(payload.containsKey('governorate'), isFalse);
      expect(payload.containsKey('notes'), isFalse);
    });
  });

  group('salaryWithdrawalToRemote', () {
    test('returns all required sync and business fields', () async {
      final empUuid = 'test-emp-uuid-001';
      final empId = await _createEmployee(empUuid, 'أحمد الموظف', 1);

      final swUuid = 'test-sw-uuid-001';
      final insertedId = await database.into(database.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: swUuid,
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000100,
              version: drift.Value(1),
              origin: drift.Value('mobile'),
              vectorClock: drift.Value('{}'),
              deviceId: drift.Value('device-001'),
              employeeId: empId,
              amount: 1500.0,
              withdrawDate: '2026-01-15',
            ),
          );
      final withdrawal = await (database.select(database.salaryWithdrawals)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.salaryWithdrawalToRemote(
        withdrawal,
        employeeUuid: empUuid,
      );

      // ── Sync fields ──
      expect(payload['localUuid'], swUuid);
      expect(payload['createdAt'], 1700000000);
      expect(payload['updatedAt'], 1700000000);
      expect(payload['lastModified'], 1700000100);
      expect(payload['version'], 1);
      expect(payload['origin'], 'mobile');
      expect(payload['sync_origin'], 'mobile');
      expect(payload['syncTimestamp'], isNotNull);
      expect(payload['vectorClock'], '{}');
      expect(payload['deviceId'], 'device-001');

      // ── Business fields ──
      expect(payload['employeeId'], empId);
      expect(payload['amount'], 1500); // rounded to int for Appwrite
      expect(payload['withdrawDate'], '2026-01-15');

      // ── Employee linking ──
      expect(payload['employeeUuid'], empUuid);
      expect(payload['employeeLocalUuid'], empUuid);

      // ── Legacy fields ──
      expect(payload['date'], '2026-01-15');
      expect(payload['action'], 'withdrawal');
      expect(payload['note'], '');
      expect(payload['name'], '');
    });

    test('includes optional fields when present', () async {
      final empUuid = 'test-emp-uuid-002';
      final empId = await _createEmployee(empUuid, 'سامي الموظف', 2);

      final swUuid = 'test-sw-uuid-002';
      final insertedId = await database.into(database.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: swUuid,
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000100,
              version: drift.Value(1),
              origin: drift.Value('mobile'),
              vectorClock: drift.Value('{}'),
              deviceId: drift.Value('device-002'),
              employeeId: empId,
              amount: 2000.0,
              withdrawDate: '2026-02-20',
              reason: drift.Value('exp_629'),
              hotelDayKey: drift.Value('2026-02-20'),
              withdrawalType: drift.Value('advance'),
              description: drift.Value('سلفة لظرف طارئ'),
            ),
          );
      final withdrawal = await (database.select(database.salaryWithdrawals)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.salaryWithdrawalToRemote(
        withdrawal,
        employeeUuid: empUuid,
      );

      expect(payload['reason'], 'exp_629');
      expect(payload['hotelDayKey'], '2026-02-20');
      expect(payload['withdrawalType'], 'advance');
      expect(payload['description'], 'سلفة لظرف طارئ');
      // legacy fields derived from model
      expect(payload['action'], 'advance');
      expect(payload['note'], 'سلفة لظرف طارئ');
    });

    test('handles empty withdrawDate with today fallback', () async {
      final empUuid = 'test-emp-uuid-003';
      final empId = await _createEmployee(empUuid, 'محمد الموظف', 3);

      final swUuid = 'test-sw-uuid-003';
      final insertedId = await database.into(database.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: swUuid,
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000100,
              version: drift.Value(1),
              origin: drift.Value('mobile'),
              vectorClock: drift.Value('{}'),
              deviceId: drift.Value('device-003'),
              employeeId: empId,
              amount: 500.0,
              withdrawDate: '', // empty — should fallback to today
            ),
          );
      final withdrawal = await (database.select(database.salaryWithdrawals)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.salaryWithdrawalToRemote(withdrawal);

      // Both withdrawDate and date should be today's date (YYYY-MM-DD)
      final today = DateTime.now().toIso8601String().split('T').first;
      expect(payload['withdrawDate'], today);
      expect(payload['date'], today);
    });

    test('omits employeeUuid when not provided', () async {
      final empUuid = 'test-emp-uuid-004';
      final empId = await _createEmployee(empUuid, 'علي الموظف', 4);

      final swUuid = 'test-sw-uuid-004';
      final insertedId = await database.into(database.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: swUuid,
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000100,
              version: drift.Value(1),
              origin: drift.Value('mobile'),
              vectorClock: drift.Value('{}'),
              deviceId: drift.Value('device-004'),
              employeeId: empId,
              amount: 1000.0,
              withdrawDate: '2026-03-01',
            ),
          );
      final withdrawal = await (database.select(database.salaryWithdrawals)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.salaryWithdrawalToRemote(withdrawal);

      // employeeUuid should be absent when not provided
      expect(payload.containsKey('employeeUuid'), isFalse);
      expect(payload.containsKey('employeeLocalUuid'), isFalse);
    });
  });
}
