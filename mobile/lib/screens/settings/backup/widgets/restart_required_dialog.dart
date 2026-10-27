import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Replacing the SQLite file closes the open database, while providers and
/// sync singletons still hold the old connection. Only a fresh app start
/// reloads them safely, so this dialog cannot be dismissed.
Future<void> showRestartRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('إعادة تشغيل التطبيق مطلوبة'),
        content: Text(
          Platform.isIOS
              ? 'تمت استعادة قاعدة البيانات. أغلق التطبيق من مبدّل التطبيقات '
                    'ثم افتحه من جديد لتحميل البيانات المستعادة.'
              : 'تمت استعادة قاعدة البيانات. سيُغلق التطبيق الآن؛ افتحه من '
                    'جديد لتحميل البيانات المستعادة.',
        ),
        actions: [
          if (!Platform.isIOS)
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('إغلاق التطبيق'),
            ),
        ],
      ),
    ),
  );
}
