// ============================================================================
//  AppwriteModels — Unit Tests
// ============================================================================
//  اختبارات نماذج Appwrite (lib/services/appwrite_models.dart):
//    - التحليل الدفاعي fromJson: قيم ناقصة/نل → قيم افتراضية آمنة
//    - تحويلات الزمن: epoch-seconds (int/double) و ISO strings
//    - toJson: تحويل التواريخ لثوانٍ epoch، وإسقاط الحقول الاختيارية
//    - رحلة ذهاب وعودة لكل نموذج + حقول حسابية (AppwriteSyncLog.duration)
//
//  كل الاختبارات حتمية — بلا شبكة ولا قاعدة بيانات ولا زمن حقيقي.
// ============================================================================

library marina_hotel_mobile.test.appwrite_models_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_models.dart';

void main() {
  group('AppwriteDevice', () {
    test('fromJson يقرأ epoch-seconds كـ int ويحوله لتاريخ محلي', () {
      // 1758700000 ثانية = 2026-09-24 (تقريباً) — حتمية كمدخل/مخرج نسبةً
      final device = AppwriteDevice.fromJson({
        r'$id': 'dev-1',
        'deviceName': 'جهاز الاستقبال',
        'deviceModel': 'Pixel 8',
        'osVersion': 'Android 15',
        'lastSeen': 1758700000,
        'createdAt': 1758700000,
        'updatedAt': 1758700000.0, // double epoch
        'status': 'active',
        'version': 3,
        'origin': 'cloud',
        'localUuid': 'device-uuid-1',
      });

      expect(device.id, 'dev-1');
      expect(device.deviceName, 'جهاز الاستقبال');
      expect(device.version, 3);
      expect(device.lastActive, isNull);
      expect(
        device.lastSeen.millisecondsSinceEpoch,
        1758700000 * 1000,
      );
      expect(
        device.updatedAt.millisecondsSinceEpoch,
        1758700000 * 1000,
      );
    });

    test('fromJson: حقول ناقصة تماماً → قيم افتراضية آمنة بلا استثناء', () {
      final device = AppwriteDevice.fromJson(const {});

      expect(device.id, '');
      expect(device.deviceName, '');
      expect(device.status, 'active');
      expect(device.version, 1);
      expect(device.origin, isNull);
      expect(device.localUuid, isNull);
    });

    test('version نصية رقمية تُقبل (int.tryParse)', () {
      final device = AppwriteDevice.fromJson(const {'version': '7'});

      expect(device.version, 7);
    });

    test('lastActive عبر مفتاح موجود → يُحلل، وبدون مفتاح → null', () {
      final withActive = AppwriteDevice.fromJson({
        'lastActive': '2026-09-24T10:00:00.000Z',
      });
      final withoutKey = AppwriteDevice.fromJson(const {});

      expect(withActive.lastActive, isNotNull);
      expect(withoutKey.lastActive, isNull);
    });

    test('toJson يحول التواريخ لثوانٍ epoch ويسقط الاختياري النل', () {
      final device = AppwriteDevice(
        id: 'dev-2',
        deviceName: 'n',
        deviceModel: 'm',
        osVersion: 'o',
        lastSeen: DateTime.utc(2026, 1, 2, 3, 4, 5),
        status: 'inactive',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        version: 2,
      );
      final json = device.toJson();

      expect(json['lastSeen'], device.lastSeen.toIso8601String());
      expect(
        json['createdAt'],
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
      );
      expect(json.containsKey('lastActive'), isFalse);
      expect(json.containsKey('origin'), isFalse);
      expect(json.containsKey('localUuid'), isFalse);
      expect(json['status'], 'inactive');
    });
  });

  group('AppwriteSyncLog', () {
    test('حقول كاملة + duration محسوب', () {
      final log = AppwriteSyncLog.fromJson({
        r'$id': 'log-1',
        'deviceId': 'dev-1',
        'syncType': 'push',
        'startTime': '2026-09-24T10:00:00.000Z',
        'endTime': '2026-09-24T10:00:30.000Z',
        'status': 'completed',
        'recordsPushed': 12,
        'recordsPulled': 3.0, // num → int
        'conflicts': 1,
        'errorMessage': null,
        'details': {'batch': 2},
      });

      expect(log.id, 'log-1');
      expect(log.syncType, 'push');
      expect(log.recordsPushed, 12);
      expect(log.recordsPulled, 3);
      expect(log.conflicts, 1);
      expect(log.duration, const Duration(seconds: 30));
      expect(log.details, {'batch': 2});
    });

    test('افتراضيات آمنة: syncType=full وstatus=in_progress وعدادات صفر', () {
      final log = AppwriteSyncLog.fromJson({
        'startTime': DateTime.utc(2026, 9, 24, 8).toIso8601String(),
      });

      expect(log.syncType, 'full');
      expect(log.status, 'in_progress');
      expect(log.recordsPushed, 0);
      expect(log.recordsPulled, 0);
      expect(log.conflicts, 0);
      expect(log.endTime, isNull);
      expect(log.duration, isNull);
    });

    test('toJson يسقط endTime/errorMessage/details عند النل', () {
      final log = AppwriteSyncLog(
        id: 'log-2',
        deviceId: 'dev-1',
        syncType: 'pull',
        startTime: DateTime.utc(2026, 9, 24, 8),
        status: 'in_progress',
      );
      final json = log.toJson();

      expect(json.containsKey('endTime'), isFalse);
      expect(json.containsKey('errorMessage'), isFalse);
      expect(json.containsKey('details'), isFalse);
      expect(json['startTime'], '2026-09-24T08:00:00.000Z');
    });
  });

  group('AppwriteRoom', () {
    test('رحلة كاملة: fromJson → toJson يحافظ على القيم', () {
      final room = AppwriteRoom.fromJson({
        r'$id': 'room-1',
        'roomNumber': '101',
        'type': 'سويت',
        'status': 'شاغرة',
        'price': 25000,
        'floor': 1,
        'lastModified': '2026-09-24T09:00:00.000Z',
        'lastModifiedBy': 'manager-1',
      });
      final json = room.toJson();

      expect(room.price, 25000.0);
      expect(room.floor, 1);
      expect(room.lastModifiedBy, 'manager-1');
      expect(json['price'], 25000.0);
      expect(json['lastModified'], '2026-09-24T09:00:00.000Z');
      // id محلي Appwrite لا يُرسل في التحديثات
      expect(json.containsKey('id'), isFalse);
    });

    test('قيم ناقصة → أصفار آمنة', () {
      final room = AppwriteRoom.fromJson(const {});

      expect(room.id, '');
      expect(room.price, 0.0);
      expect(room.floor, 0);
      expect(room.lastModified, isNull);
    });
  });

  group('AppwriteBooking', () {
    test('رحلة كاملة + تحويل num إلى double للمبالغ', () {
      final booking = AppwriteBooking.fromJson({
        r'$id': 'bk-1',
        'roomId': 'room-1',
        'guestName': 'أحمد صالح',
        'guestPhone': '777000000',
        'checkIn': '2026-09-20T14:00:00.000Z',
        'checkOut': '2026-09-24T12:00:00.000Z',
        'status': 'محجوزة',
        'totalAmount': 75000,
        'paidAmount': 30000,
      });
      final json = booking.toJson();

      expect(booking.totalAmount, 75000.0);
      expect(booking.paidAmount, 30000.0);
      expect(json['totalAmount'], 75000.0);
      expect(json['checkIn'], '2026-09-20T14:00:00.000Z');
      expect(json.containsKey('lastModified'), isFalse);
    });

    test('checkIn/checkOut ناقصان → الآن كقيمة آمنة (بلا استثناء)', () {
      final before = DateTime.now();
      final booking = AppwriteBooking.fromJson(const {});
      final after = DateTime.now();

      expect(
        booking.checkIn.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        booking.checkIn.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('AppwritePayment', () {
    test('رحلة كاملة: الحقول الأساسية والاختيارية', () {
      final payment = AppwritePayment.fromJson({
        r'$id': 'pay-1',
        'bookingId': 'bk-1',
        'amount': 15000,
        'paymentMethod': 'cash',
        'paymentDate': '2026-09-24T11:00:00.000Z',
        'notes': 'دفعة أولى',
        'lastModifiedBy': 'staff-1',
      });
      final json = payment.toJson();

      expect(payment.amount, 15000.0);
      expect(payment.notes, 'دفعة أولى');
      expect(json['bookingId'], 'bk-1');
      expect(json['notes'], 'دفعة أولى');
      expect(json.containsKey('id'), isFalse);
    });

    test('نموذج فارغ → قيم افتراضية وnotes نل يُسقط من toJson', () {
      final payment = AppwritePayment.fromJson(const {});
      final json = payment.toJson();

      expect(payment.amount, 0.0);
      expect(json.containsKey('notes'), isFalse);
    });
  });

  group('AppwriteExpense', () {
    test('رحلة كاملة مع employeeId الاختياري', () {
      final expense = AppwriteExpense.fromJson({
        r'$id': 'ex-1',
        'category': 'صيانة',
        'amount': 5000,
        'description': 'إصلاح مكيف',
        'expenseDate': '2026-09-23T00:00:00.000Z',
        'employeeId': 'emp-1',
      });
      final json = expense.toJson();

      expect(expense.amount, 5000.0);
      expect(json['employeeId'], 'emp-1');
      expect(json['expenseDate'], '2026-09-23T00:00:00.000Z');
    });

    test('employeeId نل يُسقط من toJson', () {
      final expense = AppwriteExpense.fromJson(const {});
      final json = expense.toJson();

      expect(json.containsKey('employeeId'), isFalse);
    });
  });

  group('AppwriteEmployee', () {
    test('رحلة كاملة مع حقول الإنهاء', () {
      final employee = AppwriteEmployee.fromJson({
        r'$id': 'emp-1',
        'name': 'سالم علي',
        'phone': '777123456',
        'position': 'موظف استقبال',
        'salary': 120000,
        'status': 'على رأس العمل',
        'terminationDate': '2026-10-01',
        'terminationReason': 'استقالة',
      });
      final json = employee.toJson();

      expect(employee.salary, 120000.0);
      expect(json['terminationDate'], '2026-10-01');
      expect(json['terminationReason'], 'استقالة');
    });

    test('بدون إنهاء: الحقول تُسقط من toJson', () {
      final employee = AppwriteEmployee.fromJson(const {});
      final json = employee.toJson();

      expect(json.containsKey('terminationDate'), isFalse);
      expect(json.containsKey('terminationReason'), isFalse);
    });
  });

  group('AppwriteDebt', () {
    test('رحلة كاملة: الحقول وdueDate', () {
      final debt = AppwriteDebt.fromJson({
        r'$id': 'debt-1',
        'bookingId': 'bk-1',
        'guestName': 'أحمد صالح',
        'amount': 45000,
        'status': 'غير مسدد',
        'dueDate': '2026-10-24T00:00:00.000Z',
      });
      final json = debt.toJson();

      expect(debt.amount, 45000.0);
      expect(debt.status, 'غير مسدد');
      expect(json['dueDate'], '2026-10-24T00:00:00.000Z');
      expect(json['guestName'], 'أحمد صالح');
    });

    test('افتراضات آمنة عند فراغ JSON', () {
      final debt = AppwriteDebt.fromJson(const {});

      expect(debt.id, '');
      expect(debt.amount, 0.0);
      expect(debt.lastModified, isNull);
    });
  });
}
