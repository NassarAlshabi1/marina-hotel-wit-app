import '../models/sync_result.dart';

/// واجهة محول المزامنة - كل خدمة مزامنة يجب أن تنفذ هذه الواجهة
abstract class SyncAdapter {
  /// اسم المحول
  String get name;

  /// هل تم تهيئة المحول
  bool get isInitialized;

  /// هل المزامنة مفعلة لهذا المحول
  bool get isEnabled;

  /// تهيئة المحول
  Future<void> initialize();

  /// إجراء مزامنة
  Future<SyncResult> sync({required bool push, required bool pull});

  /// تفعيل/تعطيل المزامنة
  Future<void> setEnabled(bool enabled);

  /// الحصول على إحصائيات المزامنة
  Future<Map<String, dynamic>> getStats();

  /// التحقق من صحة الاتصال
  Future<bool> checkConnection();

  /// تنظيف الموارد
  void dispose();
}

/// معلومات حالة المحول
class AdapterStatus {
  AdapterStatus({
    required this.isConnected,
    required this.isAuthenticated,
    this.lastSyncTime,
    this.pendingChanges = 0,
    this.errorMessage,
  });
  final bool isConnected;
  final bool isAuthenticated;
  final DateTime? lastSyncTime;
  final int pendingChanges;
  final String? errorMessage;

  bool get isReady => isConnected && isAuthenticated;
  bool get hasError => errorMessage != null;
}
