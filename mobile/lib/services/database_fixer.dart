import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../utils/expense_reason_matcher.dart';
import 'local_db.dart';
import 'repositories/expenses_repository.dart';
import 'sync/payload_mapper.dart';

/// خدمة لإصلاح البيانات الفاسدة في قاعدة البيانات
class DatabaseFixer {

  DatabaseFixer(this.db);
  final AppDatabase db;

  /// إصلاح جميع المشاكل المعروفة في قاعدة البيانات
  Future<FixResult> fixAllIssues() async {
    final result = FixResult();

    try {
      // 1. إصلاح serverId التي تحتوي على UUID بدلاً من أرقام
      result.serverIdFixed = await _fixInvalidServerIds();

      // 2. إصلاح المدفوعات التي تشير لحجوزات غير موجودة
      result.orphanPaymentsFixed = await _fixOrphanPayments();

      // 3. إصلاح المصروفات التي تشير لبيانات غير موجودة
      result.orphanExpensesFixed = await _fixOrphanExpenses();

      result.success = true;
    } catch (e) {
      result.error = e.toString();
      result.success = false;
    }

    return result;
  }

  /// إصلاح serverId التي تحتوي على UUID
  Future<int> _fixInvalidServerIds() async {
    int fixed = 0;

    try {
      // إصلاح serverId في جدول Rooms
      final roomsQuery = await db
          .customSelect(
            'SELECT id, server_id FROM rooms WHERE server_id IS NOT NULL',
          )
          .get();

      for (final row in roomsQuery) {
        final serverId = row.data['server_id'];
        if (serverId != null && serverId is String) {
          // إذا كان serverId يحتوي على UUID (يحتوي على -)
          if (serverId.contains('-')) {
            await db.customUpdate(
              'UPDATE rooms SET server_id = NULL WHERE id = ?',
              variables: [Variable.withInt(row.data['id'] as int)],
              updates: {db.rooms},
            );
            fixed++;
          }
        }
      }

      // إصلاح serverId في جدول Payments
      final paymentsQuery = await db
          .customSelect(
            'SELECT id, server_id FROM payments WHERE server_id IS NOT NULL',
          )
          .get();

      for (final row in paymentsQuery) {
        final serverId = row.data['server_id'];
        if (serverId != null && serverId is String) {
          if (serverId.contains('-')) {
            await db.customUpdate(
              'UPDATE payments SET server_id = NULL WHERE id = ?',
              variables: [Variable.withInt(row.data['id'] as int)],
              updates: {db.payments},
            );
            fixed++;
          }
        }
      }

      // إصلاح serverId في جدول Expenses
      final expensesQuery = await db
          .customSelect(
            'SELECT id, server_id FROM expenses WHERE server_id IS NOT NULL',
          )
          .get();

      for (final row in expensesQuery) {
        final serverId = row.data['server_id'];
        if (serverId != null && serverId is String) {
          if (serverId.contains('-')) {
            await db.customUpdate(
              'UPDATE expenses SET server_id = NULL WHERE id = ?',
              variables: [Variable.withInt(row.data['id'] as int)],
              updates: {db.expenses},
            );
            fixed++;
          }
        }
      }

      debugPrint('Fixed $fixed invalid serverId records');
    } catch (e) {
      debugPrint('Error fixing serverId: $e');
    }

    return fixed;
  }

  /// إصلاح المدفوعات اليتيمة (التي تشير لحجوزات غير موجودة)
  Future<int> _fixOrphanPayments() async {
    int fixed = 0;

    try {
      // البحث عن المدفوعات التي تشير لحجوزات غير موجودة
      final orphanPayments = await db.customSelect('''
        SELECT p.id, p.booking_local_id, p.room_number
        FROM payments p
        LEFT JOIN bookings b ON p.booking_local_id = b.id
        WHERE p.booking_local_id IS NOT NULL 
          AND b.id IS NULL
          AND p.deleted_at IS NULL
        ''').get();

      for (final payment in orphanPayments) {
        final paymentId = payment.data['id'] as int;
        // إزالة الربط بالحجز غير الموجود
        await db.customUpdate(
          'UPDATE payments SET booking_local_id = NULL WHERE id = ?',
          variables: [Variable.withInt(paymentId)],
          updates: {db.payments},
        );
        fixed++;
        debugPrint('Fixed orphan payment: $paymentId');
      }

      debugPrint('Fixed $fixed orphan payments');
    } catch (e) {
      debugPrint('Error fixing orphan payments: $e');
    }

    return fixed;
  }

