import 'package:flutter/foundation.dart';

/// إعدادات Appwrite المركزية
class AppwriteConfig {
  // Appwrite Endpoint
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';
  
  // Project ID - من لوحة تحكم Appwrite
  static const String projectId = '690ff0da0025518570c1';
  
  // Database ID - من لوحة تحكم Appwrite
  static const String databaseId = 'hotel_db';
  
  // Collections IDs
  static const String roomsCollectionId = 'rooms';
  static const String bookingsCollectionId = 'bookings';
  static const String paymentsCollectionId = 'payments';
  static const String expensesCollectionId = 'expenses';
  static const String employeesCollectionId = 'employees';
  static const String debtsCollectionId = 'debts';
  static const String devicesCollectionId = 'devices';
  static const String syncLogsCollectionId = 'sync_logs';
  
  // إعدادات المزامنة
  static const Duration syncInterval = Duration(minutes: 15);
  static const Duration cacheExpiry = Duration(hours: 6);
  static const int maxCacheSizeMB = 20;
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 5);
  
  // إعدادات الـ Batch
  static const int batchSize = 50; // عدد السجلات في كل دفعة
  
  /// طباعة الإعدادات (للتشخيص)
  static void printConfig() {
    if (kDebugMode) {
      debugPrint('═══════════════════════════════════════');
      debugPrint('🔧 Appwrite Configuration');
      debugPrint('═══════════════════════════════════════');
      debugPrint('Endpoint: $endpoint');
      debugPrint('Project ID: $projectId');
      debugPrint('Database ID: $databaseId');
      debugPrint('Sync Interval: ${syncInterval.inMinutes} minutes');
      debugPrint('Cache Expiry: ${cacheExpiry.inHours} hours');
      debugPrint('Max Cache Size: $maxCacheSizeMB MB');
      debugPrint('Batch Size: $batchSize');
      debugPrint('═══════════════════════════════════════');
    }
  }
  
  /// التحقق من صحة الإعدادات
  static bool validateConfig() {
    if (projectId == 'YOUR_PROJECT_ID_HERE') {
      debugPrint('❌ Error: Please set your Appwrite Project ID');
      return false;
    }
    return true;
  }
}
