// lib/services/review_report_service.dart
//
// ✅ (G-8 / 2026-10-06 — تدقيق الهوية المالية، البنود 9 و10 و12):
// **تقرير المراجعة القابل للتصدير** — Excel (XLSX) بورق واحد لكل فئة.
//
// **لماذا هذا الملف:** التدقيق انتهى إلى قاعدة «لا إصلاح بالحدس» (البند 12):
// كل حالة لا يمكن إثباتها آلياً يجب أن تُعرض **بأدلة قابلة للفحص البشري**
// لا أن تُصلَح بالتخمين. وكانت المصادر جاهزة لكن مبعثرة:
//   • `MoneyIntegrityService.scan()` — كسور عشرية (G-10، قراءة فقط).
//   • `DeferredRelationStore` — سجلات ناقصة الربط (G-3).
//   • `sync_conflicts` — تعارضات مسجّلة للمراجعة (G-4/G-11).
//   • `integrity_violations` — انتهاكات سلامة البيانات (فحص ما بعد المزامنة).
//   • فجوات هوية تاريخية (تدقيق §9.1): سحوبات/دورات/ترحيل بلا `employee_uuid`،
//     مصروفات رواتب بلا هوية موظف، وموظفون يحملون `server_id = id` المحلي
//     (البصمة الحرفية لعلّة G-3 قبل الإصلاح).
//   • حالة نطاق المزوّد (G-7) — بصمة الوجهة وآخر تبديل (قائمة الانتقال، البند 9).
//
// **ضمانات صارمة:**
//   • **قراءة فقط 100%** — لا INSERT/UPDATE/DELETE في أي جدول بيانات. الاختبار
//     يُثبت ذلك بمقارنة لقطة كل الجداول قبل/بعد التصدير.
//   • لا يكتب فوق أي قيمة تاريخية، ولا يقترح «تصحيحاً» تلقائياً: يقترح **قراراً
//     بشرياً** مع الدليل (المعرّف، المبلغ المخزون، القيمة وفق السياسة).
//   • كل قسم محمي بـ try/catch: غياب جدول (تثبيت أقدم) لا يُسقط التقرير — يُذكر
//     القسم بصف «تعذّر الفحص: …» حتى لا يبدو نظيفاً كذباً.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_xlsx_export_service.dart' show AppwriteXlsxExportService;
import 'local_db.dart';
import 'money_integrity_service.dart';
import 'salary_mirror_matcher.dart';
import 'sync_core/deferred_relation_store.dart';
import 'sync_core/financial_link_store.dart';
import 'sync_core/provider_scope.dart';

/// وسم حالة وجود جدول/عمود في التقرير.
class ReviewSectionStatus {
  const ReviewSectionStatus({this.error, this.rows = 0});

  final String? error;
  final int rows;

  bool get ok => error == null;

  Map<String, Object?> toJson() => {'ok': ok, 'rows': rows, 'error': error};
}

/// تقرير مراجعة كامل — بنية قابلة للعرض/الاختبار (لا تعتمد على الملف).
class ReviewReport {
  const ReviewReport({
    required this.generatedAtIso,
    required this.status,
    required this.fractionalMoney,
    required this.deferredRelations,
    required this.conflicts,
    required this.integrityViolations,
    required this.identityGaps,
    required this.providerScope,
    required this.summary,
    this.durableLinks = const {},
    this.heuristicMirrors = const [],
  });

  final String generatedAtIso;

  /// حالة كل قسم (نجاح/تعذّر الفحص + عدد الصفوف).
  final Map<String, ReviewSectionStatus> status;

  final MoneyIntegrityReport fractionalMoney;
  final List<DeferredRelationRow> deferredRelations;
  final List<Map<String, Object?>> conflicts;
  final List<Map<String, Object?>> integrityViolations;

  /// فجوات الهوية التاريخية — مفاتيحها ثابتة:
  /// employees_local_server_id · withdrawals_missing_employee_uuid ·
  /// cycles_missing_employee_uuid · carryover_missing_employee_uuid ·
  /// salary_expenses_missing_employee_uuid.
  final Map<String, List<Map<String, Object?>>> identityGaps;
  final Map<String, Object?> providerScope;

