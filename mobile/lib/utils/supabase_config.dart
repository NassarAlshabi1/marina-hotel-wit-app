// ============================================================================
// Marina Hotel - Supabase Configuration
// إعدادات Supabase - التكوين والإعداد الأولي
// Supabase configuration and initialization
// ============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// إعدادات Supabase
/// 
/// Supabase Configuration
/// 
/// يجب تحديث هذه القيم بقيم مشروع Supabase الخاص بك
/// Update these values with your Supabase project credentials
class SupabaseConfig {
  /// Supabase Project URL
  /// 
  /// احصل عليه من: Project Settings > API > Project URL
  /// Get it from: Project Settings > API > Project URL
  /// 
  /// Example: https://xxxxxxxxxxx.supabase.co
  static const String supabaseUrl = 'https://mjsexsrrjphcgpvqcisb.supabase.co';

  /// Supabase Anonymous Key
  /// 
  /// احصل عليه من: Project Settings > API > Project API keys > anon public
  /// Get it from: Project Settings > API > Project API keys > anon public
  /// 
  /// هذا المفتاح آمن للاستخدام في التطبيق لأن RLS مفعّل
  /// This key is safe to use in the app because RLS is enabled
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1qc2V4c3JyanBoY2dwdnFjaXNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIwMzk2ODAsImV4cCI6MjA3NzYxNTY4MH0.8mLsJqum971em7zG1Mv2h3zj8hg06KzsMXQAXsBbniA';

  /// Service Role Key (للاستخدام في السيرفر فقط)
  /// 
  /// ⚠️ لا تستخدم هذا المفتاح في التطبيق! استخدمه فقط في Edge Functions
  /// ⚠️ DO NOT use this key in the app! Use it only in Edge Functions
  /// 
  /// احصل عليه من: Project Settings > API > Project API keys > service_role
  /// Get it from: Project Settings > API > Project API keys > service_role
  static const String supabaseServiceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1qc2V4c3JyanBoY2dwdnFjaXNiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MjAzOTY4MCwiZXhwIjoyMDc3NjE1NjgwfQ.KeX9eFC8hD0wMI_7xK84mg6pSNtLVam-y_rel5QqMKQ';

