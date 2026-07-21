// lib/services/sync_core/conflict_detector.dart
//
// نظام كشف التعارضات الذكي
//
// جميع التعارضات تُحل تلقائياً على مستوى السجل بالكامل
// بما في ذلك الحقول المالية — لا يوجد تصعيد يدوي

import 'package:collection/collection.dart';

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

  /// متزامن ونفس الحقول تغيّرت → تعارض حقيقي يُحل تلقائياً
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

  /// جميع التعارضات تُحل تلقائياً — لا يوجد تصعيد يدوي
  /// ما عدا التعارضات المتزامنة التي تمس حقولاً مالية/حرجة
  bool get needsManualResolution =>
      type == ConflictType.concurrentSameFields &&
      conflictingFields.any(ConflictDetector.isCriticalField);

  /// جميع التعارضات قابلة للحل التلقائي
  bool get canAutoResolve => !needsManualResolution;
}

/// كاشف التعارضات — يُصنّف العلاقة بين نسختين محلية وبعيدة
class ConflictDetector {
  const ConflictDetector._();

  /// الكشف عن نوع التعارض
  static ConflictDetectionResult detect({
    required Map<String, dynamic>? localData,
    required Map<String, dynamic> remoteData,
    required Map<String, dynamic>? commonAncestor,
  }) {
    if (localData == null) {
      return ConflictDetectionResult(
        type: ConflictType.noConflictRemoteNewer,
        remoteChangedFields: remoteData.keys.toSet(),
      );
    }

    final localDeleted = localData['deletedAt'] != null;
    final remoteDeleted = remoteData['deletedAt'] != null;

    if (localDeleted && remoteDeleted) {
      return const ConflictDetectionResult(type: ConflictType.deleteVsDelete);
    }
    if (localDeleted && !remoteDeleted) {
      return ConflictDetectionResult(
        type: ConflictType.deleteVsUpdate,
        localChangedFields: {'deletedAt'},
        remoteChangedFields: _findChangedFields(remoteData, commonAncestor),
      );
    }
    if (!localDeleted && remoteDeleted) {
      return const ConflictDetectionResult(type: ConflictType.noConflictRemoteNewer);
    }

    final localVcStr = (localData['vectorClock'] as String?) ?? (localData['vector_clock'] as String?) ?? '{}';
    final remoteVcStr = (remoteData['vectorClock'] as String?) ?? (remoteData['vector_clock'] as String?) ?? '{}';

    final localVc = VectorClock.fromString(localVcStr);
    final remoteVc = VectorClock.fromString(remoteVcStr);

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
        return ConflictDetectionResult(type: ConflictType.noConflictEqual, localVc: localVc, remoteVc: remoteVc);

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
        return _detectFieldConflict(
          localData: localData,
          remoteData: remoteData,
          commonAncestor: commonAncestor,
          localVc: localVc,
          remoteVc: remoteVc,
        );
    }
  }

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
      type: conflicting.isEmpty ? ConflictType.concurrentDifferentFields : ConflictType.concurrentSameFields,
      localVc: localVc,
      remoteVc: remoteVc,
      localChangedFields: localChanged,
      remoteChangedFields: remoteChanged,
      conflictingFields: conflicting,
      commonAncestor: commonAncestor,
    );
  }

  static Set<String> _findChangedFields(Map<String, dynamic> current, Map<String, dynamic>? ancestor) {
    if (ancestor == null) return current.keys.toSet();
    final changed = <String>{};
    for (final key in current.keys) {
      if (key.startsWith(r'$')) continue;
      if (key == 'lastModified' ||
          key == 'updatedAt' ||
          key == 'version' ||
          key == 'vectorClock' ||
          key == 'vector_clock' ||
          key == 'last_modified' ||
          key == 'last_modified_epoch' ||
          key == 'updated_at') {
        continue;
      }
      if (!const DeepCollectionEquality().equals(ancestor[key], current[key])) {
        changed.add(key);
      }
    }
    return changed;
  }

  static int _extractTs(Map<String, dynamic> data) {
    return (data['lastModified'] as int?) ??
        (data['last_modified'] as int?) ??
        (data['lastModifiedEpoch'] as int?) ??
        0;
  }

  /// الحقول المالية/الحرجة التي تتطلب عناية خاصة في conflict resolution.
  /// أُزيل 'status' لأن سياسة بعض الكيانات تستخدم newerWins.
  static final Set<String> _criticalFields = {
    'amount',
    'paidAmount',
    'price',
    'basicSalary',
    'isVoided',
    'discount',
    'discountAmount',
  };

  /// هل الحقل [fieldName] حرج (مالي)؟
  static bool isCriticalField(String fieldName) => _criticalFields.contains(fieldName);
}
