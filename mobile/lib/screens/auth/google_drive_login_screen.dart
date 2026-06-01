import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_mobile/providers/backup_provider.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart';

/// ✅ Google Drive Login Screen - مع حفظ الجلسة 350 يوماً
class GoogleDriveLoginScreen extends ConsumerStatefulWidget {
  const GoogleDriveLoginScreen({super.key});

  @override
  ConsumerState<GoogleDriveLoginScreen> createState() => _GoogleDriveLoginScreenState();
}

class _GoogleDriveLoginScreenState extends ConsumerState<GoogleDriveLoginScreen> {
  Map<String, String?> _sessionInfo = {};
  bool _loadingSession = true;

  @override
  void initState() {
    super.initState();
    _loadSessionInfo();
  }

  Future<void> _loadSessionInfo() async {
    final service = GoogleDriveBackupService();
    final info = await service.getSavedUser();
    if (mounted) {
      setState(() {
        _sessionInfo = info;
        _loadingSession = false;
      });
    }
  }

  String _formatRemainingDays(String? validUntilStr) {
    if (validUntilStr == null) return '';
    try {
      final validUntil = DateTime.parse(validUntilStr);
      final remaining = validUntil.difference(DateTime.now());
      if (remaining.isNegative) {
        return 'منتهية الصلاحية';
      }
      final days = remaining.inDays;
      if (days > 0) {
        return '$days يوماً متبقية';
      }
      final hours = remaining.inHours;
      if (hours > 0) {
        return '$hours ساعة متبقية';
      }
      return 'تنتهي قريباً';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 80,
                color: Colors.blue.shade300,
              ),
              const SizedBox(height: 24),
              const Text(
                'Google Drive',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'نسخ احتياطي واستعادة فقط',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                'المزامنة التلقائية معطلة',
                style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
              ),
              const SizedBox(height: 32),
              if (!backupState.isSignedIn)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref.read(backupStatusProvider.notifier).signInToDrive();
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('تسجيل الدخول بـ Google'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 40),
                        const SizedBox(height: 8),
                        const Text(
                          'متصل بـ Google Drive',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (backupState.signedInAccount != null)
                          Text(
                            backupState.signedInAccount!.email,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'النسخ الاحتياطي والاستعادة متاحان',
                          style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                        ),
                        // ─── عرض صلاحية الجلسة ───
                        if (_sessionInfo['sessionValidUntil'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule, size: 14, color: Colors.green.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    'الجلسة صالحة: ${_formatRemainingDays(_sessionInfo['sessionValidUntil'])}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(backupStatusProvider.notifier).signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
