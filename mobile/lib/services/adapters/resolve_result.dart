class ResolveResult {
  const ResolveResult({
    this.bookingLocalId,
    this.bookingUuidCache,
    this.employeeLocalId,
    this.employeeRelatedId,
    this.salaryCycleLocalId,
    this.createdAtEpoch,
    this.lastModifiedEpoch,
  });

  final int? bookingLocalId;
  final String? bookingUuidCache;

  /// معرّف الموظف المحلي بعد الحل (لـ FK: salary_withdrawals, salary_cycles)
  final int? employeeLocalId;

  /// معرّف الموظف المحلي بعد الحل (لـ FK: expenses.relatedId في مصروفات الرواتب)
  /// يُستخدم فقط عندما يكون expenseType مرتبطاً بالرواتب
  final int? employeeRelatedId;

  /// معرّف دورة الراتب المحلي بعد الحل (لـ FK: salary_payments)
  final int? salaryCycleLocalId;

  final int? createdAtEpoch;
  final int? lastModifiedEpoch;

  static const empty = ResolveResult();

  ResolveResult copyWith({
    int? bookingLocalId,
    String? bookingUuidCache,
    int? employeeLocalId,
    int? employeeRelatedId,
    int? salaryCycleLocalId,
    int? createdAtEpoch,
    int? lastModifiedEpoch,
  }) {
    return ResolveResult(
      bookingLocalId: bookingLocalId ?? this.bookingLocalId,
      bookingUuidCache: bookingUuidCache ?? this.bookingUuidCache,
      employeeLocalId: employeeLocalId ?? this.employeeLocalId,
      employeeRelatedId: employeeRelatedId ?? this.employeeRelatedId,
      salaryCycleLocalId: salaryCycleLocalId ?? this.salaryCycleLocalId,
      createdAtEpoch: createdAtEpoch ?? this.createdAtEpoch,
      lastModifiedEpoch: lastModifiedEpoch ?? this.lastModifiedEpoch,
    );
  }
}
