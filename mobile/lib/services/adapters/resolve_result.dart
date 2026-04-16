class ResolveResult {
  const ResolveResult({
    this.bookingLocalId,
    this.bookingUuidCache,
    this.createdAtEpoch,
    this.lastModifiedEpoch,
  });

  final int? bookingLocalId;
  final String? bookingUuidCache;
  final int? createdAtEpoch;
  final int? lastModifiedEpoch;

  static const empty = ResolveResult();

  ResolveResult copyWith({
    int? bookingLocalId,
    String? bookingUuidCache,
    int? createdAtEpoch,
    int? lastModifiedEpoch,
  }) {
    return ResolveResult(
      bookingLocalId: bookingLocalId ?? this.bookingLocalId,
      bookingUuidCache: bookingUuidCache ?? this.bookingUuidCache,
      createdAtEpoch: createdAtEpoch ?? this.createdAtEpoch,
      lastModifiedEpoch: lastModifiedEpoch ?? this.lastModifiedEpoch,
    );
  }
}
