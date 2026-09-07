import 'package:flutter/material.dart';

/// عرض رسائل قصيرة للمستخدم بطريقة موحّدة وآمنة.
///
/// المساعد يلغي الرسالة السابقة قبل عرض الجديدة حتى لا تتراكم رسائل الحفظ
/// والمزامنة فوق بعضها، ويتجاهل الاستدعاء إذا لم يعد السياق مرتبطاً بالشجرة.
class SnackBarHelper {
  const SnackBarHelper._();

  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: action,
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message, backgroundColor: Colors.green);
  }

  static void showError(BuildContext context, String message) {
    show(context, message, isError: true, duration: const Duration(seconds: 4));
  }

  static void showWarning(BuildContext context, String message) {
    show(context, message, backgroundColor: Colors.orange.shade800);
  }

  /// إخفاء الرسالة الحالية دون إظهار رسالة جديدة.
  static void hide(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }
}
