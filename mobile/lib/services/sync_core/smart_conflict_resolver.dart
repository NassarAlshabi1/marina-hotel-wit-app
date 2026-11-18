// lib/services/sync_core/smart_conflict_resolver.dart
//
// محلّل التعارضات الذكي — حل تلقائي على مستوى السجل بالكامل
//
// جميع التعارضات تُحل تلقائياً باستخدام 3-way merge على مستوى الحقل:
// - تعديل حقول مختلفة → دمج تلقائي (خذ من كل جهة ما تغيّر)
// - تعديل نفس الحقول → طبّق سياسة الحقل (newerWins, concat, maxValue, إلخ)
// - لا يوجد تصعيد يدوي — كل تعارض يُحل ويسجّل للتدقيق فقط

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

/// محلّل التعارضات الذكي — يحل جميع التعارضات تلقائياً على مستوى السجل
class SmartConflictResolver {
  const SmartConflictResolver._();

  /// سياسات الكيانات — جميع الحقول تُحل تلقائياً (no manual strategy)
  static final Map<String, EntityResolutionPolicy> _entityPolicies = {
    'rooms': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'status': FieldResolutionRule(FieldStrategy.newerWins),
        'cleaningStatus': FieldResolutionRule(FieldStrategy.newerWins),
        'price': FieldResolutionRule(FieldStrategy.newerWins),
        'roomNumber': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'bookings': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'status': FieldResolutionRule(FieldStrategy.newerWins),
        'actualCheckout': FieldResolutionRule(FieldStrategy.newerWins),
        'guestName': FieldResolutionRule(
          FieldStrategy.remoteWins,
          reason: 'آخر تحديث للمعلومات الشخصية',
        ),
        'guestPhone': FieldResolutionRule(FieldStrategy.remoteWins),
        'notes': FieldResolutionRule(FieldStrategy.concat),
        'discount': FieldResolutionRule(FieldStrategy.newerWins),
        'isFullyPaid': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'payments': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
        'paymentMethod': FieldResolutionRule(FieldStrategy.newerWins),
        'isVoided': FieldResolutionRule(FieldStrategy.newerWins),
        'notes': FieldResolutionRule(FieldStrategy.concat),
      },
    ),

    'expenses': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
        'description': FieldResolutionRule(FieldStrategy.concat),
        'categoryUuid': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'debts': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'totalAmount': FieldResolutionRule(FieldStrategy.newerWins),
        'paidAmount': FieldResolutionRule(FieldStrategy.newerWins),
        'remainingAmount': FieldResolutionRule(FieldStrategy.newerWins),
        'isSettled': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'employees': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'basicSalary': FieldResolutionRule(FieldStrategy.newerWins),
        'name': FieldResolutionRule(FieldStrategy.newerWins),
        'phone': FieldResolutionRule(FieldStrategy.newerWins),
        'status': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'booking_notes': const EntityResolutionPolicy(
      // ✅ Audit Fix (2026-08-06): defaultRule كان concat — الوحيد بين كل 21 كيان!
      // concat كـ default خطير لأنه يطبّق على أي حقل غير مُدرج في rules:
      //   - alertUntil (تاريخ) → concat يُنتج تاريخ فاسد
      //   - bookingId (FK integer) → concat يُنتج رقم فاسد
      // الإصلاح: newerWins كـ default (آمن لكل أنواع الحقول)، concat فقط لـ noteText.
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'noteText': FieldResolutionRule(FieldStrategy.concat),
        'alertType': FieldResolutionRule(FieldStrategy.newerWins),
        'isActive': FieldResolutionRule(FieldStrategy.newerWins),
        // ✅ Audit Fix: إضافة alertUntil (تاريخ) — كان يقع لـ concat default
        'alertUntil': FieldResolutionRule(FieldStrategy.newerWins),
        // ✅ Audit Fix: إضافة bookingId (FK) — كان يقع لـ concat default
        'bookingId': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'salary_withdrawals': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
        'description': FieldResolutionRule(FieldStrategy.concat),
        'notes': FieldResolutionRule(FieldStrategy.concat),
        'withdrawDate': FieldResolutionRule(FieldStrategy.newerWins),
        'withdraw_date': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'salary_payments': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
        'paymentDate': FieldResolutionRule(FieldStrategy.newerWins),
        'payment_date': FieldResolutionRule(FieldStrategy.newerWins),
        'notes': FieldResolutionRule(FieldStrategy.concat),
      },
    ),

    'daily_closures': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'totalIncome': FieldResolutionRule(FieldStrategy.newerWins),
        'totalExpenses': FieldResolutionRule(FieldStrategy.newerWins),
        'closingBalance': FieldResolutionRule(FieldStrategy.newerWins),
        'notes': FieldResolutionRule(FieldStrategy.concat),
      },
    ),

    'shift_notes': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        // ✅ Audit Fix (2026-08-06): إزالة قاعدتين ميتتين.
        // 'noteText' كان لا يطابق أي حقل — الحقل الفعلي هو 'content'
        // 'isCompleted' كان لا يطابق أي حقل — الحقل الفعلي هو 'isRead'
        // إضافة قواعد صريحة للحقول الفعلية:
        'title': FieldResolutionRule(FieldStrategy.newerWins),
        'content': FieldResolutionRule(FieldStrategy.concat),
        'priority': FieldResolutionRule(FieldStrategy.newerWins),
        'shiftType': FieldResolutionRule(FieldStrategy.newerWins),
        'isRead': FieldResolutionRule(FieldStrategy.newerWins),
        'expiresAt': FieldResolutionRule(FieldStrategy.newerWins),
        'createdBy': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'guest_infos': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        // ✅ Audit Fix (2026-08-06): إزالة قاعدة guestIdNumber الميتة.
        // guestIdNumber لا يطابق أي حقل في جدول guest_infos — الحقل الفعلي
        // هو idNumber (مع altKey id_number في الـ adapter). قاعدة guestIdNumber
        // كانت تطابق لا شيء وتُهدر الذاكرة.
        // إضافة قواعد صريحة للحقول المهمة:
        'idNumber': FieldResolutionRule(FieldStrategy.newerWins),
        'roomNumber': FieldResolutionRule(FieldStrategy.newerWins),
        'guestName': FieldResolutionRule(FieldStrategy.newerWins),
        'nationality': FieldResolutionRule(FieldStrategy.newerWins),
        'notes': FieldResolutionRule(FieldStrategy.concat),
      },
    ),

    'booking_nights': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'price': FieldResolutionRule(FieldStrategy.newerWins),
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'hotel_day_ledger': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'totalIncome': FieldResolutionRule(FieldStrategy.newerWins),
        'totalExpenses': FieldResolutionRule(FieldStrategy.newerWins),
        'pendingBalances': FieldResolutionRule(FieldStrategy.newerWins),
        'occupancyRate': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'salary_cycles': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'totalAmount': FieldResolutionRule(FieldStrategy.newerWins),
        'totalPaid': FieldResolutionRule(FieldStrategy.newerWins),
        'totalDeductions': FieldResolutionRule(FieldStrategy.newerWins),
        'status': FieldResolutionRule(FieldStrategy.newerWins),
        'closedAt': FieldResolutionRule(FieldStrategy.newerWins),
        'startDate': FieldResolutionRule(FieldStrategy.newerWins),
        'endDate': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'booking_price_adjustments': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
        'reason': FieldResolutionRule(FieldStrategy.concat),
        'type': FieldResolutionRule(FieldStrategy.newerWins),
        'adjustmentType': FieldResolutionRule(FieldStrategy.newerWins),
        'appliedAt': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'blacklist': const EntityResolutionPolicy(
      // ✅ Audit Fix (2026-08-06): القواعد السابقة كانت تطابق مفاتيح JSON
      // داخل حقل 'content' وليس أعمدة. لكن SmartConflictResolver يُطبّق
      // القواعد على مستوى أعمدة الـ DB (عند الدمج في _autoMerge).
      // البيانات الفعلية لـ blacklist تُخزّن كـ JSON في حقل 'content' لجدول
      // shift_notes. هذا يعني أن القواعد الفردية للحقول لا تطابق أعمدة.
      //
      // الحل الصحيح: newerWins لكل شيء (لأن الـ JSON كامل يُعامَل كوحدة واحدة).
      // لو احتاج مستخدم لتعديل حقل واحد في blacklist، فإن الكيان يُكتب كاملاً
      // محلياً (مع version+1 و VC bump)، وnewerWins يضمن أن آخر تعديل يفوز.
      //
      // ملاحظة: 'name' و 'content' هما الأعمدة الفعلية في shift_notes table.
      // 'name' = اسم الشخص، 'content' = JSON payload (nationality, phone, etc.)
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'name': FieldResolutionRule(FieldStrategy.newerWins),
        'content': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'price_adjustments': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
        'reason': FieldResolutionRule(FieldStrategy.concat),
        'description': FieldResolutionRule(FieldStrategy.concat),
        'targetType': FieldResolutionRule(FieldStrategy.newerWins),
        'appliedAt': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

    'payment_voids': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'originalPaymentUuid': FieldResolutionRule(FieldStrategy.newerWins),
        'voidedAmount': FieldResolutionRule(FieldStrategy.newerWins),
        'voided_at': FieldResolutionRule(FieldStrategy.newerWins),
        'voidedAt': FieldResolutionRule(FieldStrategy.newerWins),
        'reason': FieldResolutionRule(FieldStrategy.concat),
        'isVoided': FieldResolutionRule(FieldStrategy.newerWins),
      },
    ),

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

    'salary_carry_over_logs': const EntityResolutionPolicy(
      defaultRule: FieldResolutionRule(FieldStrategy.newerWins),
      rules: {
        'amount': FieldResolutionRule(FieldStrategy.newerWins),
        'reason': FieldResolutionRule(FieldStrategy.concat),
        'carriedAt': FieldResolutionRule(FieldStrategy.newerWins),
        'employeeId': FieldResolutionRule(FieldStrategy.newerWins),
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

  /// حل التعارض تلقائياً — جميع التعارضات تُحل على مستوى السجل
  static ResolutionResult resolve({
    required String entity,
    required Map<String, dynamic>? localData,
    required Map<String, dynamic> remoteData,
    required Map<String, dynamic>? commonAncestor,
  }) {
    final detection = ConflictDetector.detect(
      localData: localData,
      remoteData: remoteData,
      commonAncestor: commonAncestor,
    );

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

    if (detection.type == ConflictType.deleteVsDelete) {
      return ResolutionResult(
        mergedData: localData!,
        strategy: ResolutionStrategy.localWins,
      );
    }
    if (detection.type == ConflictType.deleteVsUpdate) {
      return ResolutionResult(
        mergedData: localData!,
        strategy: ResolutionStrategy.localWins,
        warnings: const ['حذف محلي له أولوية على تعديل بعيد'],
        pushedToRemote: true,
      );
    }

    // جميع التعارضات المتزامنة تُحل تلقائياً على مستوى الحقل
    return _autoMerge(
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

    for (final field in detection.remoteChangedFields) {
      if (!detection.localChangedFields.contains(field)) {
        merged[field] = remoteData[field];
      }
    }

    final warnings = <String>[];

    for (final field in detection.conflictingFields) {
      final rule = policy.rules[field] ?? policy.defaultRule;
      final result = _resolveField(
        field: field,
        rule: rule,
        localData: localData,
        remoteData: remoteData,
        commonAncestor: detection.commonAncestor,
      );
      merged[field] = result.value;
      if (result.warning != null) {
        warnings.add(result.warning!);
      }
    }

    final localVc = VectorClock.fromString(
      (localData['vectorClock'] as String?) ?? '{}',
    );
    final remoteVc = VectorClock.fromString(
      (remoteData['vectorClock'] as String?) ?? '{}',
    );
    final mergedVc = localVc.copy();
    mergedVc.merge(remoteVc);
    merged['vectorClock'] = mergedVc.toString();

    final localTs = _extractTs(localData);
    final remoteTs = _extractTs(remoteData);
    merged['lastModified'] = localTs > remoteTs ? localTs : remoteTs;
    merged['version'] = ((merged['version'] as int?) ?? 0) + 1;

    return ResolutionResult(
      mergedData: merged,
      strategy: ResolutionStrategy.fieldLevelMerge,
      warnings: warnings,
      pushedToRemote: true,
    );
  }

  /// حل حقل واحد حسب قاعدة السياسة
  static _FieldResolution _resolveField({
    required String field,
    required FieldResolutionRule rule,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    Map<String, dynamic>? commonAncestor,
  }) {
    final localVal = localData[field];
    final remoteVal = remoteData[field];

    switch (rule.strategy) {
      case FieldStrategy.newerWins:
        final localTs = _extractTs(localData);
        final remoteTs = _extractTs(remoteData);
        // ✅ Audit Fix: عند تساوي الـ timestamp لا نترك البعيد يربح تلقائياً
        // (`>=` كان يمسح التعديلات المحلية على الحقول المالية عند التعارض).
        // نكسر التعادل بشكل حتمي ومتماثل عبر الأجهزة باستخدام deviceId
        // (نفس منطق LWW في sync_pull_service).
        bool remoteWins;
        if (remoteTs > localTs) {
          remoteWins = true;
        } else if (remoteTs < localTs) {
          remoteWins = false;
        } else {
          final remoteDev = (remoteData['deviceId'] as String?) ?? '';
          final localDev = (localData['deviceId'] as String?) ?? '';
          remoteWins = remoteDev.compareTo(localDev) < 0;
        }
        return _FieldResolution(
          value: remoteWins ? remoteVal : localVal,
          warning: remoteWins
              ? 'newerWins: remote won for $field'
              : 'newerWins: local won for $field',
        );

      case FieldStrategy.localWins:
        return _FieldResolution(value: localVal);

      case FieldStrategy.remoteWins:
        return _FieldResolution(value: remoteVal);

      case FieldStrategy.maxValue:
        final l = _asDouble(localVal);
        final r = _asDouble(remoteVal);
        return _FieldResolution(value: l > r ? l : r);

      case FieldStrategy.minValue:
        final l = _asDouble(localVal);
        final r = _asDouble(remoteVal);
        return _FieldResolution(value: l < r ? l : r);

      case FieldStrategy.sum:
        final ancestorVal = _asDouble(commonAncestor?[field]);
        final localDelta = _asDouble(localVal) - ancestorVal;
        final remoteDelta = _asDouble(remoteVal) - ancestorVal;
        return _FieldResolution(value: ancestorVal + localDelta + remoteDelta);

      case FieldStrategy.concat:
        final l = localVal?.toString() ?? '';
        final r = remoteVal?.toString() ?? '';
        if (l == r) return _FieldResolution(value: l);
        final mergedValue = _concatWithDedup(l, r);
        return _FieldResolution(
          value: mergedValue,
          warning: 'concat merge: $field',
        );
    }
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _extractTs(Map<String, dynamic> data) {
    return (data['lastModified'] as int?) ??
        (data['last_modified'] as int?) ??
        (data['lastModifiedEpoch'] as int?) ??
        0;
  }

  static String _concatWithDedup(String local, String remote) {
    const separator = '\n---\n';
    final localParts = local.split(separator);
    final remoteParts = remote.split(separator);
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

class _FieldResolution {
  const _FieldResolution({required this.value, this.warning});
  final dynamic value;
  final String? warning;
}
