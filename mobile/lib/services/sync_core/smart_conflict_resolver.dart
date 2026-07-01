// lib/services/sync_core/smart_conflict_resolver.dart
//
// ✅ محلّل التعارضات الذكي (2026-06-27)
//
// يحل التعارضات تلقائياً باستخدام 3-way merge على مستوى الحقل:
// - تعديل حقول مختلفة → دمج تلقائي (خذ من كل جهة ما تغيّر)
// - تعديل نفس الحقول → طبّق سياسة الحقل (newerWins, manual, concat, إلخ)
// - حقول مالية حرجة → تصعيد يدوي (لا تُدمج تلقائياً أبداً)
//
// سياسات الكيانات مُخصّصة لكل جدول (rooms, bookings, payments, إلخ)

import '../vector_clock_service.dart';
import 'conflict_detector.dart';

/// استراتيجية حل الحقل المتعارض
enum FieldStrategy {
  /// آخر تعديل زمنياً يفوز
  newerWins,

  /// المحلي يفوز دائماً
  localWins,

  /// البعيد يفوز دائماً
  remoteWins,

  /// أكبر قيمة (للعدّادات)
  maxValue,

  /// أصغر قيمة
  minValue,

  /// جمع (مع طرح ancestor: local + remote - ancestor)
  sum,

  /// دمج نصي
  concat,

  /// تصعيد يدوي
  manual,
}

/// قاعدة حل حقل معيّن
class FieldResolutionRule {
  const FieldResolutionRule(this.strategy, {this.reason});
  final FieldStrategy strategy;
  final String? reason;
}

/// سياسة حل التعارض لكيان معيّن
class EntityResolutionPolicy {
  const EntityResolutionPolicy({
    required this.defaultRule,
    this.rules = const {},
  });
  final FieldResolutionRule defaultRule;
  final Map<String, FieldResolutionRule> rules;
}

/// استراتيجية الحل المُطبّقة
enum ResolutionStrategy {
  /// المحلي يفوز
  localWins,

  /// البعيد يفوز
  remoteWins,

  /// دمج على مستوى الحقل
  fieldLevelMerge,

  /// تصعيد يدوي
  manualEscalation,
}

/// نتيجة حل التعارض
class ResolutionResult {
  const ResolutionResult({
    required this.mergedData,
    required this.strategy,
    this.warnings = const [],
    this.pushedToRemote = false,
  });

  final Map<String, dynamic> mergedData;
  final ResolutionStrategy strategy;
  final List<String> warnings;

  /// هل يجب رفع النتيجة المدمجة للسحابة؟
  final bool pushedToRemote;
}

/// محلّل التعارضات الذكي
class SmartConflictResolver {
  const SmartConflictResolver._();

