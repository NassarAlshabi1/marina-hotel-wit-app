import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/appwrite_realtime_sync.dart';
import '../services/auth_local_store.dart' show AuthLocalStore, AuthType;
import '../services/payment_session_context.dart';
import '../utils/app_logger.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.userType,
    this.cloudUserId,
    this.permissions = const [],
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawPerms = json['permissions'];
    final idValue = json['id'] ?? json['user_id'];
    final int parsedId;
    if (idValue is int) {
      parsedId = idValue;
    } else if (idValue is String) {
      parsedId = int.tryParse(idValue) ?? 0;
    } else {
      parsedId = 0;
    }
    return AuthUser(
      id: parsedId,
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? '').toString(),
      userType: (json['user_type'] ?? '').toString(),
      cloudUserId: json['cloud_user_id']?.toString(),
      permissions: rawPerms is List
          ? rawPerms.map((e) => e.toString()).toList()
          : const <String>[],
    );
  }
  final int id;
  final String username;
  final String fullName;
  final String userType;
  final String? cloudUserId;
  final List<String> permissions;

  String get name => fullName.isNotEmpty ? fullName : username;

  bool get isAdmin => userType == 'admin' || permissions.contains('all');

  bool canPerform(String module, String action) => AuthLocalStore.canPerform(
    userType: userType,
    permissions: permissions,
    module: module,
    action: action,
  );

  bool canAccessModule(String module) => AuthLocalStore.canAccessModule(
    userType: userType,
    permissions: permissions,
    module: module,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'full_name': fullName,
    'user_type': userType,
    'permissions': permissions,
  };

  AuthUser copyWith({List<String>? permissions}) {
    return AuthUser(
      id: id,
      username: username,
      fullName: fullName,
      userType: userType,
      permissions: permissions ?? this.permissions,
    );
  }
}

