import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../components/app_scaffold.dart';

class RealtimeDashboardExample extends StatefulWidget {
  const RealtimeDashboardExample({super.key});

  @override
  State<RealtimeDashboardExample> createState() => _RealtimeDashboardExampleState();
}

class _RealtimeDashboardExampleState extends State<RealtimeDashboardExample> {
  RealtimeChannel? _roomsChannel;
  RealtimeChannel? _bookingsChannel;
  RealtimeChannel? _notesChannel;

  int roomsEvents = 0;
  int bookingsEvents = 0;
  int notesEvents = 0;

  Map<String, dynamic>? roomStats;
  Map<String, dynamic>? bookingStats;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final supabase = Supabase.instance.client;
      final roomRes = await supabase.rpc('get_room_statistics');
      final bookingRes = await supabase.rpc('get_booking_statistics');
      if (mounted) {
        setState(() {
          roomStats = (roomRes as Map?)?.cast<String, dynamic>();
          bookingStats = (bookingRes as Map?)?.cast<String, dynamic>();
        });
      }
    } catch (_) {}
  }

  void _subscribe() {
    final supabase = Supabase.instance.client;

    _roomsChannel = supabase
        .channel('public:rooms')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rooms',
          callback: (_) {
            if (!mounted) return;
            setState(() => roomsEvents++);
            _loadStats();
          },
        )
        .subscribe();

    _bookingsChannel = supabase
        .channel('public:bookings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) {
            if (!mounted) return;
            setState(() => bookingsEvents++);
            _loadStats();
          },
        )
        .subscribe();

    _notesChannel = supabase
        .channel('public:booking_notes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_notes',
          callback: (_) {
            if (!mounted) return;
            setState(() => notesEvents++);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final supabase = Supabase.instance.client;
    if (_roomsChannel != null) supabase.removeChannel(_roomsChannel!);
    if (_bookingsChannel != null) supabase.removeChannel(_bookingsChannel!);
    if (_notesChannel != null) supabase.removeChannel(_notesChannel!);
    super.dispose();
  }

  Widget _buildStatCard(String title, IconData icon, Color color, Map<String, dynamic>? stats) {
    final total = stats?['total'] ?? 0;
    final lastUpdated = stats?['last_updated'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (lastUpdated != null)
              Text('آخر تحديث: $lastUpdated', style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'لوحة البث الفوري',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(width: 360, child: _buildStatCard('الغرف', Icons.meeting_room, Colors.blue, roomStats)),
                SizedBox(width: 360, child: _buildStatCard('الحجوزات', Icons.event, Colors.green, bookingStats)),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('الأحداث الفورية', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _eventTile('الغرف', roomsEvents, Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _eventTile('الحجوزات', bookingsEvents, Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _eventTile('الملاحظات', notesEvents, Colors.orange)),
                    ],
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث الإحصائيات'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(String title, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(Icons.circle, size: 10, color: color), const SizedBox(width: 8), Text(title)]),
          const SizedBox(height: 8),
          Text('$count حدث', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
