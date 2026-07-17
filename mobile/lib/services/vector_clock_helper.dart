// lib/services/vector_clock_helper.dart
//
// ✅ مساعد زيادة Vector Clock للسجلات (2026-06-28)
//
// يوفر دالة عامة لزيادة VC لأي سجل بعد الكتابة المحلية.
// هذا يضمن أن التعديلات المحلية محمية من التعارضات المتزامنة
// حتى قبل أن تُعالج بواسطة outbox (sync push).
//
// الاستخدام:
// ```dart
// await bookingsRepo.update(id, status: 'مكتمل');
// await VectorClockHelper.bump(db, 'bookings', booking.localUuid);
// ```

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';
import 'vector_clock_service.dart';

/// مساعد زيادة Vector Clock للسجلات
class VectorClockHelper {
  VectorClockHelper._();

  /// خريطة أسماء الكيانات إلى أسماء الجداول في SQLite
  static const Map<String, String> entityToTable = {
    'rooms': 'rooms',
    'bookings': 'bookings',
    'expenses': 'expenses',
    'payments': 'payments',
    'salary_payments': 'salary_payments',
    'cash_transactions': 'cash_transactions',
    'shift_notes': 'shift_notes',
    'debts': 'debts',
    'employees': 'employees',
    'booking_notes': 'booking_notes',
    'booking_nights': 'booking_nights',
    'salary_cycles': 'salary_cycles',
    'booking_price_adjustments': 'booking_price_adjustments',
    'guest_infos': 'guest_infos',
    'salary_withdrawals': 'salary_withdrawals',
    'blacklist': 'blacklist',
    'price_adjustments': 'price_adjustments',
    'payment_voids': 'payment_voids',
  };

  /// يقرأ معرّف الجهاز من SharedPreferences
  static Future<String?> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('appwrite_delta_device_id');
    } catch (_) {
      return null;
    }
  }

  /// يزيد Vector Clock للسجل المحلي بعد الكتابة
  ///
  /// [entity] اسم الكيان (مثل 'bookings', 'payments')
  /// [localUuid] معرّف السجل الفريد
  ///
  /// يقرأ VC الحالي من DB، يزيد عداد الجهاز، يكتبه مرة أخرى.
  /// إذا فشل (مثلاً deviceId غير متوفر)، يُسجّل تحذيراً ولا يُعطل العملية.
  static Future<void> bump(AppDatabase db, String entity, String localUuid) async {
    final tableName = entityToTable[entity];
    if (tableName == null || localUuid.isEmpty) {
      return;
    }

    final deviceId = await _getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      // deviceId غير متوفر بعد — VC سيُزاد عند الـ push بواسطة _bumpVectorClockBeforePush
      return;
    }

    try {
      final rows = await db
          .customSelect(
            'SELECT vector_clock AS vc FROM $tableName WHERE local_uuid = ? LIMIT 1',
            variables: [Variable<String>(localUuid)],
          )
          .get();

      if (rows.isEmpty) return;

      final currentVcStr = (rows.first.data['vc'] as String?) ?? '{}';
      final vc = VectorClock.fromString(currentVcStr);
      vc.increment(deviceId);
      final newVcStr = vc.toString();

      await db.customStatement('UPDATE $tableName SET vector_clock = ? WHERE local_uuid = ?', [newVcStr, localUuid]);
    } catch (_) {
      // فشل زيادة VC ليس خطأ قاتلاً — الـ push سيزيده لاحقاً
    }
  }

  /// نسخة محمّلة (overload) تقبل عدة سجلات دفعة واحدة
  static Future<void> bumpMany(AppDatabase db, String entity, List<String> localUuids) async {
    for (final uuid in localUuids) {
      await bump(db, entity, uuid);
    }
  }
}
