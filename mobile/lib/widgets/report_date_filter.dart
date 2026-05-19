import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/widgets/neu_card.dart';
import '../utils/hotel_time_engine.dart';

/// نطاق تاريخ للتقرير
class DateRange {

  const DateRange({this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  bool get isValid => from != null && to != null;
}

/// تحكم برمجي بفلتر التاريخ — يسمح بقراءة وتعديل التواريخ من خارج الويدجت
class DateFilterController {
  _ReportDateFilterWidgetState? _state;

  /// قراءة التاريخ الحالي "من"
  DateTime? get fromDate => _state?._fromDate;

  /// قراءة التاريخ الحالي "إلى"
  DateTime? get toDate => _state?._toDate;

  /// قراءة النطاق الكامل
  DateRange get dateRange => DateRange(from: fromDate, to: toDate);

  void _attach(_ReportDateFilterWidgetState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// تطبيق فلتر سريع برمجياً
  void applyQuickFilter(String type) {
    _state?._applyQuickFilter(type);
  }

  /// تعيين تواريخ يدوياً مع مراعاة قواعد 14:00/13:59
  void setDates(DateTime? from, DateTime? to) {
    _state?._setDates(from, to);
  }

  /// النطاق الافتراضي لليوم الفندقي الحالي (14:00 → 13:59 من اليوم التالي)
  static DateRange getDefaultHotelDayRange() {
    final range = HotelTimeEngine.getHotelDayRange(DateTime.now());
    return DateRange(from: range['start'], to: range['end']);
  }

  /// حساب نطاق زمني لفلتر سريع محدد
  static DateRange computeQuickFilterRange(String type) {
    final now = DateTime.now();
    switch (type) {
      case 'hotelDay':
        final range = HotelTimeEngine.getHotelDayRange(now);
        return DateRange(from: range['start'], to: range['end']);
      case 'week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final hotelWeekStart = HotelTimeEngine.getHotelDay(weekStart);
        // ✅ إصلاح: نهاية النطاق يجب أن تكون 13:59 وليس 23:59
        // اليوم الفندقي ينتهي الساعة 13:59، وليس 23:59
        final hotelToday = HotelTimeEngine.getHotelDay(now);
        return DateRange(
          from: DateTime(hotelWeekStart.year, hotelWeekStart.month,
              hotelWeekStart.day, 14,),
          to: DateTime(hotelToday.year, hotelToday.month,
              hotelToday.day + 1, 13, 59, 59),
        );
      case 'month':
        final monthStart = DateTime(now.year, now.month);
        final hotelMonthStart = HotelTimeEngine.getHotelDay(monthStart);
        // ✅ إصلاح: نهاية النطاق يجب أن تكون 13:59 وليس 23:59
        final hotelTodayMonth = HotelTimeEngine.getHotelDay(now);
        return DateRange(
          from: DateTime(hotelMonthStart.year, hotelMonthStart.month,
              hotelMonthStart.day, 14,),
          to: DateTime(hotelTodayMonth.year, hotelTodayMonth.month,
              hotelTodayMonth.day + 1, 13, 59, 59),
        );
      case 'year':
        final yearStart = DateTime(now.year);
        final hotelYearStart = HotelTimeEngine.getHotelDay(yearStart);
        // ✅ إصلاح: نهاية النطاق يجب أن تكون 13:59 وليس 23:59
        final hotelTodayYear = HotelTimeEngine.getHotelDay(now);
        return DateRange(
          from: DateTime(hotelYearStart.year, hotelYearStart.month,
              hotelYearStart.day, 14,),
          to: DateTime(hotelTodayYear.year, hotelTodayYear.month,
              hotelTodayYear.day + 1, 13, 59, 59),
        );
      default:
        return getDefaultHotelDayRange();
    }
  }
}

/// ويدجت فلتر التاريخ المشترك لجميع شاشات التقارير
///
/// يوفر:
/// - شيبس الفلترة السريعة (اليوم الفندقي، الأسبوع، الشهر، السنة)
/// - أزرار اختيار التاريخ مع ضبط تلقائي 14:00 / 13:59
/// - منطق اليوم الفندقي عبر [HotelTimeEngine]
///
/// **الاستخدام الأساسي:**
/// ```dart
/// ReportDateFilterWidget(
///   controller: _filterController,
///   onDateRangeChanged: (range) {
///     _fromDate = range.from;
///     _toDate = range.to;
///     _fetchReport();
///   },
/// )
/// ```
class ReportDateFilterWidget extends StatefulWidget {

  const ReportDateFilterWidget({
    super.key,
    this.controller,
    required this.onDateRangeChanged,
    this.extraChips,
    this.dateButtonsBuilder,
    this.dateButtonsFirst = false,
  });
  /// تحكم برمجي (اختياري) — للقراءة والتعديل من خارج الويدجت
  final DateFilterController? controller;

  /// يُستدعى عند تغيير النطاق الزمني (مطلوب)
  final ValueChanged<DateRange> onDateRangeChanged;

  /// شيبس إضافية تُعرض بعد شيبس الفلترة السريعة (اختياري)
  final List<Widget>? extraChips;

  /// بناء مخصص لأزرار التاريخ (اختياري).
  ///
  /// عند توفيره، يُستدعى بدلاً من الأزرار الافتراضية (OutlinedButton).
  /// يُمرَّر `onPickFrom` و `onPickTo` لربطها بمُنتقي التاريخ الداخلي.
  final List<Widget> Function(
    BuildContext context,
    VoidCallback onPickFrom,
    VoidCallback onPickTo,
  )? dateButtonsBuilder;

  /// إذا كان true، تظهر أزرار التاريخ قبل شيبس الفلترة.
  /// الافتراضي false (الشيبس أولاً ثم أزرار التاريخ).
  final bool dateButtonsFirst;

  @override
  State<ReportDateFilterWidget> createState() =>
      _ReportDateFilterWidgetState();
}

class _ReportDateFilterWidgetState extends State<ReportDateFilterWidget> {
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    // تهيئة النطاق الافتراضي: اليوم الفندقي الحالي (14:00 → 13:59)
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from!;
    _toDate = range.to!;
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant ReportDateFilterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // منطق الفلترة
  // ═══════════════════════════════════════════════════════════════

  /// تطبيق فلتر سريع
  void _applyQuickFilter(String type) {
    final range = DateFilterController.computeQuickFilterRange(type);
    if (range.from != null && range.to != null) {
      setState(() {
        _fromDate = range.from!;
        _toDate = range.to!;
      });
      _notifyChanged();
    }
  }

  /// تعيين تواريخ يدوياً (من الخارج عبر Controller)
  void _setDates(DateTime? from, DateTime? to) {
    if (from == null || to == null) {
      return;
    }
    setState(() {
      _fromDate = from;
      _toDate = to;
    });
    _notifyChanged();
  }

  /// إرسال النطاق الجديد للشاشة الأب
  void _notifyChanged() {
    widget.onDateRangeChanged(DateRange(from: _fromDate, to: _toDate));
  }

  /// فتح منتقي التاريخ
  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          // ضبط الساعة 14:00 تلقائياً
          _fromDate = DateTime(picked.year, picked.month, picked.day, 14);
          if (_fromDate.isAfter(_toDate)) {
            _toDate = _fromDate
                .add(const Duration(days: 1))
                .subtract(const Duration(seconds: 1));
          }
        } else {
          // ضبط الساعة 13:59:59 تلقائياً
          _toDate =
              DateTime(picked.year, picked.month, picked.day, 13, 59, 59);
          if (_toDate.isBefore(_fromDate)) {
            _fromDate = _toDate.subtract(const Duration(days: 1));
            _fromDate = DateTime(
                _fromDate.year, _fromDate.month, _fromDate.day, 14,);
          }
        }
      });
      _notifyChanged();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // فحوصات حالة الشيبس — تحديد الشريحة النشطة
  // ═══════════════════════════════════════════════════════════════

