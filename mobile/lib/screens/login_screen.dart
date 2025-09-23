import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('تسجيل الدخول', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _userCtrl,
                          decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                          validator: (v) => (v == null || v.isEmpty) ? 'أدخل اسم المستخدم' : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'كلمة المرور'),
                          validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                        ),
                        const SizedBox(height: 16),
                        if (auth.error != null)
                          Text(auth.error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _loading
                              ? null
                              : () async {
                                  if (!_formKey.currentState!.validate()) return;
                                  setState(() => _loading = true);
                                  await ref.read(authProvider.notifier).login(_userCtrl.text.trim(), _passCtrl.text);
                                  setState(() => _loading = false);
                                },
                          child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('دخول'),
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
}
