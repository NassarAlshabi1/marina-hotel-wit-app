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
///
/// ✅ (2026-10-31) تُحفظ نسخة JSON في التخزين الخارجي المشترك على أندرويد
/// (/storage/emulated/0/Documents/MarinaHotelBackups/Appwrite) حتى تبقى
/// النسخة بعد إلغاء تثبيت التطبيق ويمكن نسخها يدوياً. عند رفض صلاحية
/// «جميع الملفات» نتراجع لمجلد التطبيق ونوضح ذلك للمستخدم.
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
  bool _lastSavedToExternal = false;
  String? _lastFileSize;

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
        Card(
          color: colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sd_storage, color: colorScheme.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'يُحفظ ملف النسخة في الذاكرة الخارجية',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المسار: Documents/MarinaHotelBackups/Appwrite\n'
                        'تبقى النسخة محفوظة حتى بعد حذف التطبيق، ويمكن '
                        'نسخها إلى جهاز آخر أو Google Drive يدوياً.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _lastSavedToExternal
                            ? Icons.sd_card
                            : Icons.folder_special,
                        size: 20,
                        color: _lastSavedToExternal
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastSavedToExternal
                              ? 'تم حفظ النسخة في الذاكرة الخارجية'
                              : 'حُفظت النسخة في مجلد التطبيق (لم تُمنح '
                                  'صلاحية الوصول لجميع الملفات)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _lastSavedToExternal
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _lastExportedFile!.path,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (_lastFileSize != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'الحجم: $_lastFileSize',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
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
          'سيُنشأ ملف نسخة احتياطية من بيانات هذا الجهاز (يُحفظ في الذاكرة '
          'الخارجية إن مُنحت الصلاحية) ثم يُرفع إلى Appwrite. السجلات ذات '
          'UUID نفسه ستُحدَّث، ولن تُحذف السجلات البعيدة الأخرى. '
          'هل تريد المتابعة؟',
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

      final (_, isExternal) = await backupService.getBackupDirectory();
      final sizeBytes = await file.length();

      if (!mounted) return;
      setState(() {
        _lastExportedFile = file;
        _lastSavedToExternal = isExternal;
        _lastFileSize = _formatFileSize(sizeBytes);
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
        SnackBar(
          content: Text(
            isExternal
                ? 'تم إنشاء النسخة في الذاكرة الخارجية ورفعها إلى Appwrite بنجاح'
                : 'تم إنشاء النسخة (مجلد التطبيق) ورفعها إلى Appwrite بنجاح',
          ),
          backgroundColor: isExternal ? Colors.green : Colors.orange,
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} م.ب';
  }
}