  /// ✅ (G-5 / P2-7 / 2026-10-06): مرايا السحوبات التي حُسمت **بمطابقة
  /// بياناتية** (أو بعلامة رقم غير قابلة للإثبات) لا بهوية/رقم مُثبت —
  /// تُعرض صريحةً بدل أن تُخفى بنفس ثقة الحاسم. قراءة فقط، وبحدود أعلى.
  final List<Map<String, Object?>> heuristicMirrors;

  /// ✅ (G-1/G-2 / 2026-10-06): ملخص الروابط المالية الدائمة —
  /// دفعات الرواتب (المرتبطة/غير المرتبطة بدورة) وسجلات الترحيل
  /// (المرتبطة/غير المرتبطة بالدورتين). أعداده للتوثيق والمراجعة.
  final Map<String, int> durableLinks;

  /// ملخص عددي للعرض السريع (وللاستخدام في الاختبارات).
  final Map<String, int> summary;

  int get totalFindings =>
      summary.values.fold<int>(0, (sum, value) => sum + value);

  Map<String, Object?> toJson() => {
    'generatedAt': generatedAtIso,
    'summary': summary,
    'status': status.map((key, value) => MapEntry(key, value.toJson())),
    'providerScope': providerScope,
    'fractionalMoney': {
      'scannedTables': fractionalMoney.scannedTables,
      'rows': [
        for (final row in fractionalMoney.rows)
          {
            'table': row.table,
            'uuid': row.localUuid,
            'stored': row.storedAmount,
            'policy': row.policyAmount,
          },
      ],
    },
    'deferredRelations': [
      for (final row in deferredRelations)
        {
          'collection': row.collection,
          'uuid': row.localUuid,
          'state': row.state.value,
          'missingParent': row.missingParent,
          'parentUuid': row.parentUuid,
          'remoteParentId': row.remoteParentId,
          'sourceDeviceId': row.sourceDeviceId,
          'attempts': row.attempts,
          'reason': row.reason,
        },
    ],
    'conflicts': conflicts,
    'integrityViolations': integrityViolations,
    'identityGaps': identityGaps,
    'durableLinks': durableLinks,
    'heuristicMirrors': heuristicMirrors,
  };
}

/// خدمة بناء وتصدير تقرير المراجعة — قراءة فقط.
class ReviewReportService {
  ReviewReportService({
    required this.db,
    DeferredRelationStore? deferredStore,
    FinancialLinkStore? financialLinks,
  }) : _deferredStore = deferredStore ?? DeferredRelationStore(db),
       _financialLinks = financialLinks ?? FinancialLinkStore(db);

  final AppDatabase db;
  final DeferredRelationStore _deferredStore;
  final FinancialLinkStore _financialLinks;

  /// أقصى عدد صفوف لكل قسم في العرض (والملف). القيمة مقصودة آمنة للذاكرة
  /// على أجهزة ضعيفة؛ التقرير يذكر العدد الكلي حتى لو اقتُطع العرض.
  static const int maxRowsPerSection = 1500;

  // ─────────────────────────────────────────────────────────────────────
  // بناء التقرير
  // ─────────────────────────────────────────────────────────────────────

