/// القيم الافتراضية لإعدادات Appwrite
/// هذا الملف منفصل لتجنب الاعتمادية الدائرية بين AppwriteConfig و AppwriteConfigManager
class AppwriteDefaults {
  AppwriteDefaults._(); // منع الإنشاء

  /// Endpoint الافتراضي
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';

  /// Project ID الافتراضي
  static const String projectId = '690ff0da0025518570c1';

  /// Database ID الافتراضي
  static const String databaseId = 'hotel_db';
}