  /// إصلاح المصروفات اليتيمة
  ///
  /// ✅ التوصية 6: توسّع هذه الدالة لتشمل مصروفات الرواتب.
  ///
  /// قبل هذا الإصلاح كانت الدالة تتعامل فقط مع `expenseType == 'employee'`
  /// و `'booking'`، وكانت **تُصفّر** `related_id` عند غياب الهدف. هذا يُفقد
  /// ربط مصروفات الرواتب بصمت (خطر — راجع القسم 4 من تقرير التوصيات).
  ///
  /// السلوك الجديد لمصروفات الرواتب (التي يكتشفها `PayloadMapper.isSalaryExpenseType`):
  /// 1. إن وُجد `employeeUuid` صالح وحُلَّ عبره موظف محلي → **إعادة الربط**
  ///    بـ `related_id = employee.id` (لا تصفير).
  /// 2. إن تعذّر الحل (UUID فارغ أو موظف غير موجود بعد) → **لا نُصفّر**
  ///    `related_id` بل نتركه ونكتب تحذيرًا، حتى لا نفقد الربط بصمت.
  ///    يُعالَج لاحقًا عبر `_relinkOrphanSalaryExpenses` عند وصول الموظف.
  ///
  /// مصروفات `'employee'` و `'booking'` تحتفظ بسلوكها القديم (التصفير)
  /// لأنها لا تحمل UUID محمولًا.
  Future<int> _fixOrphanExpenses() async {
    int fixed = 0;
    int relinked = 0;

    // ✅ استخدم ExpensesRepository.update() بدل customUpdate المباشر لضمان:
    // - تحديث lastModified + updatedAt تلقائياً (للرفع للسحاب)
    // - إضافة العملية للـ outbox (للمزامنة التلقائية مع Appwrite Cloud)
    // - توافق الحقول camelCase مع مخطط Appwrite Cloud
    final repo = ExpensesRepository(db);

    try {
      // ✅ التوصية 6: نختار أيضاً employee_uuid للإعادة ربط الرواتب عبر UUID.
      final orphanExpenses = await db.customSelect('''
        SELECT e.id, e.related_id, e.expense_type, e.employee_uuid
        FROM expenses e
        WHERE e.related_id IS NOT NULL
          AND e.deleted_at IS NULL
        ''').get();

      for (final expense in orphanExpenses) {
        final expenseId = expense.data['id'] as int;
        final relatedId = expense.data['related_id'] as int?;
        final expenseType = expense.data['expense_type'] as String;
        final employeeUuid = expense.data['employee_uuid'] as String?;

        bool shouldFix = false;

        // التحقق من وجود البيانات المرتبطة بناءً على نوع المصروف
        if (relatedId != null) {
          // ✅ التوصية 6: فرع مصروفات الرواتب — إعادة ربط عبر UUID لا تصفير.
          if (PayloadMapper.isSalaryExpenseType(expenseType)) {
            // تحقق أن الموظف المحلي المرتبط عبر relatedId ما زال موجودًا.
            final employee = await (db.select(db.employees)
                  ..where((e) => e.id.equals(relatedId))
                  ..limit(1))
                .getSingleOrNull();
            if (employee == null) {
              // الموظف المحلي غير موجود — حاول إعادة الربط عبر employeeUuid.
              if (employeeUuid != null && employeeUuid.isNotEmpty) {
                final byUuid = await (db.select(db.employees)
                      ..where((e) => e.localUuid.equals(employeeUuid))
                      ..limit(1))
                    .getSingleOrNull();
                if (byUuid != null) {
                  // ✅ إعادة الربط عبر UUID — لا تصفير.
                  // repo.update يُحدّث lastModified + updatedAt + يُضيف للـ outbox.
                  await repo.update(
                    expenseId,
                    relatedId: byUuid.id,
                    employeeUuid: byUuid.localUuid,
                  );
                  relinked++;
                  debugPrint(
                    'Re-linked orphan salary expense #$expenseId → '
                    'employee #${byUuid.id} (uuid: $employeeUuid) '
                    '+ lastModified updated for cloud sync',
                  );
                  // تمت المعالجة — لا نمرّ عبر فرع التصفير.
                  continue;
                } else {
                  // UUID موجود لكن الموظف لم يصل بعد — لا نُصفّر.
                  debugPrint(
                    '⚠️ Salary expense #$expenseId has employeeUuid '
                    '$employeeUuid but employee not yet synced — '
                    'left related_id=$relatedId intact (not zeroed).',
                  );
                  continue;
                }
              } else {
                // ✅ لا UUID ولا موظف محلي — حاول عبر salary_withdrawals
                // كرابط عكسي موثوق (السحب يحتفظ بـ employeeId الصحيح دائماً).
                // هذا يُكمّل التوصية 6 ويُغطّي البيانات القديمة جداً التي
                // ليس لها employeeUuid أصلاً.
                int? employeeIdFromWithdrawal;
                try {
                  final swRow = await db.customSelect(
                    'SELECT employee_id FROM salary_withdrawals '
                    'WHERE expense_id = ? AND deleted_at IS NULL LIMIT 1',
                    variables: [Variable.withInt(expenseId)],
                    readsFrom: {db.salaryWithdrawals},
                  ).getSingleOrNull();
                  if (swRow != null) {
                    employeeIdFromWithdrawal = swRow.read<int>('employee_id');
                  }
                } catch (_) {
                  // العمود expense_id قد لا يكون موجوداً في DBs القديمة جداً.
                }

                // fallback: ابحث عبر reason للسجلات القديمة جداً.
                if (employeeIdFromWithdrawal == null) {
                  final swByReason = await db.customSelect(
                    'SELECT employee_id, reason FROM salary_withdrawals '
                    'WHERE deleted_at IS NULL AND reason LIKE ?',
                    variables: [Variable.withString('%exp_$expenseId%')],
                    readsFrom: {db.salaryWithdrawals},
                  ).get();
                  for (final sw in swByReason) {
                    final reason = sw.read<String?>('reason');
                    if (reason != null &&
                        matchesExpenseRef(reason, expenseId)) {
                      employeeIdFromWithdrawal = sw.read<int>('employee_id');
                      break;
                    }
                  }
                }

                if (employeeIdFromWithdrawal != null) {
                  // حلّ الموظف من employeeId المستخرج من السحب.
                  final byWithdrawal = await (db.select(db.employees)
                        ..where((e) => e.id.equals(employeeIdFromWithdrawal!))
                        ..where((e) => e.deletedAt.isNull())
                        ..limit(1))
                      .getSingleOrNull();
                  if (byWithdrawal != null) {
                    // ✅ إعادة ربط عبر السحب + ملء employeeUuid لتفادي
                    // المشكلة مستقبلاً (التوصية 1).
                    // repo.update يُحدّث lastModified + updatedAt + يُضيف للـ outbox.
                    await repo.update(
                      expenseId,
                      relatedId: byWithdrawal.id,
                      employeeUuid: byWithdrawal.localUuid,
                    );
                    relinked++;
                    debugPrint(
                      'Re-linked orphan salary expense #$expenseId via '
                      'salary_withdrawal → employee #${byWithdrawal.id} '
                      '(uuid: ${byWithdrawal.localUuid}) '
                      '+ lastModified updated for cloud sync',
                    );
                    continue;
                  }
                }

                // فشل كل شيء: لا نُصفّر مصروف الراتب (تفادي فقدان الربط
                // بصمت). نترك relatedId القديم ونُسجّل تحذيرًا.
                debugPrint(
                  '⚠️ Salary expense #$expenseId is orphan with empty '
                  'employeeUuid and no salary_withdrawal — left '
                  'related_id=$relatedId intact (not zeroed).',
                );
                continue;
              }
            }
            // الموظف المحلي موجود — الربط سليم، لا شيء لنفعله.
            continue;
          } else if (expenseType == 'employee') {
            final employee = await (db.select(
              db.employees,
            )..where((e) => e.id.equals(relatedId))).getSingleOrNull();
            if (employee == null) {
              shouldFix = true;
            }
          } else if (expenseType == 'booking') {
            final booking = await (db.select(
              db.bookings,
            )..where((b) => b.id.equals(relatedId))).getSingleOrNull();
            if (booking == null) {
              shouldFix = true;
            }
          }
        }

        if (shouldFix) {
          // إزالة الربط بالبيانات غير الموجودة (يبقى سلوك 'employee'/'booking' كما هو)
          await db.customUpdate(
            'UPDATE expenses SET related_id = NULL WHERE id = ?',
            variables: [Variable.withInt(expenseId)],
            updates: {db.expenses},
          );
          fixed++;
          debugPrint('Fixed orphan expense: $expenseId');
        }
      }

      debugPrint(
        'Fixed $fixed orphan expenses; re-linked $relinked salary expenses via UUID',
      );
    } catch (e) {
      debugPrint('Error fixing orphan expenses: $e');
    }

    return fixed + relinked;
  }

