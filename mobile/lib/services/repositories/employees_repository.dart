import 'dart:async';

import 'package:drift/drift.dart' as d;

import '../../utils/debug_log.dart';
import '../../utils/status_utils.dart';
import '../auto_backup_manager.dart';
import '../crashlytics_service.dart';
import '../daos/employees_dao.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../sync/payload_mapper.dart';
import 'expenses_repository.dart';

class EmployeesRepository {
  EmployeesRepository(this.db)
    : outbox = OutboxDao(db),
      dao = EmployeesDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final EmployeesDao dao;

  /// أنواع المصروفات المرتبطة بالموظف — مجموعة القراءة الحرفية لخدمة
  /// الاستحقاق (salary_entitlement_service) + النوع القديم 'employee'.
  ///
  /// ⚠️ لا يكفي `PayloadMapper.isSalaryExpenseType` وحدها: لا تغطي
  /// «سلفة/خصم/غياب» التي تقرأها خدمة الاستحقاق أيضاً. ولا يصح استخدام
  /// contains('راتب') المطوّع هنا: قد يلتقط مصروفات إضافية ويربك
  /// التمييز عن مصروفات الحجوزات (related_id متعدد الدلالة).
  static const Set<String> _employeeLinkedExpenseTypes = {
    'سحب راتب',
    'رواتب',
    'سحب من الراتب',
    'سلفة',
    'خصم من الراتب',
    'خصم راتب',
    'خصم',
    'غياب',
    'employee',
  };

  bool _isEmployeeLinkedExpenseType(String type) =>
      _employeeLinkedExpenseTypes.contains(type.trim()) ||
      PayloadMapper.isSalaryExpenseType(type);

  /// ✅ (2026-09-14) تسوية ما بعد التعديل — «لا سجلات يتيمة»:
  ///
  /// تعديل الموظف يُبقي (id, localUuid) ثابتين، لكن سجلاته المرتبطة قد
  /// تتفكك عبر الأجهزة: مصروف سحب من السحابة بـ employeeUuid قبل وصول
  /// الموظف (related_id يُترك فارغاً عمداً في expenses_adapter)، انزياح
  /// معرفات بعد استعادة نسخة احتياطية، أو بقايا إصلاحات قديمة. النتيجة:
  /// شاشة الاستحقاقات (تقرأ expenses عبر related_id) ترى مجموعة مختلفة
  /// عن الشاشات التي تقرأ employee_uuid — سجلات يتيمة جزئياً.
  ///
  /// هذا التسوية تجعل كل تعديل موظف لحظة شفاء: كل مصروف مرتبط به يتفق
  /// فيه (related_id = id) مع (employee_uuid = localUuid):
  ///
  /// 1. **الهوية المحمولة تفوز**: مصروف يحمل localUuid الموظف لكن
  ///    related_id قديم/فارغ → يُعاد ربطه بـ id الحالي (uuid دلالة أقوى
  ///    من رقم محلي — نفس قرار IdResolver/إصلاحات database_fixer).
  /// 2. **ترحيل الهوية**: مصروف تابع عبر related_id = id لكنه بلا
  ///    employee_uuid (سجلات قديمة سبب إنشاء employeeUuid) → تُمنح
  ///    الهوية المحمولة لتبقى قابلة الحل عبر الأجهزة.
  ///
  /// حماية من الربط الخاطئ:
  /// - مصروف «حجز/أنواع غير مرتبطة» تطابق related_id رقمياً مع id الموظف
  ///   لا يُمس (related_id متعدد الدلالة — نقبل الترحيل للأنواع المرتبطة
  ///   بالموظف فقط).
  /// - مصروف يحمل employee_uuid لموظف **آخر** لا يُمس هنا وإن تطابق
  ///   related_id رقمياً — صاحب uuid الآخر هو من يصلحه عند تعديله.
  ///
  /// التحديثات عبر ExpensesRepository.update فتُحدّث lastModified وتكتب
  /// outbox — فتتزامن التصحيحات مع السحابة وتتعلمها بقية الأجهزة
  /// (نفس عقد database_fixer._fixOrphanExpenses).
  ///
  /// returns: عدد السجلات المُصلحة. لا ترمي أبداً — فشل التسوية لا يجوز
  /// أن يُفشل تعديل الموظف نفسه.
  Future<int> _reconcileLinkedRecords({
    required int id,
    required String localUuid,
  }) async {
    var repaired = 0;
    try {
      final expensesRepo = ExpensesRepository(db);

      // 1) uuid = موظفنا لكن related_id لا يطابق → إعادة ربط بالهوية المحمولة
      final byUuidRows =
          await (db.select(
                  db.expenses,
                )
                ..where((e) => e.employeeUuid.equals(localUuid))
                ..where((e) => e.deletedAt.isNull()))
              .get();
      for (final exp in byUuidRows) {
        if (exp.relatedId != id) {
          await expensesRepo.update(
            exp.id,
            relatedId: id,
            employeeUuid: localUuid,
          );
          repaired++;
          dlog(
            () =>
                '🔗 إعادة ربط مصروف #${exp.id} بالموظف #$id عبر uuid '
                '(كان related_id=${exp.relatedId})',
          );
        }
      }

      // 2) تابع عبر id لكن بلا uuid → ترحيل الهوية المحمولة
      final byIdRows =
          await (db.select(
                  db.expenses,
                )
                ..where((e) => e.relatedId.equals(id))
                ..where((e) => e.deletedAt.isNull()))
              .get();
      for (final exp in byIdRows) {
        final uuid = exp.employeeUuid;
        if ((uuid == null || uuid.isEmpty) &&
            _isEmployeeLinkedExpenseType(exp.expenseType)) {
          await expensesRepo.update(
            exp.id,
            relatedId: id,
            employeeUuid: localUuid,
          );
          repaired++;
          dlog(
            () =>
                '🪪 ترحيل هوية محمولة لمصروف #${exp.id} '
                '(نوع ${exp.expenseType}) → الموظف #$id',
          );
        }
      }
    } catch (e, stack) {
      // فشل التسوية لا يُفشل التعديل — يُسجل ويُعاد المحاولة عند التعديل التالي
      await CrashlyticsService.instance.recordScreenError(
        screen: 'EmployeesRepository',
        action: 'reconcileLinkedRecords',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.warning,
        extra: {'employeeId': '$id'},
      );
    }
    return repaired;
  }

