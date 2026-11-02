// lib/providers/sync_dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync_health_monitor.dart';
import 'repository_providers.dart';

/// مزوّد بيانات لوحة تحكم المزامنة — يستخدم SyncHealthMonitor الجديد.
final syncDashboardProvider = FutureProvider.autoDispose<SyncHealthReport>((ref) async {
  final db = ref.read(databaseProvider);
  return SyncHealthMonitor.instance.getHealthReport(db);
});

/// مزوّد قديم للتوافق مع الكود الذي يستخدم SyncDashboardData.
/// TODO: ترحيل كل الاستخدامات إلى syncDashboardProvider ثم حذف هذا.
class SyncDashboardData {
  const SyncDashboardData({required this.healthReport});

  final SyncHealthReport healthReport;
}
