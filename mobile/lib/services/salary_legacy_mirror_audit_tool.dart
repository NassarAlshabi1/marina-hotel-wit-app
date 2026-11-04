// lib/services/salary_legacy_mirror_audit_tool.dart
//
// ✅ (2026-11-05 — وثيقة الربط والمزامنة الموحدة §6.3) أداة معالجة تاريخية
// منفصلة ومدقّقة — المستوى الرابع القديم من SalaryMirrorMatcher.
//
// §6.3: «إزالة المستوى الرابع من SalaryMirrorMatcher الذي يتجاهل المبلغ.
// تبقى المطابقة القديمة فقط في أداة معالجة تاريخية منفصلة ومدقّقة».
//
// القواعد الملزمة (§1.3/§6.3/§14):
// - قراءة فقط: لا تكتب في قاعدة البيانات إطلاقاً — لا outbox، لا
//   version/lastModified، لا ربط، لا حذف. النتيجة «أدلة» للعرض في
//   تقارير السلامة (§11) وتقرير المطابقة (§16.4-E) فقط.
// - «المرشّح الفريد ليس إثباتاً» (§14) — الناتج باسم suspected لا
//   matched، ولا يدخل في أي إجمالي مالي، ولا يُنسب تشغيلياً لأي مصروف.
// - تُستخدم لعرض حالات «مرآة بعلامة رابط أجنبي/مبلغ معدّل» التي لا تحسمها
//   المستويات 0-3، لتُراجع يدوياً أو من الجهاز المنشئ/مصدر موثوق.
import 'salary_expense_classifier.dart';
import 'salary_mirror_matcher.dart';

/// مرشّح مشتبه به ناتج عن الخوارزمية التاريخية (المستوى 4 القديم):
/// مرآة تحمل علامة رابط (expenseId أو reason=exp_N) لا يقابلها مصروف
/// محلي بالمستويات 0-2، وتوجد مصفوفة وحيدة لنفس الموظف/اليوم من نفس
/// العائلة (نقدي لمرآة موجبة / خصم لمرآة سالبة) **بغض النظر عن المبلغ**.
class LegacyMirrorSuspicion {
  const LegacyMirrorSuspicion({
    required this.withdrawalId,
    required this.withdrawalLocalUuid,
    required this.withdrawalEmployeeId,
    required this.withdrawalExpenseId,
    required this.withdrawalReason,
    required this.withdrawalAmount,
    required this.withdrawDate,
    required this.withdrawalHotelDayKey,
    required this.suspectedExpenseId,
    required this.suspectedExpenseType,
    required this.suspectedExpenseAmount,
    this.suspectedExpenseLocalUuid,
    required this.amountDiffers,
  });

  final int withdrawalId;
  final String withdrawalLocalUuid;
  final int withdrawalEmployeeId;
  final int? withdrawalExpenseId;
  final String? withdrawalReason;
  final double withdrawalAmount;
  final String withdrawDate;
  final String? withdrawalHotelDayKey;

  final int suspectedExpenseId;
  final String suspectedExpenseType;
  final double suspectedExpenseAmount;
  final String? suspectedExpenseLocalUuid;

  /// هل اختلف المبلغ بين المرآة والمرشّح؟ (السبب التاريخي للمستوى 4)
  final bool amountDiffers;
}

/// أداة التدقيق التاريخي — static وبلا حالة، قراءة فقط (§6.3).
class SalaryLegacyMirrorAuditTool {
  SalaryLegacyMirrorAuditTool._();

