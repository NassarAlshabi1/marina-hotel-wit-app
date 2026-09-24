import 'salary_expense_classifier.dart';

/// مطابِق مرايا السحوبات — مصدر الحقيقة الموحّد لمنع الاحتساب المزدوج.
///
/// ✅ المشكلة المُثبتة (حالة «الاورمو محمد» 2026-09-14):
/// جهاز المصدر يُنشئ مصروف «سحب راتب» (مثلاً محلي id=962) + سحبة مرآة
/// reason=exp_962. عند الدفع للسحابة لا يُرسل المصروف أي معرف رقمي
/// (لا id ولا serverId — ثبت من المستند السحابي الخام)، لذا على أي جهاز
/// آخر يحصل المصروف على id محلي جديد، وتبقى السحبة تشير لـ exp_962 الذي
/// لا يقابل أي مصروف محلي → dedup بالمعرفات يفشل → السحبة تُعَد مرة ثانية
/// في استحقاق الموظف وتقارير الإيرادات/المصروفات → المعادلة
/// «مصروفات الرواتب = استحقاقات الموظف» تنكسر بالعد المزدوج.
///
/// ✅ الحل (بلا أي كتابة في قاعدة البيانات — قراءة فقط):
/// مستوى 1: عمود expense_id يشير لمصروف محلي مقروء.
/// مستوى 2: reason=exp_N حيث N معرف مصروف محلي مقروء.
/// مستوى 3 (الجديد): مطابقة بيانات حتمية ضمن مصروفات **نفس الموظف**:
///   نوع نقدي (سحب/سلفة) + نفس المبلغ + نفس اليوم (hotelDayKey أو التاريخ).
/// المستوى 3 نفسه المستخدم في تقرير المصروفات منذ إصلاح المرايا — هنا
/// يُوحَّد ليعمل في الاستحقاق وتقرير الإيرادات أيضاً، فتضمن المعادلة
/// بالبناء في الأجهزة الثلاثة.
class SalaryMirrorMatcher {
  SalaryMirrorMatcher._();

  /// هل سحبة الراتب هذه مرآة لمصروف مقروء (فلا تُعَد نقداً مرة ثانية)؟
  ///
  /// [expenseId] عمود expense_id في salary_withdrawals (قد يكون null).
  /// [reason] حقل reason الخام (قد يحمل exp_N).
  /// [amount] مبلغ السحبة (المرايا السالبة تُقرر الطبقة العليا — هنا نقدي فقط).
  /// [hotelDayKey] يوم السحبة الفندقي (قد يكون فارغاً).
  /// [withdrawDate] تاريخ السحبة (yyyy-MM-dd).
  /// [employeeId] معرف الموظف المحلي للسحبة.
  /// [expenses] المصروفات المقروءة (بنطاق التقرير/الدورة المطلوب).
  static bool isMirrorOfReadExpense({
    required int? expenseId,
    required String? reason,
    required double amount,
    required String? hotelDayKey,
    required String withdrawDate,
    required int employeeId,
    required Iterable<MirrorExpenseCandidate> expenses,
  }) {
    // ── الحارس: السحوبات المباشرة الحقيقية ليست مرايا أبداً ──
    // يُنشئها زر «سحب راتب» في شاشة الموظفين بلا مصروف مقابل — نقد خرج
    // فعلاً ويجب أن يُعَد مرة واحدة في التقارير والاستحقاق معاً.
    final rawReason0 = (reason ?? '').trim();
    if (rawReason0.startsWith('direct_withdrawal_')) return false;

    // ── المستوى 1: عمود expense_id → مصروف محلي مقروء ──
    if (expenseId != null && expenseId > 0) {
      for (final e in expenses) {
        if (e.id == expenseId) return true;
      }
    }

    // ── المستوى 2: reason=exp_N → معرف مصروف محلي مقروء ──
    final rawReason = (reason ?? '').trim();
    if (rawReason.isNotEmpty) {
      final match = RegExp(r'exp_(\d+)').firstMatch(rawReason);
      if (match != null) {
        final n = int.tryParse(match.group(1)!);
        if (n != null) {
          for (final e in expenses) {
            if (e.id == n) return true;
          }
          // 2-ب: معرف جهاز المصدر محفوظ في serverId للمصروف
          for (final e in expenses) {
            if (e.serverId != null && e.serverId == n) return true;
          }
        }
      }
    }

    // ── المستوى 3: مطابقة بيانات حتمية (نفس الموظف + نقدي + مبلغ + يوم) ──
    for (final e in expenses) {
      if (!SalaryExpenseClassifier.isSalaryCashOut(e.expenseType)) continue;
      if (e.relatedId != employeeId) continue;
      if (e.amount.abs() != amount.abs()) continue;
      if (!_sameDay(e, hotelDayKey, withdrawDate)) continue;
      return true;
    }

    // ── المستوى 4: علامة مرآة برابط أجنبي + مصروف وحيد لنفس الموظف/اليوم ──
    // ✅ إصلاح تكرار التقرير عند تعديل المبلغ (2026-09-25):
    // المرآة تحمل علامة رابط (expenseId أو exp_N) لكن الرقم هو معرّف
    // جهاز المصدر — لا يقابل أي مصروف محلي (المستوى 1/2 فشلا) — وبعد
    // تعديل مبلغ المصروف لم يعد المبلغ متطابقاً فينكسر المستوى 3
    // → السحبة تُعَد «يتيمة» فتُضاف مكررة في التقارير.
    // هنا: إن وُجد مصروف واحد فقط لنفس الموظف في نفس اليوم من نفس
    // العائلة (نقدي لمرآة موجبة / خصم لمرآة سالبة) → مرآة بغض النظر
    // عن المبلغ. السحوبات المباشرة محمية بحارس direct_withdrawal_ أعلاه،
    // والسحوبات بلا علامة رابط إطلاقاً تظل خاضعة للمستوى 3 وحده.
    final markerInReason = RegExp(r'exp_\d+').hasMatch(rawReason);
    final rawExpId = expenseId ?? 0;
    final hasMirrorMarker = rawExpId > 0 || markerInReason;
    if (hasMirrorMarker) {
      final positive = amount > 0;
      var familyMatches = 0;
      for (final e in expenses) {
        if (e.relatedId != employeeId) continue;
        final familyOk = positive
            ? SalaryExpenseClassifier.isSalaryCashOut(e.expenseType)
            : SalaryExpenseClassifier.isSalaryDeduction(e.expenseType);
        if (!familyOk) continue;
        if (!_sameDay(e, hotelDayKey, withdrawDate)) continue;
        familyMatches++;
        if (familyMatches > 1) break;
      }
      if (familyMatches == 1) return true;
    }
    return false;
  }

  /// مقارنة اليوم: hotelDayKey عند توفرهما، وإلا التاريخ التقويمي.
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

/// أبسط تمثيل لمصروف لغرض المطابقة — يعزل المطابِق عن أنواع Drift.
class MirrorExpenseCandidate {
  final int id;
  final int? serverId;
  final String expenseType;
  final double amount;
  final String? date;
  final String? hotelDayKey;
  final int? relatedId;

  const MirrorExpenseCandidate({
    required this.id,
    required this.serverId,
    required this.expenseType,
    required this.amount,
    required this.date,
    required this.hotelDayKey,
    required this.relatedId,
  });
}
