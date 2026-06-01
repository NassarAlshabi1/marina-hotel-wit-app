/// ⚠️ Smart Sync widgets are REMOVED
/// SmartSyncManager has been completely removed from the project.
/// All sync is handled via Appwrite only.
/// These widget stubs remain for compilation compatibility only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [REMOVED] Returns SizedBox.shrink() — SmartSyncManager was removed.
class SmartSyncStatusWidget extends StatelessWidget {
  const SmartSyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// [REMOVED] Passes through child — SmartSyncManager was removed.
class SmartSyncNotificationListener extends StatelessWidget {
  const SmartSyncNotificationListener({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// [REMOVED] Returns SizedBox.shrink() — SmartSyncManager was removed.
class SmartSyncFloatingButton extends StatelessWidget {
  const SmartSyncFloatingButton({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// [REMOVED] Returns SizedBox.shrink() — SmartSyncManager was removed.
class SmartSyncDashboardCard extends StatelessWidget {
  const SmartSyncDashboardCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