  /// التحقق من صحة قاعدة البيانات
  Future<ValidationReport> validate() async {
    final report = ValidationReport();

    try {
      // التحقق من serverId الفاسدة
      final invalidServerIds = await db.customSelect('''
        SELECT 'rooms' as table_name, COUNT(*) as count 
        FROM rooms 
        WHERE server_id IS NOT NULL AND typeof(server_id) = 'text' AND server_id LIKE '%-%'
        UNION ALL
        SELECT 'payments', COUNT(*) 
        FROM payments 
        WHERE server_id IS NOT NULL AND typeof(server_id) = 'text' AND server_id LIKE '%-%'
        UNION ALL
        SELECT 'expenses', COUNT(*) 
        FROM expenses 
        WHERE server_id IS NOT NULL AND typeof(server_id) = 'text' AND server_id LIKE '%-%'
        ''').get();

      int totalInvalidServerIds = 0;
      for (final row in invalidServerIds) {
        final count = row.data['count'] as int;
        totalInvalidServerIds += count;
      }
      report.invalidServerIds = totalInvalidServerIds;

      // التحقق من المدفوعات اليتيمة
      final orphanPaymentsResult = await db.customSelect('''
        SELECT COUNT(*) as count
        FROM payments p
        LEFT JOIN bookings b ON p.booking_local_id = b.id
        WHERE p.booking_local_id IS NOT NULL 
          AND b.id IS NULL
          AND p.deleted_at IS NULL
        ''').getSingle();

      report.orphanPayments = orphanPaymentsResult.data['count'] as int;

      // التحقق من المصروفات اليتيمة
      final orphanExpensesResult = await db.customSelect('''
        SELECT COUNT(*) as count
        FROM expenses e
        WHERE e.related_id IS NOT NULL 
          AND e.deleted_at IS NULL
        ''').getSingle();

      report.orphanExpenses = orphanExpensesResult.data['count'] as int;

      report.hasIssues =
          report.invalidServerIds > 0 ||
          report.orphanPayments > 0 ||
          report.orphanExpenses > 0;
    } catch (e) {
      report.error = e.toString();
    }

    return report;
  }
}

