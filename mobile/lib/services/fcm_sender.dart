// lib/services/fcm_sender.dart
//
// ✅ خدمة إرسال FCM مباشرة من التطبيق (للأحداث المهمة فقط).
//
// الاستخدام:
// ```dart
// await FcmSender.notifyBookingCreated(
//   roomNumber: '101',
//   guestName: 'أحمد',
// );
// ```
//
// الأحداث المدعومة:
// - booking_created: حجز جديد
// - booking_checked_out: خروج نزيل
// - payment_added: دفعة جديدة
// - expense_added: مصروف جديد
// - backup_completed: نسخة احتياطية مكتملة
//
// ⚠️ أمني: يستخدم Legacy Server Key (مُهمَل لكنه يعمل).
// للإنتاج، استبدل بـ Appwrite Function + Firebase Admin SDK.

import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart' show Query;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/env.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'crashlytics_service.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// نوع الحدث المهم لإرسال إشعار FCM
enum FcmEventType {
  bookingCreated,
  bookingCheckedOut,
  paymentAdded,
  expenseAdded,
  backupCompleted,
}

/// خدمة إرسال FCM مباشرة من التطبيق للأجهزة الأخرى.
///
/// تعمل كالتالي:
/// 1. تقرأ `fcmToken` لكل الأجهزة المسجّلة من Appwrite.devices collection
/// 2. تستثني جهاز المُرسِل (حتى لا يُرسل لنفسه)
/// 3. تُرسل FCM عبر HTTP v1 API باستخدام Server Key
/// 4. تُشغّل المزامنة على الأجهزة المستلمة (silent push)
class FcmSender {
  factory FcmSender() => _instance;
  FcmSender._internal();
  static final FcmSender _instance = FcmSender._internal();

  static const _fcmEndpoint = 'https://fcm.googleapis.com/fcm/send';

  /// إرسال إشعار حجز جديد
  Future<void> notifyBookingCreated({
    required String roomNumber,
    required String guestName,
  }) async {
    await _sendToAllDevices(
      type: FcmEventType.bookingCreated,
      title: 'حجز جديد',
      body: 'غرفة $roomNumber - $guestName',
      data: {'room_number': roomNumber, 'guest_name': guestName},
    );
  }

  /// إرسال إشعار خروج نزيل
  Future<void> notifyBookingCheckedOut({
    required String roomNumber,
    required String guestName,
  }) async {
    await _sendToAllDevices(
      type: FcmEventType.bookingCheckedOut,
      title: 'خروج نزيل',
      body: 'غرفة $roomNumber - $guestName',
      data: {'room_number': roomNumber, 'guest_name': guestName},
    );
  }

  /// إرسال إشعار دفعة جديدة
  Future<void> notifyPaymentAdded({
    required double amount,
    required String roomNumber,
  }) async {
    await _sendToAllDevices(
      type: FcmEventType.paymentAdded,
      title: 'دفعة جديدة',
      body: '${amount.toStringAsFixed(0)} - غرفة $roomNumber',
      data: {'amount': amount.toString(), 'room_number': roomNumber},
    );
  }

  /// إرسال إشعار مصروف جديد
  Future<void> notifyExpenseAdded({
    required double amount,
    required String expenseType,
  }) async {
    await _sendToAllDevices(
      type: FcmEventType.expenseAdded,
      title: 'مصروف جديد',
      body: '$expenseType - ${amount.toStringAsFixed(0)}',
      data: {'amount': amount.toString(), 'expense_type': expenseType},
    );
  }

  /// إرسال إشعار اكتمال نسخة احتياطية
  Future<void> notifyBackupCompleted({required String backupName}) async {
    await _sendToAllDevices(
      type: FcmEventType.backupCompleted,
      title: 'نسخة احتياطية',
      body: 'تم إنشاء: $backupName',
      data: {'backup_name': backupName},
    );
  }

