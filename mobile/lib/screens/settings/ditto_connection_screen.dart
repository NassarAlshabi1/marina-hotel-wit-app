import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../utils/ditto_config.dart';
import '../../services/ditto_sync_service.dart';
import '../../services/ditto_realtime_service.dart';
import '../../services/providers.dart';

class DittoConnectionScreen extends ConsumerStatefulWidget {
  const DittoConnectionScreen({super.key});

  @override
  ConsumerState<DittoConnectionScreen> createState() => _DittoConnectionScreenState();
}

class _DittoConnectionScreenState extends ConsumerState<DittoConnectionScreen> {
  Map<String, dynamic>? _dittoStatus;
  List<Map<String, dynamic>> _peers = [];
  bool _isLoading = false;
  String? _lastCheckTime;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _checkConnection(silent: true);
      }
    });
  }

  Future<void> _checkConnection({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _lastCheckTime = null;
      });
    }

    try {
      final status = await DittoConfig.getDetailedStatus();
      final peers = await DittoConfig.getCurrentPeers();
      
      if (!mounted) return;
      
      setState(() {
        _dittoStatus = status;
        _peers = peers.map((peer) => {
          'deviceName': peer.deviceName,
          'connections': peer.connections.map((c) => c.toString()).toList(),
        }).toList();
        _lastCheckTime = TimeOfDay.now().format(context);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dittoStatus = {'isInitialized': false, 'error': e.toString()};
        _peers = [];
        _lastCheckTime = TimeOfDay.now().format(context);
        _isLoading = false;
      });
    }
  }

  Future<void> _reconnect() async {
    setState(() => _isLoading = true);
    
    try {
      await DittoConfig.stopSync();
      await Future.delayed(const Duration(seconds: 1));
      await DittoConfig.startSync();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم إعادة الاتصال بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل إعادة الاتصال: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      await _checkConnection();
    }
  }

  Future<void> _manualSync() async {
    setState(() => _isLoading = true);
    
    try {
      final syncService = ref.read(dittoSyncServiceProvider);
      await syncService.runSync();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تمت المزامنة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشلت المزامنة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final realtimeService = ref.watch(dittoRealtimeServiceProvider);
    final syncService = ref.watch(dittoSyncServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حالة اتصال Ditto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : () => _checkConnection(),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading && _dittoStatus == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _checkConnection(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildDeviceInfoCard(),
                  const SizedBox(height: 16),
                  _buildPeersCard(),
                  const SizedBox(height: 16),
                  _buildSyncStatsCard(syncService),
                  const SizedBox(height: 16),
                  _buildRealtimeStatsCard(realtimeService),
                  const SizedBox(height: 16),
                  _buildActionsCard(),
                  if (_lastCheckTime != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'آخر تحديث: $_lastCheckTime',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final isConnected = _dittoStatus?['isInitialized'] == true;
    final error = _dittoStatus?['error'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected ? Icons.check_circle : Icons.error,
                  color: isConnected ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected ? 'متصل' : 'غير متصل',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: isConnected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (error != null)
                        Text(
                          error,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('حالة Realtime', _getRealtimeStatusText()),
            _buildInfoRow('عدد الأجهزة المتصلة', '${_peers.length} جهاز'),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    final deviceName = _dittoStatus?['deviceName'] ?? 'غير متوفر';
    final appId = _dittoStatus?['appId'] ?? DittoConfig.dittoAppId;
    final bigPeerUrl = _dittoStatus?['bigPeerUrl'] ?? DittoConfig.dittoBigPeerUrl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معلومات الجهاز',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            _buildInfoRow('اسم الجهاز', deviceName),
            _buildInfoRow('App ID', appId, isMonospace: true),
            _buildInfoRow('Big Peer', bigPeerUrl, isMonospace: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPeersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الأجهزة المتصلة',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _peers.isEmpty ? Colors.grey : Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_peers.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_peers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لا توجد أجهزة متصلة حالياً',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ..._peers.map((peer) => _buildPeerTile(peer)),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerTile(Map<String, dynamic> peer) {
    final deviceName = peer['deviceName'] as String;
    final connections = peer['connections'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  deviceName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (connections.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: connections.map((conn) {
                final connStr = conn.toString();
                IconData icon = Icons.wifi;
                Color color = Colors.blue;
                
                if (connStr.contains('Bluetooth')) {
                  icon = Icons.bluetooth;
                  color = Colors.indigo;
                } else if (connStr.contains('Lan')) {
                  icon = Icons.router;
                  color = Colors.orange;
                } else if (connStr.contains('WebSocket')) {
                  icon = Icons.cloud;
                  color = Colors.purple;
                }
                
                return Chip(
                  avatar: Icon(icon, size: 16, color: color),
                  label: Text(
                    _formatConnectionType(connStr),
                    style: const TextStyle(fontSize: 11),
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncStatsCard(DittoSyncService syncService) {
    final stats = syncService.getPerformanceStats();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إحصائيات المزامنة',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            _buildInfoRow('عمليات المزامنة', '${stats['totalSyncs'] ?? 0}'),
            _buildInfoRow('نجح', '${stats['successfulSyncs'] ?? 0}', valueColor: Colors.green),
            _buildInfoRow('فشل', '${stats['failedSyncs'] ?? 0}', valueColor: Colors.red),
            if (stats['lastSyncTime'] != null)
              _buildInfoRow('آخر مزامنة', stats['lastSyncTime']),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeStatsCard(DittoRealtimeService realtimeService) {
    final stats = realtimeService.getStats();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إحصائيات Realtime',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            _buildInfoRow('إضافة', '${stats['insertEvents'] ?? 0}', valueColor: Colors.green),
            _buildInfoRow('تحديث', '${stats['updateEvents'] ?? 0}', valueColor: Colors.blue),
            _buildInfoRow('حذف', '${stats['deleteEvents'] ?? 0}', valueColor: Colors.red),
            _buildInfoRow('إجمالي', '${stats['totalEvents'] ?? 0}', valueColor: Colors.purple),
            if (stats['lastEventTime'] != null)
              _buildInfoRow('آخر حدث', stats['lastEventTime']),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الإجراءات',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _manualSync,
              icon: const Icon(Icons.sync),
              label: const Text('مزامنة يدوية'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _reconnect,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة الاتصال'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : () => _checkConnection(),
              icon: const Icon(Icons.check_circle),
              label: const Text('فحص الاتصال'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isMonospace = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontFamily: isMonospace ? 'monospace' : null,
                fontSize: isMonospace ? 12 : null,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  String _getRealtimeStatusText() {
    final realtimeService = ref.read(dittoRealtimeServiceProvider);
    switch (realtimeService.currentStatus) {
      case RealtimeStatus.connected:
        return '🟢 متصل';
      case RealtimeStatus.connecting:
        return '🟡 جاري الاتصال...';
      case RealtimeStatus.disconnected:
        return '🔴 غير متصل';
      case RealtimeStatus.error:
        return '❌ خطأ';
    }
  }

  String _formatConnectionType(String conn) {
    if (conn.contains('Bluetooth')) return 'Bluetooth';
    if (conn.contains('Lan')) return 'LAN';
    if (conn.contains('WebSocket')) return 'Cloud';
    if (conn.contains('Awdl')) return 'AWDL';
    return 'P2P';
  }
}
