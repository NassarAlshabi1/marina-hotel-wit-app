// lib/services/sync_core/conflict_detector.dart
//
// ✅ نظام كشف التعارضات الذكي (2026-06-27)
//
// يُصنّف التعارضات إلى 7 أنواع بدلاً من "تحديث أو لا":
// 1. noConflictRemoteNewer — البعيد أحدث سببياً
// 2. noConflictLocalNewer — المحلي أحدث سببياً
// 3. noConflictEqual — متطابقتان
// 4. concurrentDifferentFields — متزامن لكن حقول مختلفة → دمج تلقائي
// 5. concurrentSameFields — متزامن ونفس الحقول → تعارض حقيقي
// 6. deleteVsUpdate — حذف محلي + تعديل بعيد
// 7. deleteVsDelete — كلاهما محذوف

import '../vector_clock_service.dart';

/// أنواع التعارضات المُكتشفة
enum ConflictType {
  /// البعيد أحدث سببياً (happensBefore) → لا تعارض
  noConflictRemoteNewer,

  /// المحلي أحدث سببياً → لا تعارض
  noConflictLocalNewer,

  /// متطابقتان (equal) → لا تحديث
  noConflictEqual,

  /// متزامن (concurrent) لكن الحقول المتغيرة مختلفة → دمج تلقائي
  concurrentDifferentFields,

  /// متزامن ونفس الحقول تغيّرت → تعارض حقيقي يحتاج حل
  concurrentSameFields,

  /// حذف محلي + تعديل بعيد → الحذف له أولوية
  deleteVsUpdate,

  /// كلاهما محذوف → لا تعارض
  deleteVsDelete,
}

/// نتيجة كشف التعارض
class ConflictDetectionResult {
  const ConflictDetectionResult({
    required this.type,
    this.localVc,
    this.remoteVc,
    this.localChangedFields = const {},
    this.remoteChangedFields = const {},
    this.conflictingFields = const {},
    this.commonAncestor,
  });

  final ConflictType type;
  final VectorClock? localVc;
  final VectorClock? remoteVc;
  final Set<String> localChangedFields;
  final Set<String> remoteChangedFields;

  /// الحقول المتعارضة فقط (التقاطع بين localChangedFields و remoteChangedFields)
  final Set<String> conflictingFields;
  final Map<String, dynamic>? commonAncestor;

  /// هل يحتاج تصعيداً يدوياً؟
  bool get needsManualResolution =>
      type == ConflictType.concurrentSameFields &&
      conflictingFields.any(ConflictDetector.isCriticalField);

  /// هل يمكن حلّه تلقائياً؟
  bool get canAutoResolve =>
      type == ConflictType.concurrentDifferentFields ||
      type == ConflictType.deleteVsDelete ||
      type == ConflictType.noConflictEqual ||
      type == ConflictType.noConflictRemoteNewer ||
      type == ConflictType.noConflictLocalNewer ||
      (type == ConflictType.concurrentSameFields &&
          !conflictingFields.any(ConflictDetector.isCriticalField));
}

/// كاشف التعارضات — يُصنّف العلاقة بين نسختين محلية وبعيدة
class ConflictDetector {
  const ConflictDetector._();

  /// الحقول المالية الحرجة — لا تُدمج تلقائياً أبداً
  static const _criticalFields = {
    'amount', 'paidAmount', 'totalAmount', 'remainingAmount',
    'price', 'basicSalary',
    'isVoided', 'voidedAmount',
    'status',
    'discount', 'discountAmount',
  };

  static bool isCriticalField(String field) => _criticalFields.contains(field);

