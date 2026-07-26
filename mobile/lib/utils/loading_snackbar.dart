// lib/utils/loading_snackbar.dart
//
// ✅ Helper موحّد لإشعارات "جاري..." التي تختفي فور انتهاء العملية.

import 'package:flutter/material.dart';

/// إشعار تحميل قابل للإغلاق برمجياً.
class LoadingSnackBar {
  LoadingSnackBar._(this._messenger);

  final ScaffoldMessengerState _messenger;

  /// عرض إشعار "جاري..." مع spinner.
  // ignore: prefer_constructors_over_static_methods
  static LoadingSnackBar show(
    BuildContext context, {
    String message = 'جاري التحميل...',
    Color backgroundColor = Colors.blue,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(minutes: 10),
        dismissDirection: DismissDirection.none,
      ),
    );
    return LoadingSnackBar._(messenger);
  }

  /// إغلاق إشعار التحميل فوراً.
  void close() {
    _messenger.clearSnackBars();
  }

  /// إغلاق إشعار التحميل وعرض إشعار نجاح.
  void success(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _messenger.clearSnackBars();
    _messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: duration,
      ),
    );
  }

  /// إغلاق إشعار التحميل وعرض إشعار خطأ.
  void error(String message, {Duration duration = const Duration(seconds: 4)}) {
    _messenger.clearSnackBars();
    _messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: duration,
      ),
    );
  }

  /// اختصار ثابت لعرض نجاح بدون كائن LoadingSnackBar.
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: duration,
      ),
    );
  }

  /// اختصار ثابت لعرض خطأ بدون كائن LoadingSnackBar.
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: duration,
      ),
    );
  }
}
