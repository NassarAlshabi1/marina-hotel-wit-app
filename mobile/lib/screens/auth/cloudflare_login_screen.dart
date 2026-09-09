// ═══════════════════════════════════════════════════════════════
//  cloudflare_login_screen.dart — شاشة تسجيل الدخول إلى Cloudflare
//  ✅ (2026-09-10) طلب المستخدم: «اضف شاشة تسجيل الدخول الى cloudflare»
//
//  ماذا تعرض:
//   • حالة الاتصال الحيّة (من syncStatusStream) + حالة تسجيل الدخول
//   • نقطة النهاية الفعّالة (النطاق المخصّص أو workers.dev)
//   • معرّف الجهاز واسم المستخدم الحالي
//   • رسالة آخر خطأ تهيئة (initError) إن وُجدت — بنص عربي مفهوم
//
//  ماذا تفعل:
//   • تُدخل اسم مستخدم/كلمة مرور بديلة (overrides) تُحفظ محلياً
//     وتعمل على حساب المدمج --dart-define — فيصلح «لم يتم تسجيل
//     الدخول إلى سيرفر المزامنة» دون إعادة بناء APK
//   • زر «تسجيل الدخول»: يحفظ الاعتمادات ثم initialize(forceRetry)
//   • زر «فحص الاتصال»: يصيب /health ويعرض النتيجة
//   • زر «الرجوع للاعتمادات المدمجة»: يمسح overrides
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/appwrite_providers.dart';
import '../../services/appwrite_sync_manager.dart' show SyncStatus;
import '../../services/cloudflare_config.dart';
import '../../services/worker_endpoints.dart';
import '../../utils/theme.dart';

class CloudflareLoginScreen extends ConsumerStatefulWidget {
  const CloudflareLoginScreen({super.key});

  @override
  ConsumerState<CloudflareLoginScreen> createState() =>
      _CloudflareLoginScreenState();
}