  /// سياسات الكيانات
  static final Map<String, EntityResolutionPolicy> _entityPolicies = {
      // الغرف: حالة الغرفة - آخر تعديل يفوز
      'rooms': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'status': FieldResolutionRule(FieldStrategy.newerWins),
          'cleaningStatus': FieldResolutionRule(FieldStrategy.newerWins),
          'price': FieldResolutionRule(FieldStrategy.manual),
          'roomNumber': FieldResolutionRule(FieldStrategy.manual),
        },
      ),

      // الحجوزات: حالات حساسة
      'bookings': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'status': FieldResolutionRule(FieldStrategy.newerWins),
          'actualCheckout': FieldResolutionRule(FieldStrategy.newerWins),
          'guestName': FieldResolutionRule(FieldStrategy.remoteWins,
              reason: 'آخر تحديث للمعلومات الشخصية'),
          'guestPhone': FieldResolutionRule(FieldStrategy.remoteWins),
          'notes': FieldResolutionRule(FieldStrategy.concat),
          'discount': FieldResolutionRule(FieldStrategy.manual),
          'isFullyPaid': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // المدفوعات: المبالغ خطيرة جداً → تصعيد دائماً
      'payments': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.manual),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual),
          'paymentMethod': FieldResolutionRule(FieldStrategy.manual),
          'isVoided': FieldResolutionRule(FieldStrategy.manual),
          'notes': FieldResolutionRule(FieldStrategy.concat),
        },
      ),

      // المصروفات: المبلغ تصعيد، الباقي دمج
      'expenses': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual),
          'description': FieldResolutionRule(FieldStrategy.concat),
          'categoryUuid': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // الديون: تصعيد كامل (مالي حرج)
      'debts': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.manual),
        rules: {
          'totalAmount': FieldResolutionRule(FieldStrategy.manual),
          'paidAmount': FieldResolutionRule(FieldStrategy.manual),
          'remainingAmount': FieldResolutionRule(FieldStrategy.manual),
          'isSettled': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // الموظفون: معلومات شخصية → آخر تعديل
      'employees': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'basicSalary': FieldResolutionRule(FieldStrategy.manual),
          'name': FieldResolutionRule(FieldStrategy.newerWins),
          'phone': FieldResolutionRule(FieldStrategy.newerWins),
          'status': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // ملاحظات الحجز: دمج نصي
      'booking_notes': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.concat),
        rules: {
          'noteText': FieldResolutionRule(FieldStrategy.concat),
          'alertType': FieldResolutionRule(FieldStrategy.newerWins),
          'isActive': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // ════════════════════════════════════════════════════════════════
      // ✅ سياسات إضافية (2026-06-28): تغطية كل الكيانات الـ 17 المتزامنة
      // ════════════════════════════════════════════════════════════════

      // سحوبات الرواتب: مبلغ تصعيد، وصف دمج، تاريخ آخر تعديل
      'salary_withdrawals': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual,
              reason: 'مبلغ السحب حرج مالياً'),
          'description': FieldResolutionRule(FieldStrategy.concat),
          'notes': FieldResolutionRule(FieldStrategy.concat),
          'withdrawDate': FieldResolutionRule(FieldStrategy.newerWins),
          'withdraw_date': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // دفعات الرواتب: مبلغ تصعيد، حالة آخر تعديل، ملاحظات دمج
      'salary_payments': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual,
              reason: 'مبلغ الراتب حرج مالياً'),
          'basicSalary': FieldResolutionRule(FieldStrategy.manual),
          'deductions': FieldResolutionRule(FieldStrategy.manual),
          'bonuses': FieldResolutionRule(FieldStrategy.manual),
          'netSalary': FieldResolutionRule(FieldStrategy.manual),
          'status': FieldResolutionRule(FieldStrategy.newerWins),
          'notes': FieldResolutionRule(FieldStrategy.concat),
          'paidAt': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // الحركات النقدية: مبلغ ونوع تصعيد، وصف دمج
      'cash_transactions': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual,
              reason: 'المبلغ النقدي حرج مالياً'),
          'type': FieldResolutionRule(FieldStrategy.manual,
              reason: 'نوع الحركة النقدية لا يُدمج تلقائياً'),
          'transactionType': FieldResolutionRule(FieldStrategy.manual),
          'description': FieldResolutionRule(FieldStrategy.concat),
          'notes': FieldResolutionRule(FieldStrategy.concat),
          'timestamp': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // ملاحظات الورديات: عنوان ومحتوى، حالة آخر تعديل
      'shift_notes': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'title': FieldResolutionRule(FieldStrategy.newerWins),
          'content': FieldResolutionRule(FieldStrategy.concat),
          'noteText': FieldResolutionRule(FieldStrategy.concat),
          'shiftDate': FieldResolutionRule(FieldStrategy.newerWins),
          'isActive': FieldResolutionRule(FieldStrategy.newerWins),
          'status': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // معلومات النزلاء: بيانات شخصية، رقم الهوية تصعيد
      'guest_infos': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'name': FieldResolutionRule(FieldStrategy.newerWins),
          'guestName': FieldResolutionRule(FieldStrategy.newerWins),
          'phone': FieldResolutionRule(FieldStrategy.newerWins),
          'guestPhone': FieldResolutionRule(FieldStrategy.newerWins),
          'idNumber': FieldResolutionRule(FieldStrategy.manual,
              reason: 'رقم الهوية حساس ولا يُدمج تلقائياً'),
          'guestIdNumber': FieldResolutionRule(FieldStrategy.manual),
          'idType': FieldResolutionRule(FieldStrategy.newerWins),
          'guestIdType': FieldResolutionRule(FieldStrategy.newerWins),
          'nationality': FieldResolutionRule(FieldStrategy.newerWins),
          'email': FieldResolutionRule(FieldStrategy.newerWins),
          'address': FieldResolutionRule(FieldStrategy.concat),
        },
      ),

      // ليالي الحجز: قيم محسوبة، آخر تعديل يفوز
      'booking_nights': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'calculatedNights': FieldResolutionRule(FieldStrategy.newerWins),
          'actualNights': FieldResolutionRule(FieldStrategy.newerWins),
          'expectedNights': FieldResolutionRule(FieldStrategy.newerWins),
          'nightDate': FieldResolutionRule(FieldStrategy.newerWins),
          'price': FieldResolutionRule(FieldStrategy.manual),
          'amount': FieldResolutionRule(FieldStrategy.manual),
        },
      ),

      // دورات الرواتب: مبلغ تصعيد، حالة وتاريخ الإغلاق آخر تعديل
      'salary_cycles': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'totalAmount': FieldResolutionRule(FieldStrategy.manual,
              reason: 'إجمالي الراتب حرج مالياً'),
          'totalPaid': FieldResolutionRule(FieldStrategy.manual),
          'totalDeductions': FieldResolutionRule(FieldStrategy.manual),
          'status': FieldResolutionRule(FieldStrategy.newerWins),
          'closedAt': FieldResolutionRule(FieldStrategy.newerWins),
          'startDate': FieldResolutionRule(FieldStrategy.newerWins),
          'endDate': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // تعديلات أسعار الحجز: مبلغ تصعيد، سبب دمج
      'booking_price_adjustments': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual,
              reason: 'مبلغ التعديل حرج مالياً'),
          'reason': FieldResolutionRule(FieldStrategy.concat),
          'type': FieldResolutionRule(FieldStrategy.newerWins),
          'adjustmentType': FieldResolutionRule(FieldStrategy.newerWins),
          'appliedAt': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // القائمة السوداء: سبب دمج، حالة آخر تعديل
      'blacklist': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'reason': FieldResolutionRule(FieldStrategy.concat),
          'notes': FieldResolutionRule(FieldStrategy.concat),
          'isActive': FieldResolutionRule(FieldStrategy.newerWins),
          'guestName': FieldResolutionRule(FieldStrategy.newerWins),
          'guestPhone': FieldResolutionRule(FieldStrategy.newerWins),
          'idNumber': FieldResolutionRule(FieldStrategy.manual),
        },
      ),

      // تعديلات الأسعار العامة: مبلغ تصعيد، سبب دمج
      'price_adjustments': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual,
              reason: 'مبلغ التعديل حرج مالياً'),
          'reason': FieldResolutionRule(FieldStrategy.concat),
          'description': FieldResolutionRule(FieldStrategy.concat),
          'targetType': FieldResolutionRule(FieldStrategy.newerWins),
          'appliedAt': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // إلغاء الدفعات: كله تصعيد يدوي (مالي حرج جداً)
      'payment_voids': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.manual,
            reason: 'إلغاء الدفعات حرج مالياً ولا يُدمج تلقائياً'),
        rules: {
          'originalPaymentUuid': FieldResolutionRule(FieldStrategy.manual),
          'voidedAmount': FieldResolutionRule(FieldStrategy.manual),
          'voided_at': FieldResolutionRule(FieldStrategy.newerWins),
          'voidedAt': FieldResolutionRule(FieldStrategy.newerWins),
          'reason': FieldResolutionRule(FieldStrategy.concat),
          'isVoided': FieldResolutionRule(FieldStrategy.manual),
        },
      ),

      // سجلات التدقيق: آخر تعديل يفوز (لا حقول مالية)
      'audit_logs': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'action': FieldResolutionRule(FieldStrategy.newerWins),
          'entityType': FieldResolutionRule(FieldStrategy.newerWins),
          'entityUuid': FieldResolutionRule(FieldStrategy.newerWins),
          'details': FieldResolutionRule(FieldStrategy.concat),
          'timestamp': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),

      // سجلات ترحيل الراتب: مبلغ تصعيد، سبب دمج، تاريخ آخر تعديل
      'salary_carry_over_logs': const EntityResolutionPolicy(
        defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
        rules: {
          'amount': FieldResolutionRule(FieldStrategy.manual,
              reason: 'مبلغ الترحيل حرج مالياً'),
          'reason': FieldResolutionRule(FieldStrategy.concat),
          'carriedAt': FieldResolutionRule(FieldStrategy.newerWins),
          'employeeId': FieldResolutionRule(FieldStrategy.manual),
          'previousCycleStart': FieldResolutionRule(FieldStrategy.newerWins),
          'previousCycleEnd': FieldResolutionRule(FieldStrategy.newerWins),
          'newCycleStart': FieldResolutionRule(FieldStrategy.newerWins),
          'newCycleEnd': FieldResolutionRule(FieldStrategy.newerWins),
        },
      ),
  };

  static const _defaultPolicy = EntityResolutionPolicy(
    defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
  );

  /// حل التعارض تلقائياً
  static ResolutionResult resolve({
    required String entity,
    required Map<String, dynamic>? localData,
    required Map<String, dynamic> remoteData,
    required Map<String, dynamic>? commonAncestor,
  }) {
    // 1. كشف نوع التعارض
    final detection = ConflictDetector.detect(
      localData: localData,
      remoteData: remoteData,
      commonAncestor: commonAncestor,
    );

    // 2. لا تعارض → السماح بالتحديث العادي
    if (detection.type == ConflictType.noConflictRemoteNewer) {
      return ResolutionResult(
        mergedData: remoteData,
        strategy: ResolutionStrategy.remoteWins,
      );
    }
    if (detection.type == ConflictType.noConflictLocalNewer ||
        detection.type == ConflictType.noConflictEqual) {
      return ResolutionResult(
        mergedData: localData!,
        strategy: ResolutionStrategy.localWins,
      );
    }

    // 3. الحذف له أولوية دائماً
    if (detection.type == ConflictType.deleteVsDelete) {
      return ResolutionResult(
        mergedData: localData!,
        strategy: ResolutionStrategy.localWins,
      );
    }
    if (detection.type == ConflictType.deleteVsUpdate) {
      // الحذف المحلي متعمد → له أولوية
      return ResolutionResult(
        mergedData: localData!,
        strategy: ResolutionStrategy.localWins,
        warnings: const ['حذف محلي له أولوية على تعديل بعيد'],
        pushedToRemote: true,
      );
    }

    // 4. تعارض متزامن → هل يمكن حلّه تلقائياً؟
    if (detection.canAutoResolve) {
      return _autoMerge(
        entity: entity,
        localData: localData!,
        remoteData: remoteData,
        detection: detection,
      );
    }

    // 5. تعارض حرج → تصعيد يدوي
    return _escalateManual(
      entity: entity,
      localData: localData!,
      remoteData: remoteData,
      detection: detection,
    );
  }

  /// دمج تلقائي على مستوى الحقل
  static ResolutionResult _autoMerge({
    required String entity,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required ConflictDetectionResult detection,
  }) {
    final policy = _entityPolicies[entity] ?? _defaultPolicy;
    final merged = Map<String, dynamic>.from(localData);

    // دمج الحقول غير المتعارضة (البعيد فقط غيّرها)
    for (final field in detection.remoteChangedFields) {
      if (!detection.localChangedFields.contains(field)) {
        merged[field] = remoteData[field];
      }
    }

    // حل الحقول المتعارضة حسب القواعد
    final warnings = <String>[];
    for (final field in detection.conflictingFields) {
      final rule = policy.rules[field] ?? policy.defaultRule;
      final resolved = _applyRule(
        rule: rule,
        field: field,
        localData: localData,
        remoteData: remoteData,
        ancestor: detection.commonAncestor,
      );
      merged[field] = resolved.value;
      if (resolved.warning != null) {
        warnings.add(resolved.warning!);
      }
    }

    // دمج VectorClocks
    final localVc = VectorClock.fromString(
      (localData['vectorClock'] as String?) ?? '{}',
    );
    final remoteVc = VectorClock.fromString(
      (remoteData['vectorClock'] as String?) ?? '{}',
    );
    final mergedVc = localVc.copy();
    mergedVc.merge(remoteVc);
    merged['vectorClock'] = mergedVc.toString();

    // ✅ إصلاح (2026-06-28): استخدام max(localTs, remoteTs) بدلاً من DateTime.now()
    // المنطق القديم كان يكسر idempotency: كل دمج يُنتج timestamp جديد
    // بوقت جهاز الدمج، مما يُسبب رفض التحديث من أجهزة أخرى ذات توقيت مختلف.
    // الحل: استخدام آخر تعديل معروف بين الطرفين (max) — هذا يحافظ على
    // الترتيب السبكي ويضمن قبول النتيجة من جميع الأجهزة.
    final localTs = _extractTs(localData);
    final remoteTs = _extractTs(remoteData);
    final mergedTs = localTs > remoteTs ? localTs : remoteTs;
    merged['lastModified'] = mergedTs;
    merged['version'] = ((merged['version'] as int?) ?? 0) + 1;

    return ResolutionResult(
      mergedData: merged,
      strategy: ResolutionStrategy.fieldLevelMerge,
      warnings: warnings,
      pushedToRemote: true,
    );
  }

  /// تطبيق قاعدة حل على حقل معيّن
  static _FieldResolution _applyRule({
    required FieldResolutionRule rule,
    required String field,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required Map<String, dynamic>? ancestor,
  }) {
    final localVal = localData[field];
    final remoteVal = remoteData[field];

    switch (rule.strategy) {
      case FieldStrategy.newerWins:
        final localTs = _extractTs(localData);
        final remoteTs = _extractTs(remoteData);
        return _FieldResolution(
          value: remoteTs > localTs ? remoteVal : localVal,
        );

      case FieldStrategy.localWins:
        return _FieldResolution(value: localVal);

      case FieldStrategy.remoteWins:
        return _FieldResolution(value: remoteVal);

      case FieldStrategy.maxValue:
        final l = (localVal as num?) ?? 0;
        final r = (remoteVal as num?) ?? 0;
        return _FieldResolution(value: l > r ? l : r);

      case FieldStrategy.minValue:
        final l = (localVal as num?) ?? 0;
        final r = (remoteVal as num?) ?? 0;
        return _FieldResolution(value: l < r ? l : r);

      case FieldStrategy.sum:
        final l = (localVal as num?) ?? 0;
        final r = (remoteVal as num?) ?? 0;
        final a = (ancestor?[field] as num?) ?? 0;
        return _FieldResolution(
          value: l + r - a,
          warning: 'sum merge: $field = $l + $r - $a = ${l + r - a}',
        );

      case FieldStrategy.concat:
        final l = localVal?.toString() ?? '';
        final r = remoteVal?.toString() ?? '';
        if (l == r) return _FieldResolution(value: l);
        // ✅ إصلاح (2026-06-28): إضافة deduplication قبل الـ concat.
        // المنطق القديم كان يُضخّم النصوص بعد عدة عمليات دمج متتالية
        // (ملاحظة A\n---\nملاحظة A\n---\nملاحظة B\n---\nملاحظة A...).
        // الحل: تقسيم النصين على \n---\n، دمج الأجزاء، إزالة التكرارات
        // مع الحفاظ على الترتيب (أول ظهور يُحتفظ به).
        final mergedValue = _concatWithDedup(l, r);
        return _FieldResolution(
          value: mergedValue,
          warning: 'concat merge: $field',
        );

      case FieldStrategy.manual:
        // تصعيد يدوي — نُبقي المحلي مؤقتاً
        return _FieldResolution(
          value: localVal,
          warning: '⚠️ تصعيد يدوي للحقل $field — تم الاحتفاظ بالقيمة المحلية',
        );
    }
  }

  /// تصعيد يدوي للتعارضات الحرجة
  static ResolutionResult _escalateManual({
    required String entity,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required ConflictDetectionResult detection,
  }) {
    final criticalFields = detection.conflictingFields
        .where(ConflictDetector.isCriticalField)
        .toList();

    return ResolutionResult(
      mergedData: localData,
      strategy: ResolutionStrategy.manualEscalation,
      warnings: [
        '⚠️ تعارض حرج في $entity — الحقول: ${criticalFields.join(", ")}',
        'تم الاحتفاظ بالبيانات المحلية حتى المراجعة اليدوية',
      ],
    );
  }

  /// استخراج الطابع الزمني
  static int _extractTs(Map<String, dynamic> data) {
    return (data['lastModified'] as int?) ??
        (data['last_modified'] as int?) ??
        (data['lastModifiedEpoch'] as int?) ??
        0;
  }

  /// ✅ دمج نصّي مع إزالة التكرار (deduplication)
  /// يُقسّم كل نص على الفاصل '\n---\n'، يدمج الأجزاء، ويُزيل التكرارات
  /// مع الحفاظ على ترتيب أول ظهور لكل جزء.
  /// مثال: 'A\n---\nB' + 'A\n---\nC' → 'A\n---\nB\n---\nC'
  static String _concatWithDedup(String local, String remote) {
    const separator = '\n---\n';
    final localParts = local.split(separator);
    final remoteParts = remote.split(separator);

    // دمج القائمتين مع إزالة التكرارات (الترتيب: local أولاً ثم remote)
    final seen = <String>{};
    final merged = <String>[];
    for (final part in [...localParts, ...remoteParts]) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        merged.add(part);
      }
    }

    if (merged.isEmpty) return '';
    if (merged.length == 1) return merged.first;
    return merged.join(separator);
  }
}

/// نتيجة حل حقل واحد
class _FieldResolution {
  const _FieldResolution({required this.value, this.warning});
  final dynamic value;
  final String? warning;
}
