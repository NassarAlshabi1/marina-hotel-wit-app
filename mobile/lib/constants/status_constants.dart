class EmployeeStatus {
  static const String active = 'active';
  static const String inactive = 'inactive';

  static const List<String> all = [active, inactive];
}

class RoomStatus {
  static const String available = 'شاغرة';
  static const String occupied = 'محجوزة';

  static const List<String> all = [available, occupied];
}

class BookingStatus {
  static const String booked = 'محجوزة';
  static const String active = 'active';
  static const String confirmed = 'confirmed';
  static const String checkedIn = 'checked_in';
  static const String completed = 'مكتمل';
  static const String completedEn = 'completed';
  static const String departed = 'غادر';
  static const String departedEn = 'departed';

  static const List<String> activeStatuses = [
    booked,
    active,
    confirmed,
    checkedIn,
  ];

  static const List<String> completedStatuses = [
    completed,
    completedEn,
    departed,
    departedEn,
  ];

  static const List<String> all = [
    booked,
    active,
    confirmed,
    checkedIn,
    completed,
    completedEn,
    departed,
    departedEn,
  ];

  static bool isActive(String status) {
    return activeStatuses.contains(status);
  }

  static bool isCompleted(String status) {
    final normalized = status.toLowerCase();
    return completedStatuses
        .map((s) => s.toLowerCase())
        .contains(normalized);
  }
}
