import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class DebugLogs {
  static const _maxEntries = 300;
  static final List<String> _entries = [];
  static final ValueNotifier<List<String>> notifier =
      ValueNotifier<List<String>>(const []);

  static void add(String source, String message) {
    final entry = '[${DateTime.now().toIso8601String()}][$source] $message';
    dlog(entry);
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifier.value = List.unmodifiable(_entries);
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static void clear() {
    _entries.clear();
    notifier.value = const [];
  }
}
