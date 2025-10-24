import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/drive_backup_service.dart';
import '../../services/providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _isBackingUp = false;
  bool _isRestoring = false;
  List<Map<String, dynamic>> _backups = [];
  String? _lastBackupTime;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final db = ref.read(databaseProvider);
    final driveService = DriveService();
    final backupService = DriveBackupService(db, driveService);
    final backups = await backupService.listBackups();
    if (mounted) {
      setState(() {
        _backups = backups;
      });
    }
  }

  Future<void> _performBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final db = ref.read(databaseProvider);
      final driveService = DriveService();
      final backupService = DriveBackupService(db, driveService);
      final success = await backupService.backup();
      if (success && mounted) {
        _lastBackupTime = DateTime.now().toString();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم النسخ الاحتياطي بنجاح!')),
        );
        await _loadBackups();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في النسخ الاحتياطي')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _performRestore(String fileId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير!'),
        content: const Text('سيتم استبدال جميع البيانات المحلية بالنسخة المختارة. هذا العمل غير قابل للعكس.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRestoring = true);
    try {
      final db = ref.read(databaseProvider);
      final driveService = DriveService();
      final backupService = DriveBackupService(db, driveService);
      final success = await backupService.restore(fileId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الاستعادة بنجاح!')),
        );
        // Refresh app data
        ref.invalidate(roomsListProvider);
        ref.invalidate(bookingsListProvider);
        // etc.
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في الاستعادة')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الاستعادة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.backup, size: 64, color: Colors.blue),
                    const SizedBox(height: 16),
                    const Text('نسخ احتياطي لـ Google Drive', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isBackingUp ? null : _performBackup,
                      icon: _isBackingUp ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : const Icon(Icons.cloud_upload),
                      label: Text(_isBackingUp ? 'جاري النسخ...' : 'نسخ احتياطي الآن'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                    if (_lastBackupTime != null) ...[
                      const SizedBox(height: 12),
                      Text('آخر نسخ احتياطي: $_lastBackupTime', style: const TextStyle(color: Colors.green)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.restore, size: 32, color: Colors.orange),
                        const SizedBox(width: 12),
                        const Text('استعادة من Google Drive', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_backups.isEmpty)
                      const Center(child: Text('لا توجد نسخ احتياطية متاحة'))
                    else ...[
                      ..._backups.map((backup) => ListTile(
                            leading: const Icon(Icons.description),
                            title: Text(backup['name'] ?? 'Unknown'),
                            subtitle: Text('الحجم: ${(backup['size'] / 1024).toStringAsFixed(1)} KB'),
                            trailing: IconButton(
                              icon: const Icon(Icons.download, color: Colors.orange),
                              onPressed: () => _performRestore(backup['id']),
                            ),
                          )),
                    ],
                    if (_isRestoring) const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}