  Future<ReviewReport> build() async {
    final status = <String, ReviewSectionStatus>{};
    final nowIso = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // 1) الكسور العشرية (G-10) — خدمة قراءة فقط قائمة.
    MoneyIntegrityReport fractions;
    try {
      fractions = await MoneyIntegrityService(db).scan();
      status['fractional_money'] = ReviewSectionStatus(
        rows: fractions.rows.length,
      );
    } catch (e) {
      fractions = const MoneyIntegrityReport(rows: [], scannedTables: []);
      status['fractional_money'] = ReviewSectionStatus(error: '$e');
    }

    // 2) السجلات ناقصة الربط (G-3).
    List<DeferredRelationRow> deferred = const [];
    try {
      deferred = await _deferredStore.all(limit: maxRowsPerSection);
      final pending = deferred
          .where((r) => r.state == DeferredRelationState.pending)
          .length;
      final review = deferred
          .where((r) => r.state == DeferredRelationState.needsReview)
          .length;
      status['deferred_relations'] = ReviewSectionStatus(rows: deferred.length);
      status['deferred_pending'] = ReviewSectionStatus(rows: pending);
      status['deferred_needs_review'] = ReviewSectionStatus(rows: review);
    } catch (e) {
      status['deferred_relations'] = ReviewSectionStatus(error: '$e');
    }

    // 3) التعارضات المسجّلة (G-4/G-11) — جدول sync_conflicts.
    final conflicts = <Map<String, Object?>>[];
    try {
      final rows = await db
          .customSelect(
            'SELECT id, table_name, uuid, resolution, created_at, log_id '
            'FROM sync_conflicts ORDER BY created_at DESC LIMIT ?',
            variables: [Variable.withInt(maxRowsPerSection)],
          )
          .get();
      for (final row in rows) {
        conflicts.add({
          'id': row.data['id'],
          'table': row.data['table_name'],
          'uuid': row.data['uuid'],
          'resolution': row.data['resolution'],
          'createdAt': row.data['created_at'],
          'logId': row.data['log_id'],
        });
      }
      status['conflicts'] = ReviewSectionStatus(rows: conflicts.length);
    } catch (e) {
      status['conflicts'] = ReviewSectionStatus(error: '$e');
    }

    // 4) انتهاكات السلامة — جدول integrity_violations.
    final violations = <Map<String, Object?>>[];
    try {
      final rows = await db
          .customSelect(
            'SELECT id, affected_table_name, record_uuid, violation_type, '
            'details, is_critical, created_at_iso FROM integrity_violations '
            'ORDER BY created_at_epoch DESC LIMIT ?',
            variables: [Variable.withInt(maxRowsPerSection)],
          )
          .get();
      for (final row in rows) {
        violations.add({
          'id': row.data['id'],
          'table': row.data['affected_table_name'],
          'uuid': row.data['record_uuid'],
          'type': row.data['violation_type'],
          'details': row.data['details'],
          'critical': row.data['is_critical'] == 1,
          'createdAt': row.data['created_at_iso'],
        });
      }
      status['integrity_violations'] = ReviewSectionStatus(
        rows: violations.length,
      );
    } catch (e) {
      status['integrity_violations'] = ReviewSectionStatus(error: '$e');
    }

    // 5) فجوات الهوية التاريخية (تدقيق §9.1) — كلها «قراءة فقط».
    final identityGaps = await _collectIdentityGaps(status);

    // 5-ب) الروابط المالية الدائمة (G-1: دورة الدفعة · G-2: دورتا الترحيل).
    // تُقرأ من مخزن مشترك مع المزامنة — لا كتابة من التقرير.
    Map<String, int> durableLinks = const {};
    try {
      durableLinks = await _financialLinks.summary();
      status['durable_links'] = ReviewSectionStatus(rows: durableLinks.length);
    } catch (e) {
      status['durable_links'] = ReviewSectionStatus(error: '$e');
    }

    // 5-ج) مرايا حُكمية (G-5): تُعرض بالدليل ولا تُخفى.
    List<Map<String, Object?>> heuristicMirrors = const [];
    try {
      heuristicMirrors = await _collectHeuristicMirrors();
      status['heuristic_mirrors'] = ReviewSectionStatus(
        rows: heuristicMirrors.length,
      );
    } catch (e) {
      status['heuristic_mirrors'] = ReviewSectionStatus(error: '$e');
    }

    // 6) نطاق المزوّد (G-7) — للتحقق من قائمة الانتقال (البند 9).
    Map<String, Object?> providerScope = const {};
    try {
      final prefs = await _prefs();
      providerScope = {
        'current': prefs.getString(ProviderScopeGuard.fingerprintKey),
        'previous': prefs.getString(ProviderScopeGuard.previousFingerprintKey),
        'changedAt': prefs.getInt(ProviderScopeGuard.changedAtKey),
        'checkpointRows': await _checkpointCount(),
      };
      status['provider_scope'] = const ReviewSectionStatus(rows: 1);
    } catch (e) {
      status['provider_scope'] = ReviewSectionStatus(error: '$e');
    }

    final summary = <String, int>{
      'fractional_money': fractions.rows.length,
      'payments_without_cycle_link':
          durableLinks['payments_cycle_unlinked'] ?? 0,
      'carry_over_without_cycle_links':
          durableLinks['carry_over_cycle_unlinked'] ?? 0,
      'heuristic_mirrors': heuristicMirrors.length,
      'deferred_pending': status['deferred_pending']?.rows ?? 0,
      'deferred_needs_review': status['deferred_needs_review']?.rows ?? 0,
      'conflicts': conflicts.length,
      'integrity_violations': violations.length,
      for (final entry in identityGaps.entries) entry.key: entry.value.length,
    };

    return ReviewReport(
      generatedAtIso: nowIso,
      status: status,
      fractionalMoney: fractions,
      deferredRelations: deferred,
      conflicts: conflicts,
      integrityViolations: violations,
      identityGaps: identityGaps,
      providerScope: providerScope,
      summary: summary,
      durableLinks: durableLinks,
      heuristicMirrors: heuristicMirrors,
    );
  }

