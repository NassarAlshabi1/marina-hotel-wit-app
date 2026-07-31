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
// آلية الإرسال (تُختار تلقائياً حسب الإعداد المتوفر):
//   1. **HTTP v1** (موصى بها) — عبر `FCM_SERVICE_ACCOUNT_JSON` + `FCM_PROJECT_ID`
//      يبني OAuth2 access token محلياً (RS256 JWT) ثم يُرسل عبر
//      https://fcm.googleapis.com/v1/projects/{id}/messages:send
//   2. **Legacy Server Key** (مهمل) — عبر `FCM_SERVER_KEY`
//      يستخدم https://fcm.googleapis.com/fcm/send كحل احتياطي.
//
// ⚠️ أمني: مفاتيح حساب الخدمة حساسة جداً. ضعها في GitHub Secret، لا في الكود.
// البديل الأكثر أماناً للإنتاج: Appwrite Function + Firebase Admin SDK على الخادم.

import 'dart:async';
import 'dart:convert';


import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/env.dart';
import 'crashlytics_service.dart';
import 'fcm_jwt_helper.dart';

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
  ///
  /// تدعم طريقتين للإرسال:
  ///   1. **HTTP v1** (موصى بها) — عبر حساب خدمة Firebase + OAuth2.
  ///      تتطلب `FCM_SERVICE_ACCOUNT_JSON` + `FCM_PROJECT_ID`.
  ///   2. **Legacy Server Key** (مهمل) — عبر `FCM_SERVER_KEY`.
  ///      يستخدم كحل احتياطي إذا لم تُكوّن الطريقة الأولى.
  Future<void> _sendToAllDevices({
    required FcmEventType type,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    // ✅ no-op آمن إذا لم يُكوّن FCM بأي طريقة
    if (!Env.isFcmSendConfigured) {
      debugPrint(
        'ℹ️ FCM sender: skipped '
        '(neither FCM_SERVICE_ACCOUNT_JSON nor FCM_SERVER_KEY configured)',
      );
      return;
    }

    // اختيار طريقة الإرسال: v1 مفضّلة، Legacy كاحتياطي
    if (Env.isFcmV1Configured) {
      await _sendViaHttpV1(type: type, title: title, body: body, data: data);
    } else {
      await _sendViaLegacyKey(type: type, title: title, body: body, data: data);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  HTTP v1 API — عبر حساب خدمة Firebase + OAuth2 access token
  // ═══════════════════════════════════════════════════════════════

  Future<void> _sendViaHttpV1({
    required FcmEventType type,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    try {
      // 1. تهيئة FcmJwtHelper (مرة واحدة)
      //    نحاول base64 أولاً (الشكل الموصى به عبر encode_fcm_key.py).
      //    إذا فشل، نحاول JSON الخام (يتحمل المستخدم الذي لصق fcm-key.json مباشرة).
      if (!FcmJwtHelper.instance.isConfigured) {
        const raw = Env.fcmServiceAccountJson;
        FcmServiceAccountCredentials creds;
        try {
          creds = FcmServiceAccountCredentials.fromBase64(raw);
        } catch (_) {
          // ربما JSON خام — جرّب مباشرة
          creds = FcmServiceAccountCredentials.fromJsonString(raw);
        }
        FcmJwtHelper.instance.configure(creds);
      }

      // 2. الحصول على access token
      final accessToken = await FcmJwtHelper.instance.getAccessToken();
      if (accessToken == null) {
        debugPrint('⚠️ FCM v1: failed to obtain OAuth2 access token');
        // محاولة احتياطية عبر Legacy إذا كان متاحاً
        if (Env.isFcmLegacyConfigured) {
          debugPrint('ℹ️ FCM v1: falling back to Legacy Server Key');
          await _sendViaLegacyKey(type: type, title: title, body: body, data: data);
        }
        return;
      }

      // 3. قراءة توكنات الأجهزة من Appwrite
      final tokens = await _getAllDeviceTokens();
      if (tokens.isEmpty) {
        debugPrint('ℹ️ FCM v1: no registered devices to notify');
        return;
      }

      // 4. الحصول على senderDeviceId لتضمينه في الـ payload
      final senderDeviceId = await _getMyDeviceId();
      final eventTypeString = _eventTypeToString(type);

      // 5. الإرسال لكل توكن على حدة (v1 API لا يدعم multicast مباشرة)
      const endpoint =
          'https://fcm.googleapis.com/v1/projects/${Env.fcmProjectId}/messages:send';
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      int success = 0;
      int failure = 0;
      for (final token in tokens) {
        final payload = <String, dynamic>{
          'message': {
            'token': token,
            'notification': {
              'title': title,
              'body': body,
            },
            'data': {
              'type': 'marina_sync',
              'event': eventTypeString,
              'title': title,
              'body': body,
              if (senderDeviceId != null) 'senderDeviceId': senderDeviceId,
              ...data,
            },
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'marina_sync_channel',
                'icon': '@mipmap/ic_launcher',
              },
            },
          },
        };

        try {
          final response = await http
              .post(
                Uri.parse(endpoint),
                headers: headers,
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            success++;
          } else {
            failure++;
            debugPrint(
              '⚠️ FCM v1: send to token ${token.substring(0, 12)}... failed: '
              '${response.statusCode} ${response.body}',
            );
          }
        } catch (e) {
          failure++;
          debugPrint('⚠️ FCM v1: send to token failed: $e');
        }
      }

      debugPrint(
        '✅ FCM v1 sent: $success success, $failure failure '
        '(event=$eventTypeString, recipients=${tokens.length})',
      );
    } catch (e, st) {
      debugPrint('⚠️ FCM v1 sender error: $e\n$st');
      unawaited(
        CrashlyticsService.instance.recordSyncError(
          operation: 'fcm_v1_send',
          error: e.toString(),
          stackTrace: st,
          severity: CrashlyticsSeverity.warning,
          context: {'event': _eventTypeToString(type)},
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Legacy HTTP API — عبر Server Key (مهمل لكنه يعمل)
  // ═══════════════════════════════════════════════════════════════

  Future<void> _sendViaLegacyKey({
    required FcmEventType type,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    // ملاحظة: التحقع من التهيئة يتم في _sendToAllDevices قبل الاستدعاء.

    try {
      // 1. قراءة fcmToken لكل الأجهزة من Appwrite.devices
      final tokens = await _getAllDeviceTokens();
      if (tokens.isEmpty) {
        debugPrint('ℹ️ FCM Legacy: no registered devices to notify');
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
        debugPrint(
          '✅ FCM sent: $success success, $failure failure '
          '(event=$eventTypeString, recipients=${tokens.length})',
        );
      } else {
        debugPrint(
          '⚠️ FCM send failed: ${response.statusCode} - ${response.body}',
        );
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
      debugPrint('⚠️ FCM sender error: $e');
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

      // Use Cloudflare Worker API to get device tokens
      final response = await http.get(
        Uri.parse('${Env.cloudflareWorkerUrl}/api/devices/tokens?exclude=$myDeviceId'),
        headers: {
          'Authorization': 'Bearer ${Env.cloudflareAuthToken}',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tokens = (data['tokens'] as List? ?? [])
            .map((t) => t as String)
            .toList();
        return tokens;
      }

      debugPrint('⚠️ FCM sender: devices/tokens returned ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('⚠️ FCM sender: failed to fetch device tokens: $e');
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
