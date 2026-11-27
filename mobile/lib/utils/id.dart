import 'package:uuid/uuid.dart';

class IdGen {
  static const _uuid = Uuid();
  static String uuid() => _uuid.v4();

  /// معرّف قصير (8 أحرف) قابل للقراءة — يُستخدم في أسماء الأجهزة
  static String shortId() => _uuid.v4().substring(0, 8);

  /// معرّف UUID حتمي (Deterministic v5) لليلة الحجز مشتق من (bookingLocalUuid, hotelDayKey).
  /// يضمن أن أي جهازين يولّدان نفس الليلة لنفس الحجز ينتجان نفس الـ localUuid تماماً،
  /// فلا تتكرر مستندات booking_nights على Appwrite Cloud أو محلياً أبداً.
  static String bookingNightUuid(String bookingLocalUuid, String hotelDayKey) {
    final normalizedBookingUuid = bookingLocalUuid
        .trim()
        .toLowerCase()
        .replaceAll('-', '');
    final normalizedDayKey = hotelDayKey.trim();
    return _uuid.v5(
      Namespace.url.value,
      'marina:booking_night:$normalizedBookingUuid:$normalizedDayKey',
    );
  }
}
