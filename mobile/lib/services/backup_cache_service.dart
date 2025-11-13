import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupCacheService {
  static const String _cacheFileName = 'last_backup_cache.json';
  static const String _cacheTimestampKey = 'cache_timestamp';

  static Future<void> saveToCache(Uint8List compressedData) async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final cacheFile = File('${cacheDir.path}/$_cacheFileName');

      await cacheFile.writeAsBytes(compressedData);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);

      debugPrint('💾 تم حفظ النسخة في Cache (${_formatBytes(compressedData.length)})');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ Cache: $e');
    }
  }

  static Future<Uint8List?> loadFromCache() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final cacheFile = File('${cacheDir.path}/$_cacheFileName');

      if (!await cacheFile.exists()) {
        debugPrint('ℹ️ لا يوجد Cache محفوظ');
        return null;
      }

      final data = await cacheFile.readAsBytes();
      debugPrint('📥 تم تحميل Cache (${_formatBytes(data.length)})');
      return Uint8List.fromList(data);
    } catch (e) {
      debugPrint('❌ خطأ في تحميل Cache: $e');
      return null;
    }
  }

  static Future<bool> isCacheValid({Duration maxAge = const Duration(hours: 24)}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);

      if (timestamp == null) return false;

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final age = DateTime.now().difference(cacheTime);

      return age < maxAge;
    } catch (e) {
      return false;
    }
  }

  static Future<void> clearCache() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final cacheFile = File('${cacheDir.path}/$_cacheFileName');

      if (await cacheFile.exists()) {
        await cacheFile.delete();
        debugPrint('🧹 تم مسح Cache');
      }
    } catch (e) {
      debugPrint('❌ خطأ في مسح Cache: $e');
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
