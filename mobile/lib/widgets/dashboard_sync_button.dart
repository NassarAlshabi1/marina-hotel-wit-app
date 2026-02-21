import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rxdart/rxdart.dart'; // For debouncing
import '../services/sync/core/sync_orchestrator.dart'; // Import SyncOrchestrator
import '../services/sync/models/sync_state.dart'; // Import SyncStatus

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/appwrite_delta_sync.dart';
import '../services/appwrite_realtime_sync.dart';
import '../services/sync/core/conflict_resolver.dart';

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  late final SyncOrchestrator _syncOrchestrator; // Added for direct access
  StreamSubscription? _pendingChangesSubscription;
  StreamSubscription? _syncStateSubscription;
  bool _isPulling = false;
  bool _isPushing = false;
  bool _appwriteEnabled = true;
  late AnimationController _pullAnimationController;
  late AnimationController _pushAnimationController;
  int _pendingChangesCount = 0;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _syncOrchestrator = ref.read(syncOrchestratorProvider);

    _pullAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pushAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _loadAppwriteEnabled();

    _pendingChangesSubscription = _syncOrchestrator.outbox.pendingCountStream.listen((count) {
      if (mounted) {
        setState(() {
          _pendingChangesCount = count;
        });
      }
    });

    _syncStateSubscription = _syncOrchestrator.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPulling = state.status == SyncStatus.syncing; // Simplified for now
          _isPushing = state.status == SyncStatus.syncing;
          _lastSyncTime = state.lastSyncTime;
        });
      }
    });

    _syncOrchestrator.outbox.pendingCount.then((count) {
      if (mounted) {
        setState(() {
          _pendingChangesCount = count;
        });
      }
    });
  }

  @override
  void dispose() {
    _pendingChangesSubscription?.cancel();
    _syncStateSubscription?.cancel();
    _pullAnimationController.dispose();
    _pushAnimationController.dispose();
    super.dispose();
  }

  Future<bool> _isAppwriteSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appwrite_sync_enabled') ?? false;
  }

  Future<void> _loadAppwriteEnabled() async {
    try {
      final enabled = await _isAppwriteSyncEnabled();
      if (mounted) {
        setState(() => _appwriteEnabled = enabled);
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل حالة Appwrite: $e');
      if (mounted) {
        setState(() => _appwriteEnabled = true);
      }
    }
  }

  Future<void> _pullChanges(BuildContext context) async {
    if (_isPulling) return;

    if (!mounted) return;

    setState(() {
      _isPulling = true;
    });
    try {
      await _syncOrchestrator.pullOnly();
      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isPulling = false;
        });
      }
    }
  }

  Future<void> _pushChanges(BuildContext context) async {
    if (_isPushing) return;

    if (!mounted) return;

    setState(() {
      _isPushing = true;
    });
    try {
      await _syncOrchestrator.pushOnly();
      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في دفع التغييرات: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isPushing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocalChanges = _pendingChangesCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pull button logic here
            const SizedBox(width: 8),
            // Push button logic here
          ],
        ),
        const SizedBox(height: 6),
        StreamBuilder<SyncState>(
          stream: _syncOrchestrator.stateStream,
          initialData: _syncOrchestrator.currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? SyncState.idle();
            return Text(_formatLastSyncTime(state.lastSyncTime));
          },
        ),
      ],
    );
  }

  String _formatLastSyncTime(DateTime? time) {
    if (time == null) {
      return 'لم تتم المزامنة بعد';
    }
    final difference = DateTime.now().difference(time);
    if (difference.inSeconds < 60) {
      return 'منذ ${difference.inSeconds} ثانية';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }
}