class AuthState {
  const AuthState({
    required this.isAuthenticated,
    this.isRestoring = false,
    this.error,
    this.currentUser,
    this.rememberMe = false,
    this.authType = AuthType.local,
    this.sessionInvalidated = false,
  });
  final bool isAuthenticated;
  final bool isRestoring;
  final String? error;
  final AuthUser? currentUser;
  final bool rememberMe;
  final AuthType authType;
  final bool sessionInvalidated;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isRestoring,
    String? error,
    AuthUser? currentUser,
    bool? rememberMe,
    AuthType? authType,
    bool? sessionInvalidated,
  }) => AuthState(
    isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    isRestoring: isRestoring ?? this.isRestoring,
    error: error, // null يمسح الخطأ
    currentUser: currentUser ?? this.currentUser,
    rememberMe: rememberMe ?? this.rememberMe,
    authType: authType ?? this.authType,
    sessionInvalidated: sessionInvalidated ?? this.sessionInvalidated,
  );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({AuthLocalStore? store, bool restoreSessionOnCreate = true})
    : _store = store ?? AuthLocalStore(),
      super(const AuthState(isAuthenticated: false, isRestoring: true)) {
    if (restoreSessionOnCreate) {
      restoreSession();
    }
  }

  final AuthLocalStore _store;
  Timer? _sessionCheckTimer;

  /// فحص دوري لصلاحية الجلسة — كل 30 ثانية
  void _startSessionCheck() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkSession(),
    );
  }

  void _stopSessionCheck() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = null;
  }

  /// يبدأ فحص الجلسة فقط للحسابات المخزنة في Appwrite.
  ///
  /// الحسابات المحلية الثابتة، ومنها `admin`، لا تحتاج اتصالاً بالشبكة للتحقق
  /// من جلساتها. تجاوز التحميل السحابي هنا يبقي تسجيل الدخول فورياً ويمنع
  /// انتظار مهلة الشبكة على الأجهزة الضعيفة أو في الاختبارات غير المتصلة.
  Future<void> _startCloudSessionCheckIfNeeded(AuthUser user) async {
    if (_store.isFixedAccount(user.username)) return;

    try {
      final accounts = await _store.loadCloudAccounts();
      if (accounts.containsKey(user.username)) {
        _startSessionCheck();
      }
    } catch (e) {
      dlog(() => r'Error loading cloud accounts: $e');
    }
  }

  Future<void> _checkSession() async {
    if (!state.isAuthenticated || state.currentUser == null) {
      return;
    }
    final valid = await _store.checkSessionValidity();
    if (!valid && mounted) {
      AppLogger.warning(
        'Session invalidated — credentials changed from another device',
        tag: 'AUTH',
      );
      await _store.clearSession();
      PaymentSessionContext.clear();
      _stopSessionCheck();
      state = const AuthState(
        isAuthenticated: false,
        error: 'تم تغيير بيانات الدخول من جهاز آخر. يرجى تسجيل الدخول مجدداً.',
        sessionInvalidated: true,
      );
    }
  }

  @override
  void dispose() {
    _stopSessionCheck();
    super.dispose();
  }

  void _requireAdmin() {
    if (!state.isAuthenticated || !(state.currentUser?.isAdmin ?? false)) {
      throw StateError('هذه العملية مخصصة للمسؤول فقط');
    }
  }

  Future<void> restoreSession() async {
    state = state.copyWith(isRestoring: true);

    final rememberMe = await _store.getRememberMe();
    if (!rememberMe) {
      PaymentSessionContext.clear();
      state = const AuthState(isAuthenticated: false);
      return;
    }

    final json = await _store.loadCurrentUser();
    if (json == null) {
      PaymentSessionContext.clear();
      state = const AuthState(isAuthenticated: false);
      return;
    }

    final user = AuthUser.fromJson(json);
    final authType = await _store.getAuthType();

    // التحقق من صلاحية الجلسة عند الاستعادة
    if (!_store.isFixedAccount(user.username)) {
      final valid = await _store.checkSessionValidity();
      if (!valid) {
        await _store.clearSession();
        PaymentSessionContext.clear();
        state = const AuthState(
          isAuthenticated: false,
          error:
              'تم تغيير بيانات الدخول من جهاز آخر. يرجى تسجيل الدخول مجدداً.',
          sessionInvalidated: true,
        );
        return;
      }
    }

    state = AuthState(
      isAuthenticated: true,
      currentUser: user,
      rememberMe: rememberMe,
      authType: authType,
    );
    PaymentSessionContext.start(
      userId: user.id,
      userName: user.name,
      cloudUserId: user.cloudUserId,
    );

    // يبدأ للمستخدمين السحابيين فقط؛ الحسابات المحلية لا تتصل بالشبكة.
    await _startCloudSessionCheckIfNeeded(user);

    // ✅ V-4: استئناف مستمع Realtime بعد الدخول/الاستعادة (أُوقف في
    // logout). Idempotent: start() تعود مبكراً إن كان الاستماع جارياً.
    unawaited(_resumeCloudSyncAfterLogin());
  }

  Future<void> login(
    String username,
    String password, {
    bool rememberMe = true,
  }) async {
    PaymentSessionContext.clear();
    state = state.copyWith();

    final data = await _store.validateCredentials(username, password);
    if (data == null) {
      state = const AuthState(
        isAuthenticated: false,
        error: 'اسم المستخدم أو كلمة المرور غير صحيحة',
      );
      return;
    }

    final user = AuthUser.fromJson(data);
    await _store.saveCurrentUser(user.toJson());
    await _store.setRememberMe(rememberMe);
    await _store.setAuthType(AuthType.local);

    state = AuthState(
      isAuthenticated: true,
      currentUser: user,
      rememberMe: rememberMe,
    );
    PaymentSessionContext.start(
      userId: user.id,
      userName: user.name,
      cloudUserId: user.cloudUserId,
    );

    // يبدأ للمستخدمين السحابيين فقط؛ الحسابات المحلية لا تتصل بالشبكة.
    await _startCloudSessionCheckIfNeeded(user);

    // ✅ V-4: استئناف مستمع Realtime بعد الدخول/الاستعادة (أُوقف في
    // logout). Idempotent: start() تعود مبكراً إن كان الاستماع جارياً.
    unawaited(_resumeCloudSyncAfterLogin());
  }

  Future<void> logout() async {
    _stopSessionCheck();
    PaymentSessionContext.clear();

    // ✅ V-4 (تدقيق معماري): إيقاف مستمع Realtime عند الخروج — stop()
    // تغلق الاشتراك وتفرّغ طابور الأحداث وتمنع إعادة الاتصال الإرادية.
    // الاستئناف عند تسجيل الدخول التالي (_resumeCloudSyncAfterLogin).
    await AppwriteRealtimeSync().stop();

    await _store.clearSession();
    state = const AuthState(isAuthenticated: false);
  }

  /// استئناف مستمع Realtime بعد الدخول/الاستعادة.
  ///
  /// قاعدة البيانات لا تُعاد إنشاؤها عند تسجيل الدخول
  /// (DatabaseManager.instance ثابت) لذا لا توجد نقطة إعادة تشغيل
  /// أخرى في دورة الحياة. العملية idempotent بالكامل:
  /// - initialize() تضمن جاهزية Appwrite client وقناة Realtime.
  /// - start() تعود مبكراً إذا كان الاستماع جارياً (_isListening).
  /// - بلا deviceId محفوظ (تثبيت أول) نتخطى — مسار main.dart يسجّل
  ///   الجهاز لاحقاً ويشغّل الاستماع من مساره الأساسي.
  Future<void> _resumeCloudSyncAfterLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId =
          prefs.getString('appwrite_device_id') ??
          prefs.getString('appwrite_realtime_device_id');
      if (deviceId == null) {
        return;
      }
      final realtime = AppwriteRealtimeSync();
      await realtime.initialize(deviceId: deviceId);
      await realtime.start();
    } catch (e) {
      dwarn(() => 'Resume realtime after login error: $e');
    }
  }

  Future<bool> updateUserPermissions(
    String username,
    List<String> permissions,
  ) async {
    _requireAdmin();
    final updatedCloud = await _store.setPermissions(username, permissions);
    if (state.currentUser != null && state.currentUser!.username == username) {
      final updated = state.currentUser!.copyWith(
        permissions: username == 'admin' ? ['all'] : permissions,
      );
      await _store.saveCurrentUser(updated.toJson());
      state = state.copyWith(currentUser: updated);
    }
    return updatedCloud;
  }

  Future<void> addUser({
    required String username,
    required String password,
    required String fullName,
    required String userType,
    required List<String> permissions,
  }) async {
    _requireAdmin();
    await _store.addUser(
      username: username,
      password: password,
      fullName: fullName,
      userType: userType,
      permissions: permissions,
    );
  }

  /// تحديث بيانات مستخدم سحابي (من شاشة إدارة المستخدمين)
  Future<bool> updateCloudUser({
    required String username,
    required String docId,
    String? newPassword,
    String? newFullName,
    String? newUserType,
    List<String>? newPermissions,
    bool? active,
  }) async {
    _requireAdmin();
    return _store.updateCloudUser(
      username: username,
      docId: docId,
      newPassword: newPassword,
      newFullName: newFullName,
      newUserType: newUserType,
      newPermissions: newPermissions,
      active: active,
    );
  }

  /// تحديث حساب محلي مخصص
  Future<bool> updateLocalUser({
    required String username,
    String? newPassword,
    String? newFullName,
    String? newUserType,
    List<String>? newPermissions,
  }) async {
    _requireAdmin();
    return _store.updateLocalUser(
      username: username,
      newPassword: newPassword,
      newFullName: newFullName,
      newUserType: newUserType,
      newPermissions: newPermissions,
    );
  }

  /// حذف مستخدم محلي مخصص
  Future<bool> deleteLocalUser({required String username}) async {
    _requireAdmin();
    return _store.deleteLocalUser(username);
  }

  /// حذف مستخدم سحابي
  Future<bool> deleteCloudUser({
    required String docId,
    String? username,
  }) async {
    _requireAdmin();
    if (username != null && username == state.currentUser?.username) {
      throw StateError('لا يمكن حذف الحساب المستخدم حالياً');
    }
    return _store.deleteCloudUser(docId: docId);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
