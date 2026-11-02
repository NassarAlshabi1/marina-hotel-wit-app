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
        remoteChangedFields: _findChangedFields(
          remoteData,
          commonAncestor,
          other: localData,
        ),
      );
    }
    if (!localDeleted && remoteDeleted) {
      // ✅ P0-4 Audit Fix (2026-08-06): تماثل سياسة الحذف.
      // سابقاً، كان هذا يُرجع `noConflictRemoteNewer` (يُطبّق الحذف البعيد
      // ويُفقد التحديث المحلي بصمت). هذا غير متماثل مع `deleteVsUpdate`
      // (الذي يحمي الحذف المحلي).
      // الإصلاح: تصنيف كـ `deleteVsUpdate` (معكوس) ليُعالجه SmartConflictResolver
      // بقرار واعٍ بدلاً من تطبيق الحذف صامتاً. الـ resolver يقرر: الحذف يربح
      // (لأن الـ delete أكثر حداثة عادةً) لكن مع تسجيل في audit trail.
      return ConflictDetectionResult(
        type: ConflictType.deleteVsUpdate,
        localChangedFields: _findChangedFields(
          localData,
          commonAncestor,
          other: remoteData,
        ),
        remoteChangedFields: {'deletedAt'},
      );
    }

    final localVcStr =
        (localData['vectorClock'] as String?) ??
        (localData['vector_clock'] as String?) ??
        '{}';
    final remoteVcStr =
        (remoteData['vectorClock'] as String?) ??
        (remoteData['vector_clock'] as String?) ??
        '{}';

    final localVc = VectorClock.fromString(localVcStr);
    final remoteVc = VectorClock.fromString(remoteVcStr);

    if (localVc.isEmpty && remoteVc.isEmpty) {
      final localTs = _extractTs(localData);
      final remoteTs = _extractTs(remoteData);
      if (remoteTs > localTs) {
        return ConflictDetectionResult(
          type: ConflictType.noConflictRemoteNewer,
          remoteChangedFields: _findChangedFields(
            remoteData,
            commonAncestor,
            other: localData,
          ),
        );
      }
      return ConflictDetectionResult(
        type: ConflictType.noConflictLocalNewer,
        localChangedFields: _findChangedFields(
          localData,
          commonAncestor,
          other: remoteData,
        ),
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
          remoteChangedFields: _findChangedFields(
            remoteData,
            commonAncestor,
            other: localData,
          ),
        );

      case VectorClockComparison.localNewer:
        return ConflictDetectionResult(
          type: ConflictType.noConflictLocalNewer,
          localVc: localVc,
          remoteVc: remoteVc,
          localChangedFields: _findChangedFields(
            localData,
            commonAncestor,
            other: remoteData,
          ),
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
    final localChanged = _findChangedFields(
      localData,
      commonAncestor,
      other: remoteData,
    );
    final remoteChanged = _findChangedFields(
      remoteData,
      commonAncestor,
      other: localData,
    );
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

  static Set<String> _findChangedFields(
    Map<String, dynamic> current,
    Map<String, dynamic>? ancestor, {
    Map<String, dynamic>? other,
  }) {
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
      // ✅ (2026-11-02) إصلاح «تعارضات المصروفات ومصروفات الرواتب»:
      // معرفات FK الرقمية محلية لكل جهاز (autoincrement يُعاد ترقيمه على
      // كل جهاز — نفس مبررات migration 68 و P0.2/R2). روابط الهوية عبر
      // الأجهزة هي حقول *Uuid (employeeUuid / withdrawalUuid / cashFlowUuid
      // / bookingUuidCache…). لو تركنا هذه الحقول تدخل حساب الحقول
      // المتغيّرة لكانت «مختلفة» بين كل جهازين حتماً → كل دمج 3-way
      // يراها تغيّراً بعيداً → version+1 ورفع النتيجة → الجهاز الآخر يدمج
      // بدوره ويرفع معرفاته → ping-pong تعارضات لا ينتهي على المصروفات
      // ومصروفات الرواتب تحديداً (relatedId/cashTransactionId/employeeId/
      // expenseId لا تتطابق أبداً عبر الأجهزة).
      if (_isDeviceLocalIdField(key)) continue;
      if (ancestor != null) {
        // ✅ 3-way: الحقل تغيّر فقط إذا اختلف عن السلف المشترك.
        if (!const DeepCollectionEquality().equals(
          ancestor[key],
          current[key],
        )) {
          changed.add(key);
        }
      } else if (other != null) {
        // ✅ Audit Fix: عند غياب السلف (أول تعارض على السجل)، لا نُرجع كل
        // الحقول كمتعارضة (كان يُحوّل الدمج إلى LWW على مستوى السجل). بدلاً
        // من ذلك نحسب الفرق الفعلي بين النسختين — الحقول التي تختلف بين
        // local و remote فقط هي المتعارضة. هذا يُبقي الدمج على مستوى الحقل
        // يعمل حتى دون سلف، ويحمي التعديلات المحلية من المسح الصامت.
        if (!const DeepCollectionEquality().equals(other[key], current[key])) {
          changed.add(key);
        }
      }
    }
    return changed;
  }

  /// ✅ (2026-11-02) أسماء أعمدة FK الرقمية المحلية لكل جهاز — لا تُقارن
  /// ولا تُدمج ولا تُنسخ من البعيد أبداً (قيمها على الجهاز الآخر بلا معنى
  /// هنا). القائمة مطابقة لأعمدة المخطط الفعلية:
  ///   id (كل الجداول)، relatedId/cashTransactionId (expenses)،
  ///   employeeId (salary_withdrawals/salary_payments/salary_carry_over_logs)،
  ///   expenseId (salary_withdrawals)، bookingId (booking_notes)،
  ///   cycleId (salary_payments).
  /// ملاحظة: serverBookingId/serverId ليست هنا — فهي معرفات سحابية
  /// ذات معنى عبر الأجهزة.
  static const Set<String> _deviceLocalIdFields = {
    'id',
    'relatedId',
    'related_id',
    'cashTransactionId',
    'cash_transaction_id',
    'employeeId',
    'employee_id',
    'expenseId',
    'expense_id',
    'bookingId',
    'booking_id',
    'cycleId',
    'cycle_id',
  };

  /// هل الحقل معرّف رقمي محلي لجهاز بعينه؟
  static bool _isDeviceLocalIdField(String key) =>
      _deviceLocalIdFields.contains(key);

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
  static bool isCriticalField(String fieldName) =>
      _criticalFields.contains(fieldName);
}
