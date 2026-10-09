// ═══════════════════════════════════════════════════════════════
//  salary_mirror_matcher.dart
//
//  عقد الربط الثابت:
//   • local_uuid هو هوية كل سجل.
//   • expenses.employee_uuid / salary_withdrawals.employee_uuid يربطان
//     الموظف عبر الأجهزة.
//   • salary_withdrawals.expense_uuid / expenses.withdrawal_uuid يربطان
//     المرآة المالية عبر الأجهزة.
//
//  expense_id وreason=exp_<id> لا يُستخدمان إلا كمسار توافق لبيانات
//  محلية قديمة تفتقد روابط UUID؛ لا يُعتمدان كهوية مزامنة.
// ═══════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';

import 'local_db.dart';
import 'sync/payload_mapper.dart';

class SalaryMirrorMatcher {
  SalaryMirrorMatcher._();

  static final RegExp _expenseRefPattern = RegExp(r'exp_(\d+)');

  /// هل توجد علامة رابط للمرآة؟ تُستكمل العلامات العكسية من expenses
  /// في dedupeMirrorDuplicates لأن هذه الدالة لا تقرأ قاعدة البيانات.
  static bool hasMirrorMarker(SalaryWithdrawal sw) {
    if (_nonEmpty(sw.expenseUuid) != null) return true;
    if (sw.expenseId != null && sw.expenseId! > 0) return true;
    final reason = sw.reason;
    return reason != null && _expenseRefPattern.hasMatch(reason);
  }

  /// رابط UUID متوافق بين سجل المصروف وسجل السحبة.
  /// إذا وُجدت مراجع UUID متعارضة، لا نُسقطها إلى مطابقة رقمية.
  static bool hasStableExpenseLink(Expense expense, SalaryWithdrawal sw) {
    final expenseRef = _nonEmpty(sw.expenseUuid);
    final withdrawalRef = _nonEmpty(expense.withdrawalUuid);

    if (expenseRef != null && expenseRef != expense.localUuid) return false;
    if (withdrawalRef != null && withdrawalRef != sw.localUuid) return false;

    return expenseRef == expense.localUuid || withdrawalRef == sw.localUuid;
  }

  /// مطابقة الموظف عبر UUID أولاً. لا نستخدم الأرقام المحلية إذا كان
  /// أحد الطرفين يحمل UUID؛ اختلاف UUID دليل تعارض لا يجوز تجاهله.
  static bool employeesMatch(Expense expense, SalaryWithdrawal sw) {
    final expenseUuid = _nonEmpty(expense.employeeUuid);
    final withdrawalUuid = _nonEmpty(sw.employeeUuid);
    if (expenseUuid != null || withdrawalUuid != null) {
      return expenseUuid != null &&
          withdrawalUuid != null &&
          expenseUuid == withdrawalUuid;
    }
    if (expense.employeeLinkCleared != 0) return false;
    return expense.relatedId != null && expense.relatedId == sw.employeeId;
  }

  /// يحل مرجع السحبة إلى local_uuid للمصروف الحي.
  /// UUID هو المصدر الأول والمرجع الرقمي لا يُستخدم إلا إذا كان UUID
  /// مفقوداً بالكامل في السجل القديم.
  static Future<String?> resolveLinkedExpenseUuid(
    AppDatabase db,
    SalaryWithdrawal sw,
  ) async {
    final stableRef = _nonEmpty(sw.expenseUuid);
    if (stableRef != null) {
      final expense = await _liveExpenseByUuid(db, stableRef);
      return expense != null &&
              PayloadMapper.isSalaryExpenseType(expense.expenseType) &&
              hasStableExpenseLink(expense, sw)
          ? stableRef
          : null;
    }

    // الرابط العكسي المستقر في expenses.
    final reverseRows =
        await (db.select(db.expenses)..where(
              (e) =>
                  e.withdrawalUuid.equals(sw.localUuid) & e.deletedAt.isNull(),
            ))
            .get();
    final reverseUuids = reverseRows
        .where((e) => PayloadMapper.isSalaryExpenseType(e.expenseType))
        .map((e) => e.localUuid)
        .where((uuid) => uuid.isNotEmpty)
        .toSet();
    if (reverseUuids.length == 1) return reverseUuids.single;
    if (reverseUuids.length > 1) return null;

    // توافق فقط لسجلات محلية قديمة لم تُخزّن expense_uuid.
    final legacyId = sw.expenseId;
    if (legacyId != null && legacyId > 0) {
      final uuid = await _liveExpenseUuidByLocalId(db, legacyId);
      if (uuid != null) return uuid;
    }

    final reason = sw.reason;
    if (reason == null || reason.isEmpty) return null;
    final candidateIds = _expenseRefPattern
        .allMatches(reason)
        .map((m) => int.tryParse(m.group(1)!))
        .whereType<int>()
        .toSet();
    final liveUuids = <String>{};
    for (final id in candidateIds) {
      final uuid = await _liveExpenseUuidByLocalId(db, id);
      if (uuid != null) liveUuids.add(uuid);
    }
    return liveUuids.length == 1 ? liveUuids.single : null;
  }

  static Future<String?> _liveExpenseUuidByLocalId(
    AppDatabase db,
    int expenseId,
  ) async {
    final row =
        await (db.select(db.expenses)..where(
              (e) => e.id.equals(expenseId) & e.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (row == null || !PayloadMapper.isSalaryExpenseType(row.expenseType)) {
      return null;
    }
    return row.localUuid;
  }

  static Future<Expense?> _liveExpenseByUuid(
    AppDatabase db,
    String expenseUuid,
  ) async {
    return (db.select(db.expenses)..where(
          (e) => e.localUuid.equals(expenseUuid) & e.deletedAt.isNull(),
        ))
        .getSingleOrNull();
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