  /// الكشف عن نوع التعارض
  static ConflictDetectionResult detect({
    required Map<String, dynamic>? localData,
    required Map<String, dynamic> remoteData,
    required Map<String, dynamic>? commonAncestor,
  }) {
    // 1. لا يوجد سجل محلي → سحب عادي
    if (localData == null) {
      return ConflictDetectionResult(
        type: ConflictType.noConflictRemoteNewer,
        remoteChangedFields: remoteData.keys.toSet(),
      );
    }

    // 2. فحص الحذف
    final localDeleted = localData['deletedAt'] != null;
    final remoteDeleted = remoteData['deletedAt'] != null;

    if (localDeleted && remoteDeleted) {
      return const ConflictDetectionResult(
        type: ConflictType.deleteVsDelete,
      );
    }
    if (localDeleted && !remoteDeleted) {
      return ConflictDetectionResult(
        type: ConflictType.deleteVsUpdate,
        localChangedFields: {'deletedAt'},
        remoteChangedFields: _findChangedFields(remoteData, commonAncestor),
      );
    }
    if (!localDeleted && remoteDeleted) {
      // البعيد محذوف — نسجّله كتحديث عادي (الحذف البعيد يفوز)
      return const ConflictDetectionResult(
        type: ConflictType.noConflictRemoteNewer,
      );
    }

    // 3. مقارنة Vector Clocks
    final localVcStr = (localData['vectorClock'] as String?) ??
        (localData['vector_clock'] as String?) ??
        '{}';
    final remoteVcStr = (remoteData['vectorClock'] as String?) ??
        (remoteData['vector_clock'] as String?) ??
        '{}';

    final localVc = VectorClock.fromString(localVcStr);
    final remoteVc = VectorClock.fromString(remoteVcStr);

    // إذا كلتا الساعتين فارغتين → LWW (fallback)
    if (localVc.isEmpty && remoteVc.isEmpty) {
      final localTs = _extractTs(localData);
      final remoteTs = _extractTs(remoteData);
      if (remoteTs > localTs) {
        return ConflictDetectionResult(
          type: ConflictType.noConflictRemoteNewer,
          remoteChangedFields: _findChangedFields(remoteData, commonAncestor),
        );
      }
      return ConflictDetectionResult(
        type: ConflictType.noConflictLocalNewer,
        localChangedFields: _findChangedFields(localData, commonAncestor),
      );
    }

    final comparison = VectorClockComparator.compare(localVc, remoteVc);

    switch (comparison) {
      case VectorClockComparison.equal:
        return ConflictDetectionResult(
          type: ConflictType.noConflictEqual,
          localVc: localVc,
          remoteVc: remoteVc,
        );

      case VectorClockComparison.remoteNewer:
        return ConflictDetectionResult(
          type: ConflictType.noConflictRemoteNewer,
          localVc: localVc,
          remoteVc: remoteVc,
          remoteChangedFields: _findChangedFields(remoteData, commonAncestor),
        );

      case VectorClockComparison.localNewer:
        return ConflictDetectionResult(
          type: ConflictType.noConflictLocalNewer,
          localVc: localVc,
          remoteVc: remoteVc,
          localChangedFields: _findChangedFields(localData, commonAncestor),
        );

      case VectorClockComparison.concurrent:
        // 4. كشف حقل بحقل
        return _detectFieldConflict(
          localData: localData,
          remoteData: remoteData,
          commonAncestor: commonAncestor,
          localVc: localVc,
          remoteVc: remoteVc,
        );
    }
  }

  /// كشف التعارض على مستوى الحقل
  static ConflictDetectionResult _detectFieldConflict({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required Map<String, dynamic>? commonAncestor,
    required VectorClock localVc,
    required VectorClock remoteVc,
  }) {
    final localChanged = _findChangedFields(localData, commonAncestor);
    final remoteChanged = _findChangedFields(remoteData, commonAncestor);
    final conflicting = localChanged.intersection(remoteChanged);

    return ConflictDetectionResult(
      type: conflicting.isEmpty
          ? ConflictType.concurrentDifferentFields
          : ConflictType.concurrentSameFields,
      localVc: localVc,
      remoteVc: remoteVc,
      localChangedFields: localChanged,
      remoteChangedFields: remoteChanged,
      conflictingFields: conflicting,
      commonAncestor: commonAncestor,
    );
  }

  /// إيجاد الحقول التي تغيّرت مقارنة بالـ ancestor
  static Set<String> _findChangedFields(
    Map<String, dynamic> current,
    Map<String, dynamic>? ancestor,
  ) {
    if (ancestor == null) return current.keys.toSet();
    final changed = <String>{};
    for (final key in current.keys) {
      if (key.startsWith('\$')) continue; // تخطّي metadata
      if (key == 'lastModified' || key == 'updatedAt' || key == 'version') {
        continue; // تخطّي حقول النظام
      }
      if (ancestor[key] != current[key]) {
        changed.add(key);
      }
    }
    return changed;
  }

  /// استخراج الطابع الزمني من البيانات
  static int _extractTs(Map<String, dynamic> data) {
    return (data['lastModified'] as int?) ??
        (data['last_modified'] as int?) ??
        (data['lastModifiedEpoch'] as int?) ??
        0;
  }
}