class _CloudflareLoginScreenState extends ConsumerState<CloudflareLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoggingIn = false;
  bool _isCheckingHealth = false;
  bool _obscurePassword = true;
  String? _message;
  Color? _messageColor;
  String? _healthResult;

  @override
  void initState() {
    super.initState();
    // نملأ اسم المستخدم بالقيمة الفعّالة (override أو مدمج) ليعدّل
    // فوقها بدل الكتابة من الصفر. كلمة المرور لا تُعاد أبداً — الحقل
    // فارغ = «إبقاء الحالية» كما هو موثّق أسفل الحقل.
    _usernameController.text = CloudflareConfig.username;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoggingIn = true;
      _message = null;
      _healthResult = null;
    });
    try {
      // 1) حفظ الاعتمادات (فارغ = إبقاء) — تعمل فوراً على getters
      await CloudflareConfig.setCredentialOverrides(
        username: _usernameController.text,
        password: _passwordController.text.isEmpty
            ? null
            : _passwordController.text,
      );

      // 2) تهيئة إجبارية — تُعيد تسجيل الدخول بالاعتمادات الجديدة
      final manager = ref.read(appwriteSyncManagerProvider);
      await manager.initialize(forceRetry: true, loginAttempts: 2);

      if (!mounted) return;
      setState(() {
        _isLoggingIn = false;
        if (manager.isAvailable) {
          _message = '✅ تم تسجيل الدخول بنجاح — المزامنة جاهزة';
          _messageColor = AppColors.successColor;
          _passwordController.clear();
        } else {
          _message = manager.initError ?? 'فشل تسجيل الدخول — راجع البيانات';
          _messageColor = AppColors.dangerColor;
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoggingIn = false;
        _message = 'خطأ: $e';
        _messageColor = AppColors.dangerColor;
      });
    }
  }

  Future<void> _checkHealth() async {
    setState(() {
      _isCheckingHealth = true;
      _healthResult = null;
    });
    final notifier = ref.read(connectionStatusProvider.notifier);
    await notifier.checkConnection();
    if (!mounted) return;
    final state = ref.read(connectionStatusProvider);
    setState(() {
      _isCheckingHealth = false;
      _healthResult = state.isConnected
          ? '✅ الاتصال بخادم المزامنة يعمل (${WorkerEndpoints.active})'
          : '❌ تعذر الوصول للخادم: ${state.errorMessage ?? 'غير معروف'}';
    });
  }

  Future<void> _resetOverrides() async {
    await CloudflareConfig.clearCredentialOverrides();
    if (!mounted) return;
    setState(() {
      _usernameController.text = CloudflareConfig.username;
      _passwordController.clear();
      _message = 'أُزيلت الاعتمادات المخصّصة — الرجوع للمدمجة';
      _messageColor = AppColors.infoColor;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(cloudflareSyncStatusProvider);
    final status = statusAsync.when(
      data: (s) => s,
      loading: () => SyncStatus.idle,
      error: (_, __) => SyncStatus.failed,
    );
    final workerUrl = WorkerEndpoints.active;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          title: const Text('تسجيل الدخول إلى Cloudflare'),
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── بطاقة الحالة الحالية ───
              _StatusCard(status: status, workerUrl: workerUrl),
              const SizedBox(height: 16),

              // ─── رسالة آخر خطأ تهيئة إن وُجد ───
              _buildInitErrorBanner(),

              // ─── نموذج الاعتمادات ───
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.key, color: AppColors.primaryColor),
                          SizedBox(width: 8),
                          Text(
                            'اعتمادات حساب المزامنة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'اترك كلمة المرور فارغة للإبقاء على الحالية.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_isLoggingIn,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        enabled: !_isLoggingIn,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoggingIn ? null : _login,
                        icon: _isLoggingIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          _isLoggingIn
                              ? 'جارٍ تسجيل الدخول...'
                              : 'تسجيل الدخول',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isCheckingHealth
                                  ? null
                                  : _checkHealth,
                              icon: _isCheckingHealth
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.wifi_tethering),
                              label: const Text('فحص الاتصال'),
                            ),
                          ),
                          if (CloudflareConfig.hasCredentialOverrides) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: (_isLoggingIn || _isCheckingHealth)
                                  ? null
                                  : _resetOverrides,
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: const Text('الاعتمادات المدمجة'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                _buildBanner(_message!, _messageColor ?? AppColors.infoColor),
              ],
              if (_healthResult != null) ...[
                const SizedBox(height: 8),
                _buildBanner(
                  _healthResult!,
                  ref.read(connectionStatusProvider).isConnected
                      ? AppColors.successColor
                      : AppColors.dangerColor,
                ),
              ],
              const SizedBox(height: 16),

              // ─── شرح مختصر ───
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.infoColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'تُحفظ الاعتمادات على هذا الجهاز فقط وتُستخدم مع كل عمليات '
                  'المزامنة (دفع/سحب). إذا كان workers.dev محجوباً في شبكتك '
                  'أضف نطاقاً مخصّصاً من إعدادات المزامنة أولاً.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitErrorBanner() {
    final manager = ref.watch(appwriteSyncManagerProvider);
    final initError = manager.initError;
    if (initError == null || initError.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _buildBanner(initError, AppColors.dangerColor),
    );
  }

  Widget _buildBanner(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة الحالة العلوية — لحظية عبر cloudflareSyncStatusProvider.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.workerUrl});
  final SyncStatus status;
  final String workerUrl;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      SyncStatus.syncing => (
        Icons.sync,
        Colors.blue,
        'جاري المزامنة الآن...',
      ),
      SyncStatus.success => (
        Icons.cloud_done,
        Colors.green,
        'متصل — آخر مزامنة نجحت',
      ),
      SyncStatus.failed => (
        Icons.cloud_off,
        Colors.orange,
        'آخر مزامنة فشلت — جرّب تسجيل الدخول أدناه',
      ),
      _ => (Icons.cloud_outlined, Colors.grey, 'جاهز — لا مزامنة جارية'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(Icons.dns, 'الخادم', workerUrl),
            const SizedBox(height: 6),
            _row(Icons.key, 'الحساب', CloudflareConfig.username),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
