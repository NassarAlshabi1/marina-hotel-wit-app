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
/// مستوى 0 (الهوية — الحاسم): رابط المرآة الدائم بالـ UUID:
///   سحبة.expenseUuid == مصروف.localUuid (أو عكسه: مصروف.withdrawalUuid ==
///   سحبة.localUuid). هوية ثابتة عبر الأجهزة لا تصطدم ولا تُخمَّن —
///   «التمييز بهوية العملية نفسها، وليس باسم الموظف أو اليوم أو المبلغ».
/// مستوى 1: عمود expense_id يشير لمصروف محلي مقروء (روابط رقمية محلية).
/// مستوى 2: reason=exp_N حيث N معرف مصروف محلي مقروء.
/// مستوى 3: مطابقة بيانات حتمية ضمن مصروفات **نفس الموظف**:
///   نوع نقدي (سحب/سلفة) + نفس المبلغ + نفس اليوم (hotelDayKey أو التاريخ).
///   شبكة أمان للسجلات القديمة بلا روابط — المستويات 1-3 تُطبَّق فقط عند
///   غياب رابط الهوية (مستوى 0).
/// المستوى 3 نفسه المستخدم في تقرير المصروفات منذ إصلاح المرايا — هنا
/// يُوحَّد ليعمل في الاستحقاق وتقرير الإيرادات أيضاً، فتضمن المعادلة
/// بالبناء في الأجهزة الثلاثة.
class SalaryMirrorMatcher {
  SalaryMirrorMatcher._();

  /// هل سحبة الراتب هذه مرآة لمصروف مقروء (فلا تُعَد نقداً مرة ثانية)؟
  ///
  /// [expenseUuid] رابط الهوية الدائم على السحبة (سحبة → مصروف، هجرة 68) —
  ///   إن وُجد وطابق مصروفاً مقروءاً حُسمت المرآة فوراً (المستوى 0).
  /// [withdrawalLocalUuid] هوية السحبة نفسها — تُطابق ضد الختم العكسي
  ///   [MirrorExpenseCandidate.withdrawalUuid] على المصروف (مصروف → سحبة).
  /// [expenseId] عمود expense_id في salary_withdrawals (قد يكون null).
  /// [reason] حقل reason الخام (قد يحمل exp_N).
  /// [amount] مبلغ السحبة (المرايا السالبة تُقرر الطبقة العليا — هنا نقدي فقط).
  /// [hotelDayKey] يوم السحبة الفندقي (قد يكون فارغاً).
  /// [withdrawDate] تاريخ السحبة (yyyy-MM-dd).
  /// [employeeId] معرف الموظف المحلي للسحبة.
  /// [expenses] المصروفات المقروءة (بنطاق التقرير/الدورة المطلوب).
  static bool isMirrorOfReadExpense({
    String? expenseUuid,
    String? withdrawalLocalUuid,
    required int? expenseId,
    required String? reason,
    required double amount,
    required String? hotelDayKey,
    required String withdrawDate,
    required int employeeId,
    required Iterable<MirrorExpenseCandidate> expenses,
    String? sourceDeviceId,
  }) {
    return classify(
          expenseUuid: expenseUuid,
          withdrawalLocalUuid: withdrawalLocalUuid,
          expenseId: expenseId,
          reason: reason,
          amount: amount,
          hotelDayKey: hotelDayKey,
          withdrawDate: withdrawDate,
          employeeId: employeeId,
          expenses: expenses,
          sourceDeviceId: sourceDeviceId,
        ) !=
        MirrorMatchLevel.none;
  }

