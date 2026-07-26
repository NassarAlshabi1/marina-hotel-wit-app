import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// مدير الإشعارات للمزامنة التلقائية
class SyncNotificationManager {
  SyncNotificationManager._() {
    _initLocalNotifications();
  }
  static SyncNotificationManager? _instance;
  // ignore: prefer_constructors_over_static_methods
  static SyncNotificationManager get instance =>
      _instance ??= SyncNotificationManager._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> _initLocalNotifications() async {
    if (_isInitialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // يمكن إضافة توجيه عند الضغط على الإشعار هنا
      },
    );
    _isInitialized = true;
  }

  /// إظهار إشعار النظام (يظهر حتى والتطبيق مغلق/في الخلفية)
  Future<void> showSystemNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await _initLocalNotifications();
    }

    const androidDetails = AndroidNotificationDetails(
      'marina_notes_channel',
      'الملاحظات والتنبيهات',
      channelDescription: 'تنبيهات عند وصول ملاحظات إدارية جديدة',
      importance: Importance.max,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    // نستخدم رقم عشوائي أو ثابت للـ ID
    final id = DateTime.now().millisecondsSinceEpoch % 100000;

    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  /// إشعار نجاح المزامنة
  static void showSyncSuccess(
    BuildContext context, {
    required String fromDevice,
    required int recordsCount,
    required DateTime syncTime,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.cloud_sync,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '✅ تمت المزامنة بنجاح',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تم تحديث $recordsCount سجل من $fromDevice',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => overlayEntry.remove(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // إزالة تلقائية بعد 5 ثوان
    Future<void>.delayed(const Duration(seconds: 5), () {
      try {
        overlayEntry.remove();
      } catch (_) {}
    });

    // اهتزاز خفيف للإشعار
    HapticFeedback.lightImpact();
  }

  /// إشعار فشل المزامنة
  static void showSyncError(
    BuildContext context, {
    required String error,
    VoidCallback? onRetry,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade400, Colors.red.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.sync_problem,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '❌ فشلت المزامنة',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            error,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => overlayEntry.remove(),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        overlayEntry.remove();
                        onRetry();
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('إعادة المحاولة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // إزالة تلقائية بعد 7 ثوان
    Future<void>.delayed(const Duration(seconds: 7), () {
      try {
        overlayEntry.remove();
      } catch (_) {}
    });

    // اهتزاز للتنبيه
    HapticFeedback.heavyImpact();
  }

  /// إشعار بدء المزامنة
  static void showSyncStarted(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 8),
            Text('🔄 بدأت المزامنة التلقائية...'),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// إشعار اكتشاف بيانات جديدة
  static void showNewDataDetected(
    BuildContext context, {
    required String sourceDevice,
    required int changesCount,
    VoidCallback? onViewDetails,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.blue.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.new_releases,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🆕 بيانات جديدة متاحة',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'تم العثور على $changesCount تغيير من $sourceDevice',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => overlayEntry.remove(),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          overlayEntry.remove();
                          // سيتم المزامنة تلقائياً
                        },
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('مزامنة تلقائية'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    if (onViewDetails != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          overlayEntry.remove();
                          onViewDetails();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                        ),
                        child: const Text('تفاصيل'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // إزالة تلقائية بعد 10 ثوان
    Future<void>.delayed(const Duration(seconds: 10), () {
      try {
        overlayEntry.remove();
      } catch (_) {}
    });

    // اهتزاز للإشعار
    HapticFeedback.selectionClick();
  }

  /// إشعار بوجود تضارب في البيانات تم حله تلقائياً
  /// يُستدعى عندما يتم تجاهل تغييرات السيرفر أو المحلية أثناء المزامنة
  static void showConflictWarning(
    BuildContext context, {
    required String table,
    required int discardedCount,
    required String winnerSide,
    String? details,
  }) {
    final sideText = winnerSide == 'local' ? 'الإصدار المحلي' : 'إصدار السيرفر';
    final tableNames = {
      'bookings': 'حجوزات',
      'payments': 'مدفوعات',
      'debts': 'ديون',
      'expenses': 'مصروفات',
      'rooms': 'غرف',
      'employees': 'موظفين',
      'guest_infos': 'معلومات ضيوف',
      'shift_notes': 'ملاحظات',
      'booking_notes': 'ملاحظات حجوزات',
      'salary_payments': 'دفعات رواتب',
      'salary_withdrawals': 'سحوبات رواتب',
      'cash_transactions': 'معاملات نقدية',
      'booking_price_adjustments': 'تسعير',
      'blacklist': 'القائمة السوداء',
    };
    final tableName = tableNames[table] ?? table;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تضارب في $tableName: تم تفضيل $sideText ($discardedCount سجل)',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: details != null
            ? SnackBarAction(
                label: 'تفاصيل',
                textColor: Colors.white,
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('تفاصيل التضارب'),
                      content: Text(details, textDirection: TextDirection.rtl),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('فهمت'),
                        ),
                      ],
                    ),
                  );
                },
              )
            : null,
      ),
    );

    HapticFeedback.mediumImpact();
  }
}