class FixResult {
  bool success = false;
  String? error;
  int serverIdFixed = 0;
  int orphanPaymentsFixed = 0;
  int orphanExpensesFixed = 0;

  int get totalFixed =>
      serverIdFixed + orphanPaymentsFixed + orphanExpensesFixed;

  @override
  String toString() {
    if (!success) {
      return 'فشل الإصلاح: $error';
    }
    return '''
تم الإصلاح بنجاح:
- serverId فاسدة: $serverIdFixed
- مدفوعات يتيمة: $orphanPaymentsFixed
- مصروفات يتيمة: $orphanExpensesFixed
الإجمالي: $totalFixed
    ''';
  }
}

class ValidationReport {
  bool hasIssues = false;
  String? error;
  int invalidServerIds = 0;
  int orphanPayments = 0;
  int orphanExpenses = 0;

  int get totalIssues => invalidServerIds + orphanPayments + orphanExpenses;

  @override
  String toString() {
    if (error != null) {
      return 'خطأ في التحقق: $error';
    }
    if (!hasIssues) {
      return 'قاعدة البيانات صحيحة ✓';
    }
    return '''
تم العثور على مشاكل:
- serverId فاسدة: $invalidServerIds
- مدفوعات يتيمة: $orphanPayments
- مصروفات يتيمة: $orphanExpenses
الإجمالي: $totalIssues
    ''';
  }
}
