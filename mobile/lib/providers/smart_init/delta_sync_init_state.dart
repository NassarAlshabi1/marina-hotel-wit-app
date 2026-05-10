/// حالات تهيئة Delta Sync الذكية.
///
/// تُستخدم لعرض حالة التهيئة في UI واتخاذ القرارات.
enum DeltaSyncInitState {
  /// لم يبدأ المراقب بعد.
  idle,

  /// ينتظر عودة الشبكة.
  waitingNetwork,

  /// جاري تهيئة AppwriteDeltaSync.
  initializing,

  /// التهيئة مكتملة بنجاح — النظام جاهز.
  ready,

  /// فشلت التهيئة — سيعاد المحاولة تلقائياً.
  failed;

  /// النص العربي لعرضه في UI.
  String get displayArabic {
    switch (this) {
      case DeltaSyncInitState.idle:
        return 'في انتظار البدء';
      case DeltaSyncInitState.waitingNetwork:
        return 'في انتظار الاتصال بالإنترنت';
      case DeltaSyncInitState.initializing:
        return 'جاري التهيئة...';
      case DeltaSyncInitState.ready:
        return 'جاهز';
      case DeltaSyncInitState.failed:
        return 'خطأ - جاري إعادة المحاولة...';
    }
  }

  /// أيقونة Material المرتبطة.
  String get iconName {
    switch (this) {
      case DeltaSyncInitState.idle:
        return 'hourglass_empty';
      case DeltaSyncInitState.waitingNetwork:
        return 'wifi_off';
      case DeltaSyncInitState.initializing:
        return 'sync';
      case DeltaSyncInitState.ready:
        return 'check_circle';
      case DeltaSyncInitState.failed:
        return 'error';
    }
  }

  /// لون الحالة.
  String get colorHex {
    switch (this) {
      case DeltaSyncInitState.idle:
        return '#9E9E9E'; // grey
      case DeltaSyncInitState.waitingNetwork:
        return '#FF9800'; // orange
      case DeltaSyncInitState.initializing:
        return '#2196F3'; // blue
      case DeltaSyncInitState.ready:
        return '#4CAF50'; // green
      case DeltaSyncInitState.failed:
        return '#F44336'; // red
    }
  }
}