  /// تهيئة Supabase
  /// 
  /// Initialize Supabase
  /// 
  /// يجب استدعاء هذه الدالة في main() قبل runApp()
  /// This function must be called in main() before runApp()
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // تمكين التحديث التلقائي للـ token
        // Enable auto token refresh
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        // تفعيل Realtime للتحديثات الفورية
        // Enable Realtime for instant updates
        eventsPerSecond: 10,
        logLevel: RealtimeLogLevel.info,
      ),
      postgrestOptions: const PostgrestClientOptions(
        schema: 'public',
      ),
      storageOptions: const StorageClientOptions(
        retryAttempts: 3,
      ),
    );

    debugPrint('✅ Supabase initialized successfully');
    debugPrint('🌐 URL: $supabaseUrl');
  }

  /// الحصول على Supabase Client
  /// 
  /// Get Supabase Client
  static SupabaseClient get client => Supabase.instance.client;

  /// التحقق من حالة تسجيل الدخول
  /// 
  /// Check if user is logged in
  static bool get isLoggedIn => client.auth.currentUser != null;

  /// الحصول على المستخدم الحالي
  /// 
  /// Get current user
  static User? get currentUser => client.auth.currentUser;

  /// الحصول على JWT token للمستخدم الحالي
  /// 
  /// Get JWT token for current user
  static Future<String?> get currentToken async {
    final session = client.auth.currentSession;
    return session?.accessToken;
  }

  /// تسجيل الدخول بالبريد الإلكتروني وكلمة المرور
  /// 
  /// Sign in with email and password
  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        debugPrint('✅ User signed in: ${response.user!.email}');
      }

      return response;
    } catch (e) {
      debugPrint('❌ Sign in error: $e');
      rethrow;
    }
  }

  /// التسجيل بالبريد الإلكتروني وكلمة المرور
  /// 
  /// Sign up with email and password
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );

      if (response.user != null) {
        debugPrint('✅ User signed up: ${response.user!.email}');
      }

      return response;
    } catch (e) {
      debugPrint('❌ Sign up error: $e');
      rethrow;
    }
  }

  /// تسجيل الخروج
  /// 
  /// Sign out
  static Future<void> signOut() async {
    try {
      await client.auth.signOut();
      debugPrint('✅ User signed out');
    } catch (e) {
      debugPrint('❌ Sign out error: $e');
      rethrow;
    }
  }

  /// إعادة تعيين كلمة المرور
  /// 
  /// Reset password
  static Future<void> resetPassword({
    required String email,
  }) async {
    try {
      await client.auth.resetPasswordForEmail(email);
      debugPrint('✅ Password reset email sent to: $email');
    } catch (e) {
      debugPrint('❌ Reset password error: $e');
      rethrow;
    }
  }

  /// الاستماع لتغييرات حالة المصادقة
  /// 
  /// Listen to auth state changes
  static Stream<AuthState> get authStateChanges {
    return client.auth.onAuthStateChange;
  }

  /// استدعاء Edge Function
  /// 
  /// Invoke Edge Function
  static Future<FunctionResponse> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await client.functions.invoke(
        functionName,
        body: body,
        headers: headers,
      );

      return response;
    } catch (e) {
      debugPrint('❌ Function invoke error: $e');
      rethrow;
    }
  }

  /// التحقق من اتصال Supabase
  /// 
  /// Test Supabase connection
  static Future<bool> testConnection() async {
    try {
      // محاولة قراءة جدول sync_state للتحقق من الاتصال
      // Try to read sync_state table to test connection
      final response = await client.from('sync_state').select('id').limit(1);

      if (response != null) {
        debugPrint('✅ Supabase connection successful');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Supabase connection failed: $e');
      return false;
    }
  }

  /// الحصول على معلومات المشروع
  /// 
  /// Get project information
  static Map<String, dynamic> getProjectInfo() {
    return {
      'url': supabaseUrl,
      'is_logged_in': isLoggedIn,
      'user_email': currentUser?.email,
      'user_id': currentUser?.id,
    };
  }
}

/// Extension لتسهيل الوصول إلى Supabase Client
/// 
/// Extension for easy access to Supabase Client
extension SupabaseExtension on BuildContext {
  SupabaseClient get supabase => Supabase.instance.client;
}

/// ملاحظات مهمة:
/// 
/// Important Notes:
/// 
/// 1. يجب تحديث supabaseUrl و supabaseAnonKey بقيم مشروعك
///    You must update supabaseUrl and supabaseAnonKey with your project values
/// 
/// 2. لا تستخدم supabaseServiceRoleKey في التطبيق، استخدمه فقط في Edge Functions
///    Do not use supabaseServiceRoleKey in the app, use it only in Edge Functions
/// 
/// 3. يجب استدعاء SupabaseConfig.initialize() في main() قبل runApp()
///    You must call SupabaseConfig.initialize() in main() before runApp()
/// 
/// 4. مثال على الاستخدام في main.dart:
///    Example usage in main.dart:
/// 
///    void main() async {
///      WidgetsFlutterBinding.ensureInitialized();
///      await SupabaseConfig.initialize();
///      runApp(MyApp());
///    }
/// 
/// 5. للحصول على Supabase Client في أي مكان:
///    To get Supabase Client anywhere:
/// 
///    final supabase = SupabaseConfig.client;
///    // أو
///    // or
///    final supabase = Supabase.instance.client;
/// 
/// 6. يمكنك استخدام المتغيرات البيئية بدلاً من القيم الثابتة:
///    You can use environment variables instead of hardcoded values:
/// 
///    static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
///    static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
