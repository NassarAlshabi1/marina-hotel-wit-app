import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';
import 'tabs/google_drive_tab.dart';
import 'tabs/local_backups_tab.dart';

/// Comprehensive Backup Screen - الشاشة الرئيسية للنسخ الاحتياطي
///
/// ✅ تحسين (audit agent-9):
/// تم إزالة تبويب "نظرة عامة" (كان mock ببيانات hardcoded من 2024-01-29)
/// وتبويب "إدارة الملفات" (كان mock بأزرار لا تعمل).
/// الآن الشاشة تحتوي فقط على التبويبات الوظيفية:
/// - Google Drive: للنسخ السحابي
/// - النسخ المحلية: للنسخ على الجهاز
///
/// كما تم:
/// - إزالة زر التحديث الذي كان يعرض snackbar كاذب دون فعل شيء
/// - إزالة عنصر "إعدادات النسخ الاحتياطي" من القائمة (كان لا يقوم بأي شيء)
/// - إبقاء "مساعدة" و"حول" فقط
class ComprehensiveBackupScreen extends ConsumerStatefulWidget {
  const ComprehensiveBackupScreen({super.key});

  @override
  ConsumerState<ComprehensiveBackupScreen> createState() =>
      _ComprehensiveBackupScreenState();
}

class _ComprehensiveBackupScreenState
    extends ConsumerState<ComprehensiveBackupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'النسخ الاحتياطي',
      actions: [
        IconButton(
          onPressed: _showHelpDialog,
          icon: const Icon(Icons.help_outline),
          tooltip: 'مساعدة',
        ),
      ],
      body: Column(
        children: [
          // Tab Bar
          ColoredBox(
            color: Colors.grey.shade100,
            child: TabBar(
              controller: _tabController,
              labelColor: UIConstants.backupColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: UIConstants.backupColor,
              tabs: const [
                Tab(icon: Icon(Icons.cloud), text: 'Google Drive'),
                Tab(icon: Icon(Icons.phone_android), text: 'النسخ المحلية'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [GoogleDriveTab(), LocalBackupsTab()],
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مساعدة'),
        content: const SingleChildScrollView(
          child: Text(
            'نظام النسخ الاحتياطي:\n\n'
            '• Google Drive: نسخ احتياطي سحابي تلقائي ويدوي\n'
            '  - يسجل الدخول بحساب Google\n'
            '  - يرفع النسخ مشفّرة ومضغوطة\n'
            '  - يدعم المزامنة التفاضلية (Delta Sync)\n\n'
            '• النسخ المحلية: نسخ على ذاكرة الجهاز\n'
            '  - إنشاء نسخة احتياطية محلية\n'
            '  - استعادة من نسخة محلية\n'
            '  - مشاركة أو حذف النسخ القديمة\n'
            '  - استيراد نسخة من ملف خارجي',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }
}