  /// ✅ (G-5): يجمع السحوبات التي تحمل **علامة مرآة** (رقم أجنبي) ثم
  /// يصنّفها بالمطابِق الموحّد، ويُعيد فقط ما حُسم بمطابقة بياناتية أو
  /// بعلامة غير مُثبتة — أي ما يحتاج عيناً بشرية.
  ///
  /// حدود مقصودة: أحدث [maxRowsPerSection] سحبة تحمل علامة، ومصروفات
  /// الرواتب (نفس الشرط) فقط — لا سحب كامل الجداول في الذاكرة.
  Future<List<Map<String, Object?>>> _collectHeuristicMirrors() async {
    final withdrawals = await db
        .customSelect(
          'SELECT w.local_uuid, w.employee_id, w.employee_uuid, w.amount, '
          'w.withdraw_date, w.hotel_day_key, w.reason, w.expense_id, '
          'w.expense_uuid, w.device_id '
          'FROM salary_withdrawals w '
          'WHERE w.deleted_at IS NULL AND w.amount > 0 '
          "AND w.reason NOT LIKE 'direct_withdrawal_%' "
          "AND (w.expense_id IS NOT NULL OR w.reason LIKE 'exp_%') "
          'ORDER BY w.withdraw_date DESC LIMIT ?',
          variables: [Variable.withInt(maxRowsPerSection)],
        )
        .get();
    if (withdrawals.isEmpty) return const [];

    final expenses = await db
        .customSelect(
          'SELECT id, local_uuid, server_id, expense_type, amount, date, '
          'hotel_day_key, related_id, withdrawal_uuid, device_id '
          'FROM expenses WHERE deleted_at IS NULL '
          'AND related_id IN (SELECT DISTINCT employee_id FROM '
          'salary_withdrawals WHERE deleted_at IS NULL) LIMIT ?',
          variables: [Variable.withInt(maxRowsPerSection * 4)],
        )
        .get();

    final candidates = [
      for (final row in expenses)
        MirrorExpenseCandidate(
          id: (row.data['id'] as int?) ?? 0,
          serverId: row.data['server_id'] as int?,
          expenseType: (row.data['expense_type'] as String?) ?? '',
          amount: ((row.data['amount'] as num?) ?? 0).toDouble(),
          date: row.data['date'] as String?,
          hotelDayKey: row.data['hotel_day_key'] as String?,
          relatedId: row.data['related_id'] as int?,
          localUuid: row.data['local_uuid'] as String?,
          withdrawalUuid: row.data['withdrawal_uuid'] as String?,
          deviceId: row.data['device_id'] as String?,
        ),
    ];

    final result = <Map<String, Object?>>[];
    for (final row in withdrawals) {
      final level = SalaryMirrorMatcher.classify(
        expenseUuid: row.data['expense_uuid'] as String?,
        withdrawalLocalUuid: row.data['local_uuid'] as String?,
        expenseId: row.data['expense_id'] as int?,
        reason: row.data['reason'] as String?,
        amount: ((row.data['amount'] as num?) ?? 0).toDouble(),
        hotelDayKey: row.data['hotel_day_key'] as String?,
        withdrawDate: (row.data['withdraw_date'] as String?) ?? '',
        employeeId: (row.data['employee_id'] as int?) ?? 0,
        expenses: candidates,
        sourceDeviceId: row.data['device_id'] as String?,
      );
      if (!level.isHeuristic) continue;
      result.add({
        'withdrawalUuid': row.data['local_uuid'],
        'employeeUuid': row.data['employee_uuid'],
        'amount': row.data['amount'],
        'day': row.data['hotel_day_key'] ?? row.data['withdraw_date'],
        'reason': row.data['reason'],
        'level': level.name,
      });
    }
    return result;
  }

