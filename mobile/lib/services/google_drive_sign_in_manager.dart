import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kGoogleDriveScopes = [
  drive.DriveApi.driveFileScope,
  drive.DriveApi.driveAppdataScope,
];

const String kGoogleDriveServerClientId =
    '256666337807-561s7dakv86m3kugsalv8opa8idkjmd0.apps.googleusercontent.com';

const String _prefsWasSignedInKey = 'google_drive_was_signed_in';
const String _prefsSignedInEmailKey = 'google_drive_signed_in_email';

/// ✅ مدير تسجيل الدخول الموحّد لـ Google Drive
///
/// مصدر واحد للحقيقة لكائن [GoogleSignIn] — جميع الخدمات
/// (BackupService, SyncService, AlarmBackup) تستخدم نفس النسخة
/// لضمان مشاركة حالة الجلسة وتجنب تضارب الصلاحيات.
///
/// يوفّر أيضاً تتبّع حالة الجلسة في [SharedPreferences] بحيث
/// يمكن للتطبيق معرفة أن المستخدم سبق له تسجيل الدخول حتى
/// لو فشل `signInSilently()` مؤقتاً.
class GoogleDriveSignInManager {
  GoogleDriveSignInManager._();

  static final GoogleDriveSignInManager instance = GoogleDriveSignInManager._();

  GoogleSignIn? _client;

  /// كائن [GoogleSignIn] الموحّد — يتضمن جميع الصلاحيات و serverClientId
  GoogleSignIn get client {
    _client ??= GoogleSignIn(
      scopes: kGoogleDriveScopes,
      serverClientId: kGoogleDriveServerClientId,
    );
    return _client!;
  }

  /// الحساب الحالي (مُختصر)
  GoogleSignInAccount? get currentUser => client.currentUser;

  /// هل المستخدم مسجّل الدخول حالياً؟
  bool get isSignedIn => client.currentUser != null;

  // ──────────────────────────────────────────────────────────
  //  تتبّع حالة الجلسة بشكل دائم
  // ──────────────────────────────────────────────────────────

  /// حفظ حالة تسجيل الدخول في SharedPreferences
  ///
  /// يُستدعى بعد نجاح تسجيل الدخول (صامت أو تفاعلي)
  /// وكذلك بعد تسجيل الخروج.
  Future<void> persistSignInState(GoogleSignInAccount? account) async {
    final prefs = await SharedPreferences.getInstance();
    if (account != null) {
      await prefs.setBool(_prefsWasSignedInKey, true);
      await prefs.setString(_prefsSignedInEmailKey, account.email);
    } else {
      await prefs.setBool(_prefsWasSignedInKey, false);
      await prefs.remove(_prefsSignedInEmailKey);
    }
  }

  /// هل سبق للمستخدم تسجيل الدخول من قبل؟
  ///
  /// يُستخدم لمعرفة ما إذا كان يجب محاولة تسجيل الدخول الصامت
  /// حتى لو لم يكن هناك حساب حالي.
  Future<bool> wasPreviouslySignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsWasSignedInKey) ?? false;
  }

  /// البريد الإلكتروني لآخر حساب مسجّل
  Future<String?> getLastSignedInEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsSignedInEmailKey);
  }

  // ──────────────────────────────────────────────────────────
  //  عمليات تسجيل الدخول الموحّدة
  // ──────────────────────────────────────────────────────────

  /// محاولة تسجيل الدخول الصامت — تستعيد الجلسة بدون تفاعل المستخدم
  ///
  /// تُرجع الحساب إذا نجح، أو `null` إذا لم تكن هناك جلسة محفوظة.
  /// تحفظ حالة الجلسة تلقائياً عند النجاح.
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      final account = await client.signInSilently();
      if (account != null) {
        await persistSignInState(account);
      }
      return account;
    } catch (e) {
      return null;
    }
  }

  /// تسجيل الدخول التفاعلي — يعرض واجهة اختيار الحساب
  ///
  /// يحاول الصامت أولاً، ثم التفاعلي إذا فشل.
  /// يحفظ حالة الجلسة عند النجاح.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      // محاولة صامتة أولاً
      var account = await client.signInSilently();
      account ??= await client.signIn();
      if (account != null) {
        await persistSignInState(account);
      }
      return account;
    } catch (e) {
      return null;
    }
  }

  /// تسجيل الخروج — يمسح الجلسة والحالة المحفوظة
  Future<void> signOut() async {
    try {
      await client.signOut();
    } catch (e) {
      debugPrint('⚠️ Swallowed error in google_drive_sign_in_manager.dart: ');
    }
    await persistSignInState(null);
  }

  /// استمع لتغييرات الحساب (مثلاً عند إلغاء الصلاحية من الإعدادات)
  Stream<GoogleSignInAccount?> get onCurrentUserChanged =>
      client.onCurrentUserChanged;
}
