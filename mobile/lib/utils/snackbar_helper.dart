import 'package:flutter/material.dart';

class SnackBarHelper {
  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : backgroundColor,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'إغلاق',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message, backgroundColor: Colors.green);
  }

  static void showError(BuildContext context, String message) {
    show(context, message, isError: true);
  }

  static void showWarning(BuildContext context, String message) {
    show(context, message, backgroundColor: Colors.orange);
  }
}