  Future<Map<String, List<Map<String, Object?>>>> _collectIdentityGaps(
    Map<String, ReviewSectionStatus> status,
  ) async {
    final gaps = <String, List<Map<String, Object?>>>{};

    Future<void> run(String key, String sql) async {
      try {
        final rows = await db
            .customSelect(sql, variables: [Variable.withInt(maxRowsPerSection)])
            .get();
        gaps[key] = [for (final row in rows) row.data.cast<String, Object?>()];
        status[key] = ReviewSectionStatus(rows: rows.length);
      } catch (e) {
        gaps[key] = const [];
        status[key] = ReviewSectionStatus(error: '$e');
      }
    }

    // (أ) البصمة الحرفية لعلّة G-3 قبل الإصلاح: رقم محلي استُخدم كهوية.
    await run(
      'employees_local_server_id',
      'SELECT id, local_uuid, name, server_id, device_id, origin '
          'FROM employees WHERE deleted_at IS NULL '
          'AND server_id IS NOT NULL AND server_id = id LIMIT ?',
    );
    // (ب) سحوبات بلا هوية موظف ثابتة (لا يمكن ربطها عبر الأجهزة بلا تخمين).
    await run(
      'withdrawals_missing_employee_uuid',
      'SELECT id, local_uuid, employee_id, amount, withdraw_date, device_id '
          'FROM salary_withdrawals WHERE deleted_at IS NULL '
          "AND (employee_uuid IS NULL OR TRIM(employee_uuid) = '') LIMIT ?",
    );
    // (ج) دورات رواتب بلا هوية موظف.
    await run(
      'cycles_missing_employee_uuid',
      'SELECT id, local_uuid, employee_id, cycle_key, device_id '
          'FROM salary_cycles WHERE deleted_at IS NULL '
          "AND (employee_uuid IS NULL OR TRIM(employee_uuid) = '') LIMIT ?",
    );
    // (د) سجلات ترحيل بلا هوية موظف.
    await run(
      'carryover_missing_employee_uuid',
      'SELECT id, local_uuid, employee_id, amount, device_id '
          'FROM salary_carry_over_logs WHERE deleted_at IS NULL '
          "AND (employee_uuid IS NULL OR TRIM(employee_uuid) = '') LIMIT ?",
    );
    // (هـ) مصروفات رواتب بلا هوية موظف (تحتاج مراجعة يدوية قبل أي ربط).
    await run(
      'salary_expenses_missing_employee_uuid',
      'SELECT id, local_uuid, related_id, amount, expense_type, device_id '
          'FROM expenses WHERE deleted_at IS NULL '
          "AND (employee_uuid IS NULL OR TRIM(employee_uuid) = '') "
          'AND related_id IS NOT NULL LIMIT ?',
    );
    return gaps;
  }

