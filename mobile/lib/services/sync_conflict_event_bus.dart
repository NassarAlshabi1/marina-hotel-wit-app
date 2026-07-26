import 'dart:async';
import 'package:flutter/foundation.dart';

/// حدث تضارب في المزامنة
class SyncConflictEvent {
  SyncConflictEvent({
    required this.table,
    required this.localUuid,
    required this.winnerSide,
    required this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  final String table;
  final String localUuid;
  final String winnerSide; // 'local' أو 'remote'
  final String reason;
  final DateTime timestamp;

  @override
  String toString() =>
      'SyncConflictEvent($table/$localUuid → $winnerSide: $reason)';
}

/// ناقل أحداث تضاربات المزامنة
///
/// يوفر stream عالمي لإرسال أحداث التضارب من أي خدمة مزامنة
/// ويمكن لأي جزء من التطبيق الاستماع إليه وعرض إشعارات للمستخدم.
///
/// الاستخدام:
/// ```dart
/// // إرسال حدث تضارب من خدمة المزامنة
/// SyncConflictEventBus.instance.emit(SyncConflictEvent(
///   table: 'payments',
///   localUuid: uuid,
///   winnerSide: 'local',
///   reason: 'البيانات المحلية أحدث',
/// ));
///
/// // الاستماع للأحداث في الواجهة
/// SyncConflictEventBus.instance.events.listen((event) {
///   showConflictWarning(context, ...);
/// });
/// ```
class SyncConflictEventBus {
  SyncConflictEventBus._();
  static final SyncConflictEventBus instance = SyncConflictEventBus._();

  final _controller = StreamController<SyncConflictEvent>.broadcast();
  final List<SyncConflictEvent> _recentEvents = [];
  static const int _maxRecentEvents = 50;

  /// Stream للأحداث الجديدة
  Stream<SyncConflictEvent> get events => _controller.stream;

  /// قائمة الأحداث الأخيرة (لعرضها لاحقاً)
  List<SyncConflictEvent> get recentEvents => List.unmodifiable(_recentEvents);

  /// عدد التضاربات غير المعروضة
  int get unshownConflictCount => _recentEvents.length;

  /// إرسال حدث تضارب جديد
  void emit(SyncConflictEvent event) {
    _recentEvents.add(event);
    if (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }
    _controller.add(event);
    debugPrint(
      '[ConflictBus] ${event.table}/${event.localUuid} → ${event.winnerSide}: ${event.reason}',
    );
  }

  /// إرسال حدث تضارب مبسط
  void emitSimple({
    required String table,
    required String localUuid,
    required String winnerSide,
    required String reason,
  }) {
    emit(
      SyncConflictEvent(
        table: table,
        localUuid: localUuid,
        winnerSide: winnerSide,
        reason: reason,
      ),
    );
  }

  /// مسح الأحداث الأخيرة (بعد عرضها للمستخدم)
  void clearRecent() {
    _recentEvents.clear();
  }

  /// تنظيف الموارد
  void dispose() {
    _controller.close();
  }
}
