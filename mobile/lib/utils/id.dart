import 'package:uuid/uuid.dart';

class IdGen {
  static const _uuid = Uuid();
  static String uuid() => _uuid.v4();

  /// UUID حتمي لاسم ثابت، لاستخدامه في السجلات المشتقة عبر الأجهزة.
  static String stableUuid(String name) => _uuid.v5(Namespace.url.value, name);

  static String bookingNightUuid({
    required String bookingUuid,
    required String hotelDayKey,
  }) {
    final bookingIdentity = bookingUuid.trim().toLowerCase().replaceAll(
      '-',
      '',
    );
    return stableUuid(
      'marina-hotel:booking-night:v1:$bookingIdentity:$hotelDayKey',
    );
  }

  /// معرّف قصير (8 أحرف) قابل للقراءة — يُستخدم في أسماء الأجهزة
  static String shortId() => _uuid.v4().substring(0, 8);
}
