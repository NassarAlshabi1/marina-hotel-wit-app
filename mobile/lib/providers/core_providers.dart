import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';

final syncProvider = Provider<SyncService>(
  (ref) => SyncService(DatabaseManager.instance),
);

/// ✅ إصدار التطبيق الكامل (version+buildNumber) — يُقرأ من package_info_plus.
///
/// مصدر واحد موحّد لكل الشاشات التي تحتاج عرض رقم الإصدار (لوحة التحكم،
/// الإعدادات، شاشة الصيانة، النسخ الاحتياطي). يُحمل مرة واحدة فقط عبر
/// Riverpod cache.
///
/// الصيغة: "1.2.0+3" (version من pubspec.yaml + buildNumber من Gradle/xcconfigs).
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    // Fallback ثابت في حال فشل package_info_plus (نادراً، يحدث فقط في
    // اختبارات الوحدة بدون Flutter binding مهيّأ).
    return '1.2.0+3';
  }
});
