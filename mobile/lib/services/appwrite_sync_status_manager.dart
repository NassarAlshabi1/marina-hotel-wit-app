import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_config.dart';

/// مدير حالة مزامنة الجداول مع Appwrite
/// يتولى إدارة تفعيل/تعطيل المزامنة لكل جدول على حدة
class AppwriteSyncStatusManager {
  static const String _syncStatusPrefix = 'appwrite_sync_status_';
  static const String _lastSyncTimePrefix = 'appwrite_last_sync_';
  static const String _syncCountPrefix = 'appwrite_sync_count_';

  static final AppwriteSyncStatusManager _instance =
      AppwriteSyncStatusManager._internal();

  factory AppwriteSyncStatusManager() => _instance;

  AppwriteSyncStatusManager._internal();

  /// جميع معرفات الجداول المتاحة
  static const List<String> allCollectionIds = [
    AppwriteConfig.roomsCollectionId,
    AppwriteConfig.bookingsCollectionId,
    AppwriteConfig.bookingNotesCollectionId,
    AppwriteConfig.bookingNightsCollectionId,
    AppwriteConfig.paymentsCollectionId,
    AppwriteConfig.expensesCollectionId,
    AppwriteConfig.cashTransactionsCollectionId,
    AppwriteConfig.debtsCollectionId,
    AppwriteConfig.employeesCollectionId,
    AppwriteConfig.salaryCyclesCollectionId,
    AppwriteConfig.salaryPaymentsCollectionId,
    // ❌ hotel_day_ledger - محلي فقط
    AppwriteConfig.shiftNotesCollectionId,
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
  ];

  /// الحصول على حالة مزامنة جدول معين
  /// الافتراضي: مفعل (true)
  Future<bool> isCollectionSyncEnabled(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_syncStatusPrefix$collectionId') ?? true;
  }

  /// تعيين حالة مزامنة جدول معين
  Future<void> setCollectionSyncEnabled(
    String collectionId,
    bool enabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_syncStatusPrefix$collectionId', enabled);

    if (kDebugMode) {
      debugPrint(
        '📱 Collection Sync Status Updated: $collectionId = $enabled',
      );
    }
  }

  /// الحصول على حالة المزامنة لجميع الجداول
  Future<Map<String, bool>> getAllCollectionsSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final status = <String, bool>{};

    for (final collectionId in allCollectionIds) {
      status[collectionId] =
          prefs.getBool('$_syncStatusPrefix$collectionId') ?? true;
    }