  /// هل الفلتر الحالي مطابق لليوم الفندقي؟
  bool _isHotelDayActive() {
    final hotelDay = HotelTimeEngine.getHotelDay(DateTime.now());
    final expectedFrom =
        DateTime(hotelDay.year, hotelDay.month, hotelDay.day, 14);
    return _fromDate.year == expectedFrom.year &&
        _fromDate.month == expectedFrom.month &&
        _fromDate.day == expectedFrom.day;
  }

  /// هل الفلتر الحالي مطابق لبداية الأسبوع الحالي؟
  bool _isThisWeekActive() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final hotelWeekStart = HotelTimeEngine.getHotelDay(weekStart);
    return _fromDate.year == hotelWeekStart.year &&
        _fromDate.month == hotelWeekStart.month &&
        _fromDate.day == hotelWeekStart.day;
  }

  /// هل الفلتر الحالي مطابق لبداية الشهر الحالي؟
  bool _isThisMonthActive() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final hotelMonthStart = HotelTimeEngine.getHotelDay(monthStart);
    return _fromDate.year == hotelMonthStart.year &&
        _fromDate.month == hotelMonthStart.month &&
        _fromDate.day == hotelMonthStart.day;
  }

  /// هل الفلتر الحالي مطابق لبداية السنة الحالية؟
  bool _isThisYearActive() {
    final now = DateTime.now();
    final yearStart = DateTime(now.year);
    final hotelYearStart = HotelTimeEngine.getHotelDay(yearStart);
    return _fromDate.year == hotelYearStart.year &&
        _fromDate.month == hotelYearStart.month &&
        _fromDate.day == hotelYearStart.day;
  }

  // ═══════════════════════════════════════════════════════════════
  // بناء الواجهة
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // بناء صف شيبس الفلترة السريعة
    final chipsRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          NeuQuickFilterChip(
            label: 'اليوم الفندقي',
            selected: _isHotelDayActive(),
            onTap: () => _applyQuickFilter('hotelDay'),
          ),
          const SizedBox(width: 6),
          NeuQuickFilterChip(
            label: 'الأسبوع',
            selected: _isThisWeekActive(),
            onTap: () => _applyQuickFilter('week'),
          ),
          const SizedBox(width: 6),
          NeuQuickFilterChip(
            label: 'الشهر',
            selected: _isThisMonthActive(),
            onTap: () => _applyQuickFilter('month'),
          ),
          const SizedBox(width: 6),
          NeuQuickFilterChip(
            label: 'السنة',
            selected: _isThisYearActive(),
            onTap: () => _applyQuickFilter('year'),
          ),
          // شيبس إضافية من الشاشة الأب
          if (widget.extraChips != null) ...[
            const SizedBox(width: 6),
            ...widget.extraChips!,
          ],
        ],
      ),
    );

    // بناء أزرار التاريخ
    Widget dateButtons;
    if (widget.dateButtonsBuilder != null) {
      dateButtons = Row(
        children: widget.dateButtonsBuilder!(
          context,
          () => _pickDate(isFrom: true),
          () => _pickDate(isFrom: false),
        ),
      );
    } else {
      dateButtons = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildDefaultDateSelector(
            label: 'من (14:00)',
            value: _fromDate,
            onPressed: () => _pickDate(isFrom: true),
          ),
          _buildDefaultDateSelector(
            label: 'إلى (13:59)',
            value: _toDate,
            onPressed: () => _pickDate(isFrom: false),
          ),
        ],
      );
    }

    // ترتيب العناصر حسب التفضيل
    final selectedRangeLabel =
        'النطاق: ${DateFormat('yyyy-MM-dd').format(_fromDate)} 14:00'
        ' - ${DateFormat('yyyy-MM-dd').format(_toDate)} 13:59';

    final children = widget.dateButtonsFirst
        ? [
            dateButtons,
            const SizedBox(height: 8),
            chipsRow,
            const SizedBox(height: 6),
            Text(
              selectedRangeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ]
        : [
            chipsRow,
            const SizedBox(height: 8),
            dateButtons,
            const SizedBox(height: 6),
            Text(
              selectedRangeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// بناء زر تاريخ افتراضي (OutlinedButton)
  Widget _buildDefaultDateSelector({
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
  }) {
    final text =
        value != null ? DateFormat('yyyy-MM-dd').format(value) : '—';
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text('$label: $text'),
    );
  }
}
