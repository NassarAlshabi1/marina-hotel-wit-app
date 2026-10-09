import 'package:flutter/foundation.dart';

/// Drop-in replacement for debugPrint that avoids string interpolation in release mode.
///
/// Instead of: debugPrint('Result: $value')  ← string is allocated even in release
/// Use:        dlog(() => 'Result: $value')  ← thunk is never called in release
///
/// For simple strings without interpolation, just use: dlog('simple message')
///
/// The function accepts either a String or a thunk (() => String).
/// In release mode, both are no-ops (the thunk is never executed).
void dlog(Object messageOrThunk) {
  if (kDebugMode) {
    if (messageOrThunk is String) {
      debugPrint(messageOrThunk);
    } else if (messageOrThunk is String Function()) {
      debugPrint(messageOrThunk());
    }
  }
}

/// Log a warning — same as dlog but with ⚠️ prefix
void dwarn(Object messageOrThunk) {
  if (kDebugMode) {
    if (messageOrThunk is String) {
      debugPrint('⚠️ $messageOrThunk');
    } else if (messageOrThunk is String Function()) {
      debugPrint('⚠️ ${messageOrThunk()}');
    }
  }
}

/// Log an error — same as dlog but with ❌ prefix
void derr(Object messageOrThunk) {
  if (kDebugMode) {
    if (messageOrThunk is String) {
      debugPrint('❌ $messageOrThunk');
    } else if (messageOrThunk is String Function()) {
      debugPrint('❌ ${messageOrThunk()}');
    }
  }
}
