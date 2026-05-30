import 'package:flutter/material.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart';

/// ⚠️ Google Drive Sync DISABLED
/// Sign-in/sign-out still works for authentication, but ALL
/// backup/restore/delete operations are disabled.
class GoogleDriveSettingsScreen extends StatefulWidget {
  const GoogleDriveSettingsScreen({super.key});

  @override
  State<GoogleDriveSettingsScreen> createState() =>
      _GoogleDriveSettingsScreenState();
}

class _GoogleDriveSettingsScreenState
    extends State<GoogleDriveSettingsScreen> {
  final _driveService = GoogleDriveBackupService();
  bool _isLoading = true;
  bool _isInitializing = true;
  String? _statusMessage;
  Map<String, String?> _savedUser = {};

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    setState(() => _isInitializing = true);
    
    // Get saved user info
    _savedUser = await _driveService.getSavedUser();
    
    // Try silent sign-in to restore session
    final isRestored = await _driveService.initialize();
    
    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isLoading = false;
        if (isRestored) {
          _statusMessage = 'تم استعادة الجلسة بنجاح (المزامنة معطلة)';
        } else if (_savedUser['email'] != null) {
          _statusMessage = 'آخر مستخدم: ${_savedUser['email']}';
        }
      });
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    final success = await _driveService.signIn();
    setState(() {
      _isLoading = false;
      _statusMessage = success
          ? 'تم تسجيل الدخول بنجاح (المزامنة معطلة)'
          : 'فشل في تسجيل الدخول';
    });
  }

  Future<void> _signOut() async {
    await _driveService.signOut();
    setState(() {
      _statusMessage = 'تم تسجيل الخروج';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _driveService.isSignedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive'),
      ),
      body: Column(
        children: [
          // ⚠️ Disabled banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade100,
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'مزامنة Google Drive معطلة حالياً. تسجيل الدخول متاح لكن النسخ الاحتياطي والاستعادة ومزامنة البيانات معطلة.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Status message
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: _statusMessage!.contains('نجاح') || _statusMessage!.contains('تم')
                  ? Colors.green.shade100
                  : Colors.orange.shade100,
              child: Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusMessage!.contains('نجاح') || _statusMessage!.contains('تم')
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ),

          // Sign in/out card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'حالة الاتصال',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_savedUser['email'] != null && isSignedIn)
                              Text(
                                _savedUser['email']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSignedIn
                              ? Colors.green.shade100
                              : _savedUser['email'] != null
                                  ? Colors.orange.shade100
                                  : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isSignedIn
                              ? 'متصل (معطل)'
                              : _savedUser['email'] != null
                                  ? 'جلسة محفوظة'
                                  : 'غير متصل',
                          style: TextStyle(
                            color: isSignedIn
                                ? Colors.green.shade800
                                : _savedUser['email'] != null
                                    ? Colors.orange.shade800
                                    : Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Show initialization status
                  if (_isInitializing)
                    const LinearProgressIndicator()
                  else if (!isSignedIn && _savedUser['email'] != null)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _signIn,
                            icon: const Icon(Icons.login),
                            label: const Text('استئناف الجلسة'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _signIn,
                            icon: const Icon(Icons.account_circle),
                            label: const Text('حساب جديد'),
                          ),
                        ),
                      ],
                    )
                  else if (!isSignedIn)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _signIn,
                        icon: const Icon(Icons.login),
                        label: const Text('تسجيل الدخول بـ Google'),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('تسجيل الخروج'),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Info card explaining disabled state
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'ملاحظة',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'مزامنة Google Drive معطلة حالياً. يمكنك تسجيل الدخول لكن لن يتم رفع أو تنزيل أي بيانات تلقائياً أو يدوياً.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
