import 'package:flutter/material.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart';

class GoogleDriveSettingsScreen extends StatefulWidget {
  const GoogleDriveSettingsScreen({super.key});

  @override
  State<GoogleDriveSettingsScreen> createState() =>
      _GoogleDriveSettingsScreenState();
}

class _GoogleDriveSettingsScreenState
    extends State<GoogleDriveSettingsScreen> {
  final _driveService = GoogleDriveBackupService();
  bool _isLoading = false;
  List<GoogleDriveBackupFile> _backups = [];
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final backups = await _driveService.listBackups();
      setState(() {
        _backups = backups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'خطأ في جلب النسخ: $e';
      });
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    final success = await _driveService.signIn();
    setState(() {
      _isLoading = false;
      _statusMessage = success
          ? 'تم تسجيل الدخول بنجاح'
          : 'فشل في تسجيل الدخول';
    });
    if (success) {
      _loadBackups();
    }
  }

  Future<void> _signOut() async {
    await _driveService.signOut();
    setState(() {
      _backups = [];
      _statusMessage = 'تم تسجيل الخروج';
    });
  }

  Future<void> _createBackup() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final result = await _driveService.createBackup();

    setState(() {
      _isLoading = false;
      _statusMessage = result.message;
    });

    if (result.success) {
      _loadBackups();
    }
  }

  Future<void> _restoreBackup(String fileId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: const Text(
          'هل تريد استعادة هذه النسخة؟ سيتم استبدال البيانات الحالية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
        _statusMessage = null;
      });

      final result = await _driveService.restoreBackup(fileId);

      setState(() {
        _isLoading = false;
        _statusMessage = result.message;
      });
    }
  }

  Future<void> _deleteBackup(String fileId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف النسخة'),
        content: const Text('هل تريد حذف هذه النسخة نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _driveService.deleteBackup(fileId);
      if (success) {
        _loadBackups();
        setState(() => _statusMessage = 'تم حذف النسخة');
      } else {
        setState(() => _statusMessage = 'فشل في حذف النسخة');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _driveService.isSignedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBackups,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status card
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
                      const Text(
                        'حالة الاتصال',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isSignedIn ? 'متصل' : 'غير متصل',
                          style: TextStyle(
                            color: isSignedIn
                                ? Colors.green.shade800
                                : Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!isSignedIn)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _signIn,
                        icon: const Icon(Icons.login),
                        label: const Text('تسجيل الدخول بـ Google'),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout),
                            label: const Text('تسجيل الخروج'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _createBackup,
                            icon: const Icon(Icons.backup),
                            label: const Text('إنشاء نسخة'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Backups list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !isSignedIn
                    ? const Center(
                        child: Text(
                          'قم بتسجيل الدخول أولاً لعرض النسخ',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : _backups.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد نسخ احتياطية',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _backups.length,
                            itemBuilder: (ctx, index) {
                              final backup = _backups[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.description),
                                  title: Text(backup.name),
                                  subtitle: Text(
                                    '${_formatSize(backup.size)} • ${_formatDate(backup.modifiedTime)}',
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'restore') {
                                        _restoreBackup(backup.id);
                                      } else if (value == 'delete') {
                                        _deleteBackup(backup.id);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'restore',
                                        child: Row(
                                          children: [
                                            Icon(Icons.restore),
                                            SizedBox(width: 8),
                                            Text('استعادة'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('حذف',
                                                style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}