import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_db.dart';
import '../services/sync_guardian.dart';
import '../services/sync_health_monitor.dart';
import '../services/sync_integrity_checker.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_queue_service.dart';
import 'repository_providers.dart';

final syncDashboardProvider = FutureProvider.autoDispose<SyncDashboardData>((
  ref,
) async {
  final guardian = ref.watch(syncGuardianProvider);
  final orchestrator = SyncOrchestrator.instance();
  final queueService = SyncQueueService.instance;
  final healthMonitor = SyncHealthMonitor.instance;
  final db = DatabaseManager.instance;

  final results = await Future.wait([
    orchestrator.getHealth(),
    queueService.getStats(),
    healthMonitor.getHealthMetrics(),
    SyncIntegrityChecker.instance.verify(db),
  ]);

  final orchestratorHealth = results[0] as SyncHealth;
  final queueStats = results[1] as QueueStats;
  final healthMetrics = results[2] as SyncHealthMetrics;
  final integrityReport = results[3] as IntegrityReport;

  final guardianHealthSnapshot = await guardian.watchHealth().first.timeout(
    const Duration(seconds: 2),
    onTimeout: () => const SyncHealthSnapshot(
      lastSyncAt: null,
      failedAttempts: 0,
      pendingEvents: false,
      isInitialized: false,
      lastError: null,
      monitoringActive: false,
      priorityOverridden: false,
      status: null,
    ),
  );

  return SyncDashboardData(
    guardianHealth: guardianHealthSnapshot,
    orchestratorHealth: orchestratorHealth,
    orchestratorMetrics: orchestrator.metrics,
    queueStats: queueStats,
    healthMetrics: healthMetrics,
    integrityReport: integrityReport,
  );
});

class SyncDashboardData {

  const SyncDashboardData({
    required this.guardianHealth,
    required this.orchestratorHealth,
    this.orchestratorMetrics,
    required this.queueStats,
    required this.healthMetrics,
    this.integrityReport,
  });
  final SyncHealthSnapshot guardianHealth;
  final SyncHealth orchestratorHealth;
  final SyncMetricsData? orchestratorMetrics;
  final QueueStats queueStats;
  final SyncHealthMetrics healthMetrics;
  final IntegrityReport? integrityReport;
}
