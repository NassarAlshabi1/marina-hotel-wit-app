import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../services/auth_local_store.dart';
import '../../services/cloudflare_auth_service.dart';
import '../../utils/env.dart';
import '../../utils/performance_config.dart';
import '../../utils/performance_monitor.dart';
import '../../utils/theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  bool _rememberMe = true;

  // ✅ (2026-09-10) حالة اتصال Cloudflare — مؤشر حي أعلى الشاشة.
  // null = جاري الفحص، true = متصل، false = وضع محلي.
  bool? _cloudOnline;
  CloudflareAuthService? _cfAuth;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRememberMe());
    unawaited(_checkCloudConnection());
  }

  /// فحص توفر الـ Worker — فقط عند ضبطه في البنية؛ وإلا الشاشة محلية
  /// منذ البداية (بيئات الاختبار/البنيات بلا سحابة لا تتصل إطلاقاً).
  Future<void> _checkCloudConnection() async {
    if (!Env.isCloudflareConfigured) {
      if (mounted) setState(() => _cloudOnline = false);
      return;
    }
    _cfAuth ??= CloudflareAuthService();
    final online = await _cfAuth!.checkHealth();
    if (mounted) setState(() => _cloudOnline = online);
  }

  Future<void> _loadRememberMe() async {
    final store = AuthLocalStore();
    final rememberMe = await store.getRememberMe();
    if (mounted) {
      setState(() => _rememberMe = rememberMe);
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _cfAuth?.dispose();
    super.dispose();
  }

  /// شريط حالة الاتصال بـ Cloudflare — نقطة ملونة + نص، وزر إعادة
  /// فحص عند الفشل. بلا حواف ملوّنة صارخة: التطبيق offline-first
  /// والوضع المحلي ليس خطأً بل تدهور مقصود للخدمة.
  Widget _buildCloudStatusBanner() {
    final checking = _cloudOnline == null;
    final online = _cloudOnline == true;
    final color = checking
        ? Colors.grey
        : (online ? AppColors.successColor : Colors.orange);
    final label = checking
        ? 'جاري فحص الاتصال بـ Cloudflare…'
        : online
        ? 'متصل بـ Cloudflare — التحقق عبر الخادم'
        : 'وضع محلي — تحقق محلي من بيانات الدخول';
    return Row(
      children: [
        if (checking)
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          )
        else
          Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: color),
          ),
        ),
        if (!checking && !online && Env.isCloudflareConfigured)
          GestureDetector(
            onTap: () {
              setState(() => _cloudOnline = null);
              unawaited(_checkCloudConnection());
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.refresh, size: 18, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return PerformanceInspector(
      name: 'LoginScreen',
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppColors.backgroundColor,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: isLowEndDevice ? 0 : null,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.lock,
                                size: 28,
                                color: AppColors.primaryColor,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'تسجيل الدخول',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildCloudStatusBanner(),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _usernameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'اسم المستخدم',
                              hintText: 'أدخل اسم المستخدم',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'يرجى إدخال اسم المستخدم'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              hintText: 'أدخل كلمة المرور',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'يرجى إدخال كلمة المرور'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (value) => setState(
                                  () => _rememberMe = value ?? false,
                                ),
                              ),
                              const Text('تذكرني'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (auth.error != null) ...[
                            Text(
                              auth.error!,
                              style: const TextStyle(
                                color: AppColors.dangerColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          ElevatedButton(
                            onPressed: _submitting ? null : _onSubmit,
                            child: _submitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('دخول'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    await ref
        .read(authProvider.notifier)
        .login(
          _usernameCtrl.text.trim(),
          _passwordCtrl.text,
          rememberMe: _rememberMe,
        );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    // سيقوم RootRouter بإظهار الواجهة الرئيسية تلقائيًا عند نجاح الدخول
  }
}
