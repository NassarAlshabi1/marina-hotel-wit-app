import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/sync_service.dart';
import 'rooms_list.dart';
import 'rooms_dashboard.dart';

/// شاشة رئيسية للغرف مع إمكانية التبديل بين العرض التقليدي وعرض الطوابق
class RoomsMainScreen extends ConsumerStatefulWidget {
  const RoomsMainScreen({super.key});

  @override
  ConsumerState<RoomsMainScreen> createState() => _RoomsMainScreenState();
}

class _RoomsMainScreenState extends ConsumerState<RoomsMainScreen> 
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
      title: 'إدارة الغرف',
      actions: [
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
      ],
      body: Column(
        children: [
          // شريط التبويبات
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(25),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: Theme.of(context).colorScheme.primary,
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Theme.of(context).colorScheme.onPrimary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  icon: Icon(Icons.grid_view),
                  text: 'عرض الطوابق',
                ),
                Tab(
                  icon: Icon(Icons.view_list),
                  text: 'قائمة الغرف',
                ),
              ],
            ),
          ),
          // محتوى التبويبات
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                RoomsDashboard(),
                RoomsListScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}