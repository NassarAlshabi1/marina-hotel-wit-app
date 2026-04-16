import '../services/local_db.dart';

/// Adapter لتحويل البيانات بين ShiftNote و BookingNote
class ShiftNoteAdapter {
  // استخدام bookingId = -1 للملاحظات العامة غير المرتبطة بحجز
  static const int GENERAL_NOTES_BOOKING_ID = -1;

  /// تحويل ShiftNote إلى BookingNote للحفظ في قاعدة البيانات
  static Map<String, dynamic> toBookingNoteData(ShiftNote note) {
    // تحويل الأولوية والنوبة إلى نص alertType
    final alertType = _encodeAlertType(note.priority, note.shiftType);

    return {
      'booking_id': GENERAL_NOTES_BOOKING_ID,
      'note_text': '${note.title}|||${note.content}', // استخدام ||| كفاصل
      'alert_type': alertType,
      'alert_until': note.expiresAt?.toIso8601String(),
      'is_active': note.isRead ? 0 : 1, // عكس المنطق - isActive = !isRead
    };
  }

  /// تحويل BookingNote إلى ShiftNote للعرض في الواجهة
  static ShiftNote fromBookingNote(BookingNote bookingNote) {
    // فك تشفير العنوان والمحتوى
    final parts = bookingNote.noteText.split('|||');
    final title = parts.length >= 1 ? parts[0] : 'ملاحظة';
    final content = parts.length >= 2 ? parts[1] : bookingNote.noteText;

    // فك تشفير الأولوية والنوبة
    final (priority, shiftType) = _decodeAlertType(bookingNote.alertType);

    return ShiftNote(
      id: bookingNote.id.toString(),
      title: title,
      content: content,
      priority: priority,
      shiftType: shiftType,
      createdAt: DateTime.fromMillisecondsSinceEpoch(bookingNote.createdAt),
      expiresAt: bookingNote.alertUntil != null
          ? DateTime.tryParse(bookingNote.alertUntil!)
          : null,
      isRead: bookingNote.isActive == 0, // عكس المنطق
      status: bookingNote.isActive == 1
          ? NoteStatus.active
          : NoteStatus.completed,
      createdBy: 'user', // قيمة افتراضية
    );
  }

  /// ترميز الأولوية ونوع النوبة في نص واحد
  static String _encodeAlertType(NotePriority priority, ShiftType shiftType) {
    final priorityCode = priority == NotePriority.high
        ? 'H'
        : priority == NotePriority.medium
        ? 'M'
        : 'L';
    final shiftCode = shiftType == ShiftType.morning
        ? 'MOR'
        : shiftType == ShiftType.evening
        ? 'EVE'
        : shiftType == ShiftType.night
        ? 'NIG'
        : 'ALL';
    return '$priorityCode-$shiftCode';
  }

  /// فك ترميز الأولوية ونوع النوبة من النص
  static (NotePriority, ShiftType) _decodeAlertType(String alertType) {
    try {
      final parts = alertType.split('-');
      if (parts.length != 2) return (NotePriority.medium, ShiftType.all);

      final priorityCode = parts[0];
      final shiftCode = parts[1];

      final priority = priorityCode == 'H'
          ? NotePriority.high
          : priorityCode == 'M'
          ? NotePriority.medium
          : NotePriority.low;

      final shiftType = shiftCode == 'MOR'
          ? ShiftType.morning
          : shiftCode == 'EVE'
          ? ShiftType.evening
          : shiftCode == 'NIG'
          ? ShiftType.night
          : ShiftType.all;

      return (priority, shiftType);
    } catch (e) {
      return (NotePriority.medium, ShiftType.all);
    }
  }
}

// نماذج البيانات للملاحظات
class ShiftNote {
  final String id;
  String title;
  String content;
  NotePriority priority;
  ShiftType shiftType;
  final DateTime createdAt;
  DateTime? expiresAt;
  bool isRead;
  NoteStatus status;
  final String createdBy;

  ShiftNote({
    required this.id,
    required this.title,
    required this.content,
    required this.priority,
    required this.shiftType,
    required this.createdAt,
    this.expiresAt,
    this.isRead = false,
    this.status = NoteStatus.active,
    required this.createdBy,
  });

  /// تحديث الملاحظة من البيانات الجديدة
  void updateFrom(ShiftNote other) {
    title = other.title;
    content = other.content;
    priority = other.priority;
    shiftType = other.shiftType;
    expiresAt = other.expiresAt;
    // لا نحدث isRead و status لأنها تحتاج معالجة خاصة
  }
}

enum NotePriority { high, medium, low }

enum ShiftType { morning, evening, night, all }

enum NoteStatus { active, completed, expired }
