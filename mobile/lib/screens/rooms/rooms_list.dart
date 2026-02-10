import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/price_adjustment_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/theme.dart';
import '../../utils/status_utils.dart';

import '../../providers/auth_provider.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/core_providers.dart';

class RoomsListScreen extends ConsumerStatefulWidget {
  const RoomsListScreen({super.key});

  @override
  ConsumerState<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends ConsumerState<RoomsListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'rooms_list';

  String _searchQuery = '';
  String? _statusFilter;
  String? _typeFilter;
  bool _isGridView = true;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Room> _filterRooms(List<Room> rooms) {
    return rooms.where((room) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!room.roomNumber.toLowerCase().contains(query) &&
            !room.type.toLowerCase().contains(query)) {
          return false;
        }
      }
      if (_statusFilter != null && room.status != _statusFilter) {
        return false;
      }
      if (_typeFilter != null && room.type != _typeFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  Map<String, List<Room>> _groupByFloor(List<Room> rooms) {
    final Map<String, List<Room>> floorMap = {};
    for (final room in rooms) {
      String floorNumber = '0';
      if (room.roomNumber.isNotEmpty) {
        floorNumber = room.roomNumber[0];
      }
      floorMap.putIfAbsent(floorNumber, () => []).add(room);
    }
    for (final floor in floorMap.keys) {
      floorMap[floor]!.sort((a, b) {
        final aNum = int.tryParse(a.roomNumber);
        final bNum = int.tryParse(b.roomNumber);
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        return a.roomNumber.compareTo(b.roomNumber);
      });
    }
    return floorMap;
  }

  Set<String> _getUniqueTypes(List<Room> rooms) {
    return rooms.map((r) => r.type).where((t) => t.isNotEmpty).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final roomsStream = ref.watch(roomsListProvider);
    final auth = ref.watch(authProvider);
    final canRooms =
        auth.currentUser?.permissions.contains('all') == true ||
        auth.currentUser?.userType == 'admin' ||
        (auth.currentUser?.permissions.contains('rooms') ?? false);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'إدارة الغرف',
        actions: [
          IconButton(
            onPressed: () => setState(() => _isGridView = !_isGridView),
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: _isGridView ? 'عرض قائمة' : 'عرض شبكي',
          ),
          if (canRooms)
            IconButton(
              onPressed: () => _editRoom(context, ref),
              icon: const Icon(Icons.add),
              tooltip: 'إضافة غرفة',
            ),
        ],
        body: roomsStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('خطأ: $e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(roomsListProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: (rooms) {
            if (rooms.isEmpty) {
              return _buildEmptyState(canRooms);
            }
            
            return _isGridView
                ? _buildGridView(rooms, canRooms)
                : _buildListView(rooms, canRooms);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool canAdd) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              Icons.hotel,
              size: 50,
              color: AppColors.primaryColor.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'لا توجد غرف مسجلة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'ابدأ بإضافة الغرف لإدارة الفندق',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          if (canAdd) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _editRoom(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('إضافة غرفة'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'لا توجد نتائج',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'جرب تغيير معايير البحث',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.clear_all),
            label: const Text('مسح الفلاتر'),
          ),
        ],
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _statusFilter = null;
      _typeFilter = null;
    });
  }

  Widget _buildStatsBar(List<Room> rooms) {
    final totalRooms = rooms.length;
    final availableRooms = rooms.where((r) => StatusUtils.isRoomAvailable(r.status)).length;
    final occupiedRooms = totalRooms - availableRooms;
    final occupancyRate = totalRooms > 0 ? (occupiedRooms / totalRooms * 100) : 0.0;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryColor.withOpacity(0.1),
            AppColors.primaryLight.withOpacity(0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _buildStatItem(
            icon: Icons.hotel,
            label: 'الإجمالي',
            value: totalRooms.toString(),
            color: AppColors.infoColor,
          )),
          _buildDivider(),
          Expanded(child: _buildStatItem(
            icon: Icons.check_circle,
            label: 'شاغرة',
            value: availableRooms.toString(),
            color: AppColors.successColor,
          )),
          _buildDivider(),
          Expanded(child: _buildStatItem(
            icon: Icons.block,
            label: 'محجوزة',
            value: occupiedRooms.toString(),
            color: AppColors.dangerColor,
          )),
          _buildDivider(),
          Expanded(child: _buildStatItem(
            icon: Icons.percent,
            label: 'نسبة الإشغال',
            value: '${occupancyRate.toStringAsFixed(0)}%',
            color: occupancyRate > 70 
                ? AppColors.successColor 
                : (occupancyRate > 40 ? AppColors.warningColor : AppColors.dangerColor),
          )),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 50,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppColors.dividerColor,
    );
  }

  Widget _buildSearchAndFilters(Set<String> uniqueTypes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'بحث برقم الغرفة أو النوع...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.lightGray),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'الكل',
                  selected: _statusFilter == null,
                  onSelected: (_) => setState(() => _statusFilter = null),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'شاغرة',
                  selected: _statusFilter == 'شاغرة',
                  onSelected: (_) => setState(() => _statusFilter = 'شاغرة'),
                  color: AppColors.successColor,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'محجوزة',
                  selected: _statusFilter == 'محجوزة',
                  onSelected: (_) => setState(() => _statusFilter = 'محجوزة'),
                  color: AppColors.dangerColor,
                ),
                if (uniqueTypes.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Container(height: 24, width: 1, color: AppColors.dividerColor),
                  const SizedBox(width: 16),
                  ...uniqueTypes.map((type) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _buildFilterChip(
                      label: type,
                      selected: _typeFilter == type,
                      onSelected: (_) => setState(() {
                        _typeFilter = _typeFilter == type ? null : type;
                      }),
                      color: AppColors.infoColor,
                    ),
                  )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required Function(bool) onSelected,
    Color? color,
  }) {
    final chipColor = color ?? AppColors.primaryColor;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: chipColor.withOpacity(0.2),
      checkmarkColor: chipColor,
      labelStyle: TextStyle(
        color: selected ? chipColor : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? chipColor : AppColors.lightGray,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildGridView(List<Room> rooms, bool canEdit) {
    final floorMap = _groupByFloor(rooms);
    final sortedFloors = floorMap.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: sortedFloors.length,
      itemBuilder: (context, index) {
        final floorNumber = sortedFloors[index];
        final floorRooms = floorMap[floorNumber]!;
        final availableCount = floorRooms.where((r) => StatusUtils.isRoomAvailable(r.status)).length;
        
        return _FloorExpansionTile(
          floorNumber: floorNumber,
          totalRooms: floorRooms.length,
          availableRooms: availableCount,
          initiallyExpanded: index < 2,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 5 : 3,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: floorRooms.length,
                itemBuilder: (context, i) {
                  final room = floorRooms[i];
                  return _RoomGridCard(
                    room: room,
                    onTap: () => _showRoomActions(context, ref, room, canEdit),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListView(List<Room> rooms, bool canEdit) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final room = rooms[index];
        return _RoomListCard(
          room: room,
          onTap: () => _showRoomActions(context, ref, room, canEdit),
          onEdit: canEdit ? () => _editRoom(context, ref, existing: room) : null,
        );
      },
    );
  }

  void _showRoomActions(BuildContext context, WidgetRef ref, Room room, bool canEdit) {
    final isAvailable = StatusUtils.isRoomAvailable(room.status);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildRoomHeader(room, isAvailable),
              const Divider(),
              if (canEdit) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit, color: AppColors.primaryColor),
                  ),
                  title: const Text('تعديل الغرفة'),
                  subtitle: const Text('تغيير السعر والنوع والحالة'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editRoom(context, ref, existing: room);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isAvailable ? AppColors.dangerColor : AppColors.successColor).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isAvailable ? Icons.block : Icons.check_circle,
                      color: isAvailable ? AppColors.dangerColor : AppColors.successColor,
                    ),
                  ),
                  title: Text(isAvailable ? 'تحويل إلى محجوزة' : 'تحويل إلى شاغرة'),
                  subtitle: const Text('تغيير حالة الغرفة بسرعة'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _quickStatusChange(room, isAvailable ? 'محجوزة' : 'شاغرة');
                  },
                ),
              ],
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.infoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.info_outline, color: AppColors.infoColor),
                ),
                title: const Text('تفاصيل الغرفة'),
                subtitle: const Text('عرض المعلومات الكاملة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRoomDetails(context, room);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomHeader(Room room, bool isAvailable) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: (isAvailable ? AppColors.successColor : AppColors.dangerColor).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isAvailable ? AppColors.successColor : AppColors.dangerColor).withOpacity(0.3),
              ),
            ),
            child: Center(
              child: Text(
                room.roomNumber,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isAvailable ? AppColors.successColor : AppColors.dangerColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'غرفة ${room.roomNumber}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (room.type.isNotEmpty) ...[
                      Icon(Icons.category, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(room.type, style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(width: 12),
                    ],
                    Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      CurrencyFormatter.formatAmount(room.price),
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (isAvailable ? AppColors.successColor : AppColors.dangerColor).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              room.status,
              style: TextStyle(
                color: isAvailable ? AppColors.successColor : AppColors.dangerColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quickStatusChange(Room room, String newStatus) async {
    final repo = ref.read(roomsRepoProvider);
    await repo.updateByRoomNumber(
      room.roomNumber,
      status: newStatus,
    );
    markDataChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تغيير حالة الغرفة ${room.roomNumber} إلى $newStatus'),
          backgroundColor: AppColors.successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showRoomDetails(BuildContext context, Room room) {
    final isAvailable = StatusUtils.isRoomAvailable(room.status);
    
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isAvailable ? Icons.hotel : Icons.hotel_outlined,
                color: isAvailable ? AppColors.successColor : AppColors.dangerColor,
              ),
              const SizedBox(width: 8),
              Text('غرفة ${room.roomNumber}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(Icons.category, 'النوع', room.type.isNotEmpty ? room.type : '-'),
              _buildDetailRow(Icons.attach_money, 'السعر', CurrencyFormatter.formatAmount(room.price)),
              _buildDetailRow(
                isAvailable ? Icons.check_circle : Icons.block,
                'الحالة',
                room.status,
                color: isAvailable ? AppColors.successColor : AppColors.dangerColor,
              ),
              if (room.imageUrl != null && room.imageUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    room.imageUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported, size: 40),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 12),
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editRoom(
    BuildContext context,
    WidgetRef ref, {
    Room? existing,
  }) async {
    final roomNumberCtrl = TextEditingController(text: existing?.roomNumber ?? '');
    final typeCtrl = TextEditingController(text: existing?.type ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null ? CurrencyFormatter.formatAmount(existing.price) : '',
    );
    String status = existing?.status ?? 'شاغرة';
    final imageUrl = existing?.imageUrl;
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  existing == null ? Icons.add : Icons.edit,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(existing == null ? 'إضافة غرفة جديدة' : 'تعديل غرفة ${existing.roomNumber}'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: roomNumberCtrl,
                    decoration: InputDecoration(
                      labelText: 'رقم الغرفة',
                      prefixIcon: const Icon(Icons.meeting_room),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    readOnly: existing != null,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'أدخل رقم الغرفة';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: typeCtrl,
                    decoration: InputDecoration(
                      labelText: 'نوع الغرفة',
                      prefixIcon: const Icon(Icons.category),
                      hintText: 'مثال: فردية، مزدوجة، جناح',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: priceCtrl,
                    decoration: InputDecoration(
                      labelText: 'السعر لليلة',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'أدخل السعر';
                      final price = CurrencyFormatter.parseAmount(v);
                      if (price == null || price <= 0) return 'أدخل سعراً صحيحاً';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setLocalState) => DropdownButtonFormField<String>(
                      value: status,
                      decoration: InputDecoration(
                        labelText: 'الحالة',
                        prefixIcon: const Icon(Icons.toggle_on),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'شاغرة',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: AppColors.successColor, size: 18),
                              SizedBox(width: 8),
                              Text('شاغرة'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'محجوزة',
                          child: Row(
                            children: [
                              Icon(Icons.block, color: AppColors.dangerColor, size: 18),
                              SizedBox(width: 8),
                              Text('محجوزة'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) => setLocalState(() => status = v ?? status),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(ctx, true);
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final repo = ref.read(roomsRepoProvider);
    final newPrice = CurrencyFormatter.parseAmount(priceCtrl.text) ?? 0;

    if (existing == null) {
      await repo.create(
        roomNumber: roomNumberCtrl.text.trim(),
        type: typeCtrl.text.trim(),
        price: newPrice,
        status: status,
        imageUrl: imageUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة الغرفة ${roomNumberCtrl.text.trim()}'),
            backgroundColor: AppColors.successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      final oldPrice = existing.price;
      final priceChanged = (oldPrice - newPrice).abs() > 0.01;

      await repo.updateByRoomNumber(
        existing.roomNumber,
        type: typeCtrl.text.trim(),
        price: newPrice,
        status: status,
        imageUrl: imageUrl,
      );

      if (priceChanged && context.mounted) {
        await _handlePriceChange(
          context,
          ref,
          roomNumber: existing.roomNumber,
          oldPrice: oldPrice,
          newPrice: newPrice,
        );
      }
    }
    markDataChanged();
  }

  Future<void> _handlePriceChange(
    BuildContext context,
    WidgetRef ref, {
    required String roomNumber,
    required double oldPrice,
    required double newPrice,
  }) async {
    final db = ref.read(dbProvider);
    final service = PriceAdjustmentService(db);

    final preview = await service.previewPriceChange(
      roomNumber: roomNumber,
      newPrice: newPrice,
    );

    final affectedBookings = preview['bookingsAffected'] as int;
    if (affectedBookings == 0) return;

    if (!context.mounted) return;

    final totalDiff = preview['totalDifference'] as double;
    final nightsAffected = preview['totalNightsAffected'] as int;

    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.price_change, color: AppColors.warningColor),
              ),
              const SizedBox(width: 12),
              const Text('تطبيق السعر الجديد؟'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        const Text('السعر القديم', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        Text(
                          CurrencyFormatter.formatAmount(oldPrice),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.arrow_forward, color: Colors.grey[400]),
                    ),
                    Column(
                      children: [
                        const Text('السعر الجديد', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        Text(
                          CurrencyFormatter.formatAmount(newPrice),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: newPrice > oldPrice ? AppColors.successColor : AppColors.dangerColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildImpactRow(Icons.book, 'الحجوزات المتأثرة', affectedBookings.toString()),
              _buildImpactRow(Icons.nightlight, 'الليالي المتأثرة', nightsAffected.toString()),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الفرق الإجمالي:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${totalDiff >= 0 ? "+" : ""}${CurrencyFormatter.formatAmount(totalDiff)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: totalDiff >= 0 ? AppColors.successColor : AppColors.dangerColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا، إبقاء السعر القديم'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check),
              label: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );

    if (apply == true && context.mounted) {
      final auth = ref.read(authProvider);
      final appliedBy = auth.currentUser?.name ?? 'unknown';

      final result = await service.applyRoomPriceChange(
        roomNumber: roomNumber,
        oldPrice: oldPrice,
        newPrice: newPrice,
        appliedBy: appliedBy,
        reason: 'تعديل السعر من شاشة الغرف',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.success
                  ? 'تم تحديث ${result.nightsUpdated} ليلة في ${result.bookingsAffected} حجز'
                  : 'خطأ: ${result.error}',
            ),
            backgroundColor: result.success ? AppColors.successColor : AppColors.dangerColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Widget _buildImpactRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FloorExpansionTile extends StatefulWidget {
  final String floorNumber;
  final int totalRooms;
  final int availableRooms;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _FloorExpansionTile({
    required this.floorNumber,
    required this.totalRooms,
    required this.availableRooms,
    this.initiallyExpanded = true,
    required this.children,
  });

  @override
  State<_FloorExpansionTile> createState() => _FloorExpansionTileState();
}

class _FloorExpansionTileState extends State<_FloorExpansionTile> with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    if (_isExpanded) _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final occupiedRooms = widget.totalRooms - widget.availableRooms;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: _isExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        widget.floorNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الطابق ${widget.floorNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${widget.totalRooms} غرفة',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildMiniStat(widget.availableRooms, AppColors.successColor, 'شاغرة'),
                  const SizedBox(width: 8),
                  _buildMiniStat(occupiedRooms, AppColors.dangerColor, 'محجوزة'),
                  const SizedBox(width: 8),
                  RotationTransition(
                    turns: _iconTurns,
                    child: const Icon(Icons.expand_more, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedCrossSize(
              alignment: Alignment.topCenter,
              firstChild: const SizedBox.shrink(),
              secondChild: Column(children: widget.children),
              crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(int count, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedCrossSize extends StatelessWidget {
  final Widget firstChild;
  final Widget secondChild;
  final CrossFadeState crossFadeState;
  final Duration duration;
  final Alignment alignment;

  const AnimatedCrossSize({
    super.key,
    required this.firstChild,
    required this.secondChild,
    required this.crossFadeState,
    required this.duration,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: firstChild,
      secondChild: secondChild,
      crossFadeState: crossFadeState,
      duration: duration,
      alignment: alignment,
      sizeCurve: Curves.easeInOut,
    );
  }
}

class _RoomGridCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;

  const _RoomGridCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAvailable = StatusUtils.isRoomAvailable(room.status);
    final cardColor = isAvailable ? AppColors.successColor : AppColors.dangerColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardColor.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: cardColor.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAvailable ? Icons.hotel : Icons.hotel_outlined,
                  color: cardColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                room.roomNumber,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: cardColor,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  room.status,
                  style: TextStyle(
                    fontSize: 9,
                    color: cardColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (room.type.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  room.type,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomListCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _RoomListCard({required this.room, required this.onTap, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final isAvailable = StatusUtils.isRoomAvailable(room.status);
    final statusColor = isAvailable ? AppColors.successColor : AppColors.dangerColor;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Center(
                  child: Text(
                    room.roomNumber,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'غرفة ${room.roomNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (room.type.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.infoColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              room.type,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.infoColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          CurrencyFormatter.formatAmount(room.price),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAvailable ? Icons.check_circle : Icons.block,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      room.status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 20),
                  color: AppColors.primaryColor,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryColor.withOpacity(0.1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
