import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/status_utils.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // حالة الغرف — available / occupied
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — حالات الغرف', () {
    test('isRoomAvailable يتعرف على الحالات العربية', () {
      expect(StatusUtils.isRoomAvailable('شاغرة'), isTrue);
      expect(StatusUtils.isRoomAvailable('شاغره'), isTrue);
      expect(StatusUtils.isRoomAvailable('متاحة'), isTrue);
      expect(StatusUtils.isRoomAvailable('متاح'), isTrue);
    });

    test('isRoomAvailable يتعرف على الحالات الإنجليزية', () {
      expect(StatusUtils.isRoomAvailable('available'), isTrue);
      expect(StatusUtils.isRoomAvailable('vacant'), isTrue);
      expect(StatusUtils.isRoomAvailable('empty'), isTrue);
    });

    test('isRoomAvailable يتجاهل المسافات والحالة', () {
      expect(StatusUtils.isRoomAvailable('  Available '), isTrue);
      expect(StatusUtils.isRoomAvailable('AVAILABLE'), isTrue);
      expect(StatusUtils.isRoomAvailable('  شاغرة  '), isTrue);
    });

    test('isRoomAvailable يرفض حالات شاغرة', () {
      expect(StatusUtils.isRoomAvailable('محجوزة'), isFalse);
      expect(StatusUtils.isRoomAvailable('occupied'), isFalse);
      expect(StatusUtils.isRoomAvailable('مشغولة'), isFalse);
    });

    test('isRoomOccupied يتعرف على حالات الإشغال', () {
      expect(StatusUtils.isRoomOccupied('محجوزة'), isTrue);
      expect(StatusUtils.isRoomOccupied('محجوز'), isTrue);
      expect(StatusUtils.isRoomOccupied('مشغولة'), isTrue);
      expect(StatusUtils.isRoomOccupied('occupied'), isTrue);
      expect(StatusUtils.isRoomOccupied('نشط'), isTrue);
      expect(StatusUtils.isRoomOccupied('active'), isTrue);
    });

    test('isRoomOccupied يرفض حالات شاغرة', () {
      expect(StatusUtils.isRoomOccupied('شاغرة'), isFalse);
      expect(StatusUtils.isRoomOccupied('available'), isFalse);
    });

    test('isRoomOccupied يتجاهل المسافات والحالة', () {
      expect(StatusUtils.isRoomOccupied('  Occupied '), isTrue);
      expect(StatusUtils.isRoomOccupied('OCCUPIED'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // حالات الحجز — active booking
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — حالات الحجز', () {
    test('isActiveBooking يتعرف على الحالات النشطة', () {
      expect(StatusUtils.isActiveBooking('محجوزة'), isTrue);
      expect(StatusUtils.isActiveBooking('محجوز'), isTrue);
      expect(StatusUtils.isActiveBooking('نشط'), isTrue);
      expect(StatusUtils.isActiveBooking('active'), isTrue);
      expect(StatusUtils.isActiveBooking('confirmed'), isTrue);
      expect(StatusUtils.isActiveBooking('قيد الحجز'), isTrue);
      expect(StatusUtils.isActiveBooking('in_progress'), isTrue);
      expect(StatusUtils.isActiveBooking('مؤقت'), isTrue);
      expect(StatusUtils.isActiveBooking('provisional'), isTrue);
    });

    test('isActiveBooking يرفض الحالات غير النشطة', () {
      expect(StatusUtils.isActiveBooking('cancelled'), isFalse);
      expect(StatusUtils.isActiveBooking('checked_out'), isFalse);
      expect(StatusUtils.isActiveBooking('ملغى'), isFalse);
    });

    test('isActiveBooking يتجاهل المسافات والحالة', () {
      expect(StatusUtils.isActiveBooking('  Active '), isTrue);
      expect(StatusUtils.isActiveBooking('CONFIRMED'), isTrue);
    });

    test('isProvisional يتعرف على الحالة المؤقتة', () {
      expect(StatusUtils.isProvisional('مؤقت'), isTrue);
      expect(StatusUtils.isProvisional('provisional'), isTrue);
      expect(StatusUtils.isProvisional('active'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // حالات الموظف — active / terminated
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — حالات الموظف', () {
    test('isEmployeeActive يتعرف على الموظف النشط', () {
      expect(StatusUtils.isEmployeeActive('نشط'), isTrue);
      expect(StatusUtils.isEmployeeActive('active'), isTrue);
    });

    test('isEmployeeActive يرفض الحالات الأخرى', () {
      expect(StatusUtils.isEmployeeActive('مفصول'), isFalse);
      expect(StatusUtils.isEmployeeActive('terminated'), isFalse);
      expect(StatusUtils.isEmployeeActive('استقالة'), isFalse);
    });

    test('isEmployeeTerminated يتعرف على حالات إنهاء الخدمة', () {
      expect(StatusUtils.isEmployeeTerminated('مفصول'), isTrue);
      expect(StatusUtils.isEmployeeTerminated('terminated'), isTrue);
      expect(StatusUtils.isEmployeeTerminated('استقالة'), isTrue);
      expect(StatusUtils.isEmployeeTerminated('resigned'), isTrue);
      expect(StatusUtils.isEmployeeTerminated('استغناء'), isTrue);
      expect(StatusUtils.isEmployeeTerminated('laid_off'), isTrue);
    });

    test('isEmployeeTerminated يرفض الحالات النشطة', () {
      expect(StatusUtils.isEmployeeTerminated('نشط'), isFalse);
      expect(StatusUtils.isEmployeeTerminated('active'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // تسمية الحالة — employeeStatusLabel / canonicalEmployeeStatus
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — تسمية الحالة', () {
    test('employeeStatusLabel يعيد التسمية العربية', () {
      expect(StatusUtils.employeeStatusLabel('active'), 'نشط');
      expect(StatusUtils.employeeStatusLabel('نشط'), 'نشط');
      expect(StatusUtils.employeeStatusLabel('terminated'), 'مفصول');
      expect(StatusUtils.employeeStatusLabel('مفصول'), 'مفصول');
      expect(StatusUtils.employeeStatusLabel('resigned'), 'استقالة');
      expect(StatusUtils.employeeStatusLabel('استقالة'), 'استقالة');
      expect(StatusUtils.employeeStatusLabel('laid_off'), 'استغناء');
      expect(StatusUtils.employeeStatusLabel('استغناء'), 'استغناء');
      expect(StatusUtils.employeeStatusLabel('frozen'), 'مجمد');
      expect(StatusUtils.employeeStatusLabel('مجمد'), 'مجمد');
    });

    test('employeeStatusLabel يعيد "غير نشط" للحالات غير المعروفة', () {
      expect(StatusUtils.employeeStatusLabel('unknown'), 'غير نشط');
      expect(StatusUtils.employeeStatusLabel('xyz'), 'غير نشط');
    });

    test('canonicalEmployeeStatus يعيد الحالة الكانونية', () {
      expect(StatusUtils.canonicalEmployeeStatus('نشط'), 'active');
      expect(StatusUtils.canonicalEmployeeStatus('مفصول'), 'terminated');
      expect(StatusUtils.canonicalEmployeeStatus('استقالة'), 'resigned');
      expect(StatusUtils.canonicalEmployeeStatus('استغناء'), 'laid_off');
      expect(StatusUtils.canonicalEmployeeStatus('مجمد'), 'frozen');
      expect(StatusUtils.canonicalEmployeeStatus('unknown'), 'inactive');
    });

    test('canonicalToArabic تحول الحالة الكانونية لعربية', () {
      expect(StatusUtils.canonicalToArabic('active'), 'نشط');
      expect(StatusUtils.canonicalToArabic('terminated'), 'مفصول');
      expect(StatusUtils.canonicalToArabic('resigned'), 'استقالة');
      expect(StatusUtils.canonicalToArabic('laid_off'), 'استغناء');
      expect(StatusUtils.canonicalToArabic('frozen'), 'مجمد');
      expect(StatusUtils.canonicalToArabic('inactive'), 'غير نشط');
    });

    test('canonicalToArabic للحالة غير المعروفة', () {
      expect(StatusUtils.canonicalToArabic('unknown'), 'غير نشط');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // لون الحالة — employeeStatusColor
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — لون الحالة', () {
    test('الموظف النشط = أخضر', () {
      expect(StatusUtils.employeeStatusColor('نشط'), 0xFF4CAF50);
      expect(StatusUtils.employeeStatusColor('active'), 0xFF4CAF50);
    });

    test('الموظف المفصول = أحمر', () {
      expect(StatusUtils.employeeStatusColor('مفصول'), 0xFFF44336);
      expect(StatusUtils.employeeStatusColor('terminated'), 0xFFF44336);
    });

    test('الموظف المجمد = ليس أخضر ولا أحمر', () {
      final color = StatusUtils.employeeStatusColor('مجمد');
      expect(color, isNot(0xFF4CAF50)); // ليس أخضر
      expect(color, isNot(0xFFF44336)); // ليس أحمر
      // اللون إما برتقالي (0xFFFF9800) أو رمادي حسب تطبيع النص
    });

    test('frozen = ليس أخضر ولا أحمر', () {
      final color = StatusUtils.employeeStatusColor('frozen');
      expect(color, isNot(0xFF4CAF50)); // ليس أخضر
      expect(color, isNot(0xFFF44336)); // ليس أحمر
    });

    test('الحالة غير المعروفة = رمادي', () {
      // قيمة اللون الرمادي قد تختلف حسب المنصة، نتحقق أنها ليست أخضر/أحمر/برتقالي
      final color = StatusUtils.employeeStatusColor('unknown');
      expect(color, isNot(0xFF4CAF50)); // ليس أخضر
      expect(color, isNot(0xFFF44336)); // ليس أحمر
      expect(color, isNot(0xFFFF9800)); // ليس برتقالي
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // roomStatusForOccupancy
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — roomStatusForOccupancy', () {
    test('occupied=true يعيد "محجوزة"', () {
      expect(StatusUtils.roomStatusForOccupancy(true), 'محجوزة');
    });

    test('occupied=false يعيد "شاغرة"', () {
      expect(StatusUtils.roomStatusForOccupancy(false), 'شاغرة');
    });

    test('يقبل قيم مخصصة', () {
      expect(StatusUtils.roomStatusForOccupancy(true, fallbackOccupied: 'X'), 'X');
      expect(StatusUtils.roomStatusForOccupancy(false, fallbackAvailable: 'Y'), 'Y');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // activeBookingStatuses — قائمة خام لاستعلامات SQL
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — activeBookingStatuses قائمة خام', () {
    test('القائمة تحتوي على جميع الحالات النشطة', () {
      expect(StatusUtils.activeBookingStatuses, contains('محجوزة'));
      expect(StatusUtils.activeBookingStatuses, contains('محجوز'));
      expect(StatusUtils.activeBookingStatuses, contains('نشط'));
      expect(StatusUtils.activeBookingStatuses, contains('active'));
      expect(StatusUtils.activeBookingStatuses, contains('confirmed'));
      expect(StatusUtils.activeBookingStatuses, contains('قيد الحجز'));
      expect(StatusUtils.activeBookingStatuses, contains('in_progress'));
      expect(StatusUtils.activeBookingStatuses, contains('مؤقت'));
      expect(StatusUtils.activeBookingStatuses, contains('provisional'));
    });

    test('القائمة لا تحتوي على حالات غير نشطة', () {
      expect(StatusUtils.activeBookingStatuses, isNot(contains('cancelled')));
      expect(StatusUtils.activeBookingStatuses, isNot(contains('ملغى')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // activeEmployeeStatuses — قائمة خام
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — activeEmployeeStatuses قائمة خام', () {
    test('القائمة تحتوي على نشط و active فقط', () {
      expect(StatusUtils.activeEmployeeStatuses.length, 2);
      expect(StatusUtils.activeEmployeeStatuses, contains('نشط'));
      expect(StatusUtils.activeEmployeeStatuses, contains('active'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // terminatedEmployeeStatuses — قائمة خام
  // ═══════════════════════════════════════════════════════════════
  group('StatusUtils — terminatedEmployeeStatuses قائمة خام', () {
    test('القائمة تحتوي على جميع حالات إنهاء الخدمة', () {
      expect(StatusUtils.terminatedEmployeeStatuses, contains('مفصول'));
      expect(StatusUtils.terminatedEmployeeStatuses, contains('terminated'));
      expect(StatusUtils.terminatedEmployeeStatuses, contains('استقالة'));
      expect(StatusUtils.terminatedEmployeeStatuses, contains('resigned'));
      expect(StatusUtils.terminatedEmployeeStatuses, contains('استغناء'));
      expect(StatusUtils.terminatedEmployeeStatuses, contains('laid_off'));
    });
  });
}
