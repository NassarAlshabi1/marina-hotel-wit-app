/// نموذج نتيجة المزامنة
class SyncResult {

  SyncResult({
    required this.isSuccess,
    required this.message,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.conflictCount = 0,
    this.duration = Duration.zero,
    this.metadata,
    this.errors = const [],
  });

  // Factory constructors
  factory SyncResult.success({
    int pushed = 0,
    int pulled = 0,
    Map<String, dynamic>? adapters,
  }) =>
      SyncResult(
        isSuccess: true,
        message: 'تمت المزامنة بنجاح',
        pushedCount: pushed,
        pulledCount: pulled,
        metadata: adapters,
      );

  factory SyncResult.error(String error) => SyncResult(
        isSuccess: false,
        message: error,
        errors: [SyncError(message: error)],
      );

  factory SyncResult.conflict(String message) => SyncResult(
        isSuccess: false,
        message: message,
        conflictCount: 1,
      );

  factory SyncResult.offline() => SyncResult(
        isSuccess: false,
        message: 'لا يوجد اتصال بالإنترنت',
      );

  factory SyncResult.cancelled() => SyncResult(
        isSuccess: false,
        message: 'تم إلغاء المزامنة',
      );
  final bool isSuccess;
  final String message;
  final int pushedCount;
  final int pulledCount;
  final int conflictCount;
  final Duration duration;
  final Map<String, dynamic>? metadata;
  final List<SyncError> errors;

  // Getters
  bool get hasConflicts => conflictCount > 0;
  bool get hasErrors => errors.isNotEmpty;
  int get totalChanges => pushedCount + pulledCount;

  // Merge results
  SyncResult merge(SyncResult other) {
    return SyncResult(
      isSuccess: isSuccess && other.isSuccess,
      message: '$message | ${other.message}',
      pushedCount: pushedCount + other.pushedCount,
      pulledCount: pulledCount + other.pulledCount,
      conflictCount: conflictCount + other.conflictCount,
      duration: duration + other.duration,
      metadata: {...?metadata, ...?other.metadata},
      errors: [...errors, ...other.errors],
    );
  }

  @override
  String toString() {
    return 'SyncResult(success: $isSuccess, pushed: $pushedCount, pulled: $pulledCount, errors: ${errors.length})';
  }
}

/// نموذج خطأ المزامنة
class SyncError {

  SyncError({
    required this.message,
    this.code,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  final String message;
  final String? code;
  final DateTime timestamp;
  final StackTrace? stackTrace;

  @override
  String toString() => '[$code] $message';
}
