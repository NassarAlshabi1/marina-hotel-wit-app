import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../services/auth_local_store.dart';
import '../../utils/theme.dart';
import '../../components/admin_layout.dart';

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
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final backupState = ref.watch(backupStatusProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.backgroundColor,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.lock, size: 28, color: AppColors.primaryColor),
                            SizedBox(width: 8),
                            Text('تسجيل الدخول', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!backupState.isSignedIn && backupState.hasSkippedDriveLogin) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'المزامنة التلقائية معطلة. يمكنك تفعيلها من الإعدادات لاحقاً.',
                                    style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                            hintText: 'أدخل اسم المستخدم',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى إدخال اسم المستخدم' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            hintText: 'أدخل كلمة المرور',
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'يرجى إدخال كلمة المرور' : null,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) => setState(() => _rememberMe = value ?? false),
                            ),
                            const Text('تذكرني'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (auth.error != null) ...[
                          Text(auth.error!, style: const TextStyle(color: AppColors.dangerColor)),
                          const SizedBox(height: 8),
                        ],
                        ElevatedButton(
                          onPressed: _submitting ? null : _onSubmit,
                          child: _submitting
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
    );
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await ref.read(authProvider.notifier).login(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text,
      rememberMe: _rememberMe,
    );
    setState(() => _submitting = false);
    final state = ref.read(authProvider);
    // سيقوم RootRouter بإظهار الواجهة الرئيسية تلقائيًا عند نجاح الدخول
  }
}