// lib/utils/loading_snackbar.dart
//
// ✅ Helper موحّد لإشعارات "جاري..." التي تختفي فور انتهاء العملية.
//
// بدلاً من ضبط duration طويل (5 دقائق) وانتظار انتهائه، نتحكم بالـ SnackBar
// برمجياً: نُنشئه، نحفظ مثيله، ثم نُغلقه فور انتهاء العملية.
//
// الاستخدام:
// ```dart
// final loading = LoadingSnackBar.show(context, message: 'جاري المزامنة...');
// try {
//   await doWork();
//   loading.close();
//   LoadingSnackBar.showSuccess(context, 'تمت المزامنة بنجاح');
// } catch (e) {
//   loading.close();
//   LoadingSnackBar.showError(context, 'فشلت المزامنة: $e');
// }
// ```

import 'package:flutter/material.dart';

/// إشعار تحميل قابل للإغلاق برمجياً.
///
/// يُنشئ SnackBar مع CircularProgressIndicator يبقى ظاهراً حتى يُستدعى
/// [close] أو يُستبدل بإشعار آخر (نجاح/فشل).
class LoadingSnackBar {
  LoadingSnackBar._(this._messenger);

  final ScaffoldMessengerState _messenger;

  /// عرض إشعار "جاري..." مع spinner.
  ///
  /// [message] النص (مثلاً: 'جاري المزامنة...')
  /// [backgroundColor] لون الخلفية (افتراضي: أزرق)
  /// يُعيد كائن LoadingSnackBar — استدعِ .close() عند انتهاء العملية.
  static LoadingSnackBar show(
    BuildContext context, {
    String message = 'جاري التحميل...',
    Color backgroundColor = Colors.blue,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    // إغلاق أي snackbar سابق
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
        duration: const Duration(minutes: 10), // safety net — لن يصل لها
        dismissDirection: DismissDirection.none, // لا يمكن إغلاقه بالسحب
      ),
    );
    return LoadingSnackBar._(messenger);
  }

  /// إغلاق إشعار التحميل فوراً.
  void close() {
    _messenger.clearSnackBars();
  }

  /// إغلاق إشعار التحميل وعرض إشعار نجاح.
  void success(String message, {Duration duration = const Duration(seconds: 3)}) {
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
