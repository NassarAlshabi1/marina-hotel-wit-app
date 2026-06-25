import 'package:flutter/material.dart';

/// مُساعد مركزي لعرض SnackBars موحدة عبر التطبيق.
///
/// ✅ جميع الـ SnackBars:
/// - تختفي تلقائياً بعد 4 ثواني بدون أي تدخل من المستخدم
/// - تستخدم `SnackBarBehavior.floating` لمظهر عصري لا يغطي محتوى الشاشة
/// - لا تحتوي على زر "إغلاق" (الاختفاء تلقائي)
class SnackBarHelper {
  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    bool isError = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message, backgroundColor: Colors.green);
  }

  static void showError(BuildContext context, String message) {
    show(context, message, isError: true, duration: const Duration(seconds: 5));
  }

  static void showWarning(BuildContext context, String message) {
    show(context, message, backgroundColor: Colors.orange);
  }
}
