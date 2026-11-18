import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/repository_providers.dart';
import '../../../../services/comprehensive_appwrite_backup_service.dart';
import '../../../../services/daos/outbox_dao.dart';

/// رفع لقطة احتياطية كاملة من قاعدة البيانات المحلية إلى Appwrite.
///
/// هذا الإجراء يدوي ومقصود للحالات الإدارية فقط. يمنع الرفع عندما توجد
/// عمليات Outbox غير مُسلَّمة؛ يجب تفريغ الرفع الاعتيادي أولاً حتى لا
/// تستبدل اللقطة بيانات بعيدة أحدث.
class AppwriteBackupTab extends ConsumerStatefulWidget {
  const AppwriteBackupTab({super.key});

  @override
  ConsumerState<AppwriteBackupTab> createState() => _AppwriteBackupTabState();
}

class _AppwriteBackupTabState extends ConsumerState<AppwriteBackupTab> {
  bool _isUploading = false;
  double _progress = 0;
  String _stage = 'جاهز لإنشاء نسخة ورفعها';
  File? _lastExportedFile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_upload, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'رفع نسخة إلى Appwrite',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'ينشئ التطبيق ملف JSON من البيانات المحلية ثم يرفعه إلى مجموعات '
          'Appwrite باستخدام UUID لكل سجل. لا يحذف هذا الإجراء السجلات '
          'البعيدة غير الموجودة في النسخة المحلية، لكنه قد يحدّث سجلاً له '
          'نفس المعرّف؛ لذلك يتطلب تأكيداً صريحاً.',
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 20),
        if (_isUploading) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 10),
          Text(_stage, textAlign: TextAlign.center),
          const SizedBox(height: 20),
        ],
        ElevatedButton.icon(
          onPressed: _isUploading ? null : _confirmAndUpload,
          icon: _isUploading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(_isUploading ? 'جاري الرفع...' : 'إنشاء ورفع نسخة الآن'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_lastExportedFile != null) ...[
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_present),
              title: const Text('تم الاحتفاظ بالنسخة المحلية'),
              subtitle: Text(
                _lastExportedFile!.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmAndUpload() async {
    final db = ref.read(databaseProvider);
    final pending = await OutboxDao(db).countUndeliveredToPrimary();
    if (pending > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يمكن رفع نسخة كاملة قبل تسليم $pending تغييراً من Outbox. '
            'ارفع التغييرات الاعتيادية أولاً.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد رفع النسخة إلى Appwrite'),
        content: const Text(
          'سيُنشأ ملف نسخة احتياطية من بيانات هذا الجهاز ثم يُرفع إلى '
          'Appwrite. السجلات ذات UUID نفسه ستُحدَّث، ولن تُحذف السجلات '
          'البعيدة الأخرى. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إنشاء ورفع'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _uploadBackup();
    }
  }

  Future<void> _uploadBackup() async {
    final db = ref.read(databaseProvider);
    final backupService = ComprehensiveAppwriteBackupService();

    setState(() {
      _isUploading = true;
      _progress = 0;
      _stage = 'جاري إنشاء النسخة المحلية...';
    });

    try {
      final file = await backupService.exportFullBackup(
        db,
        onProgress: (stage, progress) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _progress = progress * 0.35;
          });
        },
      );
      if (file == null) {
        throw StateError('تعذر إنشاء ملف النسخة الاحتياطية');
      }

      if (!mounted) return;
      setState(() {
        _lastExportedFile = file;
        _stage = 'جاري رفع النسخة إلى Appwrite...';
        _progress = 0.35;
      });

      await backupService.restoreToAppwrite(
        file,
        onProgress: (stage, progress) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _progress = 0.35 + (progress * 0.65);
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _progress = 1;
        _stage = 'اكتمل رفع النسخة إلى Appwrite';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء النسخة ورفعها إلى Appwrite بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل رفع النسخة إلى Appwrite: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }
}
