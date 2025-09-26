import 'package:flutter/material.dart';
import '../../services/local_db.dart';

/// Widget لعرض بطاقة غرفة واحدة
class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback? onTap;
  final bool compact;

  const RoomCard({
    super.key,
    required this.room,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = room.status == 'شاغرة';
    final cardColor = isAvailable ? Colors.green : Colors.red;

    return GestureDetector(
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
                cardColor.withOpacity(0.05),
                cardColor.withOpacity(0.15),
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
                    color: cardColor.withOpacity(0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (!compact && room.price > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '${room.price.toStringAsFixed(0)} ر.س',
                  style: TextStyle(
                    fontSize: 9,
                    color: cardColor.withOpacity(0.8),
                    fontWeight: FontWeight.bold,
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

/// Widget لعرض عنوان الطابق مع الإحصائيات
class FloorHeader extends StatelessWidget {
  final String floorNumber;
  final int totalRooms;
  final int occupiedRooms;
  final int availableRooms;
  final bool isCollapsible;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const FloorHeader({
    super.key,
    required this.floorNumber,
    required this.totalRooms,
    required this.occupiedRooms,
    required this.availableRooms,
    this.isCollapsible = false,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCollapsible ? onToggle : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
              width: 1,
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
                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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
  final int occupied;
  final int available;
  final int total;
  final bool compact;

  const FloorStats({
    super.key,
    required this.occupied,
    required this.available,
    required this.total,
    this.compact = false,
  });

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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: color, width: 1),
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
  final List<Room> rooms;
  final Function(Room) onRoomTap;
  final int crossAxisCount;
  final double childAspectRatio;

  const RoomsGrid({
    super.key,
    required this.rooms,
    required this.onRoomTap,
    this.crossAxisCount = 4,
    this.childAspectRatio = 1.2,
  });

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
        final room = rooms[index];
        return RoomCard(
          room: room,
          onTap: () => onRoomTap(room),
          compact: true,
        );
      },
    );
  }
}

/// Widget لعرض قسم طابق كامل
class FloorSection extends StatefulWidget {
  final String floorNumber;
  final List<Room> rooms;
  final Function(Room) onRoomTap;
  final bool isCollapsible;
  final bool initiallyExpanded;

  const FloorSection({
    super.key,
    required this.floorNumber,
    required this.rooms,
    required this.onRoomTap,
    this.isCollapsible = false,
    this.initiallyExpanded = true,
  });

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
      _animationController.forward();
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
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final availableCount = widget.rooms.where((r) => r.status == 'شاغرة').length;
    final occupiedCount = widget.rooms.length - availableCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FloorHeader(
            floorNumber: widget.floorNumber,
            totalRooms: widget.rooms.length,
            occupiedRooms: occupiedCount,
            availableRooms: availableCount,
            isCollapsible: widget.isCollapsible,
            isExpanded: _isExpanded,
            onToggle: widget.isCollapsible ? _toggle : null,
          ),
          if (widget.isCollapsible)
            SizeTransition(
              sizeFactor: _animation,
              child: _buildRoomsContent(),
            )
          else
            _buildRoomsContent(),
        ],
      ),
    );
  }

  Widget _buildRoomsContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: RoomsGrid(
        rooms: widget.rooms,
        onRoomTap: widget.onRoomTap,
      ),
    );
  }
}

/// Widget لعرض تفاصيل الغرفة في حوار
class RoomDetailsDialog extends StatelessWidget {
  final Room room;
  final VoidCallback? onBookRoom;
  final VoidCallback? onViewBookings;

  const RoomDetailsDialog({
    super.key,
    required this.room,
    this.onBookRoom,
    this.onViewBookings,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = room.status == 'شاغرة';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              isAvailable ? Icons.hotel : Icons.hotel_outlined,
              color: isAvailable ? Colors.green : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text('غرفة ${room.roomNumber}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('النوع', room.type),
            _buildDetailRow('السعر', '${room.price.toStringAsFixed(2)} ر.س'),
            _buildDetailRow('الحالة', room.status),
            if (room.imageUrl != null && room.imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  room.imageUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    width: double.infinity,
                    color: Colors.grey.withOpacity(0.3),
                    child: const Icon(Icons.image_not_supported),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (isAvailable && onBookRoom != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onBookRoom!();
              },
              icon: const Icon(Icons.add),
              label: const Text('حجز جديد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          if (!isAvailable && onViewBookings != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onViewBookings!();
              },
              icon: const Icon(Icons.visibility),
              label: const Text('عرض الحجوزات'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}