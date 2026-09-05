import '../utils/id.dart';

/// سياق جلسة المستخدم التي تُسند إليها المدفوعات الجديدة.
///
/// لا يمثل هذا جدول نوبات مستقلاً؛ بل يمثل جلسة تسجيل الدخول الحالية
/// كما اتُّفق عليه في الخيار A. يُعاد توليد sessionUuid عند كل login/restore.
class PaymentSessionContext {
  PaymentSessionContext._();

  static int? userId;
  static String? userName;
  static String? sessionUuid;
  static String? cloudUserId;
  static DateTime? startedAt;

  static bool get isActive => userId != null && sessionUuid != null;

  static void start({
    required int userId,
    required String userName,
    String? sessionUuid,
    String? cloudUserId,
    DateTime? startedAt,
  }) {
    PaymentSessionContext.userId = userId;
    PaymentSessionContext.userName = userName;
    PaymentSessionContext.sessionUuid = sessionUuid ?? IdGen.uuid();
    PaymentSessionContext.cloudUserId = cloudUserId;
    PaymentSessionContext.startedAt = startedAt ?? DateTime.now();
  }

  static void clear() {
    userId = null;
    userName = null;
    sessionUuid = null;
    cloudUserId = null;
    startedAt = null;
  }
}
