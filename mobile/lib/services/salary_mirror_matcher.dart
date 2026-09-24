// ═══════════════════════════════════════════════════════════════
//  salary_mirror_matcher.dart — (2026-09-25)
//
//  «المرآة» = سجل salary_withdrawals الذي يمثل مصروف راتب مقابلاً.
//  الرابط بينهما موجود بشكلين في الكود الموجود (نفس منطق
//  saveFromExpense في SalaryWithdrawalsRepository و«الطريقتان 1/2»
//  في expenses_report_screen):
//
//    Level 1: عمود expense_id الخام (migration 40) — الأكثر موثوقية.
//    Level 2: علامة reason = 'exp_<id>' — الرابط عبر الأجهزة قبل
//             وجود العمود، ويُطابق بـ RegExp(r'exp_(\d+)').
//
//  تُستخرج هنا دالتان عامتان من ذلك المنطق كي يستخدمهما تنظيف
//  التكرار في تقرير سحبيات الرواتب (dedupeMirrorDuplicates) بدل
//  إعادة تفسيره في كل مكان:
//
//    • hasMirrorMarker       — هل السحوبة تحمل علامة ربط أصلاً
//                              (بصرف النظر عن نجاح الحلّ)؟
//    • resolveLinkedExpenseId — حلّ الرابط (Level 1/2) إلى id
//                              مصروف محلي حقيقي (حي) أو null.
//
//  عقد صارم بلا تخمين: resolveLinkedExpenseId لا يُعيد أبداً id
//  مصروف غير موجود أو محذوف ناعماً — الرابط إلى هدف غير حي يُعد
//  «رابطاً أجنبياً مكسوراً» ويُرجع null (المرآة اليتيمة).
// ═══════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' as d;

import 'local_db.dart';

class SalaryMirrorMatcher {
  SalaryMirrorMatcher._();

  /// نفس نمط «الطريقة 2» في expenses_report_screen: exp_ متبوعاً
  /// برقم كامل — يلتقط الرقم كاملاً فلا يختلط exp_1 بـ exp_10.
  static final RegExp _expenseRefPattern = RegExp(r'exp_(\d+)');

  /// هل السحوبة تحمل علامة ربط بمصروف أصلاً؟
  ///
  /// تعتمد على وجود أي دليل ربط آلي:
  ///  • Level 1: العمود الخام expense_id > 0، أو
  ///  • Level 2: reason يحتوي exp_<أرقام> (النمط الآلي فقط —
  ///    reason مكتوب يدوياً بلا نمط exp_ لا يُعتبر علامة).
  ///
  /// لا تبحث في قاعدة البيانات إطلاقاً — بصرف النظر عن نجاح الحلّ.
  static bool hasMirrorMarker(SalaryWithdrawal sw) {
    final columnId = sw.expenseId;
    if (columnId != null && columnId > 0) {
      return true;
    }
    final reason = sw.reason;
    if (reason == null || reason.isEmpty) {
      return false;
    }
    return _expenseRefPattern.hasMatch(reason);
  }

  /// حلّ رابط المرآة (Level 1/2) إلى id مصروف محلي حقيقي أو null.
  ///
  ///  • Level 1: expense_id يشير إلى مصروف حي → يُعاد فوراً
  ///    (الأعلى موثوقية — نفس أولوية «الطريقة 1» في saveFromExpense).
  ///  • Level 2: fallback على reason — تُستخرج كل مراجع exp_<id>
  ///    ويُعاد الوحيد الحي منها. أكثر من هدف حي واحد = غموض → null
  ///    (الحذف الآلي للغامض مرفوض مالياً).
  ///  • هدف غير موجود أو محذوف ناعماً = رابط مكسور → null.
  ///
  /// «حقيقي» = صف expenses موجود و deleted_at IS NULL.
  static Future<int?> resolveLinkedExpenseId(
    AppDatabase db,
    SalaryWithdrawal sw,
  ) async {
    // ─── Level 1: عمود expense_id الخام (الأكثر موثوقية) ───
    final columnId = sw.expenseId;
    if (columnId != null &&
        columnId > 0 &&
        await _expenseIsLive(db, columnId)) {
      return columnId;
    }

    // ─── Level 2: علامة reason = exp_<id> (الطريقة القديمة) ───
    final reason = sw.reason;
    if (reason != null && reason.isNotEmpty) {
      final candidateIds = _expenseRefPattern
          .allMatches(reason)
          .map((m) => int.tryParse(m.group(1)!))
          .whereType<int>()
          .toSet();
      final liveIds = <int>[];
      for (final id in candidateIds) {
        if (await _expenseIsLive(db, id)) {
          liveIds.add(id);
        }
      }
      if (liveIds.length == 1) {
        return liveIds.single;
      }
      // 0 → رابط مكسور؛ >1 → غموض — null في الحالين.
    }

    return null;
  }

  /// هل المصروف موجود محلياً وحيّاً (غير محذوف ناعماً)؟
  static Future<bool> _expenseIsLive(AppDatabase db, int expenseId) async {
    final row =
        await (db.select(db.expenses)..where(
              (e) => e.id.equals(expenseId) & e.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row != null;
  }
}
