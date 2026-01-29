import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';
import 'tabs/connection_tab.dart';
import 'tabs/sync_tab.dart';
import 'tabs/devices_tab.dart';
import 'tabs/tools_tab.dart';

/// Appwrite Settings Screen v2 - إعدادات Appwrite المحسّنة
/// 
/// تم تقسيم الشاشة الضخمة (1361 سطر) إلى:
/// - ملف رئيسي (هذا) - ~120 سطر
/// - 4 tabs منفصلة - كل واحد ~200-250 سطر
/// 
/// Total: من 1361 سطر → ~1000 سطر موزعة على 5 ملفات
class AppwriteSettingsScreenV2 extends ConsumerStatefulWidget {
  const AppwriteSettingsScreenV2({super.key});

  @override
  ConsumerState<AppwriteSettingsScreenV2> createState() =>
      _AppwriteSettingsScreenV2State();
}

class _AppwriteSettingsScreenV2State
    extends ConsumerState<AppwriteSettingsScreenV2>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات Appwrite',
      actions: [
        IconButton(
          onPressed: _refreshAll,
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
        ),
        IconButton(
          onPressed: _showMenu,
          icon: const Icon(Icons.more_vert),
          tooltip: 'المزيد',
        ),
      ],
      body: Column(
        children: [
          // Tab Bar
          Container(
            color: Colors.grey.shade100,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              isScrollable: true,
              tabs: const [
                Tab(icon: Icon(Icons.cloud), text: 'الاتصال'),
                Tab(icon: Icon(Icons.sync), text: 'المزامنة'),
                Tab(icon: Icon(Icons.devices), text: 'الأجهزة'),
                Tab(icon: Icon(Icons.build), text: 'الأدوات'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                AppwriteConnectionTab(),
                AppwriteSyncTab(),
                AppwriteDevicesTab(),
                AppwriteToolsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _refreshAll() {
    // Trigger refresh for all tabs
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحديث البيانات...')),
    );
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('عرض السجلات'),
              onTap: () {
                Navigator.pop(context);
                // Navigate to logs
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('إحصائيات المزامنة'),
              onTap: () {
                Navigator.pop(context);
                // Navigate to stats
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('إعدادات متقدمة'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('مساعدة'),
              onTap: () {
                Navigator.pop(context);
                _showHelpDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مساعدة Appwrite'),
        content: const SingleChildScrollView(
          child: Text(
            'إدارة اتصال ومزامنة Appwrite:\n\n'
            '• الاتصال: التحقق من الاتصال وإعدادات المشروع\n'
            '• المزامنة: إدارة المزامنة والإحصائيات\n'
            '• الأجهزة: الأجهزة المسجلة والمتصلة\n'
            '• الأدوات: أدوات الصيانة والاختبار',
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
