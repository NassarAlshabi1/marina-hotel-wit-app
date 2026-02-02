import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../components/app_scaffold.dart';
import '../../services/comprehensive_appwrite_backup_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/repository_providers.dart';

class ComprehensiveBackupScreen extends ConsumerStatefulWidget {
  const ComprehensiveBackupScreen({super.key});

  @override
  ConsumerState<ComprehensiveBackupScreen> createState() =>
      _ComprehensiveBackupScreenState();
}

class _ComprehensiveBackupScreenState
    extends ConsumerState<ComprehensiveBackupScreen> {
  final _backupService = ComprehensiveAppwriteBackupService();
  bool _isLoading = false;
  String? _statusMessage;
  double _progress = 0.0;

  // وظيفة لتصدير النسخة الاحتياطية
  Future<void> _exportBackup() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري التحضير لتصدير البيانات...';
      _progress = 0.0;
    });

    try {
      // الحصول على قاعدة البيانات من المزود
      final db = ref.read(databaseProvider);

      final file = await _backupService.exportFullBackup(
        db,
        onProgress: (msg, prog) {
          setState(() {
            _statusMessage = msg;
            _progress = prog;
          });
        },
      );

      if (file != null) {
        setState(() {
          _statusMessage = 'تم إنشاء النسخة الاحتياطية بنجاح!';
          _isLoading = false;
        });

        // عرض خيار المشاركة
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم التصدير بنجاح'),
              action: SnackBarAction(
                label: 'مشاركة',
                onPressed: () {
                  Share.shareXFiles([XFile(file.path)],
                      text: 'نسخة احتياطية Marina Hotel');
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'حدث خطأ أثناء التصدير: $e';
        _isLoading = false;
      });
    }
  }

  // وظيفة لاستيراد ورفع النسخة الاحتياطية
  Future<void> _restoreAndUpload() async {
    try {
      final file = await _backupService.pickBackupFile();
      if (file == null) return;

      setState(() {
        _isLoading = true;
        _statusMessage = 'جاري قراءة وتحليل الملف...';
        _progress = 0.0;
      });

      // تنبيه المستخدم قبل البدء
      if (mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد الاستعادة والرفع'),
            content: const Text(
                'سيقوم هذا الإجراء برفع جميع البيانات من الملف المختار إلى خادم Appwrite.\n'
                'سيتم تحديث السجلات الموجودة وإضافة السجلات الجديدة.\n\n'
                'هل أنت متأكد من المتابعة؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('بدء الرفع'),
              ),
            ],
          ),
        );

        if (confirm != true) {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
          return;
        }
      }

      await _backupService.restoreToAppwrite(
        file,
        onProgress: (msg, prog) {
          setState(() {
            _statusMessage = msg;
            _progress = prog;
          });
        },
      );

      setState(() {
        _statusMessage = 'تمت عملية الرفع والمزامنة بنجاح!';
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم رفع النسخة الاحتياطية إلى Appwrite بنجاح')),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'فشلت العملية: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'النسخ الاحتياطي الشامل (Appwrite)',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'استخدم هذه الشاشة لإنشاء نسخة احتياطية كاملة من قاعدة البيانات المحلية بتنسيق JSON، أو لرفع نسخة سابقة إلى Appwrite لتوحيد البيانات.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // زر التصدير
            _buildActionButton(
              icon: Icons.upload_file,
              label: 'تصدير نسخة محلية (JSON)',
              color: Colors.blue.shade700,
              subtitle: 'حفظ جميع البيانات في ملف واحد للمشاركة أو التخزين',
              onTap: _isLoading ? null : _exportBackup,
            ),

            const SizedBox(height: 16),

            // زر الاستيراد والرفع
            _buildActionButton(
              icon: Icons.cloud_upload,
              label: 'رفع نسخة إلى Appwrite',
              color: Colors.orange.shade800,
              subtitle: 'اختيار ملف JSON ورفعه إلى السحابة فوراً',
              onTap: _isLoading ? null : _restoreAndUpload,
            ),

            const SizedBox(height: 32),

            // حالة التقدم
            if (_isLoading || _statusMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    if (_isLoading) ...[
                      LinearProgressIndicator(
                          value: _progress > 0 ? _progress : null),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      _statusMessage ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _statusMessage?.contains('خطأ') == true
                            ? Colors.red
                            : Colors.black87,
                      ),
                    ),
                    if (_progress > 0 && _isLoading)
                      Text('${(_progress * 100).toInt()}%'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