    return status;
  }

  /// الحصول على آخر وقت مزامنة لجدول معين
  Future<DateTime?> getLastSyncTime(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('$_lastSyncTimePrefix$collectionId');

    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// تحديث آخر وقت مزامنة لجدول معين
  Future<void> updateLastSyncTime(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$_lastSyncTimePrefix$collectionId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// الحصول على عدد مرات المزامنة الناجحة لجدول معين
  Future<int> getSyncCount(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_syncCountPrefix$collectionId') ?? 0;
  }

  /// زيادة عدد مرات المزامنة الناجحة
  Future<void> incrementSyncCount(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt('$_syncCountPrefix$collectionId') ?? 0;
    await prefs.setInt('$_syncCountPrefix$collectionId', currentCount + 1);
  }

  /// إعادة تعيين إحصائيات المزامنة لجدول معين
  Future<void> resetSyncStats(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_lastSyncTimePrefix$collectionId');
    await prefs.remove('$_syncCountPrefix$collectionId');
  }

  /// إعادة تعيين جميع الإحصائيات
  Future<void> resetAllSyncStats() async {
    final prefs = await SharedPreferences.getInstance();

    for (final collectionId in allCollectionIds) {
      await prefs.remove('$_lastSyncTimePrefix$collectionId');
      await prefs.remove('$_syncCountPrefix$collectionId');
    }

    if (kDebugMode) {
      debugPrint('🔄 All Sync Stats Reset');
    }
  }

  /// تفعيل مزامنة جميع الجداول
  Future<void> enableAllCollections() async {
    final prefs = await SharedPreferences.getInstance();

    for (final collectionId in allCollectionIds) {
      await prefs.setBool('$_syncStatusPrefix$collectionId', true);
    }

    if (kDebugMode) {
      debugPrint('✅ All Collections Sync Enabled');
    }
  }

  /// تعطيل مزامنة جميع الجداول
  Future<void> disableAllCollections() async {
    final prefs = await SharedPreferences.getInstance();

    for (final collectionId in allCollectionIds) {
      await prefs.setBool('$_syncStatusPrefix$collectionId', false);
    }

    if (kDebugMode) {
      debugPrint('❌ All Collections Sync Disabled');
    }
  }

  /// الحصول على قائمة الجداول المفعلة للمزامنة
  Future<List<String>> getEnabledCollections() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = <String>[];

    for (final collectionId in allCollectionIds) {
      if (prefs.getBool('$_syncStatusPrefix$collectionId') ?? true) {
        enabled.add(collectionId);
      }
    }

    return enabled;
  }

  /// الحصول على قائمة الجداول المعطلة للمزامنة
  Future<List<String>> getDisabledCollections() async {
    final prefs = await SharedPreferences.getInstance();
    final disabled = <String>[];

    for (final collectionId in allCollectionIds) {
      if (!(prefs.getBool('$_syncStatusPrefix$collectionId') ?? true)) {
        disabled.add(collectionId);
      }
    }

    return disabled;
  }

  /// طباعة إحصائيات المزامنة (للتشخيص)
  Future<void> printSyncStats() async {
    if (!kDebugMode) return;

    debugPrint('═══════════════════════════════════════');
    debugPrint('📊 Appwrite Sync Statistics');
    debugPrint('═══════════════════════════════════════');

    for (final collectionId in allCollectionIds) {
      final isEnabled = await isCollectionSyncEnabled(collectionId);
      final lastSync = await getLastSyncTime(collectionId);
      final syncCount = await getSyncCount(collectionId);

      final status = isEnabled ? '✅' : '❌';
      final lastSyncStr = lastSync?.toString() ?? 'لم يتم';

      debugPrint('$status $collectionId');
      debugPrint('   آخر مزامنة: $lastSyncStr');
      debugPrint('   عدد المزامنات: $syncCount');
    }

    debugPrint('═══════════════════════════════════════');
  }

  /// الحصول على معلومات تفصيلية عن جدول معين
  Future<CollectionSyncInfo> getCollectionInfo(String collectionId) async {
    final isEnabled = await isCollectionSyncEnabled(collectionId);
    final lastSync = await getLastSyncTime(collectionId);
    final syncCount = await getSyncCount(collectionId);

    return CollectionSyncInfo(
      collectionId: collectionId,
      isEnabled: isEnabled,
      lastSyncTime: lastSync,
      syncCount: syncCount,
    );
  }

  /// الحصول على معلومات تفصيلية عن جميع الجداول
  Future<List<CollectionSyncInfo>> getAllCollectionsInfo() async {
    final infos = <CollectionSyncInfo>[];

    for (final collectionId in allCollectionIds) {
      final info = await getCollectionInfo(collectionId);
      infos.add(info);
    }

    return infos;
  }
}

/// فئة تمثل معلومات مزامنة جدول معين
class CollectionSyncInfo {
  final String collectionId;
  final bool isEnabled;
  final DateTime? lastSyncTime;
  final int syncCount;

  CollectionSyncInfo({
    required this.collectionId,
    required this.isEnabled,
    required this.lastSyncTime,
    required this.syncCount,
  });

  /// الحصول على نص يصف حالة المزامنة
  String get statusText => isEnabled ? 'مفعل' : 'معطل';

  /// الحصول على نص يصف آخر مزامنة
  String get lastSyncText {
    if (lastSyncTime == null) return 'لم يتم';
    return lastSyncTime!.toString();
  }

  /// التحويل إلى خريطة
  Map<String, dynamic> toMap() => {
        'collectionId': collectionId,
        'isEnabled': isEnabled,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
        'syncCount': syncCount,
      };

  @override
  String toString() => 'CollectionSyncInfo('
      'collectionId: $collectionId, '
      'isEnabled: $isEnabled, '
      'lastSyncTime: $lastSyncTime, '
      'syncCount: $syncCount'
      ')';
}
