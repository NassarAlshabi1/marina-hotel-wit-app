import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/connectivity_service.dart';
import '../services/sync_error_recovery.dart';
import '../services/sync_orchestrator.dart';

class EnhancedSyncButton extends ConsumerStatefulWidget {

  const EnhancedSyncButton({
    super.key,
    this.showHealthIndicator = true,
    this.showLastSyncTime = true,
    this.compact = false,
  });
  final bool showHealthIndicator;
  final bool showLastSyncTime;
  final bool compact;

  @override
  ConsumerState<EnhancedSyncButton> createState() => _EnhancedSyncButtonState();
}

class _EnhancedSyncButtonState extends ConsumerState<EnhancedSyncButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  StreamSubscription<OrchestratorState>? _stateSubscription;
  StreamSubscription<SyncHealth>? _healthSubscription;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  SyncHealth? _health;
  bool _isOnline = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _setupListeners();
  }

  void _setupListeners() {
    _stateSubscription = SyncOrchestrator.instance.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isSyncing = state == OrchestratorState.syncing;
        });

        if (_isSyncing) {
          _animationController.repeat();
        } else {
          _animationController.stop();
          _animationController.reset();
        }
      }
    });

    _healthSubscription = SyncOrchestrator.instance.healthStream.listen((
      health,
    ) {
      if (mounted) {
        setState(() => _health = health);
      }
    });

    _connectivitySubscription = ConnectivityService.instance.statusStream
        .listen((status) {
          if (mounted) {
            setState(() => _isOnline = status.isOnline);
          }
        });

    _isOnline = ConnectivityService.instance.isOnline;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _stateSubscription?.cancel();
    _healthSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _triggerSync() async {
    if (_isSyncing || !_isOnline) {
      return;
    }

    setState(() => _isSyncing = true);
    unawaited(_animationController.repeat());

    try {
      await SyncErrorRecovery.instance.createRollbackPoint(
        id: 'manual_sync_${DateTime.now().millisecondsSinceEpoch}',
        description: 'قبل المزامنة اليدوية',
        database: ref.read(databaseProvider),
      );

      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      final smartEnabled = await smartSyncManager.isEnabled();

      if (smartEnabled) {
        await smartSyncManager.forceSyncNow();
      }

      await appwriteSyncManager.sync();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ تمت المزامنة بنجاح'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      final error = SyncErrorRecovery.instance.createError(
        operation: 'manual_sync',
        table: 'all',
        exception: e,
      );
      SyncErrorRecovery.instance.logError(error);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('تعذر إكمال المزامنة. راجع التفاصيل.'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'تفاصيل',
              textColor: Colors.white,
              onPressed: () => _showErrorDetails(error),
            ),
          ),
        );
      }
    } finally {
      _animationController.stop();
      _animationController.reset();
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _showErrorDetails(SyncError error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('تفاصيل الخطأ'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('العملية', error.operation),
              _buildDetailRow('الجدول', error.table),
              _buildDetailRow('الخطورة', error.severity.name),
              _buildDetailRow('قابل للإعادة', error.isRetriable ? 'نعم' : 'لا'),
              const SizedBox(height: 8),
              const Text('الرسالة:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(error.message, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          if (error.isRetriable)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _triggerSync();
              },
              child: const Text('إعادة المحاولة'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  void _showSyncOptions() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    'خيارات المزامنة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(),
              _buildHealthStatus(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.cloud_upload, color: Colors.blue),
                title: const Text('رفع التغييرات'),
                subtitle: const Text('رفع التغييرات المحلية إلى السحابة'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pushOnly();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download, color: Colors.green),
                title: const Text('سحب التحديثات'),
                subtitle: const Text('تحميل آخر التحديثات من السحابة'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pullOnly();
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync, color: Colors.orange),
                title: const Text('مزامنة كاملة'),
                subtitle: const Text('رفع وسحب جميع البيانات'),
                onTap: () async {
                  Navigator.pop(context);
                  await _triggerSync();
                },
              ),
              ListTile(
                leading: const Icon(Icons.health_and_safety, color: Colors.purple),
                title: const Text('فحص سلامة البيانات'),
                subtitle: const Text('التحقق من تكامل قاعدة البيانات'),
                onTap: () async {
                  Navigator.pop(context);
                  await _verifyIntegrity();
                },
              ),
              if (SyncErrorRecovery.instance.recentErrors.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.red),
                  title: const Text('سجل الأخطاء'),
                  subtitle: Text(
                    '${SyncErrorRecovery.instance.recentErrors.length} خطأ',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showErrorLog();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthStatus() {
    final health = _health;
    if (health == null) {
      return const ListTile(
        leading: CircularProgressIndicator(strokeWidth: 2),
        title: Text('جاري فحص صحة النظام...'),
      );
    }

    final healthColor = health.isHealthy ? Colors.green : Colors.orange;
    final healthIcon = health.isHealthy ? Icons.check_circle : Icons.warning;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: healthColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: healthColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(healthIcon, color: healthColor, size: 20),
              const SizedBox(width: 8),
              Text(
                health.isHealthy
                    ? 'النظام يعمل بشكل صحيح'
                    : 'يوجد مشاكل في النظام',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: healthColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatChip(
                'نجاح',
                '${(health.successRate * 100).toStringAsFixed(0)}%',
                Colors.green,
              ),
              _buildStatChip('معلق', '${health.pendingTasks}', Colors.orange),
              _buildStatChip('Outbox', '${health.outboxCount}', Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color)),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pushOnly() async {
    setState(() => _isSyncing = true);
    unawaited(_animationController.repeat());

    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      await smartSyncManager.pushLocalChanges();
      await appwriteSyncManager.pushLocalChanges();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم رفع التغييرات'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في رفع التغييرات: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'تعذر رفع التغييرات. تحقق من الاتصال ثم أعد المحاولة',
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: _pushOnly,
            ),
          ),
        );
      }
    } finally {
      _animationController.stop();
      _animationController.reset();
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _pullOnly() async {
    setState(() => _isSyncing = true);
    unawaited(_animationController.repeat());

    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      await smartSyncManager.pullRemoteChanges();
      await appwriteSyncManager.sync(push: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تحديث البيانات'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التحديثات: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'تعذر سحب التحديثات. تحقق من الاتصال ثم أعد المحاولة',
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: _pullOnly,
            ),
          ),
        );
      }
    } finally {
      _animationController.stop();
      _animationController.reset();
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _verifyIntegrity() async {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري فحص سلامة البيانات...'),
          ],
        ),
      ),
    ),);

    try {
      final checks = await SyncOrchestrator.instance.verifyDataIntegrity();
      // ignore: use_build_context_synchronously
      Navigator.pop(context);

      unawaited(showDialog<void>(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text('نتائج الفحص'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: checks
                  .map(
                    (check) => ListTile(
                      leading: const Icon(Icons.table_chart, color: Colors.blue),
                      title: Text(check.tableName),
                      subtitle: Text('${check.recordCount} سجل'),
                      trailing: Text(
                        check.checksum.substring(0, 8),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),);
    } catch (e) {
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فحص سلامة البيانات. أعد المحاولة لاحقاً'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showErrorLog() {
    final errors = SyncErrorRecovery.instance.recentErrors;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('سجل الأخطاء'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: errors.length,
            itemBuilder: (context, index) {
              final error = errors[index];
              return ListTile(
                leading: Icon(
                  error.severity == ErrorSeverity.critical
                      ? Icons.error
                      : error.severity == ErrorSeverity.high
                      ? Icons.warning
                      : Icons.info,
                  color: error.severity == ErrorSeverity.critical
                      ? Colors.red
                      : error.severity == ErrorSeverity.high
                      ? Colors.orange
                      : Colors.blue,
                ),
                title: Text(error.operation),
                subtitle: Text(
                  error.message.length > 50
                      ? '${error.message.substring(0, 50)}...'
                      : error.message,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  '${error.timestamp.hour}:${error.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SyncErrorRecovery.instance.clearErrors();
              Navigator.pop(context);
            },
            child: const Text('مسح السجل'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final health = _health;
    final isHealthy = health?.isHealthy ?? true;
    final pendingCount = health?.outboxCount ?? 0;

    Color buttonColor;
    IconData buttonIcon;
    String buttonText;

    if (!_isOnline) {
      buttonColor = Colors.grey;
      buttonIcon = Icons.cloud_off;
      buttonText = 'غير متصل';
    } else if (_isSyncing) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.sync;
      buttonText = 'جاري المزامنة...';
    } else if (pendingCount > 0) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'رفع ($pendingCount)';
    } else if (!isHealthy) {
      buttonColor = Colors.orange;
      buttonIcon = Icons.warning;
      buttonText = 'مشكلة';
    } else {
      buttonColor = Colors.green;
      buttonIcon = Icons.cloud_done;
      buttonText = 'متزامن';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [buttonColor.withValues(alpha: 0.8), buttonColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: buttonColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _isSyncing || !_isOnline ? null : _triggerSync,
                  onLongPress: _isOnline ? _showSyncOptions : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 12 : 16,
                      vertical: widget.compact ? 8 : 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSyncing) RotationTransition(
                                turns: _animationController,
                                child: Icon(
                                  buttonIcon,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ) else Icon(buttonIcon, size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          buttonText,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: widget.compact ? 12 : 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (pendingCount > 0 && !_isSyncing)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  child: Center(
                    child: Text(
                      pendingCount > 99 ? '99+' : '$pendingCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.showHealthIndicator && !isHealthy)
              Positioned(
                bottom: -4,
                left: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.warning, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
        if (widget.showLastSyncTime && health?.lastSuccessfulSync != null) ...[
          const SizedBox(height: 4),
          Text(
            _formatLastSync(health!.lastSuccessfulSync!),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  String _formatLastSync(DateTime lastSync) {
    final diff = DateTime.now().difference(lastSync);
    if (diff.inSeconds < 60) {
      return 'منذ ${diff.inSeconds} ثانية';
    }
    if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    }
    if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    }
    return 'منذ ${diff.inDays} يوم';
  }
}
