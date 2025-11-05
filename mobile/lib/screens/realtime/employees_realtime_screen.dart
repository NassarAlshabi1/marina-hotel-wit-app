import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../components/app_scaffold.dart';

class EmployeesRealtimeScreen extends StatefulWidget {
  const EmployeesRealtimeScreen({super.key});

  @override
  State<EmployeesRealtimeScreen> createState() => _EmployeesRealtimeScreenState();
}

class _EmployeesRealtimeScreenState extends State<EmployeesRealtimeScreen> {
  RealtimeChannel? _channel;
  final List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? stats;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase.rpc('get_employee_statistics');
      if (mounted) setState(() => stats = (res as Map?)?.cast<String, dynamic>());
    } catch (_) {}
  }

  void _subscribe() {
    final supabase = Supabase.instance.client;
    _channel = supabase
        .channel('public:employees')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'employees',
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              _events.insert(0, {
                'type': payload.eventType.name,
                'record': payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord,
                'time': DateTime.now().toIso8601String(),
              });
            });
            _loadStats();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final supabase = Supabase.instance.client;
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'الموظفون - تحديث فوري',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatsBar(stats: stats),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _events[i];
                    final rec = (e['record'] as Map<String, dynamic>?) ?? {};
                    return ListTile(
                      leading: Icon(
                        e['type'] == 'insert'
                            ? Icons.add_circle
                            : e['type'] == 'update'
                                ? Icons.edit
                                : Icons.delete,
                        color: e['type'] == 'delete' ? Colors.red : Colors.green,
                      ),
                      title: Text(rec['name']?.toString() ?? 'موظف'),
                      subtitle: Text('الحدث: ${e['type']} • الوقت: ${e['time']}'),
                      trailing: Text(rec['status']?.toString() ?? ''),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats});
  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    final total = stats?['total'] ?? 0;
    final active = stats?['active'] ?? 0;
    final inactive = stats?['inactive'] ?? 0;
    final terminated = stats?['terminated'] ?? 0;
    final totalSalary = stats?['total_salary'] ?? 0;

    Widget chip(String label, String value, Color c) => Chip(
          label: Text('$label: $value'),
          backgroundColor: c.withOpacity(0.08),
          side: BorderSide(color: c.withOpacity(0.2)),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('الإجمالي', '$total', Colors.blue),
        chip('النشطون', '$active', Colors.green),
        chip('غير نشط', '$inactive', Colors.orange),
        chip('منتهي', '$terminated', Colors.red),
        chip('إجمالي الرواتب', '$totalSalary', Colors.purple),
      ],
    );
  }
}