  /// عدد صفوف نقاط الفحص — قراءة خام (لا DDL ولا إنشاء جدول من التقرير).
  Future<int> _checkpointCount() async {
    try {
      final rows = await db
          .customSelect('SELECT COUNT(*) AS c FROM sync_checkpoints')
          .getSingle();
      return rows.read<int>('c');
    } catch (_) {
      return 0;
    }
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  // ─────────────────────────────────────────────────────────────────────
  // التصدير إلى XLSX
  // ─────────────────────────────────────────────────────────────────────

  /// يبني التقرير ثم يكتبه ملفاً ويُعيد مساره (والبنية كاملة).
  Future<({File file, ReviewReport report})> exportToFile() async {
    final report = await build();
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final target = File('${dir.path}/marina_review_report_$stamp.xlsx');
    final bytes = buildXlsx(report);
    await target.writeAsBytes(
      AppwriteXlsxExportService.enforceRightToLeft(bytes),
      flush: true,
    );
    return (file: target, report: report);
  }

  /// ملف نصي JSON — نسخة ثانوية للمراجعة البرمجية/الأرشفة.
  Future<File> exportJsonToFile(ReviewReport report) async {
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final target = File('${dir.path}/marina_review_report_$stamp.json');
    await target.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
      flush: true,
    );
    return target;
  }

  /// يبني ملف XLSX من تقرير (دالة نقية — قابلة للاختبار بلا نظام ملفات).
  List<int> buildXlsx(ReviewReport report) {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    _summarySheet(excel, report);

    _tableSheet(
      excel,
      'كسور عشرية',
      const ['الجدول', 'المعرّف', 'المبلغ المخزون', 'وفق السياسة', 'الفرق'],
      [
        for (final row in report.fractionalMoney.rows)
          [
            row.table,
            row.localUuid,
            row.storedAmount,
            row.policyAmount,
            row.removedFraction,
          ],
      ],
      emptyNote: 'لا كسور عشرية — السياسة سليمة في كل الصفوف المفحوصة',
    );

    _tableSheet(
      excel,
      'علاقات معلّقة',
      const [
        'المجموعة',
        'المعرّف',
        'الحالة',
        'الأب المفقود',
        'معرّف الأب',
        'رقم الأب البعيد',
        'جهاز المصدر',
        'المحاولات',
        'السبب',
      ],
      [
        for (final row in report.deferredRelations)
          [
            row.collection,
            row.localUuid,
            row.state.value,
            row.missingParent,
            row.parentUuid,
            row.remoteParentId,
            row.sourceDeviceId,
            row.attempts,
            row.reason,
          ],
      ],
      emptyNote: 'لا سجلات معلّقة — كل العلاقات محلولة',
    );

    _tableSheet(
      excel,
      'تعارضات',
      const ['#', 'الجدول', 'المعرّف', 'القرار', 'وقت التسجيل', 'سجل المزامنة'],
      [
        for (final row in report.conflicts)
          [
            row['id'],
            row['table'],
            row['uuid'],
            row['resolution'],
            row['createdAt'],
            row['logId'],
          ],
      ],
      emptyNote: 'لا تعارضات مسجّلة',
    );

    _tableSheet(
      excel,
      'انتهاكات سلامة',
      const [
        '#',
        'الجدول',
        'المعرّف',
        'النوع',
        'حرِج',
        'وقت الاكتشاف',
        'التفاصيل',
      ],
      [
        for (final row in report.integrityViolations)
          [
            row['id'],
            row['table'],
            row['uuid'],
            row['type'],
            row['critical'] == true ? 'نعم' : 'لا',
            row['createdAt'],
            row['details'],
          ],
      ],
      emptyNote: 'لا انتهاكات سلامة مسجّلة',
    );

    _identityGapsSheet(excel, report);

    _durableLinksSheet(excel, report);

    _tableSheet(
      excel,
      'مرايا حُكمية',
      const [
        'سحبة',
        'الموظف',
        'المبلغ',
        'اليوم',
        'السبب',
        'مستوى الإثبات',
      ],
      [
        for (final row in report.heuristicMirrors)
          [
            row['withdrawalUuid'],
            row['employeeUuid'],
            row['amount'],
            row['day'],
            row['reason'],
            row['level'],
          ],
      ],
      emptyNote: 'لا مرايا حُكمية — كل المرايا محسومة بهوية أو رقم مُثبت',
    );

    _providerScopeSheet(excel, report);

    final bytes = excel.save();
    if (bytes == null) {
      throw const FormatException('فشل توليد ملف تقرير المراجعة (save=null)');
    }
    return bytes;
  }

