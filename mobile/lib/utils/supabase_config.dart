/// تم تعطيل تكامل Supabase. يحتفظ هذا الملف بواجهة بسيطة للحفاظ على التوافق.
class SupabaseConfig {
  static Future<void> initialize() async {}

  static bool get isLoggedIn => false;

  static Future<bool> testConnection() async => false;

  static Map<String, String> getProjectInfo() => const {
        'project_url': 'غير متاح',
        'project_id': 'N/A',
      };

  static dynamic get client => null;
}