  Stream<List<Employee>> watchAll({
    String? search,
    int? limit,
    int offset = 0,
  }) => dao.watchList(search: search, limit: limit, offset: offset);
  Stream<Employee?> watchOne(int id) => dao.watchById(id);

  String _normalizeStatus(String status) =>
      StatusUtils.canonicalEmployeeStatus(status);

  Future<int> create({
    required String name,
    required String status,
    double? basicSalary,
    double? salary,
    String? position,
    String? phone,
    String? hireDate,
  }) async {
    try {
      final s = salary ?? basicSalary ?? 0.0;
      final normalizedStatus = _normalizeStatus(status);
      final result = await dao.insertOne(
        EmployeesCompanion(
          name: d.Value(name),
          basicSalary: d.Value(s),
          position: d.Value(position ?? 'موظف'),
          phone: d.Value(phone ?? ''),
          hireDate: d.Value(hireDate ?? ''),
          status: d.Value(normalizedStatus),
        ),
      );
      unawaited(
        AutoBackupManager.instance.onDataChange(
          'employees',
          'INSERT',
          recordData: {'name': name},
        ),
      );
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'EmployeesRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'name': name, 'status': status},
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    String? name,
    double? basicSalary,
    double? salary,
    String? position,
    String? phone,
    String? hireDate,
    String? status,
    String? terminationDate,
    String? terminationReason,
  }) async {
    try {
      final result = await dao.updateById(
        id,
        EmployeesCompanion(
          name: name != null ? d.Value(name) : const d.Value.absent(),
          basicSalary: (salary ?? basicSalary) != null
              ? d.Value((salary ?? basicSalary)!)
              : const d.Value.absent(),
          position: position != null
              ? d.Value(position)
              : const d.Value.absent(),
          phone: phone != null ? d.Value(phone) : const d.Value.absent(),
          hireDate: hireDate != null
              ? d.Value(hireDate)
              : const d.Value.absent(),
          status: status != null
              ? d.Value(_normalizeStatus(status))
              : const d.Value.absent(),
          terminationDate: terminationDate != null
              ? d.Value(terminationDate)
              : const d.Value.absent(),
          terminationReason: terminationReason != null
              ? d.Value(terminationReason)
              : const d.Value.absent(),
        ),
      );
      if (result > 0) {
        // ✅ (2026-09-14) تسوية السجلات المرتبطة بعد التعديل — «لا سجلات يتيمة»
        // (إعادة ربط/ترحيل الهوية — التوثيق الكامل في _reconcileLinkedRecords)
        final emp = await dao.getById(id);
        if (emp != null) {
          await _reconcileLinkedRecords(id: emp.id, localUuid: emp.localUuid);
        }
        unawaited(
          AutoBackupManager.instance.onDataChange(
            'employees',
            'UPDATE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'EmployeesRepository',
        action: 'update',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  Future<int> updateByLocalUuid(
    String localUuid, {
    String? name,
    double? basicSalary,
    double? salary,
    String? position,
    String? phone,
    String? hireDate,
    String? status,
    String? terminationDate,
    String? terminationReason,
  }) async {
    final result = await dao.updateByLocalUuid(
      localUuid,
      EmployeesCompanion(
        name: name != null ? d.Value(name) : const d.Value.absent(),
        basicSalary: (salary ?? basicSalary) != null
            ? d.Value((salary ?? basicSalary)!)
            : const d.Value.absent(),
        position: position != null ? d.Value(position) : const d.Value.absent(),
        phone: phone != null ? d.Value(phone) : const d.Value.absent(),
        hireDate: hireDate != null ? d.Value(hireDate) : const d.Value.absent(),
        status: status != null
            ? d.Value(_normalizeStatus(status))
            : const d.Value.absent(),
        terminationDate: terminationDate != null
            ? d.Value(terminationDate)
            : const d.Value.absent(),
        terminationReason: terminationReason != null
            ? d.Value(terminationReason)
            : const d.Value.absent(),
      ),
    );
    if (result > 0) {
      // ✅ (2026-09-14) تسوية السجلات المرتبطة بعد التعديل — «لا سجلات يتيمة»
      // كل تعديل موظف لحظة شفاء: (related_id, employee_uuid) يتفقان مع
      // (id, localUuid) في كل المصروفات المرتبطة به (انظر التوثيق أعلاه)
      final emp = await dao.getByLocalUuid(localUuid);
      if (emp != null) {
        await _reconcileLinkedRecords(id: emp.id, localUuid: emp.localUuid);
      }
    }
    return result;
  }

  /// إنهاء خدمة موظف - يغير الحالة ويسجل تاريخ وسبب الإنهاء
  Future<int> terminate({
    required int id,
    required String terminationType,
    required String terminationDate,
    String? terminationReason,
  }) async {
    try {
      final result = await dao.updateById(
        id,
        EmployeesCompanion(
          status: d.Value(_normalizeStatus(terminationType)),
          terminationDate: d.Value(terminationDate),
          terminationReason: d.Value(terminationReason ?? ''),
        ),
      );
      if (result > 0) {
        unawaited(
          AutoBackupManager.instance.onDataChange(
            'employees',
            'TERMINATE',
            recordData: {'id': id, 'type': terminationType},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'EmployeesRepository',
        action: 'terminate',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'id': '$id', 'type': terminationType},
      );
      rethrow;
    }
  }

  /// إعادة تفعيل موظف مفصول / مستغنى عنه
  Future<int> reactivate({required int id}) async {
    try {
      final result = await dao.updateById(
        id,
        const EmployeesCompanion(
          status: d.Value('active'),
          terminationDate: d.Value<String?>(null),
          terminationReason: d.Value<String?>(null),
        ),
      );
      if (result > 0) {
        unawaited(
          AutoBackupManager.instance.onDataChange(
            'employees',
            'REACTIVATE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'EmployeesRepository',
        action: 'reactivate',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  Future<int> delete(int id) async {
    try {
      final result = await dao.softDelete(id);
      if (result > 0) {
        unawaited(
          AutoBackupManager.instance.onDataChange(
            'employees',
            'DELETE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'EmployeesRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  /// ✅ (2026-09-21) عدّاد التاريخ المالي للموظف — «لفصل موظف استخدم
  /// «إنهاء الخدمة» من التطبيق (تغيّر الحالة فقط)؛ أما الحذف فيتيّم
  /// تاريخه المالي على بقية الأجهزة».
  ///
  /// الجذر: حذف ستة موظفين خادمياً في 2026-09 علّق 299 سحباً حياً على
  /// الأجهزة الجديدة (tombstone الأب يُسلَّم no-op فلا يُبنى ظل
  /// server_id فتؤجَّل أبناؤه للأبد — انظر حارس الرفض الدائم في
  /// worker/src/sync.ts لعقد التطابق).
  ///
  /// هذا هو خط الدفاع الأول في التطبيق: قبل أي حذف موظف تُفحص الجداول
  /// الخمسة الحاملة لتاريخه. عقد الربط مطابق للخادم (employee_uuid
  /// أولاً — dash-insensitive لأن الإنتاج يحوي الشكلين — ثم المسك الرقمي
  /// employee_id/related_id = e.id سقوطاً للصفوف عديمة uuid، ومسك
  /// expenses الرقمي يُعتمد فقط مع أنواع المصروفات المرتبطة
  /// بالموظف — دونها يحجب حجزُ غرفةٍ عابرٌ الحذفَ بمجرد تطابق رقمي).
  /// الـ tombstones تُحتسب: التاريخ المحذوف ناعماً قابل للإحياء.
  ///
  /// أبداً لا ترمي — الفشل يُعاد كـ [EmployeeFinancialHistory.unknown]
  /// فيُمنع الحذف احتياطاً (الاتجاه الآمن؛ الرفض النهائي مسؤولية الخادم).
  Future<EmployeeFinancialHistory> financialHistoryCount({
    required int id,
    required String localUuid,
  }) async {
    final dashless = localUuid.replaceAll('-', '');
    final types = _employeeLinkedExpenseTypes.toList(growable: false);
    final typeHolders = List.filled(types.length, '?').join(',');
    try {
      final rows = await db
          .customSelect(
            'SELECT '
            '(SELECT COUNT(*) FROM salary_withdrawals w WHERE '
            '   (w.employee_uuid IS NOT NULL AND REPLACE(w.employee_uuid, \'-\', \'\') = ?) '
            'OR (w.employee_uuid IS NULL AND w.employee_id = e.id)) AS withdrawals, '
            '(SELECT COUNT(*) FROM salary_cycles c WHERE '
            '   (c.employee_uuid IS NOT NULL AND REPLACE(c.employee_uuid, \'-\', \'\') = ?) '
            'OR (c.employee_uuid IS NULL AND c.employee_id = e.id)) AS cycles, '
            '(SELECT COUNT(*) FROM salary_payments p WHERE '
            '   p.employee_uuid IS NOT NULL '
            '    AND REPLACE(p.employee_uuid, \'-\', \'\') = ?) AS payments, '
            '(SELECT COUNT(*) FROM salary_carry_over_logs k WHERE '
            '   k.employee_id = e.id) AS carryovers, '
            '(SELECT COUNT(*) FROM expenses x WHERE '
            '   (x.employee_uuid IS NOT NULL AND REPLACE(x.employee_uuid, \'-\', \'\') = ?) '
            'OR (x.employee_uuid IS NULL AND x.related_id = e.id '
            '    AND TRIM(x.expense_type) IN ($typeHolders))) AS expenses '
            'FROM employees e WHERE e.id = ?',
            variables: [
              d.Variable.withString(dashless),
              d.Variable.withString(dashless),
              d.Variable.withString(dashless),
              d.Variable.withString(dashless),
              ...types.map(d.Variable.withString),
              d.Variable.withInt(id),
            ],
          )
          .get();
      if (rows.isEmpty) {
        // الموظف نفسه غير موجود محلياً — لا صف، لا تاريخ معلوم
        return const EmployeeFinancialHistory.unknown();
      }
      final row = rows.first;
      return EmployeeFinancialHistory(
        withdrawals: row.read<int>('withdrawals'),
        cycles: row.read<int>('cycles'),
        payments: row.read<int>('payments'),
        carryOvers: row.read<int>('carryovers'),
        expenses: row.read<int>('expenses'),
      );
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'EmployeesRepository',
        action: 'financialHistoryCount',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.warning,
        extra: {'employeeId': '$id'},
      );
      return const EmployeeFinancialHistory.unknown();
    }
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات الموظفين
  Future<Map<String, dynamic>> exportData() async {
    final employeesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': employeesData, 'count': recordCount, 'entity': 'employees'};
  }

  /// استيراد بيانات الموظفين
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data'] as List),
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return dao.getRecordCount();
  }
}

/// ✅ (2026-09-21) نتيجة فحص التاريخ المالي للموظف قبل الحذف —
/// عدّادات لكل جدول مرتبط + [total]. انظر التوثيق الكامل على
/// [EmployeesRepository.financialHistoryCount].
///
/// عند تعذر الفحص تُعاد النسخة المصنع عليها [unknown] (isKnown=false)
/// ويمنع [blocksDeletion] الحذف احتياطاً — الاتجاه الآمن دائماً:
/// تعذّر التحقق لا يبرر تيتم التاريخ المالي على بقية الأجهزة.
class EmployeeFinancialHistory {
  const EmployeeFinancialHistory({
    required this.withdrawals,
    required this.cycles,
    required this.payments,
    required this.carryOvers,
    required this.expenses,
    this.isKnown = true,
  });

  const EmployeeFinancialHistory.unknown()
    : withdrawals = 0,
      cycles = 0,
      payments = 0,
      carryOvers = 0,
      expenses = 0,
      isKnown = false;

  /// سحوبات رواتب (salary_withdrawals)
  final int withdrawals;

  /// دورات رواتب (salary_cycles)
  final int cycles;

  /// مدفوعات رواتب (salary_payments)
  final int payments;

  /// ترحيلات راتب (salary_carry_over_logs)
  final int carryOvers;

  /// مصروفات مرتبطة بالموظف (expenses)
  final int expenses;

  /// false = تعذر الفحص (فشل الاستعلام أو غياب الموظف محلياً)
  final bool isKnown;

  int get total => withdrawals + cycles + payments + carryOvers + expenses;

  /// هل يُمنع الحذف؟ — يوجد تاريخ مرتبط، أو تعذّر التحقق أصلاً.
  bool get blocksDeletion => !isKnown || total > 0;
}