  // ── أوراق مساعدة ──────────────────────────────────────────────────────

  void _summarySheet(Excel excel, ReviewReport report) {
    final sheet = excel['الملخص'];
    sheet.isRTL = true;

    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'فندق مارينا — تقرير مراجعة الهوية المالية',
    );
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 15,
    );
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('C1'));

    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(
      'تاريخ التقرير: ${report.generatedAtIso} — قراءة فقط '
      '(لا يُعدَّل أي سجل، ولا تُقترح تصحيحات تلقائية)',
    );
    sheet.cell(CellIndex.indexByString('A2')).cellStyle = CellStyle(
      fontSize: 10,
    );
    sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('C2'));

    final headers = ['الفئة', 'العدد', 'حالة الفحص'];
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4))
          .value = TextCellValue(
        headers[i],
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4))
          .cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFDBEAFE'),
      );
    }

    const labels = {
      'fractional_money': 'كسور عشرية (سياسة «لا كسور»)',
      'deferred_pending': 'سجلات معلّقة (بانتظار الأب)',
      'deferred_needs_review': 'سجلات تحتاج مراجعة بشرية',
      'conflicts': 'تعارضات مسجّلة',
      'integrity_violations': 'انتهاكات سلامة',
      'employees_local_server_id': 'موظفون برقم محلي كـهوية (G-3 تاريخي)',
      'withdrawals_missing_employee_uuid': 'سحوبات بلا هوية موظف',
      'cycles_missing_employee_uuid': 'دورات بلا هوية موظف',
      'carryover_missing_employee_uuid': 'ترحيلات بلا هوية موظف',
      'salary_expenses_missing_employee_uuid': 'مصروفات رواتب بلا هوية موظف',
      'payments_without_cycle_link': 'دفعات رواتب بلا رابط دورة دائم (G-1)',
      'carry_over_without_cycle_links': 'سجلات ترحيل بلا رابط دورتين (G-2)',
      'heuristic_mirrors': 'مرايا رواتب حُكمية (مطابقة بياناتية — G-5)',
    };

    var row = 5;
    for (final entry in labels.entries) {
      final sectionStatus = report.status[entry.key];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        entry.value,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = IntCellValue(
        report.summary[entry.key] ?? 0,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = TextCellValue(
        sectionStatus == null
            ? '—'
            : (sectionStatus.ok ? 'مفحوص' : 'تعذّر: ${sectionStatus.error}'),
      );
      row++;
    }

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row + 1))
        .value = TextCellValue(
      'إجمالي الحالات المعروضة للمراجعة',
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row + 1))
        .cellStyle = CellStyle(
      bold: true,
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row + 1))
        .value = IntCellValue(
      report.totalFindings,
    );
  }

  void _identityGapsSheet(Excel excel, ReviewReport report) {
    final sheet = excel['فجوات الهوية'];
    sheet.isRTL = true;
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'فجوات هوية تاريخية — لا تُصلَّح آلياً. المطلوب قرار بشري مدعوم بدليل.',
    );
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 12,
    );
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('F1'));

    var row = 3;
    const labels = {
      'employees_local_server_id':
          'موظفون: server_id = id المحلي (بصمة علّة G-3 قبل الإصلاح)',
      'withdrawals_missing_employee_uuid': 'سحوبات بلا employee_uuid',
      'cycles_missing_employee_uuid': 'دورات رواتب بلا employee_uuid',
      'carryover_missing_employee_uuid': 'سجلات ترحيل بلا employee_uuid',
      'salary_expenses_missing_employee_uuid':
          'مصروفات رواتب بلا employee_uuid (لها related_id)',
    };

    for (final entry in labels.entries) {
      final rows = report.identityGaps[entry.key] ?? const [];
      final sectionStatus = report.status[entry.key];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        entry.value,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFFEF3C7'),
      );
      row++;
      if (sectionStatus != null && !sectionStatus.ok) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = TextCellValue(
          'تعذّر الفحص: ${sectionStatus.error}',
        );
        row += 2;
        continue;
      }
      if (rows.isEmpty) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = TextCellValue(
          'لا صفوف في هذه الفئة',
        );
        row += 2;
        continue;
      }
      final columns = rows.first.keys.toList(growable: false);
      for (var c = 0; c < columns.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value = TextCellValue(
          columns[c],
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('FFF3F4F6'),
        );
      }
      row++;
      for (final dataRow in rows) {
        for (var c = 0; c < columns.length; c++) {
          final value = dataRow[columns[c]];
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
              .value = _cellValueFor(
            value,
          );
        }
        row++;
      }
      row++;
    }
  }

  /// ✅ (G-1/G-2): ورقة الروابط الدائمة — تُقرأ أعدادها فقط (لا إصلاح).
  void _durableLinksSheet(Excel excel, ReviewReport report) {
    final sheet = excel['الروابط الدائمة'];
    sheet.isRTL = true;
    sheet
        .cell(CellIndex.indexByString('A1'))
        .value = TextCellValue(
      'الروابط المالية الدائمة (G-1/G-2) — أي رقم «غير مرتبط» يحتاج '
      'قراراً بشرياً، ولا يُربط تخميناً.',
    );
    sheet
        .cell(CellIndex.indexByString('A1'))
        .cellStyle = CellStyle(bold: true, fontSize: 11);
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('C1'));

    const labels = {
      'payments_total': 'إجمالي دفعات الرواتب (غير محذوفة)',
      'payments_cycle_linked': 'دفعات مرتبطة بدورة (هوية دائمة)',
      'payments_cycle_unlinked': 'دفعات بلا رابط دورة دائم',
      'carry_over_total': 'إجمالي سجلات الترحيل',
      'carry_over_cycle_linked': 'سجلات ترحيل مرتبطة بالدورتين',
      'carry_over_cycle_unlinked': 'سجلات ترحيل بلا رابط دورتين',
    };
    var row = 3;
    for (final entry in labels.entries) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(entry.value);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = IntCellValue(report.durableLinks[entry.key] ?? 0);
      row++;
    }
  }

  void _providerScopeSheet(Excel excel, ReviewReport report) {
    final sheet = excel['نطاق المزوّد'];
    sheet.isRTL = true;
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'حالة نطاق مزوّد المزامنة (G-7)',
    );
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 12,
    );

    final scope = report.providerScope;
    final rows = <List<Object?>>[
      ['البصمة الحالية', scope['current']],
      ['البصمة السابقة (آخر تبديل)', scope['previous']],
      ['وقت آخر تبديل (epoch)', scope['changedAt']],
      ['صفوف نقاط الفحص المحفوظة', scope['checkpointRows']],
      [
        'ملاحظة',
        'عند اختلاف البصمة يُعاد ضبط المؤشرات ويُفعَّل الرفع الأولي '
            'لنقل البيانات إلى الوجهة الجديدة (بلا تغيير هوية: نفس UUID).',
      ],
    ];
    var row = 3;
    for (final entry in rows) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        '${entry[0]}',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = CellStyle(
        bold: true,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = _cellValueFor(
        entry[1],
      );
      row++;
    }
  }

  void _tableSheet(
    Excel excel,
    String name,
    List<String> columns,
    List<List<Object?>> rows, {
    required String emptyNote,
  }) {
    final sheet = excel[name];
    sheet.isRTL = true;

    if (rows.isEmpty) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = TextCellValue(
        emptyNote,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .cellStyle = CellStyle(
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FF166534'),
        backgroundColorHex: ExcelColor.fromHexString('FFDCFCE7'),
      );
      return;
    }

    for (var c = 0; c < columns.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(
        columns[c],
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('FF1B3A5C'),
      );
    }
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < columns.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = _cellValueFor(
          c < rows[r].length ? rows[r][c] : null,
        );
      }
    }
  }

  CellValue? _cellValueFor(Object? value) {
    if (value == null) return null;
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    if (value is bool) return TextCellValue(value ? 'نعم' : 'لا');
    return TextCellValue(value.toString());
  }
}
