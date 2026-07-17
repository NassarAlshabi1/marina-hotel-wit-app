class OptimisticLockException implements Exception {
  OptimisticLockException({required this.table, required this.uuid, required this.expectedVersion, this.actualVersion});
  final String table;
  final String uuid;
  final int expectedVersion;
  final int? actualVersion;

  @override
  String toString() =>
      'OptimisticLockException: Version mismatch for $table/$uuid. '
      'Expected: $expectedVersion, Actual: $actualVersion';

  String toArabicMessage() =>
      'تعارض في البيانات: السجل تم تعديله من جهاز آخر. '
      'الجدول: $table، المعرّف: $uuid';
}
