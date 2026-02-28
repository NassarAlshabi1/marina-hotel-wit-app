import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../components/app_scaffold.dart';
import 'tabs/connection_tab.dart';
import 'tabs/sync_tab.dart';
import 'tabs/stats_logs_tab.dart';

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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات Appwrite الموحدة',
      actions: [
        IconButton(
          onPressed: () => _tabController.animateTo(0),
          icon: const Icon(Icons.home),
          tooltip: 'الرئيسية',
        ),
      ],
      body: Column(
        children: [
          ColoredBox(
            color: Colors.grey.shade100,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: const [
                Tab(icon: Icon(Icons.settings), text: 'عام'),
                Tab(icon: Icon(Icons.cloud_queue), text: 'الاتصال'),
                Tab(icon: Icon(Icons.bar_chart), text: 'الإحصائيات والسجلات'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                AppwriteSyncTab(),
                AppwriteConnectionTab(),
                AppwriteStatsLogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
