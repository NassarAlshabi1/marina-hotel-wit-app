import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../providers/ditto_sync_provider.dart';

class DittoSettingsScreen extends ConsumerStatefulWidget {
  const DittoSettingsScreen({super.key});

  @override
  ConsumerState<DittoSettingsScreen> createState() => _DittoSettingsScreenState();
}

class _DittoSettingsScreenState extends ConsumerState<DittoSettingsScreen> {
  bool _loading = true;
  bool _autoSyncEnabled = false;
  bool _dittoInitialized = false;
  bool _isSyncing = false;
  DateTime? _lastSync;
  String? _lastError;
  Map<String, dynamic>? _stats;
  bool _runningAction = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshStatus();
    });
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _loading = true;
    });

    final service = ref.read(dittoSyncServiceProvider);
    final database = ref.read(databaseProvider);

    try {
      if (!service.isInitialized) {
        await service.initialize(database);
      }

      final autoEnabled = await service.isAutoSyncEnabled();
      Map<String, dynamic>? stats;
      try {
        stats = await service.getSyncStats();
      } catch (_) {
        stats = null;
      }

      setState(() {
        _autoSyncEnabled = autoEnabled;
        _dittoInitialized = service.isInitialized;
        _isSyncing = service.isSyncing;
        _lastSync = service.lastSyncTime;
        _lastError = service.lastError;
        _stats = stats;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _lastError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleAutoSync(bool value) async {
    if (_runningAction) return;
    setState(() {
      _runningAction = true;
    });

    final service = ref.read(dittoSyncServiceProvider);
    final database = ref.read(databaseProvider);

    try {
      await service.setAutoSyncEnabled(value);
      if (value) {
        if (!service.isInitialized) {
          await service.initialize(database);
        }
        await service.maybeAutoSync(database);
      } else {
        await service.stopSync();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? '✅ تم تفعيل المزامنة التلقائية' : '⏸️ تم إيقاف المزامنة التلقائية'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحديث الإعداد: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
      await _refreshStatus();
    }
  }

  Future<void> _runFullSync() async {
    if (_runningAction) return;
    setState(() {
      _runningAction = true;
    });

    final service = ref.read(dittoSyncServiceProvider);
    final database = ref.read(databaseProvider);

    try {
      if (!service.isInitialized) {
        await service.initialize(database);
      }
      await service.fullSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔄 تم إجراء مزامنة كاملة بنجاح')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت المزامنة: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
      await _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات Ditto',
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildAutoSyncTile(),
                  const SizedBox(height: 16),
                  _buildActionsCard(),
                  const SizedBox(height: 16),
                  if (_stats != null) _buildStatsCard(_stats!),
                  if (_lastError != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(_lastError!),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _dittoInitialized ? Colors.green : Colors.grey,
          child: Icon(
            _dittoInitialized ? Icons.cloud_done : Icons.cloud_off,
            color: Colors.white,
          ),
        ),
        title: const Text('حالة الخدمة'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dittoInitialized ? 'الخدمة مهيأة' : 'الخدمة غير مهيأة'),
            const SizedBox(height: 4),
            Text(_isSyncing ? 'المزامنة جارية...' : 'لا توجد مزامنة حالية'),
            if (_lastSync != null)
              Text('آخر مزامنة: ${_formatDateTime(_lastSync!)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoSyncTile() {
    return SwitchListTile.adaptive(
      title: const Text('المزامنة التلقائية'),
      subtitle: const Text('تشغيل أو إيقاف المزامنة التلقائية للبيانات مع Ditto'),
      value: _autoSyncEnabled,
      onChanged: _runningAction ? null : _toggleAutoSync,
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إجراءات المزامنة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _runningAction ? null : _runFullSync,
              icon: _runningAction
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('تشغيل مزامنة كاملة الآن'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(Map<String, dynamic> stats) {
    final tiles = <Widget>[
      _buildStatRow('الغرف في قاعدة البيانات', stats['rooms_in_local']),
      _buildStatRow('الحجوزات في قاعدة البيانات', stats['bookings_in_local']),
      _buildStatRow('الموظفون في قاعدة البيانات', stats['employees_in_local']),
      _buildStatRow('المدفوعات في قاعدة البيانات', stats['payments_in_local']),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إحصائيات Ditto',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...tiles,
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Text(value?.toString() ?? '---', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: Colors.red.shade50,
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: const Text('آخر خطأ مسجل'),
        subtitle: Text(error),
        trailing: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.red),
          onPressed: _runningAction ? null : _refreshStatus,
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
