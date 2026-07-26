import '../services/local_db.dart';

class StatusUtils {
  static final Set<String> _availableRoomStatuses = {
    'شاغرة',
    'شاغره',
    'متاحة',
    'متاح',
    'available',
    'vacant',
    'empty',
  }.map(_normalize).toSet();

  static final Set<String> _occupiedRoomStatuses = {
    'محجوزة',
    'محجوز',
    'مشغولة',
    'occupied',
    'محجوز temporarily',
    'نشط',
    'active',
    'مؤقت',
    'provisional',
  }.map(_normalize).toSet();

  static final Set<String> _activeBookingStatuses = {
    'محجوزة',
    'محجوز',
    'نشط',
    'active',
    'confirmed',
    'قيد الحجز',
    'in_progress',
    'مؤقت',
    'provisional',
  }.map(_normalize).toSet();

  /// القائمة الخام للحالات النشطة (قبل التطبيع) - لاستخدامها في استعلامات SQL
  static const List<String> activeBookingStatuses = [
    'محجوزة',
    'محجوز',
    'نشط',
    'active',
    'confirmed',
    'قيد الحجز',
    'in_progress',
    'مؤقت',
    'provisional',
  ];

  static final Set<String> _activeEmployeeStatuses = {
    'نشط',
    'active',
  }.map(_normalize).toSet();

  /// ✅ حالات الغرف تحت الصيانة — عربية + إنجليزية، مُطبَّعة (trim+lowercase).
  /// تُستخدم في isUnderMaintenance() — مصدر وحيد للحقيقة (DRY) يمنع التشتت
  /// بين 'صيانة' و 'maintenance' في عدة providers/getters.
  static final Set<String> _maintenanceRoomStatuses = {
    'صيانة',
    'maintenance',
    'under_maintenance',
    'under maintenance',
  }.map(_normalize).toSet();

  static const List<String> activeEmployeeStatuses = ['نشط', 'active'];

  /// حالات إنهاء الخدمة
  static final Set<String> _terminatedEmployeeStatuses = {
    'مفصول',
    'terminated',
    'استقالة',
    'resigned',
    'استغناء',
    'laid_off',
  }.map(_normalize).toSet();

  static const List<String> terminatedEmployeeStatuses = [
    'مفصول',
    'terminated',
    'استقالة',
    'resigned',
    'استغناء',
    'laid_off',
  ];

  static final Set<String> _provisionalStatuses = {
    'مؤقت',
    'provisional',
  }.map(_normalize).toSet();

  static String _normalize(String value) => value.trim().toLowerCase();

  static bool isRoomAvailable(String status) =>
      _availableRoomStatuses.contains(_normalize(status));

  /// ✅ هل الغرفة تحت الصيانة؟ يفحص 'صيانة' و 'maintenance' (مع variants) بشكل
  /// مُطبَّع (trim+lowercase). استخدم هذا بدلاً من `status == 'صيانة' || status ==
  /// 'maintenance'` المكرر في عدة أماكن — يضمن اتساقاً كاملاً ويمنع bugs الترجمة.
  static bool isUnderMaintenance(String status) =>
      _maintenanceRoomStatuses.contains(_normalize(status));

  static bool isRoomOccupied(String status) =>
      _occupiedRoomStatuses.contains(_normalize(status));

  static bool isActiveBooking(String status) =>
      _activeBookingStatuses.contains(_normalize(status));

  static bool isEmployeeActive(String status) =>
      _activeEmployeeStatuses.contains(_normalize(status));

  /// هل الموظف مفصول / مستغنى عنه / استقال؟
  static bool isEmployeeTerminated(String status) =>
      _terminatedEmployeeStatuses.contains(_normalize(status));

  /// تسمية عرض الحالة بالعربية مع دعم حالات إنهاء الخدمة
  static String employeeStatusLabel(String status) {
    if (isEmployeeActive(status)) return 'نشط';
    if (_normalize(status) == _normalize('مفصول') ||
        _normalize(status) == _normalize('terminated')) {
      return 'مفصول';
    }
    if (_normalize(status) == _normalize('استقالة') ||
        _normalize(status) == _normalize('resigned')) {
      return 'استقالة';
    }
    if (_normalize(status) == _normalize('استغناء') ||
        _normalize(status) == _normalize('laid_off')) {
      return 'استغناء';
    }
    if (_normalize(status) == _normalize('مجمد') ||
        _normalize(status) == _normalize('frozen')) {
      return 'مجمد';
    }
    return 'غير نشط';
  }

  static String canonicalEmployeeStatus(String status) {
    if (isEmployeeActive(status)) {
      return 'active';
    }
    if (_normalize(status) == _normalize('مفصول') ||
        _normalize(status) == _normalize('terminated')) {
      return 'terminated';
    }
    if (_normalize(status) == _normalize('استقالة') ||
        _normalize(status) == _normalize('resigned')) {
      return 'resigned';
    }
    if (_normalize(status) == _normalize('استغناء') ||
        _normalize(status) == _normalize('laid_off')) {
      return 'laid_off';
    }
    if (_normalize(status) == _normalize('مجمد') ||
        _normalize(status) == _normalize('frozen')) {
      return 'frozen';
    }
    return 'inactive';
  }

  /// تحويل الحالة الكانونية إلى عربية
  static String canonicalToArabic(String canonical) {
    switch (canonical) {
      case 'active':
        return 'نشط';
      case 'terminated':
        return 'مفصول';
      case 'resigned':
        return 'استقالة';
      case 'laid_off':
        return 'استغناء';
      case 'frozen':
        return 'مجمد';
      default:
        return 'غير نشط';
    }
  }

  /// لون الحالة
  static int employeeStatusColor(String status) {
    if (isEmployeeActive(status)) return 0xFF4CAF50; // أخضر
    if (isEmployeeTerminated(status)) return 0xFFF44336; // أحمر
    if (_normalize(status) == _normalize('مجمد')) return 0xFFFF9800; // برتقالي
    return 0xFF9E9E9E; // رمادي
  }

  static bool isProvisional(String status) =>
      _provisionalStatuses.contains(_normalize(status));

  static bool isBookingProvisional(Booking booking) =>
      isProvisional(booking.status);

  static String roomStatusForOccupancy(
    bool occupied, {
    String fallbackAvailable = 'شاغرة',
    String fallbackOccupied = 'محجوزة',
  }) {
    return occupied ? fallbackOccupied : fallbackAvailable;
  }

  static bool isBookingActive(Booking booking) =>
      isActiveBooking(booking.status);
}
