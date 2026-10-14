import '../services/local_db.dart';

/// Resolves payment ownership without allowing a stale local integer ID to
/// override a trusted cross-device booking UUID.
class BookingPaymentMatcher {
  const BookingPaymentMatcher._();

  static final RegExp _uuidPattern = RegExp(
    r'^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$',
  );

  static bool matches(Payment payment, Booking booking) {
    final paymentUuid = normalizeUuid(payment.bookingUuidCache);
    if (paymentUuid.isNotEmpty) {
      return paymentUuid == normalizeUuid(booking.localUuid);
    }

    // Legacy compatibility: a row with no trusted UUID may use its local FK.
    // Remote adapters leave the FK unresolved when a remote reference cannot
    // be verified, so this fallback only applies to locally resolved legacy rows.
    return payment.bookingLocalId == booking.id;
  }

  static String normalizeUuid(String? value) {
    final trimmed = value?.trim() ?? '';
    if (_uuidPattern.hasMatch(trimmed)) {
      return trimmed.toLowerCase().replaceAll('-', '');
    }
    return trimmed.toLowerCase();
  }

  static List<String> uuidCandidates(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return const [];
    if (!_uuidPattern.hasMatch(trimmed)) return [trimmed];

    final compact = trimmed.replaceAll('-', '');
    final compactLower = compact.toLowerCase();
    final compactUpper = compact.toUpperCase();
    final dashed = compactLower.length == 32
        ? '${compactLower.substring(0, 8)}-${compactLower.substring(8, 12)}-'
              '${compactLower.substring(12, 16)}-${compactLower.substring(16, 20)}-'
              '${compactLower.substring(20)}'
        : trimmed.toLowerCase();
    return {
      trimmed,
      trimmed.toLowerCase(),
      trimmed.toUpperCase(),
      compactLower,
      compactUpper,
      dashed,
      dashed.toUpperCase(),
    }.toList();
  }
}
