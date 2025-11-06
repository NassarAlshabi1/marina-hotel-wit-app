import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/providers.dart';
import '../services/supabase_realtime_service.dart';

/// بانر التحديثات الفورية (يظهر عند وصول تحديث جديد)
class LiveUpdateBanner extends ConsumerStatefulWidget {
  const LiveUpdateBanner({super.key});

  @override
  ConsumerState<LiveUpdateBanner> createState() => _LiveUpdateBannerState();
}

class _LiveUpdateBannerState extends ConsumerState<LiveUpdateBanner> {
  RealtimeEvent? _lastEvent;
  bool _visible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (previous, next) {
        next.whenData((event) {
          setState(() {
            _lastEvent = event;
            _visible = true;
          });

          _hideTimer?.cancel();
          _hideTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _visible = false);
            }
          });
        });
      },
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _lastEvent == null) {
      return const SizedBox.shrink();
    }

    final event = _lastEvent!;
    String message;
    IconData icon;

    switch (event.eventType) {
      case 'INSERT':
        icon = Icons.add_circle;
        message = 'إضافة جديدة في ${_tableNameArabic(event.table)}';
        break;
      case 'UPDATE':
        icon = Icons.update;
        message = 'تحديث في ${_tableNameArabic(event.table)}';
        break;
      case 'DELETE':
        icon = Icons.delete;
        message = 'حذف من ${_tableNameArabic(event.table)}';
        break;
      default:
        icon = Icons.info;
        message = 'تغيير في ${_tableNameArabic(event.table)}';
        break;
    }

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Material(
        color: Colors.blue.shade100,
        child: InkWell(
          onTap: () {
            setState(() => _visible = false);
          },
          child: ListTile(
            dense: true,
            leading: Icon(icon, color: Colors.blue.shade800),
            title: Text(
              message,
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: Icon(Icons.close, color: Colors.blue.shade700, size: 18),
          ),
        ),
      ),
    );
  }

  String _tableNameArabic(String table) {
    const names = {
      'rooms': 'الغرف',
      'bookings': 'الحجوزات',
      'booking_notes': 'ملاحظات الحجوزات',
      'employees': 'الموظفين',
      'expenses': 'المصروفات',
      'cash_transactions': 'المعاملات النقدية',
      'payments': 'المدفوعات',
      'debts': 'الديون',
    };
    return names[table] ?? table;
  }
}
