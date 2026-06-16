// lib/services/vector_clock_service.dart
import 'dart:convert';

/// Vector Clock حقيقي لحل تعارضات المزامنة عبر الأجهزة.
///
/// يحل مشكلة clock skew بين الأجهزة بشكل صحيح (عكس Last-Write-Wins
/// الذي يعتمد على ساعة الجهاز وقد يكون غير دقيق).
///
/// الاستخدام:
/// ```dart
/// final vc = VectorClock.fromString(booking.vectorClock);
/// vc.increment(deviceId);
/// booking = booking.copyWith(vectorClock: vc.toString());
/// ```
///
/// عند الاستلام من جهاز آخر:
/// ```dart
/// final localVc = VectorClock.fromString(local.vectorClock);
/// final remoteVc = VectorClock.fromString(remote.vectorClock);
/// if (remoteVc.happensBefore(localVc)) {
///   // المحلي أحدث — تجاهل البعيد
/// } else if (localVc.happensBefore(remoteVc)) {
///   // البعيد أحدث — طبّقه
/// } else {
///   // تعارض حقيقي — استخدم Last-Write-Wins كحل أخير
/// }
/// ```
class VectorClock {
  VectorClock(Map<String, int>? counters) : _counters = counters ?? {};

  final Map<String, int> _counters;

  /// إنشاء من JSON string (المخزن في DB)
  factory VectorClock.fromString(String json) {
    if (json.isEmpty || json == '{}') return VectorClock({});
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return VectorClock(
          decoded.map((k, v) => MapEntry(k, (v as num).toInt())),
        );
      }
    } catch (_) {
      // JSON تالف — ابدأ بساعة فارغة
    }
    return VectorClock({});
  }

  /// إنشاء ساعة فارغة
  factory VectorClock.empty() => VectorClock({});

  /// الحصول على قيمة جهاز معين
  int get(String deviceId) => _counters[deviceId] ?? 0;

  /// زيادة عداد جهاز معين بمقدار 1
  void increment(String deviceId) {
    _counters[deviceId] = (_counters[deviceId] ?? 0) + 1;
  }

  /// ضبط قيمة جهاز معين (للاستعادة من نسخة احتياطية)
  void set(String deviceId, int value) {
    _counters[deviceId] = value;
  }

  /// دمج ساعة أخرى في هذه الساعة (merge).
  /// يأخذ max لكل جهاز.
  void merge(VectorClock other) {
    for (final entry in other._counters.entries) {
      final current = _counters[entry.key] ?? 0;
      _counters[entry.key] = current > entry.value ? current : entry.value;
    }
  }

  /// هل هذه الساعة تحدث قبل [other]؟ (happens-before)
  ///
  /// يرجع true إذا كانت كل قيم هذه الساعة <= قيم [other]
  /// وعلى الأقل قيمة واحدة <.
  bool happensBefore(VectorClock other) {
    var allLessOrEqual = true;
    var atLeastOneLess = false;

    final allKeys = {..._counters.keys, ...other._counters.keys};
    for (final key in allKeys) {
      final mine = _counters[key] ?? 0;
      final theirs = other._counters[key] ?? 0;
      if (mine > theirs) {
        allLessOrEqual = false;
        break;
      }
      if (mine < theirs) {
        atLeastOneLess = true;
      }
    }

    return allLessOrEqual && atLeastOneLess;
  }

  /// هل هذه الساعة متساوية مع [other]؟
  bool isEqual(VectorClock other) {
    final allKeys = {..._counters.keys, ...other._counters.keys};
    for (final key in allKeys) {
      if ((_counters[key] ?? 0) != (other._counters[key] ?? 0)) {
        return false;
      }
    }
    return true;
  }

  /// هل هذه الساعة متزامنة مع [other]؟ (تعارض حقيقي)
  ///
  /// يرجع true إذا لم تكن أي منهما happens-before الأخرى.
  bool isConcurrent(VectorClock other) {
    return !happensBefore(other) && !other.happensBefore(this) && !isEqual(other);
  }

  /// تحويل إلى JSON string (للتخزين في DB)
  @override
  String toString() {
    if (_counters.isEmpty) return '{}';
    return jsonEncode(_counters);
  }

  /// نسخة من الساعة
  VectorClock copy() => VectorClock(Map.from(_counters));

  /// عدد الأجهزة في الساعة
  int get deviceCount => _counters.length;

  /// هل الساعة فارغة؟
  bool get isEmpty => _counters.isEmpty;

  /// إجمالي كل الأحداث
  int get totalEvents => _counters.values.fold(0, (a, b) => a + b);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is VectorClock && isEqual(other));

  @override
  int get hashCode => toString().hashCode;
}

/// نتيجة مقارنة ساعات متجهة
enum VectorClockComparison {
  /// المحلي أحدث (البعيد يحدث قبل المحلي)
  localNewer,

  /// البعيد أحدث (المحلي يحدث قبل البعيد)
  remoteNewer,

  /// متساوية (لا حاجة للتحديث)
  equal,

  /// متزامنة (تعارض حقيقي — استخدم LWW كحل أخير)
  concurrent,
}

/// دوال مساعدة لمقارنة الساعات
class VectorClockComparator {
  VectorClockComparator._();

  /// مقارنة ساعة محلية مع بعيدة
  static VectorClockComparison compare(
    VectorClock local,
    VectorClock remote,
  ) {
    if (local.isEqual(remote)) {
      return VectorClockComparison.equal;
    }
    if (remote.happensBefore(local)) {
      return VectorClockComparison.localNewer;
    }
    if (local.happensBefore(remote)) {
      return VectorClockComparison.remoteNewer;
    }
    return VectorClockComparison.concurrent;
  }

  /// حل تعارض باستخدام vector clock + last-write-wins fallback.
  ///
  /// يرجع:
  /// - `true` إذا كان البعيد يجب أن يُطبّق
  /// - `false` إذا كان المحلي يجب أن يُحتفظ به
  static bool shouldApplyRemote({
    required VectorClock localVc,
    required VectorClock remoteVc,
    required int localLastModified,
    required int remoteLastModified,
  }) {
    final comparison = compare(localVc, remoteVc);

    switch (comparison) {
      case VectorClockComparison.equal:
        // نفس الساعة — لا حاجة للتحديث
        return false;
      case VectorClockComparison.remoteNewer:
        // البعيد أحدث — طبّقه
        return true;
      case VectorClockComparison.localNewer:
        // المحلي أحدث — احتفظ به
        return false;
      case VectorClockComparison.concurrent:
        // تعارض حقيقي — استخدم LWW كحل أخير
        return remoteLastModified > localLastModified;
    }
  }

  /// دمج ساعة بعيدة في محلية (بعد تطبيق التحديث)
  static VectorClock mergeAfterApply(
    VectorClock localVc,
    VectorClock remoteVc,
  ) {
    final merged = localVc.copy();
    merged.merge(remoteVc);
    return merged;
  }
}
