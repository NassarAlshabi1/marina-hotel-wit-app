import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

/// Hotel business timezone, independent of the device's configured timezone.
class HotelTimezone {
  HotelTimezone._();

  static const String locationId = 'Asia/Aden';
  static final timezone.Location _location = _loadLocation();

  static timezone.Location _loadLocation() {
    timezone_data.initializeTimeZones();
    return timezone.getLocation(locationId);
  }

  /// Current wall-clock time in the hotel's IANA timezone.
  static DateTime now() => timezone.TZDateTime.now(_location);

  /// Converts an absolute UTC instant to the hotel's wall-clock time.
  static DateTime fromInstant(DateTime instant) =>
      timezone.TZDateTime.from(instant.toUtc(), _location);

  /// Constructs a wall-clock value in Asia/Aden without consulting device time.
  static DateTime atHotelTime(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
    int microsecond = 0,
  ]) => timezone.TZDateTime(
    _location,
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
    microsecond,
  );

  /// Converts a DateTime to the hotel timezone.
  ///
  /// UTC DateTimes represent absolute instants and are converted by instant.
  /// Non-UTC DateTimes are treated as wall-clock values already expressed in
  /// the hotel's timezone. This preserves the meaning of legacy timestamps
  /// that were stored without an explicit UTC offset.
  static DateTime toHotelDateTime(DateTime value) {
    if (value.isUtc) return fromInstant(value);
    return timezone.TZDateTime(
      _location,
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  /// Serializes an instant as the hotel's local wall-clock ISO value for the
  /// existing `paymentDate` field. The zone-less format is intentional for
  /// compatibility with existing readers and rows. Hotel-day logic treats
  /// zone-less payment dates as Asia/Aden wall time; visible date/time fields
  /// remain the same for existing screens.
  static String paymentTimestampFromInstant(DateTime instant) {
    final hotelTime = fromInstant(instant);
    final date =
        '${hotelTime.year.toString().padLeft(4, '0')}-'
        '${hotelTime.month.toString().padLeft(2, '0')}-'
        '${hotelTime.day.toString().padLeft(2, '0')}';
    final time =
        '${hotelTime.hour.toString().padLeft(2, '0')}:'
        '${hotelTime.minute.toString().padLeft(2, '0')}:'
        '${hotelTime.second.toString().padLeft(2, '0')}.'
        '${hotelTime.millisecond.toString().padLeft(3, '0')}';
    final microseconds = hotelTime.microsecond;
    final fraction = microseconds == 0
        ? time
        : '$time${microseconds.toString().padLeft(3, '0')}';
    return '${date}T$fraction';
  }

  /// Generates a hotel-local payment timestamp for the current instant,
  /// independent of the device's local timezone setting.
  static String nowPaymentTimestamp() =>
      paymentTimestampFromInstant(DateTime.now());
}
