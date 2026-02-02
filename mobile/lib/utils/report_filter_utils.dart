import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ReportFilterDebouncer {
  ReportFilterDebouncer({this.duration = const Duration(milliseconds: 400)});

  final Duration duration;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

class DateRangeFilter {
  DateRangeFilter({DateTime? start, DateTime? end})
      : start = start ?? DateTime.now().subtract(const Duration(days: 30)),
        end = end ?? DateTime.now();

  final DateTime start;
  final DateTime end;

  DateRangeFilter copyWith({DateTime? start, DateTime? end}) {
    return DateRangeFilter(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  bool isInRange(DateTime date) {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    return !date.isBefore(startOfDay) && !date.isAfter(endOfDay);
  }

  String toSqlCondition(String column) {
    final startStr = start.toIso8601String().split('T')[0];
    final endStr = end.toIso8601String().split('T')[0];
    return "$column >= '$startStr' AND $column <= '$endStr 23:59:59'";
  }
}

class ReportFilterState<T> {
  ReportFilterState({
    this.dateRange,
    this.searchQuery = '',
    this.selectedType,
    this.data = const [],
    this.isLoading = false,
    this.error,
    this.totalAmount = 0,
    this.filteredCount = 0,
  });

  final DateRangeFilter? dateRange;
  final String searchQuery;
  final T? selectedType;
  final List<dynamic> data;
  final bool isLoading;
  final String? error;
  final double totalAmount;
  final int filteredCount;

  ReportFilterState<T> copyWith({
    DateRangeFilter? dateRange,
    String? searchQuery,
    T? selectedType,
    List<dynamic>? data,
    bool? isLoading,
    String? error,
    double? totalAmount,
    int? filteredCount,
  }) {
    return ReportFilterState<T>(
      dateRange: dateRange ?? this.dateRange,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedType: selectedType ?? this.selectedType,
      data: data ?? this.data,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      totalAmount: totalAmount ?? this.totalAmount,
      filteredCount: filteredCount ?? this.filteredCount,
    );
  }
}

class FilterCache<K, V> {
  FilterCache({this.maxSize = 10});

  final int maxSize;
  final Map<K, _CacheEntry<V>> _cache = {};

  V? get(K key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp).inMinutes > 5) {
      _cache.remove(key);
      return null;
    }
    return entry.value;
  }

  void set(K key, V value) {
    if (_cache.length >= maxSize) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b,
      );
      _cache.remove(oldest.key);
    }
    _cache[key] = _CacheEntry(value: value, timestamp: DateTime.now());
  }

  void clear() {
    _cache.clear();
  }
}

class _CacheEntry<V> {
  _CacheEntry({required this.value, required this.timestamp});

  final V value;
  final DateTime timestamp;
}

Future<R> computeFilter<T, R>(T data, R Function(T) filter) async {
  return compute(filter, data);
}

class OptimizedReportFilterMixin {
  final ReportFilterDebouncer _debouncer = ReportFilterDebouncer();
  final FilterCache<String, dynamic> _cache = FilterCache();

  void debounceFilter(VoidCallback action) {
    _debouncer.run(action);
  }

  T? getCachedResult<T>(String key) {
    return _cache.get(key) as T?;
  }

  void cacheResult<T>(String key, T value) {
    _cache.set(key, value);
  }

  String buildCacheKey(DateRangeFilter? dateRange, String? type, String? query) {
    final start = dateRange?.start.toIso8601String() ?? '';
    final end = dateRange?.end.toIso8601String() ?? '';
    return '$start|$end|${type ?? ''}|${query ?? ''}';
  }

  void disposeFilterMixin() {
    _debouncer.dispose();
    _cache.clear();
  }
}

class DateRangePickerButton extends StatelessWidget {
  const DateRangePickerButton({
    super.key,
    required this.dateRange,
    required this.onChanged,
    this.label = 'الفترة',
  });

  final DateRangeFilter dateRange;
  final ValueChanged<DateRangeFilter> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: DateTimeRange(
            start: dateRange.start,
            end: dateRange.end,
          ),
          locale: const Locale('ar'),
        );
        if (picked != null) {
          onChanged(DateRangeFilter(start: picked.start, end: picked.end));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.date_range, size: 18),
            const SizedBox(width: 8),
            Text(
              '${_formatDate(dateRange.start)} - ${_formatDate(dateRange.end)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

class SearchFilterField extends StatelessWidget {
  const SearchFilterField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'بحث...',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}

class TypeFilterDropdown<T> extends StatelessWidget {
  const TypeFilterDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.itemLabel,
    this.hint = 'الكل',
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T) itemLabel;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<T?>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        hint: Text(hint, style: const TextStyle(fontSize: 12)),
        items: [
          DropdownMenuItem<T?>(
            value: null,
            child: Text(hint, style: const TextStyle(fontSize: 12)),
          ),
          ...items.map(
            (item) => DropdownMenuItem<T?>(
              value: item,
              child: Text(itemLabel(item), style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class FilteredListView<T> extends StatelessWidget {
  const FilteredListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.isLoading,
    this.emptyMessage = 'لا توجد بيانات',
    this.separatorBuilder,
  });

  final List<T> items;
  final Widget Function(BuildContext, T, int) itemBuilder;
  final bool isLoading;
  final String emptyMessage;
  final Widget Function(BuildContext, int)? separatorBuilder;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: separatorBuilder ?? (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => itemBuilder(context, items[index], index),
    );
  }
}

class ReportSummaryCard extends StatelessWidget {
  const ReportSummaryCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.color,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).primaryColor;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (icon != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: effectiveColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: effectiveColor, size: 20),
              ),
            if (icon != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: effectiveColor,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
