/// Helpers for SQL date-range predicates over ISO-8601 text columns.
///
/// ISO date/time values preserve chronological order lexicographically. Using
/// a half-open range (`>= start AND < nextDay`) is more predictable for SQLite
/// indexes than a prefix `LIKE 'yyyy-MM-dd%'` predicate.
class SqlDateRange {
  SqlDateRange._();

  /// Returns a half-open range for a calendar or hotel-day key in `yyyy-MM-dd`
  /// form. Returns null rather than throwing for non-date input supplied by a
  /// legacy caller.
  static ({String start, String endExclusive})? forDay(String dayKey) {
    final date = DateTime.tryParse(dayKey);
    if (date == null) return null;

    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (start: _formatDate(start), endExclusive: _formatDate(end));
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
