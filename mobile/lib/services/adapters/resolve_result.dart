class ResolveResult {
  const ResolveResult({
    this.bookingLocalId,
    this.bookingUuidCache,
    this.createdAtEpoch,
    this.lastModifiedEpoch,
    this.resolvedEmployeeId,
    this.resolvedExpenseId,
  });

  final int? bookingLocalId;
  final String? bookingUuidCache;
  final int? createdAtEpoch;
  final int? lastModifiedEpoch;
  final int? resolvedEmployeeId;
  final int? resolvedExpenseId;

  static const empty = ResolveResult();

  ResolveResult copyWith({
    int? bookingLocalId,
    String? bookingUuidCache,
    int? createdAtEpoch,
    int? lastModifiedEpoch,
    int? resolvedEmployeeId,
    int? resolvedExpenseId,
  }) {
    return ResolveResult(
      bookingLocalId: bookingLocalId ?? this.bookingLocalId,
      bookingUuidCache: bookingUuidCache ?? this.bookingUuidCache,
      createdAtEpoch: createdAtEpoch ?? this.createdAtEpoch,
      lastModifiedEpoch: lastModifiedEpoch ?? this.lastModifiedEpoch,
      resolvedEmployeeId: resolvedEmployeeId ?? this.resolvedEmployeeId,
      resolvedExpenseId: resolvedExpenseId ?? this.resolvedExpenseId,
    );
  }
}
