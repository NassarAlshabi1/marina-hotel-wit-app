import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/appwrite_delta_sync.dart';
import '../services/appwrite_realtime_sync.dart';
import '../services/sync_core/conflict_resolver.dart';

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState
    extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  bool _isSyncing = false;
  int _pendingCount = 0;

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _loadPendingCount();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPendingCount() async {
    final db = ref.read(databaseProvider);
    final dao = OutboxDao(db);
    final count = await dao.count();

    if (mounted) {
      setState(() => _pendingCount = count);
    }
  }

  Future<void> _startFullSync() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    _controller.repeat();

    try {
      final db = ref.read(databaseProvider);

      /// ===============================
      /// 1️⃣ PUSH Appwrite
      /// ===============================
      final deltaSync = AppwriteDeltaSync.instance;

      if (!deltaSync.isInitialized) {
        final service = ref.read(appwriteServiceProvider);
        await deltaSync.initialize(service, db);
      }

      final pushResult = await deltaSync.pushDeltaChanges();

      /// تنظيف outbox عند نجاح كامل
      if (pushResult.failedCount == 0) {
        final dao = OutboxDao(db);
        await dao.clear();
      }

      /// ===============================
      /// 2️⃣ PULL Appwrite
      /// ===============================
      await deltaSync.pullDeltaChanges();

      /// ===============================
      /// 3️⃣ Backup to Google Drive
      /// ===============================
      final driveService = ref.read(googleDriveServiceProvider);

      await driveService.uploadDatabaseBackup(
        databasePath: db.path,
      );

      await _loadPendingCount();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت المزامنة الكاملة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل في المزامنة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _controller.stop();
      _controller.reset();
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _restoreFromDrive() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    _controller.repeat();

    try {
      final db = ref.read(databaseProvider);
      final driveService = ref.read(googleDriveServiceProvider);

      await driveService.downloadLatestBackup(
        databasePath: db.path,
      );

      await _loadPendingCount();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم استعادة النسخة من Google Drive'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الاستعادة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _controller.stop();
      _controller.reset();
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _pendingCount > 0;

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'sync') _startFullSync();
        if (value == 'restore') _restoreFromDrive();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'sync',
          child: Text('مزامنة كاملة'),
        ),
        const PopupMenuItem(
          value: 'restore',
          child: Text('استعادة من Google Drive'),
        ),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isSyncing
                    ? [Colors.orange, Colors.deepOrange]
                    : [Colors.deepPurple, Colors.purple],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _isSyncing
                    ? RotationTransition(
                        turns: _controller,
                        child: const Icon(
                          Icons.sync,
                          size: 16,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.sync,
                        size: 16,
                        color: Colors.white,
                      ),
                const SizedBox(width: 6),
                Text(
                  _isSyncing
                      ? 'جاري المزامنة...'
                      : 'مزامنة',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          if (hasChanges && !_isSyncing)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  _pendingCount > 99 ? '99+' : '$_pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