  /// الإرسال الفعلي لجميع الأجهزة المسجّلة (عدا جهاز المُرسِل).
  ///
  /// هذه الدالة تبطئ الإرسال إذا لم يُكوّن FCM (no-op آمن).
  Future<void> _sendToAllDevices({
    required FcmEventType type,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    // ✅ no-op آمن إذا لم يُكوّن FCM
    if (!Env.isFcmSendConfigured) {
      dlog('ℹ️ FCM sender: skipped (FCM_SERVER_KEY not configured)');
      return;
    }

    try {
      // 1. قراءة fcmToken لكل الأجهزة من Appwrite.devices
      final tokens = await _getAllDeviceTokens();
      if (tokens.isEmpty) {
        dlog('ℹ️ FCM sender: no registered devices to notify');
        return;
      }

      // 2. بناء payload
      final eventTypeString = _eventTypeToString(type);
      final payload = <String, dynamic>{
        'registration_ids': tokens,
        'notification': {
          'title': title,
          'body': body,
          'sound': 'default',
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
        'data': {
          'type': 'marina_sync',
          'event': eventTypeString,
          'title': title,
          'body': body,
          ...data,
        },
        'priority': 'high',
        'content_available': true,
      };

      // 3. إرسال عبر FCM HTTP API
      final response = await http
          .post(
            Uri.parse(_fcmEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'key=${Env.fcmServerKey}',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
        final success = responseBody['success'] as int? ?? 0;
        final failure = responseBody['failure'] as int? ?? 0;
        dlog(() => '✅ FCM sent: $success success, $failure failure '
          '(event=$eventTypeString, recipients=${tokens.length})');
      } else {
        dlog(() => '⚠️ FCM send failed: ${response.statusCode} - ${response.body}');
        unawaited(
          CrashlyticsService.instance.recordSyncError(
            operation: 'fcm_send',
            error: 'HTTP ${response.statusCode}: ${response.body}',
            severity: CrashlyticsSeverity.warning,
            context: {'event': eventTypeString, 'recipients': tokens.length},
          ),
        );
      }
    } catch (e, st) {
      dlog(() => '⚠️ FCM sender error: $e');
      unawaited(
        CrashlyticsService.instance.recordSyncError(
          operation: 'fcm_send',
          error: e.toString(),
          stackTrace: st,
          severity: CrashlyticsSeverity.warning,
          context: {'event': _eventTypeToString(type)},
        ),
      );
    }
  }

  /// قراءة جميع fcmToken من Appwrite.devices collection
  /// (يستثني جهاز المُرسِل تلقائياً عبر senderDeviceId field)
  ///
  /// ✅ إصلاح PR review: نستخدم AppwriteService.listAllDocuments() بدلاً من
  /// Databases.listDocuments() مباشرة. هذا يوفّر:
  /// 1. Automatic failover إلى secondary Appwrite instance عند فشل primary
  /// 2. Cursor pagination صحيح (يجلب كل الصفحات، ليس فقط أول 25)
  /// 3. Caching مدمج لتقليل الـ round-trips
  Future<List<String>> _getAllDeviceTokens() async {
    try {
      final myDeviceId = await _getMyDeviceId();

      final documents = await AppwriteService().listAllDocuments(
        collectionId: AppwriteConfig.devicesCollectionId,
        queries: [
          // فقط الأجهزة النشطة
          Query.equal('status', 'active'),
        ],
      );

      final tokens = <String>[];
      for (final doc in documents) {
        final token = doc.data['fcmToken'] as String?;
        final deviceId = doc.data['localUuid'] as String? ?? doc.$id;

        // استثني جهاز المُرسِل
        if (myDeviceId != null && deviceId == myDeviceId) continue;

        if (token != null && token.isNotEmpty) {
          tokens.add(token);
        }
      }

      return tokens;
    } catch (e) {
      dlog(() => '⚠️ FCM sender: failed to fetch device tokens: $e');
      return [];
    }
  }

  /// الحصول على معرّف الجهاز الحالي (للاستبعاد من الإرسال)
  Future<String?> _getMyDeviceId() async {
    try {
      // استخدام SharedPreferences عبر AppwriteSyncManager
      // تجنّباً لـ import cycle
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('appwrite_device_id') ??
          prefs.getString('appwrite_realtime_device_id');
    } catch (_) {
      return null;
    }
  }

  String _eventTypeToString(FcmEventType type) {
    switch (type) {
      case FcmEventType.bookingCreated:
        return 'booking_created';
      case FcmEventType.bookingCheckedOut:
        return 'booking_checked_out';
      case FcmEventType.paymentAdded:
        return 'payment_added';
      case FcmEventType.expenseAdded:
        return 'expense_added';
      case FcmEventType.backupCompleted:
        return 'backup_completed';
    }
  }
}