  /// يصنّف «المرآة» بحسب **مستوى الإثبات** — يُستخدم في التقارير لتمييز
  /// الحُكمي (بياناتي) عن الحاسم (هوية/رقم مُثبت) بدل إخفائه (G-5/P2-7).
  static MirrorMatchLevel classify({
    String? expenseUuid,
    String? withdrawalLocalUuid,
    required int? expenseId,
    required String? reason,
    required double amount,
    required String? hotelDayKey,
    required String withdrawDate,
    required int employeeId,
    required Iterable<MirrorExpenseCandidate> expenses,
    String? sourceDeviceId,
  }) {
    // ── الحارس: السحوبات المباشرة الحقيقية ليست مرايا أبداً ──
    // يُنشئها زر «سحب راتب» في شاشة الموظفين بلا مصروف مقابل — نقد خرج
    // فعلاً ويجب أن يُعَد مرة واحدة في التقارير والاستحقاق معاً.
    final rawReason0 = (reason ?? '').trim();
    if (rawReason0.startsWith('direct_withdrawal_')) {
      return MirrorMatchLevel.none;
    }

    // ── المستوى 0: هوية العملية (UUID) — حتمي وعابر للأجهزة ──
    // رابط الهوية محسوم من مصدر البيانات نفسه (إنشاء/تعديل العملية)، فلا
    // يعتمد على اسم الموظف ولا اليوم ولا المبلغ — سحبتان متطابقتان تماماً
    // (نفس الموظف/اليوم/المبلغ) تظلان عمليتين مستقلتين لأن هويتهما مختلفة.
    final eu = (expenseUuid ?? '').trim();
    if (eu.isNotEmpty) {
      for (final e in expenses) {
        final candUuid = (e.localUuid ?? '').trim();
        if (candUuid.isNotEmpty && candUuid == eu) {
          return MirrorMatchLevel.identity;
        }
      }
    }
    final wlu = (withdrawalLocalUuid ?? '').trim();
    if (wlu.isNotEmpty) {
      for (final e in expenses) {
        final stamped = (e.withdrawalUuid ?? '').trim();
        // حارس الختم الذاتي الفاسد (خطأ تاريخي كان يختم المصروف بهويته هو)
        if (stamped.isEmpty || stamped == (e.localUuid ?? '').trim()) continue;
        if (stamped == wlu) return MirrorMatchLevel.identity;
      }
    }

    // ── المستوى 1: عمود expense_id → مصروف محلي مقروء ──
    if (expenseId != null && expenseId > 0) {
      for (final e in expenses) {
        if (e.id == expenseId) return MirrorMatchLevel.provenNumeric;
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
            if (e.id == n) return MirrorMatchLevel.provenNumeric;
          }
          // 2-ب: معرّف جهاز المصدر محفوظ في serverId للمصروف.
          // ✅ (P2-7 / 2026-10-06): لا يُقبل إلا **بإثبات فضاء المعرّفات**
          // — نفس الجهاز الكاتب للسحبة والمصروف (نفس قاعدة G-3 في
          // IdResolver). بلا إثبات ⇒ لا ربط رقمي: يبقى الاحتياط
          // البياناتي (المستوى 3/4) ولا يُخمَّن الربط.
          final deviceProof = (sourceDeviceId ?? '').trim().isNotEmpty;
          if (deviceProof) {
            for (final e in expenses) {
              if (e.serverId != null &&
                  e.serverId == n &&
                  (e.deviceId ?? '').trim() == sourceDeviceId!.trim()) {
                return MirrorMatchLevel.provenNumeric;
              }
            }
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
      return MirrorMatchLevel.dataMatch;
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
      if (familyMatches == 1) return MirrorMatchLevel.unprovenMarker;
    }
    return MirrorMatchLevel.none;
  }

  /// المستويات 0/1/2: يحاول حلّ رابط المرآة إلى id مصروف محلي **حقيقي**
  /// ضمن [expenses]. يُعيد null إن لم يوجد رابط مباشر (سحبة مباشرة بلا
  /// مصروف، أو رابط أجنبي/يتيم من جهاز آخر، أو بلا علامة مرآة إطلاقاً).
  ///
  /// الترتيب:
  /// - المستوى 0 (الهوية): [expenseUuid] → localUuid المصروف — حتمي.
  /// - المستوى 1: عمود expense_id الرقمي (محلي فقط).
  /// - المستوى 2: نمط reason=exp_N.
  ///
  /// ✅ (2026-09-24) استُخرج من [isMirrorOfReadExpense] ليُستخدم في
  /// شاشات تحتاج معرفة "أي مصروف بالضبط تمثّله هذه السحبة؟" — مثل
  /// دمج سحوبات المرآة المكرّرة في تقرير سحبيات الرواتب (خلافاً
  /// لتقارير المصروفات المركّبة التي تكتفي بـ"إخفاء" المرآة لأن قيمتها
  /// تُعرض من جدول expenses مباشرة).
  static int? resolveLinkedExpenseId({
    String? expenseUuid,
    required int? expenseId,
    required String? reason,
    required Iterable<MirrorExpenseCandidate> expenses,
    String? sourceDeviceId,
  }) {
    final rawReason = (reason ?? '').trim();
    if (rawReason.startsWith('direct_withdrawal_')) return null;

    // ── المستوى 0: هوية العملية (سحبة.expenseUuid == مصروف.localUuid) ──
    final eu = (expenseUuid ?? '').trim();
    if (eu.isNotEmpty) {
      for (final e in expenses) {
        final candUuid = (e.localUuid ?? '').trim();
        if (candUuid.isNotEmpty && candUuid == eu) return e.id;
      }
    }

    if (expenseId != null && expenseId > 0) {
      for (final e in expenses) {
        if (e.id == expenseId) return e.id;
      }
    }

    if (rawReason.isNotEmpty) {
      final match = RegExp(r'exp_(\d+)').firstMatch(rawReason);
      if (match != null) {
        final n = int.tryParse(match.group(1)!);
        if (n != null) {
          for (final e in expenses) {
            if (e.id == n) return e.id;
          }
          // ✅ (P2-7): لا ربط برقم جهاز المصدر بلا إثبات نفس الجهاز الكاتب
          // (نفس قاعدة G-3) — وإلا رجع رقم مصروف لا يخصّ هذه السحبة.
          if ((sourceDeviceId ?? '').trim().isNotEmpty) {
            for (final e in expenses) {
              if (e.serverId != null &&
                  e.serverId == n &&
                  (e.deviceId ?? '').trim() == sourceDeviceId!.trim()) {
                return e.id;
              }
            }
          }
        }
      }
    }
    return null;
  }

  /// هل تحمل هذه السحبة "علامة مرآة" (رابط لمصروف — محلي أو أجنبي عن
  /// هذا الجهاز) بغض النظر عن نجاح حلّه؟ السحوبات المباشرة الحقيقية
  /// (direct_withdrawal_) تُستثنى دائماً — نقد خرج بلا مصروف مقابل.
  static bool hasMirrorMarker({
    required int? expenseId,
    required String? reason,
  }) {
    final rawReason = (reason ?? '').trim();
    if (rawReason.startsWith('direct_withdrawal_')) return false;
    if (expenseId != null && expenseId > 0) return true;
    return RegExp(r'exp_\d+').hasMatch(rawReason);
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

/// مستوى إثبات «المرآة» — يفصل **الهوية** عن **المطابقة البياناتية**.
///
/// ✅ (G-5 / P2-7 — 2026-10-06): كان المطابِق يعيد `bool` فقط، فتظهر
/// المرايا المحسومة بالمطابقة البياناتية (نفس الموظف + المبلغ + اليوم)
/// بنفس ثقة المرايا المحسومة بالـ UUID. الآن كل نداء يستطيع معرفة
/// **بأي دليل** حُسمت المرآة، والتقارير تُعلّم الحُكْمي منها بدل إخفائه.
enum MirrorMatchLevel {
  /// ليست مرآة.
  none,

  /// رابط هوية صريح: `expenseUuid` ↔ `localUuid` أو `withdrawalUuid` ↔ هوية السحبة.
  identity,

  /// رابط رقمي محلي مُثبت: `expense_id` المحلي أو `reason=exp_N` مع تطابق
  /// (معرّف جهاز المصدر) — يحتاج دليل فضاء المعرّفات.
  provenNumeric,

  /// مطابقة بيانات حتمية: نفس الموظف + نقدي + نفس المبلغ + نفس اليوم.
  dataMatch,

  /// علامة مرآة برقم أجنبي غير قابل للإثبات + مصروف وحيد لنفس الموظف/اليوم.
  unprovenMarker;

  bool get isMirror => this != MirrorMatchLevel.none;

  /// هل الحُكم مبني على مطابقة/علامة غير محسومة بالهوية؟ (للتقارير)
  bool get isHeuristic =>
      this == MirrorMatchLevel.dataMatch ||
      this == MirrorMatchLevel.unprovenMarker;
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

  /// ✅ (هجرة 68) هوية المصروف الثابتة عبر الأجهزة — تُطابق ضد
  /// سحبة.expenseUuid في المستوى 0 (التمييز بهوية العملية نفسها).
  final String? localUuid;

  /// ✅ (هجرة 68) الختم العكسي: هوية المرآة المرتبطة بهذا المصروف
  /// (مصروف → سحبة). يُطابق ضد هوية السحبة في المستوى 0.
  final String? withdrawalUuid;

  /// ✅ (P2-7 / 2026-10-06): جهاز كاتب المصروف — دليل فضاء المعرّفات
  /// للأرقام المحلية. الربط الرقمي `exp_962` لا يُقبل إلا إذا كان هذا
  /// الجهاز هو نفسه جهاز السحبة (نفس قاعدة G-3 في IdResolver).
  final String? deviceId;

  const MirrorExpenseCandidate({
    required this.id,
    required this.serverId,
    required this.expenseType,
    required this.amount,
    required this.date,
    required this.hotelDayKey,
    required this.relatedId,
    this.localUuid,
    this.withdrawalUuid,
    this.deviceId,
  });
}
