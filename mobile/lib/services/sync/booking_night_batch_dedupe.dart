// ══════════════════════════════════════════════════════════════════
//  booking_night_batch_dedupe.dart
//
//  دمج الليالي المكررة **داخل دفعة السحب الواحدة** قبل تطبيقها محلياً.
//
//  لماذا: الليلة الواحدة قد تصل بهويتين مختلفتين — صفوف كُتبت قبل الهوية
//  الحتمية (`IdGen.bookingNightUuid`)، أو صفوف بلا `booking_uuid_cache`
//  تتجاوز الفهرس الفريد `ux_booking_nights_booking_day_live` على D1، أو
//  جهازان رفعا الصف نفسه قبل أن تتقارب الهوية. تطبيق الصفين يُنتج ليلتين
//  محليتين لنفس (الحجز، اليوم) — وهو جذر التضاعف الذي بلغ 3,495 ليلة
//  مقابل 356 حجزاً (تقرير 2026-11-23، §9).
//
//  دالة نقية (بلا قاعدة بيانات) كي تُختبر دون تشغيل المزامنة كاملة:
//  المفتاح هو هوية الحجز المطبّعة + يوم الفندق، والفائز يُحدَّد بترتيب
//  حتمي يتفق عليه كل الأجهزة:
//      updated_at ← version ← last_modified ← local_uuid (الأكبر)
//  الصفوف التي لا تحمل هوية حجز صالحة تُمرَّر كما هي (يطويها مسار إعادة
//  الربط `BookingNightsIntegrityService` لاحقاً، لا التخمين هنا).
// ══════════════════════════════════════════════════════════════════

typedef PullRecord = ({String entity, Map<String, dynamic> record});

class BookingNightBatchDedupe {
  BookingNightBatchDedupe._();

  /// يرجع [records] بعد طيّ تكرار الليالي: صف واحد لكل (حجز، يوم).
  /// ترتيب الصفوف غير المكررة محفوظ كما جاء، والصفوف الفائزة تُلحق بآخر
  /// القائمة (ترتيب التطبيق يحكمه `pullApplyPriority` بعدها).
  static List<PullRecord> collapse(List<PullRecord> records) {
    final winners = <String, PullRecord>{};
    final rest = <PullRecord>[];
    for (final item in records) {
      if (item.entity != 'booking_nights') {
        rest.add(item);
        continue;
      }
      final key = slotKey(item.record);
      if (key == null) {
        rest.add(item);
        continue;
      }
      final current = winners[key];
      if (current == null || isNewer(item.record, current.record)) {
        winners[key] = item;
      }
    }
    return [...rest, ...winners.values];
  }

  /// مفتاح خانة الليلة على السلك: `<booking uuid مطبّع>|<hotel day>`
  /// أو `null` إذا كانت الحمولة ناقصة الهوية.
  static String? slotKey(Map<String, dynamic> record) {
    final day =
        (record['hotel_day_key'] ?? record['hotelDayKey'] ?? '').toString().trim();
    if (day.isEmpty) {
      return null;
    }
    final rawBooking =
        (record['booking_uuid_cache'] ??
                record['bookingUuidCache'] ??
                record['booking_uuid'] ??
                record['bookingUuid'] ??
                record['booking_local_uuid'] ??
                record['bookingLocalUuid'] ??
                '')
            .toString();
    final booking = rawBooking.trim().toLowerCase().replaceAll('-', '');
    if (booking.isEmpty) {
      return null;
    }
    return '$booking|$day';
  }

  /// هل [candidate] أحدث من [current] وفق الترتيب الحتمي المشترك؟
  static bool isNewer(
    Map<String, dynamic> candidate,
    Map<String, dynamic> current,
  ) {
    final comparisons = <int>[
      _intOf(candidate, 'updated_at', 'updatedAt').compareTo(
        _intOf(current, 'updated_at', 'updatedAt'),
      ),
      _intOf(candidate, 'version', 'version').compareTo(
        _intOf(current, 'version', 'version'),
      ),
      _intOf(candidate, 'last_modified', 'lastModified').compareTo(
        _intOf(current, 'last_modified', 'lastModified'),
      ),
    ];
    for (final result in comparisons) {
      if (result != 0) return result > 0;
    }
    // فاصل حتمي أخير: نفس الأرقام على جهازين ⇒ نفس الفائز بلا اعتماد
    // على ترتيب الصفحات.
    final candidateUuid =
        (candidate['local_uuid'] ?? candidate['localUuid'] ?? '').toString();
    final currentUuid =
        (current['local_uuid'] ?? current['localUuid'] ?? '').toString();
    return candidateUuid.compareTo(currentUuid) > 0;
  }

  static int _intOf(Map<String, dynamic> record, String snake, String camel) {
    final raw = record[snake] ?? record[camel];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
