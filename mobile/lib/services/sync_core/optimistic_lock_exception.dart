class OptimisticLockException implements Exception {
  final String table;
  final String uuid;
  final int expectedVersion;
  final int? actualVersion;

  OptimisticLockException({
    required this.table,
    required this.uuid,
    required this.expectedVersion,
    this.actualVersion,
  });

  @override
  String toString() =>
      'OptimisticLockException: Version mismatch for $table/$uuid. '
      'Expected: $expectedVersion, Actual: $actualVersion';

  String toArabicMessage() =>
      'تعارض في البيانات: السجل تم تعديله من جهاز آخر. '
      'الجدول: $table، المعرّف: $uuid';
}
