import 'package:flutter/foundation.dart';
import 'ditto_cloud_sync_service.dart';
import 'local_db.dart';

/// نسخة مبسطة من خدمة المزامنة المحلية مع Ditto بعد إزالة التكامل الفعلي.
/// تحافظ هذه الخدمة على نفس الواجهة المطلوبة من بقية التطبيق حتى
/// لا تنهار الصفحات التي تعتمد عليها، لكنها لا تنفذ أي مزامنة حقيقية.
class DittoLocalSyncService {
  static final DittoLocalSyncService _instance = DittoLocalSyncService._internal();
  factory DittoLocalSyncService() => _instance;
  DittoLocalSyncService._internal();

  final _dittoService = DittoCloudSyncService();
  AppDatabase? _database;
  bool _isInitialized = false;
  bool _isSyncing = false;

  Future<bool> initialize(AppDatabase database) async {
    _database = database;
    await _dittoService.initialize();
    _isInitialized = true;
    debugPrint('⚠️ تم تفعيل خدمة مزامنة Ditto المبسطة (بدون مزامنة فعلية).');
    return true;
  }

  Future<bool> fullSync() async {
    if (!_isInitialized) {
      debugPrint('⚠️ خدمة المزامنة المبسطة غير مهيأة.');
      return false;
    }
    _isSyncing = true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _isSyncing = false;
    return true;
  }

  Future<Map<String, dynamic>> getSyncStats() async {
    return {
      'rooms_in_local': 0,
      'bookings_in_local': 0,
      'employees_in_local': 0,
      'payments_in_local': 0,
      'is_syncing': _isSyncing,
    };
  }

  Future<void> dispose() async {
    _isInitialized = false;
    _isSyncing = false;
    _database = null;
    await _dittoService.dispose();
  }
}
