// ignore_for_file: prefer_constructors_over_static_methods
/// تتبّع أخطاء المزامنة الثانوية
///
/// يخزّن الأخطاء في الذاكرة مع إمكانية تصديرها إلى نص.
/// يُستخدم من SecondarySyncManager لجمع معلومات الإخفاقات
/// وعرضها في شاشة الإعدادات.
library;

import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// خطأ في مزامنة سجل واحد
class SyncErrorEntry {
  SyncErrorEntry({
    required this.entity,
    required this.localUuid,
    required this.reason,
    required this.isPermanent,
    this.attempts = 1,
    this.timestamp,
  });

  final String entity;
  final String localUuid;
  final String reason;
  final bool isPermanent;
  final int attempts;
  final DateTime? timestamp;

  @override
  String toString() {
    final type = isPermanent ? '☠️ دائم' : '⚠️ عابر';
    return '$type [$entity] $localUuid (محاولة $attempts): $reason';
  }

  Map<String, dynamic> toJson() => {
    'entity': entity,
    'localUuid': localUuid,
    'reason': reason,
    'isPermanent': isPermanent,
    'attempts': attempts,
    'timestamp': timestamp?.toLocal().toIso8601String(),
  };
}

/// حالة المزامنة الإجمالية
class SyncSessionSummary {
  SyncSessionSummary({
    this.totalPushed = 0,
    this.totalFailed = 0,
    this.totalDead = 0,
    this.isSuccess = true,
    this.message = '',
    this.errors = const [],
    this.sessionTime,
  });

  final int totalPushed;
  final int totalFailed;
  final int totalDead;
  final bool isSuccess;
  final String message;
  final List<SyncErrorEntry> errors;
  final DateTime? sessionTime;

  /// ملخص نصي جاهز للنسخ
  String get textSummary {
    final buf = StringBuffer();
    buf.writeln('🔄 تقرير المزامنة الثانوية');
    buf.writeln('════════════════════════════');
    buf.writeln();
    buf.writeln('${isSuccess ? "✅" : "❌"} $message');
    buf.writeln('📤 تم الرفع: $totalPushed');
    buf.writeln('❌ فشل: $totalFailed');
    buf.writeln('☠️ Dead: $totalDead');
    buf.writeln();

    if (errors.isNotEmpty) {
      // تجميع حسب الكيان
      final byEntity = <String, List<SyncErrorEntry>>{};
      for (final e in errors) {
        byEntity.putIfAbsent(e.entity, () => []).add(e);
      }

      buf.writeln('── الأخطاء حسب الجدول ──');
      for (final entry in byEntity.entries) {
        buf.writeln('  📁 ${entry.key} (${entry.value.length}):');
        for (final err in entry.value) {
          final type = err.isPermanent ? '☠️' : '⚠️';
          final reason = err.reason.length > 150
              ? '${err.reason.substring(0, 150)}...'
              : err.reason;
          buf.writeln('    $type [${err.localUuid}] $reason');
        }
      }
      buf.writeln();
    }

    buf.writeln(
      '🕐 ${sessionTime?.toLocal().toIso8601String() ?? DateTime.now().toLocal().toIso8601String()}',
    );
    buf.writeln('Marina Hotel — Secondary Sync Report');
    return buf.toString();
  }
}

/// متتبّع أخطاء المزامنة الثانوية
///
/// يخزّن سجل الأخطاء في الذاكرة ويسمح بتصديرها.
/// يمكن إرفاقه بـ SecondarySyncManager لجمع الأخطاء.
class SecondarySyncTracker {
  SecondarySyncTracker._();
  static SecondarySyncTracker? _instance;
  static SecondarySyncTracker get instance =>
      _instance ??= SecondarySyncTracker._();

  /// أخطاء الجلسة الحالية
  final List<SyncErrorEntry> _currentSessionErrors = [];

  /// آخر جلسة كاملة
  SyncSessionSummary? _lastSession;

  /// هل هناك جلسة نشطة حالياً؟
  bool _hasActiveSession = false;

  /// بدء جلسة تتبّع جديدة
  void startSession() {
    _currentSessionErrors.clear();
    _hasActiveSession = true;
  }

  /// تسجيل خطأ
  void trackError({
    required String entity,
    required String localUuid,
    required String reason,
    bool isPermanent = false,
    int attempts = 1,
  }) {
    _currentSessionErrors.add(
      SyncErrorEntry(
        entity: entity,
        localUuid: localUuid,
        reason: reason,
        isPermanent: isPermanent,
        attempts: attempts,
        timestamp: DateTime.now(),
      ),
    );
    if (kDebugMode) {
      dlog(() => '🔴 [SyncTracker] $entity/$localUuid: $reason');
    }
  }

  /// إنهاء الجلسة وإرجاع الملخص
  SyncSessionSummary endSession({
    required int pushed,
    required int failed,
    required int dead,
    required bool isSuccess,
    required String message,
  }) {
    _lastSession = SyncSessionSummary(
      totalPushed: pushed,
      totalFailed: failed,
      totalDead: dead,
      isSuccess: isSuccess,
      message: message,
      errors: List.from(_currentSessionErrors),
      sessionTime: DateTime.now(),
    );
    _hasActiveSession = false;
    return _lastSession!;
  }

  /// آخر جلسة (للقراءة)
  SyncSessionSummary? get lastSession => _lastSession;

  /// نص تقرير المزامنة الأخير (جاهز للنسخ)
  String get lastReportText =>
      _lastSession?.textSummary ?? 'لا توجد جلسة مزامنة سابقة';

  /// أخطاء الجلسة الحالية
  List<SyncErrorEntry> get currentErrors =>
      List.unmodifiable(_currentSessionErrors);

  /// هل هناك أخطاء في الجلسة الحالية؟
  bool get hasErrorsInCurrentSession => _currentSessionErrors.isNotEmpty;

  /// هل هناك جلسة نشطة؟
  bool get hasActiveSession => _hasActiveSession;

  /// تجميع الأخطاء حسب الكيان
  Map<String, List<SyncErrorEntry>> get errorsByEntity {
    final result = <String, List<SyncErrorEntry>>{};
    for (final e in _currentSessionErrors) {
      result.putIfAbsent(e.entity, () => []).add(e);
    }
    return result;
  }

  /// الأخطاء الدائمة (التي وصلت Dead)
  List<SyncErrorEntry> get permanentErrors =>
      _currentSessionErrors.where((e) => e.isPermanent).toList();

  /// مسح سجل الأخطاء
  void clear() {
    _currentSessionErrors.clear();
    _lastSession = null;
  }

  /// تصدير كل الأخطاء كنص
  String exportAllErrors() {
    if (_currentSessionErrors.isEmpty && _lastSession == null) {
      return 'لا توجد أخطاء مسجّلة';
    }

    final buf = StringBuffer();
    if (_lastSession != null) {
      buf.writeln(_lastSession!.textSummary);
      buf.writeln();
    }
    if (_currentSessionErrors.isNotEmpty) {
      buf.writeln('── أخطاء الجلسة الحالية ──');
      for (final e in _currentSessionErrors) {
        buf.writeln(e.toString());
      }
    }
    return buf.toString();
  }
}
