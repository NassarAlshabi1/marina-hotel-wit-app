import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/appwrite_providers.dart' as appwrite;
import '../../providers/auto_backup_provider.dart';
import '../../providers/backup_provider.dart';
import '../../utils/theme.dart';

class GoogleDriveLoginScreen extends ConsumerStatefulWidget {
  const GoogleDriveLoginScreen({super.key});

  @override
  ConsumerState<GoogleDriveLoginScreen> createState() =>
      _GoogleDriveLoginScreenState();
}

class _GoogleDriveLoginScreenState
    extends ConsumerState<GoogleDriveLoginScreen> {
  bool _isSigningIn = false;
  bool _isCheckingSilent = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _trySilentSignIn();
  }

  /// محاولة تسجيل الدخول الصامت تلقائياً — إذا سبق تسجيل الدخول
  /// يتم الانتقال مباشرة بدون إظهار أي واجهة
  Future<void> _trySilentSignIn() async {
    try {
      await ref.read(backupStatusProvider.notifier).silentSignInToDrive();
      final state = ref.read(backupStatusProvider);
      if (state.isSignedIn && mounted) {
        // نجح تسجيل الدخول الصامت — الانتقال مباشرة
        try {
          await ref.read(autoBackupManagerProvider).setEnabled(true);
        } catch (e) {
          debugPrint('⚠️ Failed to enable auto backup after silent sign-in: $e');
        }
      }
    } catch (_) {
      // فشل الصامت — يظهر الواجهة العادية
    }
    if (mounted) {
      setState(() => _isCheckingSilent = false);
    }
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      await ref.read(backupStatusProvider.notifier).signInToDrive();
      final state = ref.read(backupStatusProvider);

      if (state.isSignedIn) {
        try {
          await ref.read(autoBackupManagerProvider).setEnabled(true);
          debugPrint('✅ تم تفعيل المزامنة التلقائية');
        } catch (e) {
          debugPrint('⚠️ خطأ في تفعيل المزامنة التلقائية: $e');
        }
        if (mounted) {
          setState(() {
            _isSigningIn = false;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = state.message ?? 'فشل تسجيل الدخول';
            _isSigningIn = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ في تسجيل الدخول: $e';
          _isSigningIn = false;
        });
      }
    }
  }

  Future<void> _handleSkip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: AppColors.warningColor,
                size: 28,
              ),
              SizedBox(width: 8),
              Text('تحذير'),
            ],
          ),
          content: const Text(
            'إذا تخطيت تسجيل الدخول إلى Google Drive:\n\n'
            '• لن تعمل المزامنة التلقائية للبيانات\n'
            '• لن يتم حفظ نسخ احتياطية سحابية\n'
            '• قد تفقد بياناتك في حالة تلف الجهاز\n\n'
            'يمكنك تسجيل الدخول لاحقاً من الإعدادات.',
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('العودة لتسجيل الدخول'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warningColor,
              ),
              child: const Text('المتابعة بدون مزامنة'),
            ),
          ],
        ),
      ),
    );

    if (confirmed ?? false) {
      await ref.read(backupStatusProvider.notifier).setSkippedDriveLogin(true);
      unawaited(_pullAppwriteOnceAfterSkip());
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    }
  }

  Future<void> _pullAppwriteOnceAfterSkip() async {
    const key = 'appwrite_pull_after_drive_skip_done';
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(key) ?? false;
      if (done) {
        return;
      }
      await prefs.setBool(key, true);

      final manager = ref.read(appwrite.appwriteSyncManagerProvider);
      await manager.initialize();
      // سحب جميع البيانات مع تعطيل Foreign Keys مؤقتاً لضمان عدم فشل السحب
      await manager.pullAllDataWithDisabledFK();
    } catch (e) {
      debugPrint('❌ Appwrite auto pull after skip error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // أثناء فحص تسجيل الدخول الصامت — إظهار مؤشر تحميل
    if (_isCheckingSilent) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundColor,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.cloud_outlined,
                        size: 80,
                        color: AppColors.primaryColor,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'تسجيل الدخول إلى Google Drive',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'للحصول على أفضل تجربة والمزامنة التلقائية للبيانات بين أجهزتك، يرجى تسجيل الدخول إلى Google Drive',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.infoColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppColors.successColor,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'مزامنة تلقائية للبيانات',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppColors.successColor,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'نسخ احتياطي آمن في السحابة',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppColors.successColor,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'إمكانية الوصول من أي جهاز',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.dangerColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppColors.dangerColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppColors.dangerColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isSigningIn ? null : _handleSignIn,
                        icon: _isSigningIn
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          _isSigningIn
                              ? 'جارٍ تسجيل الدخول...'
                              : 'تسجيل الدخول بـ Google Drive',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isSigningIn ? null : _handleSkip,
                        child: const Text(
                          'تخطي',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
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
