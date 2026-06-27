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

    // تحديث lastModified + version
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    merged['lastModified'] = now;
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
        return _FieldResolution(
          value: '$l\n---\n$r',
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
}

/// نتيجة حل حقل واحد
class _FieldResolution {
  const _FieldResolution({required this.value, this.warning});
  final dynamic value;
  final String? warning;
}
