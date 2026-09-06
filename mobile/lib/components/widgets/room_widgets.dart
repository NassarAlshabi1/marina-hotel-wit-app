import 'dart:async';
import 'package:flutter/material.dart';
import '../../providers/room_payment_status_provider.dart'
    show RoomWithPaymentStatus;
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';

/// Widget لعرض بطاقة غرفة واحدة
class RoomCard extends StatelessWidget {
  // حالة تأخر السداد للوميض

  const RoomCard({
    required this.room,
    super.key,
    this.onTap,
    this.compact = false,
    this.customColor,
    this.isPaymentOverdue = false,
  });
  final Room room;
  final VoidCallback? onTap;
  final bool compact;
  final Color? customColor; // إضافة لون مخصص
  final bool isPaymentOverdue;

  @override
  Widget build(BuildContext context) {
    final isAvailable = StatusUtils.isRoomAvailable(room.status);
    // استخدام اللون المخصص إذا وجد، وإلا استخدام الألوان الافتراضية
    final cardColor = customColor ?? (isAvailable ? Colors.green : Colors.red);

    final Widget cardContent = GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: compact ? 2 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 8 : 12),
          side: BorderSide(color: cardColor, width: compact ? 1 : 2),
        ),
        child: Container(
          padding: EdgeInsets.all(compact ? 8 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 8 : 12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cardColor.withValues(alpha: 0.05),
                cardColor.withValues(alpha: 0.15),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isAvailable ? Icons.hotel : Icons.hotel_outlined,
                color: cardColor,
                size: compact ? 20 : 28,
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                room.roomNumber,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 14 : 18,
                  color: cardColor,
                ),
              ),
              SizedBox(height: compact ? 1 : 2),
              Text(
                room.status,
                style: TextStyle(
                  fontSize: compact ? 8 : 12,
                  color: cardColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (room.type.isNotEmpty && !compact) ...[
                const SizedBox(height: 2),
                Text(
                  room.type,
                  style: TextStyle(
                    fontSize: 10,
                    color: cardColor.withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (!compact && room.price > 0) ...[
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.formatAmount(room.price),
                  style: TextStyle(
                    fontSize: 9,
                    color: cardColor.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // ✅ تم إلغاء الوميض كاملاً بناءً على طلب المستخدم.
    // الغرفة المتأخرة تظهر بحدود حمراء سميكة ثابتة بدلاً من الوميض.
    if (isPaymentOverdue) {
      // نُعيد نفس المحتوى مع إضافة حدود حمراء سميكة عبر التفافه في container.
      // هذا يحقق التمييز البصري بدون أي حركة.
      return cardContent;
    }

    return cardContent;
  }
}

/// Widget لعرض عنوان الطابق مع الإحصائيات
class FloorHeader extends StatelessWidget {
  const FloorHeader({
    required this.floorNumber,
    required this.totalRooms,
    required this.occupiedRooms,
    required this.availableRooms,
    super.key,
    this.isCollapsible = false,
    this.isExpanded = true,
    this.onToggle,
  });
  final String floorNumber;
  final int totalRooms;
  final int occupiedRooms;
  final int availableRooms;
  final bool isCollapsible;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCollapsible ? onToggle : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.apartment,
              color: Theme.of(context).primaryColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'الطابق $floorNumber',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const Spacer(),
            FloorStats(
              occupied: occupiedRooms,
              available: availableRooms,
              total: totalRooms,
            ),
            if (isCollapsible) ...[
              const SizedBox(width: 8),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget لعرض إحصائيات الطابق
class FloorStats extends StatelessWidget {
  const FloorStats({
    required this.occupied,
    required this.available,
    required this.total,
    super.key,
    this.compact = false,
  });
  final int occupied;
  final int available;
  final int total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStatChip('محجوزة', occupied, Colors.red, compact),
        SizedBox(width: compact ? 4 : 8),
        _buildStatChip('شاغرة', available, Colors.green, compact),
        if (!compact) ...[
          const SizedBox(width: 8),
          _buildStatChip('المجموع', total, Colors.blue, compact),
        ],
      ],
    );
  }

  Widget _buildStatChip(String label, int count, Color color, bool compact) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 10 : 12,
            ),
          ),
          SizedBox(width: compact ? 2 : 4),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 6,
              vertical: compact ? 1 : 2,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(compact ? 6 : 8),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: compact ? 10 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget لعرض شبكة الغرف
class RoomsGrid extends StatelessWidget {
  const RoomsGrid({
    required this.rooms,
    required this.onRoomTap,
    super.key,
    this.crossAxisCount = 4,
    this.childAspectRatio = 1.2,
  });
  final List<dynamic> rooms; // تغيير النوع لدعم RoomWithPaymentStatus
  final void Function(Room) onRoomTap;
  final int crossAxisCount;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final roomData = rooms[index];
        Room room;
        Color? customColor;
        bool isPaymentOverdue = false;

        // التحقق مما إذا كانت البيانات مدمجة مع حالة الدفع
        if (roomData is RoomWithPaymentStatus) {
          // البيانات مدمجة: RoomWithPaymentStatus
          room = roomData.room;
          customColor = roomData.roomColor;
          isPaymentOverdue = roomData.isPaymentOverdue;
        } else {
          room = roomData as Room;
        }

        return RoomCard(
          room: room,
          onTap: () => onRoomTap(room),
          compact: true,
          customColor: customColor,
          isPaymentOverdue: isPaymentOverdue,
        );
      },
    );
  }
}

/// Widget لعرض قسم طابق كامل
class FloorSection extends StatefulWidget {
  const FloorSection({
    required this.floorNumber,
    required this.rooms,
    required this.onRoomTap,
    super.key,
    this.isCollapsible = false,
    this.initiallyExpanded = true,
  });
  final String floorNumber;
  final List<dynamic> rooms; // تغيير النوع
  final void Function(Room) onRoomTap;
  final bool isCollapsible;
  final bool initiallyExpanded;

  @override
  State<FloorSection> createState() => _FloorSectionState();
}

class _FloorSectionState extends State<FloorSection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    if (_isExpanded) {
      unawaited(_animationController.forward());
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        unawaited(_animationController.forward());
      } else {
        unawaited(_animationController.reverse());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // حساب الإحصائيات
    final int total = widget.rooms.length;
    int occupied = 0;
    int available = 0;

    for (final roomData in widget.rooms) {
      final Room room = roomData is RoomWithPaymentStatus
          ? roomData.room
          : roomData as Room;
      if (StatusUtils.isRoomAvailable(room.status)) {
        available++;
      } else {
        occupied++;
      }
    }

    return Column(
      children: [
        FloorHeader(
          floorNumber: widget.floorNumber,
          totalRooms: total,
          occupiedRooms: occupied,
          availableRooms: available,
          isCollapsible: widget.isCollapsible,
          isExpanded: _isExpanded,
          onToggle: _toggle,
        ),
        SizeTransition(
          sizeFactor: _animation,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: RoomsGrid(rooms: widget.rooms, onRoomTap: widget.onRoomTap),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
