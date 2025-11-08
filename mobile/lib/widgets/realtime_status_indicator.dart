import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/providers.dart';
import '../services/ditto_realtime_service.dart';

/// مؤشر حالة Realtime في شريط التطبيق
class RealtimeStatusIndicator extends ConsumerWidget {
  const RealtimeStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dittoService = ref.watch(dittoRealtimeServiceProvider);
    final status = dittoService.currentStatus;

    return _buildIndicator(status);
  }

  Widget _buildIndicator(RealtimeStatus status) {
    IconData icon;
    Color color;
    String tooltip;

    switch (status) {
      case RealtimeStatus.connected:
        icon = Icons.cloud_done;
        color = Colors.green;
        tooltip = 'متصل - التحديثات الفورية نشطة';
        break;
      case RealtimeStatus.connecting:
        icon = Icons.cloud_sync;
        color = Colors.orange;
        tooltip = 'جاري الاتصال بـ Realtime...';
        break;
      case RealtimeStatus.disconnected:
        icon = Icons.cloud_off;
        color = Colors.grey;
        tooltip = 'غير متصل بـ Realtime';
        break;
      case RealtimeStatus.error:
        icon = Icons.error_outline;
        color = Colors.red;
        tooltip = 'خطأ في Realtime - تحقق من الاتصال';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 20),
    );
  }
}
