import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/appwrite_delta_sync.dart';
import '../services/appwrite_realtime_sync.dart';

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});
  @override
  ConsumerState<DashboardSyncButton> createState() => _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton> with SingleTickerProviderStateMixin {
  bool _isPulling = false;
  bool _isPushing = false;
  int _pendingChangesCount = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadPendingChangesCount();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadPendingChangesCount());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingChangesCount() async {
    if (!mounted) return;
    try {
      final db = ref.read(databaseProvider);
      final count = await OutboxDao(db).count();
      if (mounted) setState(() => _pendingChangesCount = count);
    } catch (e) {
      debugPrint('❌ Error loading pending changes: $e');
    }
  }

  Future<void> _handlePush(BuildContext context) async {
    if (_isPushing) return;
    
    await _loadPendingChangesCount();
    if (_pendingChangesCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ لا توجد تغييرات للرفع'), backgroundColor: Colors.green)
      );
      return;
    }

    setState(() => _isPushing = true);
    final stopwatch = Stopwatch()..start();

    try {
      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        final appwriteService = ref.read(appwriteServiceProvider);
        final db = ref.read(databaseProvider);
        await deltaSync.initialize(appwriteService, db);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🚀 جاري الرفع المتوازي السريع...'), backgroundColor: Colors.blue)
      );

      final result = await deltaSync.pushDeltaChanges();
      stopwatch.stop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success 
              ? '✅ تم الرفع بنجاح! (${result.pushedCount} سجل في ${stopwatch.elapsed.inSeconds} ثانية)' 
              : '⚠️ تم الرفع مع وجود بعض الأخطاء'),
            backgroundColor: result.success ? Colors.green : Colors.orange,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل الرفع: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPushing = false);
        _loadPendingChangesCount();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(
            _isPushing ? Icons.cloud_upload : Icons.backup,
            color: _pendingChangesCount > 0 ? Colors.orange : Colors.blue,
          ),
          onPressed: _isPushing ? null : () => _handlePush(context),
          tooltip: 'رفع التغييرات (${_pendingChangesCount})',
        ),
        if (_isPushing)
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (_pendingChangesCount > 0 && !_isPushing)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$_pendingChangesCount',
                style: const TextStyle(color: Colors.white, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
