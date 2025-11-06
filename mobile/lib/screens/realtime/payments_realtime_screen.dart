import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../components/app_scaffold.dart';

class PaymentsRealtimeScreen extends StatefulWidget {
  const PaymentsRealtimeScreen({super.key});

  @override
  State<PaymentsRealtimeScreen> createState() => _PaymentsRealtimeScreenState();
}

class _PaymentsRealtimeScreenState extends State<PaymentsRealtimeScreen> {
  RealtimeChannel? _channel;
  final List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? stats;
  DateTimeRange? range;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _loadStats();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: range ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      helpText: 'اختر الفترة',
      confirmText: 'تأكيد',
      cancelText: 'إلغاء',
    );
    if (res != null) {
      setState(() => range = res);
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    try {
      final supabase = Supabase.instance.client;
      final params = {
        'p_start_date': (range?.start.toUtc() ?? DateTime.now().copyWith(day: 1).toUtc().toIso8601String()),
        'p_end_date': (range?.end.toUtc() ?? DateTime.now().toUtc().toIso8601String()),
      };
      final res = await supabase.rpc('get_payment_statistics', params: params);
      if (mounted) setState(() => stats = (res as Map?)?.cast<String, dynamic>());
    } catch (_) {}
  }

  void _subscribe() {
    final supabase = Supabase.instance.client;
    _channel = supabase
        .channel('public:payments')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
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
      title: 'المدفوعات - تحديث فوري',
      actions: [
        IconButton(onPressed: _pickRange, tooltip: 'تحديد الفترة', icon: const Icon(Icons.date_range)),
      ],
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
                      title: Text(rec['description']?.toString() ?? 'دفعة'),
                      subtitle: Text('الحدث: ${e['type']} • الوقت: ${e['time']}'),
                      trailing: Text('${rec['amount'] ?? ''}'),
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
    final totalCount = stats?['total_count'] ?? 0;
    final totalAmount = stats?['total_amount'] ?? 0;
    final cash = stats?['cash_payments'] ?? 0;
    final card = stats?['card_payments'] ?? 0;
    final transfer = stats?['transfer_payments'] ?? 0;
    final other = stats?['other_payments'] ?? 0;
    final roomRevenue = stats?['room_revenue'] ?? 0;
    final serviceRevenue = stats?['service_revenue'] ?? 0;

    Widget chip(String label, String value, Color c) => Chip(
          label: Text('$label: $value'),
          backgroundColor: c.withOpacity(0.08),
          side: BorderSide(color: c.withOpacity(0.2)),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('عدد العمليات', '$totalCount', Colors.blue),
        chip('الإجمالي', '$totalAmount', Colors.green),
        chip('نقدي', '$cash', Colors.teal),
        chip('بطاقة', '$card', Colors.purple),
        chip('تحويل', '$transfer', Colors.orange),
        chip('أخرى', '$other', Colors.brown),
        chip('دخل الغرف', '$roomRevenue', Colors.indigo),
        chip('دخل الخدمات', '$serviceRevenue', Colors.pink),
      ],
    );
  }
}