  /// يفحص المرايا ذات «علامة رابط غير محلولة» (expenseId/remote أو
  /// reason=exp_N) ضد مصفوفة وحيدة لنفس الموظف/اليوم/العائلة بغض
  /// النظر عن المبلغ — كما كان المستوى 4 قبل إزالته من المطابِق التشغيلي.
  ///
  /// لا يكتب أي شيء: يعيد قائمة أدلة [LegacyMirrorSuspicion] لتقارير
  /// السلامة فقط. السحوبات المباشرة (direct_withdrawal_) مستثناة دائماً.
  static List<LegacyMirrorSuspicion> findSuspectedMatches({
    required Iterable<LegacyAuditWithdrawal> withdrawals,
    required Iterable<MirrorExpenseCandidate> expenses,
  }) {
    final suspicions = <LegacyMirrorSuspicion>[];

    for (final w in withdrawals) {
      // حارس السحب المباشر — ليس مرآة أبداً (نفس حارس المطابِق).
      final rawReason = (w.reason ?? '').trim();
      if (rawReason.startsWith('direct_withdrawal_')) continue;

      // علامة مرآة فقط: رابط رقمي أو exp_N (بلاها لا استدلال أصلاً).
      final markerInReason = RegExp(r'exp_\d+').hasMatch(rawReason);
      final rawExpId = w.expenseId ?? 0;
      if (!(rawExpId > 0 || markerInReason)) continue;

      // إذا حسم المستوى 0/1/2 الرابط محلياً فليست «غير محلولة».
      final resolved = SalaryMirrorMatcher.resolveLinkedExpenseId(
        expenseUuid: w.expenseUuid,
        expenseId: w.expenseId,
        reason: w.reason,
        expenses: expenses,
      );
      if (resolved != null) continue;

      // الخوارزمية التاريخية (المستوى 4 القديم) — دليل فقط.
      final positive = w.amount > 0;
      MirrorExpenseCandidate? uniqueCandidate;
      var familyMatches = 0;
      for (final e in expenses) {
        if (e.relatedId != w.employeeId) continue;
        final familyOk = positive
            ? SalaryExpenseClassifier.isSalaryCashOut(e.expenseType)
            : SalaryExpenseClassifier.isSalaryDeduction(e.expenseType);
        if (!familyOk) continue;
        if (!_sameDay(e, w.hotelDayKey, w.withdrawDate)) continue;
        familyMatches++;
        if (familyMatches > 1) break;
        uniqueCandidate = e;
      }
      if (familyMatches != 1 || uniqueCandidate == null) continue;

      suspicions.add(
        LegacyMirrorSuspicion(
          withdrawalId: w.id,
          withdrawalLocalUuid: w.localUuid,
          withdrawalEmployeeId: w.employeeId,
          withdrawalExpenseId: w.expenseId,
          withdrawalReason: w.reason,
          withdrawalAmount: w.amount,
          withdrawDate: w.withdrawDate,
          withdrawalHotelDayKey: w.hotelDayKey,
          suspectedExpenseId: uniqueCandidate.id,
          suspectedExpenseType: uniqueCandidate.expenseType,
          suspectedExpenseAmount: uniqueCandidate.amount,
          suspectedExpenseLocalUuid: uniqueCandidate.localUuid,
          amountDiffers: uniqueCandidate.amount.abs() != w.amount.abs(),
        ),
      );
    }

    return suspicions;
  }

  static bool _sameDay(
    MirrorExpenseCandidate e,
    String? withdrawalHotelDayKey,
    String withdrawDate,
  ) {
    final eDay = (e.hotelDayKey ?? '').trim();
    final wDay = (withdrawalHotelDayKey ?? '').trim();
    if (eDay.isNotEmpty && wDay.isNotEmpty) return eDay == wDay;
    final eDate = (e.date ?? '').trim();
    return eDate.isNotEmpty && eDate == withdrawDate.trim();
  }
}

/// أبسط تمثيل لسحبة لغرض التدقيق التاريخي — يفصل الأداة عن أنواع Drift.
class LegacyAuditWithdrawal {
  final int id;
  final String localUuid;
  final int employeeId;
  final int? expenseId;
  final String? reason;

  /// رابط الهوية الدائم (إن وُجد) — يُحسم به أولاً قبل أي استدلال.
  final String? expenseUuid;
  final double amount;
  final String withdrawDate;
  final String? hotelDayKey;

  const LegacyAuditWithdrawal({
    required this.id,
    required this.localUuid,
    required this.employeeId,
    required this.expenseId,
    required this.reason,
    required this.expenseUuid,
    required this.amount,
    required this.withdrawDate,
    required this.hotelDayKey,
  });
}
