/// أدوات لاختصار وتضغيم البيانات المنقولة إلى Appwrite Cloud
///
/// الهدف: تقليل حجم البيانات المرسلة بنسبة 50-70%
class CompactPayload {
  /// قائمة الحقول الأساسية المطلوبة للمزامنة (الحد الأدنى)
  static const Set<String> essentialSyncFields = {
    'localUuid',
    'serverId',
    'lastModified',
    'version',
    'origin',
    'deviceId',
  };

  /// قائمة الحقول التي لا تحتاج مزامنة (محلية فقط)
  static const Set<String> localOnlyFields = {
    'id', // معرف محلي فقط
    'createdAtIso',
    'updatedAtIso',
    'deletedAtIso',
    'createdAtEpoch',
    'lastModifiedEpoch',
    'stayDurationIso',
    'totalNightsCached',
    'totalDueCached',
    'totalPaidCached',
    'remainingBalanceCached',
    'isFullyPaid',
    'isOverdue',
    'needsCheckoutReview',
    'hotelDayCheckin',
    'hotelDayCheckout',
    'lastNightEpoch',
    'vectorClock', // يمكن استخدامه لكنه كبير
  };

  /// اختصار payload للحقول الأساسية فقط
  /// يستخدم عند إرسال delta changes
  static Map<String, dynamic> compactForSync(
    Map<String, dynamic> fullPayload, {
    Set<String>? additionalFields,
    bool includeEssential = true,
  }) {
    final compact = <String, dynamic>{};

    // إضافة الحقول الأساسية
    if (includeEssential) {
      for (final field in essentialSyncFields) {
        if (fullPayload.containsKey(field)) {
          compact[field] = fullPayload[field];
        }
      }
    }

    // إضافة حقول إضافية محددة
    if (additionalFields != null) {
      for (final field in additionalFields) {
        if (fullPayload.containsKey(field)) {
          compact[field] = fullPayload[field];
        }
      }
    }

    return compact;
  }

  /// اختصار payload لإرسال الحقول المتغيرة فقط (delta)
  static Map<String, dynamic> compactDelta({
    required Map<String, dynamic> newPayload,
    required Map<String, dynamic> oldPayload,
    bool includeEssential = true,
  }) {
    final delta = <String, dynamic>{};

    // إضافة الحقول الأساسية دائماً
    if (includeEssential) {
      for (final field in essentialSyncFields) {
        if (newPayload.containsKey(field)) {
          delta[field] = newPayload[field];
        }
      }
    }

    // إضافة الحقول المتغيرة فقط
    for (final entry in newPayload.entries) {
      final key = entry.key;
      final newValue = entry.value;

      // تخطي الحقول المحلية فقط
      if (localOnlyFields.contains(key)) continue;

      // تخطي الحقول الأساسية (تمت إضافتها)
      if (essentialSyncFields.contains(key)) continue;

      // تحقق من التغيير
      final oldValue = oldPayload[key];
      if (newValue != oldValue) {
        delta[key] = newValue;
      }
    }

    return delta;
  }

  /// إزالة الحقول المكررة (sync_* و camelCase)
  static Map<String, dynamic> removeDuplicates(
    Map<String, dynamic> payload,
  ) {
    final cleaned = Map<String, dynamic>.from(payload);

    // قائمة بالحقول التي لها نسخة sync_*
    const syncFieldMappings = {
      'sync_created_at': 'createdAt',
      'sync_updated_at': 'updatedAt',
      'sync_deleted_at': 'deletedAt',
      'sync_last_modified': 'lastModified',
      'sync_version': 'version',
      'sync_origin': 'origin',
      'sync_vector_clock': 'vectorClock',
    };

    // إزالة النسخة المكررة والاحتفاظ بواحدة فقط
    for (final entry in syncFieldMappings.entries) {
      final syncKey = entry.key;
      final originalKey = entry.value;

      if (cleaned.containsKey(syncKey) && cleaned.containsKey(originalKey)) {
        // الاحتفاظ بالحقول الأصلية فقط وإزالة sync_*
        cleaned.remove(syncKey);
      }
    }

    return cleaned;
  }

  /// ضغط payload بالكامل
  static Map<String, dynamic> fullCompact(
    Map<String, dynamic> payload, {
    bool removeLocalFields = true,
    bool removeDuplicates = true,
    Set<String>? keepFields,
  }) {
    var compact = Map<String, dynamic>.from(payload);

    // إزالة الحقول المحلية
    if (removeLocalFields) {
      compact.removeWhere((key, value) => localOnlyFields.contains(key));
    }

    // إزالة التكرارات
    if (removeDuplicates) {
      compact = CompactPayload.removeDuplicates(compact);
    }

    // الاحتفاظ بحقول محددة
    if (keepFields != null) {
      for (final field in keepFields) {
        if (payload.containsKey(field) && !compact.containsKey(field)) {
          compact[field] = payload[field];
        }
      }
    }

    return compact;
  }

  /// حساب نسبة التوفير
  static double calculateSavings(
    Map<String, dynamic> original,
    Map<String, dynamic> compacted,
  ) {
    final originalSize = _estimateSize(original);
    final compactedSize = _estimateSize(compacted);

    if (originalSize == 0) return 0;

    return ((originalSize - compactedSize) / originalSize) * 100;
  }

  /// تقدير حجم البيانات بالبايت
  static int _estimateSize(Map<String, dynamic> payload) {
    int size = 0;
    for (final entry in payload.entries) {
      // حجم المفتاح
      size += entry.key.length;

      // حجم القيمة (تقدير تقريبي)
      final value = entry.value;
      if (value is String) {
        size += value.length * 2; // UTF-16
      } else if (value is num) {
        size += 8; // double/int
      } else if (value is bool) {
        size += 1;
      } else if (value is Map || value is List) {
        size += _estimateSize(value as Map<String, dynamic>);
      }
    }
    return size;
  }
}

/// امتداد لـ Map لتسهيل الاختصار
extension CompactPayloadExtension on Map<String, dynamic> {
  /// اختصار البيانات للمزامنة
  Map<String, dynamic> compactForSync({
    Set<String>? additionalFields,
  }) {
    return CompactPayload.compactForSync(
      this,
      additionalFields: additionalFields,
    );
  }

  /// اختصار delta فقط
  Map<String, dynamic> compactDelta(Map<String, dynamic> oldPayload) {
    return CompactPayload.compactDelta(
      newPayload: this,
      oldPayload: oldPayload,
    );
  }

  /// ضغط كامل
  Map<String, dynamic> fullCompact({
    bool removeLocalFields = true,
    bool removeDuplicates = true,
  }) {
    return CompactPayload.fullCompact(
      this,
      removeLocalFields: removeLocalFields,
      removeDuplicates: removeDuplicates,
    );
  }
}
