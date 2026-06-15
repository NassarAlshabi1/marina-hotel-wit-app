import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';
import 'appwrite_backup_endpoint.dart';

/// مدير نقاط النهاية الاحتياطية (Master/Slave)
/// 
/// الـ Master هو الإعدادات الأساسية (AppwriteConfigManager)
/// الـ Slaves هي نقاط نهاية إضافية للإرسال فقط (push backup)
class BackupEndpointsManager {
  static const String _storageKey = 'backup_appwrite_endpoints';

  /// حفظ قائمة الـ endpoints الاحتياطية
  static Future<void> saveEndpoints(List<BackupEndpoint> endpoints) async {
    final prefs = getSharedPrefs();
    final jsonList = endpoints.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
    if (kDebugMode) {
      debugPrint('💾 Saved ${endpoints.length} backup endpoint(s)');
    }
  }

  /// تحميل قائمة الـ endpoints الاحتياطية
  /// [includeInactive] إذا true، يُرجع جميع النقاط بما فيها غير النشطة
  static Future<List<BackupEndpoint>> loadEndpoints({bool includeInactive = false}) async {
    final prefs = getSharedPrefs();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    
    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      var endpoints = jsonList
          .map((e) => BackupEndpoint.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!includeInactive) {
        endpoints = endpoints.where((e) => e.isActive).toList();
      }
      if (kDebugMode) {
        debugPrint('📂 Loaded ${endpoints.length} backup endpoint(s)');
      }
      return endpoints;
    } catch (e) {
      debugPrint('❌ Failed to load backup endpoints: $e');
      return [];
    }
  }

  /// إضافة endpoint احتياطي
  static Future<void> addEndpoint(BackupEndpoint endpoint) async {
    final endpoints = await loadEndpoints(includeInactive: true);
    endpoints.add(endpoint);
    await saveEndpoints(endpoints);
  }

  /// حذف endpoint احتياطي
  static Future<void> removeEndpoint(String id) async {
    final endpoints = await loadEndpoints(includeInactive: true);
    endpoints.removeWhere((e) => e.id == id);
    await saveEndpoints(endpoints);
  }

  /// تحديث endpoint احتياطي
  static Future<void> updateEndpoint(BackupEndpoint endpoint) async {
    final endpoints = await loadEndpoints(includeInactive: true);
    final index = endpoints.indexWhere((e) => e.id == endpoint.id);
    if (index != -1) {
      endpoints[index] = endpoint;
      await saveEndpoints(endpoints);
    }
  }
}
