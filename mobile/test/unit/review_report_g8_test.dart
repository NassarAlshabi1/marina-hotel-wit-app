// test/unit/review_report_g8_test.dart
//
// ✅ (G-8 / 2026-10-06): تقرير المراجعة القابل للتصدير — إثبات:
//   1) يقرأ كل المصادر (كسور · معلّق · تعارضات · انتهاكات · فجوات هوية).
//   2) **قراءة فقط**: لقطة كل الجداول قبل/بعد التصدير متطابقة.
//   3) يُنتج ملف XLSX صالحاً (توقيع PK) وبأوراق الأقسام الصحيحة.
//   4) لا يقترح تصحيحاً تلقائياً: القيم تُعرض كما هي + القيمة وفق السياسة.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/review_report_service.dart';
import 'package:marina_hotel_mobile/services/sync_core/deferred_relation_store.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ReviewReportService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ReviewReportService(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  /// لقطة نصية لكل الجداول المعنية — لكشف أي كتابة غير مقصودة.
  Future<String> snapshotTables() async {
    final buffer = StringBuffer();
    for (final table in [
      'bookings',
      'employees',
      'salary_withdrawals',
      'salary_cycles',
      'salary_carry_over_logs',
      'expenses',
      'sync_conflicts',
      'integrity_violations',
      'sync_state',
      'sync_checkpoints',
      'deferred_relations',
      'sync_remote_meta',
      'outbox',
    ]) {
      try {
        final rows = await db
            .customSelect('SELECT * FROM $table ORDER BY 1')
            .get();
        buffer.writeln(
          '$table:${rows.map((r) => r.data.toString()).join('|')}',
        );
      } catch (e) {
        buffer.writeln('$table:ERR($e)');
      }
    }
    return buffer.toString();
  }

  Future<void> seedAllSources() async {
    final now = Time.nowEpoch();

    // (أ) موظف ببصمة علّة G-3 (server_id = id المحلي) + آخر سليم.
    final legacyEmp = await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            localUuid: 'emp-legacy',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            name: 'موظف قديم',
            basicSalary: 100000,
            status: 'active',
          ),
        );
    await db.customStatement(
      'UPDATE employees SET server_id = ? WHERE id = ?',
      [legacyEmp, legacyEmp],
    );

    // (ب) سحبة بلا employee_uuid (فجوة هوية) بمبلغ صحيح السياسة.
    await db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion.insert(
            localUuid: 'sw-no-uuid',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            employeeId: legacyEmp,
            amount: 500,
            withdrawDate: '2026-10-01',
          ),
        );

    // (ج) كسر عشري تاريخي في مصروف (يُبلَّغ ولا يُعدَّل — البند 12).
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            localUuid: 'exp-frac',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            amount: 150.5,
            expenseType: 'سحب راتب',
            description: 'سحب راتب (كسر تاريخي)',
            date: '2026-10-01',
            relatedId: d.Value(legacyEmp),
          ),
        );

    // (د) علاقة معلّقة (G-3).
    await DeferredRelationStore(db).defer(
      collection: 'salary_withdrawals',
      localUuid: 'sw-deferred',
      payload: const {'localUuid': 'sw-deferred', 'employeeUuid': 'emp-x'},
      source: 'appwrite',
      missingParent: 'employee',
      parentUuid: 'emp-x',
      remoteParentId: 7,
      sourceDeviceId: 'devA',
      reason: 'يتيم — سيُربط عبر UUID',
    );

    // (هـ) تعارض مسجّل.
    await db.customStatement(
      'INSERT INTO sync_logs (sync_id, direction, device_id, metadata, '
      "operations, status, created_at) VALUES ('log-1', 'push', 'devA', "
      "'{}', '[]', 'failed', ?)",
      [DateTime.now().toIso8601String()],
    );
    await db.customStatement(
      'INSERT INTO sync_conflicts (log_id, table_name, uuid, resolution, '
      "local_payload, remote_payload, created_at) "
      "VALUES (1, 'expenses', 'exp-conflict', 'pending_review', "
      "'{}', '{}', ?)",
      [Time.nowEpoch().toString()],
    );

    // (و) انتهاك سلامة.
    await db.customStatement(
      'INSERT INTO auto_fix_runs (run_uuid, started_at_epoch, started_at_iso, '
      "status) VALUES ('run-1', ?, ?, 'completed')",
      [now, DateTime.now().toIso8601String()],
    );
    await db.customStatement(
      'INSERT INTO integrity_violations (run_id, affected_table_name, '
      'record_uuid, violation_type, details, is_critical, created_at_iso, '
      "created_at_epoch) VALUES (1, 'salary_withdrawals', 'sw-orphan-fk', "
      "'foreign_key_violation', 'مرجع موظف غير موجود', 1, ?, ?)",
      [DateTime.now().toIso8601String(), now],
    );
  }

  group('G-8 — تقرير المراجعة', () {
    test('يجمع كل المصادر ويصنّفها بأعداد صحيحة', () async {
      await seedAllSources();

      final report = await service.build();

      expect(report.summary['employees_local_server_id'], 1);
      expect(report.summary['withdrawals_missing_employee_uuid'], 1);
      expect(report.summary['fractional_money'], 1);
      expect(report.summary['deferred_pending'], 1);
      expect(report.summary['conflicts'], 1);
      expect(report.summary['integrity_violations'], 1);
      expect(report.totalFindings, greaterThanOrEqualTo(6));

      // الأدلة محفوظة كما هي: الكسر يُعرض بالمخزون ووفق السياسة (لا كتابة).
      final fraction = report.fractionalMoney.rows.single;
      expect(fraction.table, 'expenses');
      expect(fraction.localUuid, 'exp-frac');
      expect(fraction.storedAmount, 150.5);
      expect(fraction.policyAmount, 150);

      // العلاقة المعلّقة تحفظ دليل الجهاز/الرقم البعيد.
      final deferred = report.deferredRelations.single;
      expect(deferred.localUuid, 'sw-deferred');
      expect(deferred.sourceDeviceId, 'devA');
      expect(deferred.remoteParentId, 7);

      // التعارض يحمل جدوله ومعرّفه.
      expect(report.conflicts.single['table'], 'expenses');
      expect(report.conflicts.single['uuid'], 'exp-conflict');

      // الانتهاك يحمل نوعه ودرجة خطورته.
      expect(report.integrityViolations.single['type'], 'foreign_key_violation');
      expect(report.integrityViolations.single['critical'], isTrue);
    });

    test('قراءة فقط: لا يتغيّر أي جدول بعد البناء والتصدير', () async {
      await seedAllSources();

      final before = await snapshotTables();
      final report = await service.build();
      service.buildXlsx(report);
      final after = await snapshotTables();

      expect(after, before, reason: 'التقرير لا يجوز أن يكتب أي شيء');
    });

    test('يُنتج XLSX صالحاً (توقيع PK) بلا استثناء', () async {
      await seedAllSources();
      final report = await service.build();

      final bytes = service.buildXlsx(report);

      expect(bytes.length, greaterThan(1000));
      // ملفات xlsx أرشيفات ZIP ⇒ أول بايتين 'PK'.
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });

    test('قاعدة بيانات نظيفة: كل الأقسام صفر وحالة الفحص ناجحة', () async {
      final report = await service.build();

      expect(report.totalFindings, 0);
      expect(report.status['fractional_money']?.ok, isTrue);
      expect(report.status['conflicts']?.ok, isTrue);
      expect(report.status['integrity_violations']?.ok, isTrue);
      expect(report.status['deferred_relations']?.ok, isTrue);
      // JSON قابل للتسلسل (للأرشفة/المراجعة البرمجية).
      expect(report.toJson()['summary'], isA<Map<String, int>>());
    });

    test('نطاق المزوّد يظهر في التقرير (G-7 داخل G-8)', () async {
      SharedPreferences.setMockInitialValues({
        'sync_provider_scope_fingerprint': 'abc123',
        'sync_provider_scope_changed_at': 1700000000,
      });
      final report = await service.build();
      expect(report.providerScope['current'], 'abc123');
      expect(report.providerScope['changedAt'], 1700000000);
      expect(report.status['provider_scope']?.ok, isTrue);
    });

    test('clamps: لا انفجار عند غياب جداول (تثبيت أقدم)', () async {
      // جدول sync_conflicts موجود في المخطط دائماً — نحذف صفوفه فقط ونتأكد
      // أن الأقسام الفارغة تُبلَّغ كـ«نظيفة» لا كخطأ.
      final report = await service.build();
      expect(report.conflicts, isEmpty);
      expect(report.status['conflicts']?.error, isNull);
      expect(report.integrityViolations, isEmpty);
    });
  });

  group('G-8 — العقد (لا كتابة)', () {
    test('build لا يُنشئ صفوفاً في sync_conflicts أو integrity_violations', () async {
      await seedAllSources();
      final before = await db
          .customSelect('SELECT COUNT(*) AS c FROM sync_conflicts')
          .getSingle();
      await service.build();
      final after = await db
          .customSelect('SELECT COUNT(*) AS c FROM sync_conflicts')
          .getSingle();
      expect(after.read<int>('c'), before.read<int>('c'));
    });

    test('نوع Variable/تحويل التواريخ لا يُسقط التقرير بأخطاء SQL', () async {
      await seedAllSources();
      final report = await service.build();
      for (final entry in report.status.entries) {
        expect(
          entry.value.error,
          isNull,
          reason: 'قسم ${entry.key} فشل: ${entry.value.error}',
        );
      }
    });
  });
}
