import 'package:flutter/material.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart';
import 'package:marina_hotel_mobile/providers/backup_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ✅ Google Drive: BACKUP & RESTORE ONLY
/// Sign-in/sign-out works for authentication.
/// Backup (create/list/delete) and Restore operations are fully functional.
/// All SYNC operations (auto-sync, delta sync, real-time sync) remain disabled.
class GoogleDriveSettingsScreen extends ConsumerStatefulWidget {
  const GoogleDriveSettingsScreen({super.key});

  @override
  ConsumerState<GoogleDriveSettingsScreen> createState() =>
      _GoogleDriveSettingsScreenState();
}

class _GoogleDriveSettingsScreenState
    extends ConsumerState<GoogleDriveSettingsScreen> {
  final _driveService = GoogleDriveBackupService();
  bool _isLoading = true;
  bool _isInitializing = true;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isDeleting = false;
  String? _statusMessage;
  Map<String, String?> _savedUser = {};
  List<GoogleDriveBackupFile> _backups = [];
  DateTime? _lastBackupTime;

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

    // Load last backup time
    final lastBackup = await _driveService.getLastBackupTime();

    // If signed in, load backup list
    List<GoogleDriveBackupFile> backups = [];
    if (_driveService.isSignedIn) {
      try {
        backups = await _driveService.listBackupFiles();
      } catch (e) {
        // Ignore errors loading backup list
      }
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isLoading = false;
        _backups = backups;
        _lastBackupTime = lastBackup;
        if (isRestored) {
          _statusMessage = 'تم استعادة الجلسة بنجاح';
        } else if (_savedUser['email'] != null) {
          _statusMessage = 'آخر مستخدم: ${_savedUser['email']}';
        }
      });
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    final success = await _driveService.signIn();
    List<GoogleDriveBackupFile> backups = [];
    if (success) {
      try {
        backups = await _driveService.listBackupFiles();
      } catch (_) {}
      // Also update backup provider
      ref.invalidate(backupStatusProvider);
    }
    setState(() {
      _isLoading = false;
      _backups = backups;
      _statusMessage = success
          ? 'تم تسجيل الدخول بنجاح - يمكنك إنشاء نسخ احتياطية واستعادتها'
          : 'فشل في تسجيل الدخول';
    });
  }

  Future<void> _signOut() async {
    await _driveService.signOut();
    ref.invalidate(backupStatusProvider);
    setState(() {
      _statusMessage = 'تم تسجيل الخروج';
      _backups = [];
    });
  }

  Future<void> _createBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final result = await _driveService.createBackup();
      if (result.success) {
        // Refresh backup list
        final backups = await _driveService.listBackupFiles();
        final lastBackup = await _driveService.getLastBackupTime();
        setState(() {
          _backups = backups;
          _lastBackupTime = lastBackup;
          _statusMessage = 'تم إنشاء النسخة الاحتياطية بنجاح (${result.recordCount ?? 0} سجل)';
        });
        ref.invalidate(backupStatusProvider);
      } else {
        setState(() {
          _statusMessage = 'فشل إنشاء النسخة الاحتياطية: ${result.message}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ في إنشاء النسخة الاحتياطية: $e';
      });
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreBackup(GoogleDriveBackupFile backup) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Text(
          'سيتم استبدال جميع البيانات الحالية بالنسخة الاحتياطية:\n'
          '${backup.name}\n'
          'التاريخ: ${_formatDate(backup.modifiedTime)}\n\n'
          'هل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('استعادة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);
    try {
      // Use backup provider for restore (handles download, fix service, etc.)
      await ref.read(backupStatusProvider.notifier).restoreFromBackup(backup.id);

      setState(() {
        _statusMessage = 'تم استعادة النسخة الاحتياطية بنجاح';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ في استعادة النسخة الاحتياطية: $e';
      });
    } finally {
      setState(() => _isRestoring = false);
    }
  }

  Future<void> _deleteBackup(GoogleDriveBackupFile backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
          'سيتم حذف النسخة الاحتياطية:\n${backup.name}\n\nهل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      final success = await _driveService.deleteBackup(backup.id);
      if (success) {
        setState(() {
          _backups.removeWhere((b) => b.id == backup.id);
          _statusMessage = 'تم حذف النسخة الاحتياطية بنجاح';
        });
      } else {
        setState(() {
          _statusMessage = 'فشل حذف النسخة الاحتياطية';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ في حذف النسخة الاحتياطية: $e';
      });
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _refreshBackups() async {
    if (!_driveService.isSignedIn) return;
    setState(() => _isLoading = true);
    try {
      final backups = await _driveService.listBackupFiles();
      setState(() {
        _backups = backups;
        _statusMessage = 'تم تحديث القائمة (${backups.length} نسخة)';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ في تحديث القائمة: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
          // Info banner: Backup & Restore only
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade100,
            child: Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.blue.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Google Drive مخصص للنسخ الاحتياطي والاستعادة فقط. المزامنة التلقائية معطلة.',
                    style: TextStyle(
                      color: Colors.blue.shade800,
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
              padding: const EdgeInsets.all(12),
              color: _statusMessage!.contains('نجاح') || _statusMessage!.contains('تم')
                  ? Colors.green.shade100
                  : _statusMessage!.contains('فشل') || _statusMessage!.contains('خطأ')
                      ? Colors.red.shade100
                      : Colors.blue.shade100,
              child: Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusMessage!.contains('نجاح') || _statusMessage!.contains('تم')
                      ? Colors.green.shade800
                      : _statusMessage!.contains('فشل') || _statusMessage!.contains('خطأ')
                          ? Colors.red.shade800
                          : Colors.blue.shade800,
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
                            if (_lastBackupTime != null)
                              Text(
                                'آخر نسخة: ${_formatDate(_lastBackupTime!)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
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
                              ? 'متصل'
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
                  else ...[
                    // Backup/Restore action buttons (when signed in)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isBackingUp ? null : _createBackup,
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.cloud_upload),
                            label: Text(_isBackingUp ? 'جارٍ النسخ...' : 'نسخ احتياطي'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _refreshBackups,
                            icon: const Icon(Icons.refresh),
                            label: const Text('تحديث القائمة'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _signOut,
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

          // Backup files list
          if (isSignedIn) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'النسخ الاحتياطية',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${_backups.length} نسخة',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _backups.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'لا توجد نسخ احتياطية',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _isBackingUp ? null : _createBackup,
                            icon: const Icon(Icons.cloud_upload),
                            label: const Text('إنشاء نسخة احتياطية الآن'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _backups.length,
                      itemBuilder: (context, index) {
                        final backup = _backups[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              Icons.cloud_circle,
                              color: Colors.blue.shade400,
                            ),
                            title: Text(
                              backup.name,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_formatDate(backup.modifiedTime)} - ${_formatSize(backup.size)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Restore button
                                IconButton(
                                  onPressed: _isRestoring
                                      ? null
                                      : () => _restoreBackup(backup),
                                  icon: _isRestoring
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.restore, color: Colors.orange),
                                  tooltip: 'استعادة',
                                ),
                                // Delete button
                                IconButton(
                                  onPressed: _isDeleting
                                      ? null
                                      : () => _deleteBackup(backup),
                                  icon: _isDeleting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Icon(Icons.delete, color: Colors.red.shade400),
                                  tooltip: 'حذف',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],

          // Info card explaining the mode
          if (!isSignedIn)
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
                      'Google Drive مخصص للنسخ الاحتياطي والاستعادة فقط. '
                      'يمكنك تسجيل الدخول وإنشاء نسخ احتياطية يدوياً واستعادتها في أي وقت. '
                      'المزامنة التلقائية معطلة.',
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
