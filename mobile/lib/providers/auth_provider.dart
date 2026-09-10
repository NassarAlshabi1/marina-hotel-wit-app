import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ✅ P2-1 (2026-09-09): appwrite_realtime_sync.dart حُذف - استخدم cloudflare_realtime_sync
// AppwriteRealtimeSync هو typedef لـ CloudflareRealtimeSync (cloudflare_sync_manager.dart)
import '../services/appwrite_sync_manager.dart' show AppwriteRealtimeSync;
import '../services/auth_local_store.dart' show AuthLocalStore, AuthType;
import '../services/cloudflare_auth_service.dart'
    show CloudflareAuthService, CloudflareAuthResult, CloudflareAuthStatus;
import '../services/payment_session_context.dart';
import '../utils/app_logger.dart';
import '../utils/debug_log.dart';
import '../utils/env.dart';

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
      unawaited(restoreSession());
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

    // ✅ V-4 (perf 014cc156): استئناف مستمع Realtime بعد الدخول/الاستعادة
    // (أُوقف في logout). Idempotent: start() تعود مبكراً إن كان الاستماع
    // جارياً.
    unawaited(_resumeCloudSyncAfterLogin());
  }

  Future<void> login(
    String username,
    String password, {
    bool rememberMe = true,
  }) async {
    PaymentSessionContext.clear();
    state = state.copyWith();

    // ✅ (2026-09-10) Cloudflare-first: عند ضبط Worker في البنية
    // يُتحقق من بيانات الدخول ضد الخادم (`POST /api/auth/login`) ويُخزَّن
    // JWT الجلسة. السقوط للمصادقة المحلية في الحالات التالية:
    //  - invalidCredentials: الحسابات الثابتة (admin) قد لا توجد في
    //    جدول users بـ D1 — الحكم النهائي بعد فحص المخزن المحلي.
    //  - networkError/serverError: التطبيق offline-first — انقطاع
    //    الشبكة لا يمنع الدخول.
    // أما rateLimited فالخادم حجب صراحة — يُعرض العدّاد ولا يُجرب محلياً.
    if (Env.isCloudflareConfigured) {
      final deviceId = await _currentDeviceId();
      final cf = await CloudflareAuthService().login(
        username: username,
        password: password,
        deviceId: deviceId,
      );
      if (cf.status == CloudflareAuthStatus.rateLimited) {
        state = AuthState(
          isAuthenticated: false,
          error: cf.userMessage,
          rememberMe: rememberMe,
        );
        return;
      }
      if (cf.isSuccess) {
        await _completeCloudLogin(cf, username, rememberMe);
        return;
      }
      // invalidCredentials / networkError / serverError → استمر محلياً.
    }

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

    // ✅ V-4 (perf 014cc156): استئناف مستمع Realtime بعد الدخول/الاستعادة
    // (أُوقف في logout). Idempotent: start() تعود مبكراً إن كان الاستماع
    // جارياً.
    unawaited(_resumeCloudSyncAfterLogin());
  }

  /// إنهاء جلسة دخول سحابية ناجحة: بناء [AuthUser] من رد الـ Worker
  /// مع إثرائه من المخزن المحلي (صلاحيات/اسم كامل) عند توافق الحساب،
  /// ثم حفظ الجلسة وJWT وبدء فحص الجلسة والمزامنة الفورية.
  Future<void> _completeCloudLogin(
    CloudflareAuthResult cf,
    String username,
    bool rememberMe,
  ) async {
    // إثراء البيانات من الحسابات المزامنة محلياً (app_users) — قراءة
    // خالصة بلا فحص كلمة مرور؛ الخادم هو من قرّر بصحة الاعتمادات.
    Map<String, dynamic>? localData;
    try {
      localData = (await _store.loadCloudAccounts())[username];
    } catch (_) {
      localData = null;
    }
    List<String> localPerms = const <String>[];
    if (localData != null) {
      try {
        final parsed = jsonDecode(
          localData['permissions_json'] as String? ?? '[]',
        );
        if (parsed is List) {
          localPerms = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {
        localPerms = const <String>[];
      }
    }
    final isAdmin = cf.role == 'admin';
    final user = AuthUser(
      id: localData?['id'] as int? ?? int.tryParse(cf.userId ?? '') ?? 0,
      username: username,
      fullName: (localData?['full_name'] ?? username).toString(),
      userType: isAdmin
          ? 'admin'
          : (localData?['user_type'] ?? 'user').toString(),
      cloudUserId: cf.userId ?? localData?['cloud_user_id']?.toString(),
      permissions: isAdmin ? const ['all'] : localPerms,
    );

    if (cf.token != null && cf.token!.isNotEmpty) {
      await _store.saveAuthToken(cf.token!);
    }
    await _store.saveCurrentUser(user.toJson());
    await _store.setRememberMe(rememberMe);
    await _store.setAuthType(AuthType.cloudflare);

    state = AuthState(
      isAuthenticated: true,
      currentUser: user,
      rememberMe: rememberMe,
      authType: AuthType.cloudflare,
    );
    PaymentSessionContext.start(
      userId: user.id,
      userName: user.name,
      cloudUserId: user.cloudUserId,
    );
    AppLogger.info(
      'تم تسجيل الدخول عبر Cloudflare: $username (role: ${cf.role})',
      tag: 'AUTH',
    );

    // المستخدم السحابي — فحص دوري للجلسة كما في المسار المحلي.
    await _startCloudSessionCheckIfNeeded(user);

    unawaited(_resumeCloudSyncAfterLogin());
  }

  /// معرّف الجهاز المُسجّل (نفس مفاتيح طبقة المزامنة) — يُرسل مع الدخول
  /// ليربط الـ Worker الـ JWT بالجهاز (عمود device_id في الـ token).
  Future<String> _currentDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('appwrite_device_id') ??
          prefs.getString('appwrite_realtime_device_id') ??
          '';
    } catch (_) {
      return '';
    }
  }

  Future<void> logout() async {
    _stopSessionCheck();
    // ✅ (2026-09-10) مسح JWT جلسة Cloudflare عند الخروج — JWT عديم
    // الحالة على الخادم فالإبطال محلي فقط.
    try {
      await _store.clearAuthToken();
    } catch (e) {
      dwarn(() => 'clear auth token on logout error: $e');
    }
    PaymentSessionContext.clear();

    // ✅ V-4 (تدقيق معماري — perf 014cc156): إيقاف مستمع Realtime عند
    // الخروج — stop() تغلق الاشتراك وتفرّغ طابور الأحداث وتمنع إعادة
    // الاتصال الإرادية. الاستئناف عند تسجيل الدخول التالي
    // (_resumeCloudSyncAfterLogin).
    await AppwriteRealtimeSync().stop();

    await _store.clearSession();
    state = const AuthState(isAuthenticated: false);
  }

  /// استئناف مستمع Realtime بعد الدخول/الاستعادة (V-4 — perf 014cc156).
  ///
  /// قاعدة البيانات لا تُعاد إنشاؤها عند تسجيل الدخول
  /// (DatabaseManager.instance ثابت) لذا لا توجد نقطة إعادة تشغيل
  /// أخرى في دورة الحياة. العملية idempotent بالكامل:
  /// - initialize() تضمن جاهزية قناة Realtime.
  /// - start() تعود مبكراً إذا كان الاستماع جارياً (_isListening)، وتحترم
  ///   مفتاح Dual-Run البعيد (بوابة kill-switch).
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
