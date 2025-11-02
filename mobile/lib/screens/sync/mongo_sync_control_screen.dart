import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/mongo_sync_provider.dart';
import '../../services/flutter_mongo_sync_service.dart';
import '../../utils/theme.dart';

class MongoSyncControlScreen extends ConsumerStatefulWidget {
  const MongoSyncControlScreen({super.key});

  @override
  ConsumerState<MongoSyncControlScreen> createState() => _MongoSyncControlScreenState();
}

class _MongoSyncControlScreenState extends ConsumerState<MongoSyncControlScreen> {
  final _passwordController = TextEditingController();
  int _syncIntervalMinutes = 1;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_passwordController.text.isEmpty) {
      _showSnackBar('الرجاء إدخال كلمة المرور', isError: true);
      return;
    }

    try {
      await ref.read(mongoConnectionProvider.notifier).connect(_passwordController.text);
      _showSnackBar('✅ تم الاتصال بنجاح');
    } catch (e) {
      _showSnackBar('❌ فشل الاتصال: $e', isError: true);
    }
  }

  Future<void> _toggleAutoSync() async {
    final connectionState = ref.read(mongoConnectionProvider);
    
    if (!connectionState.isConnected) {
      _showSnackBar('الرجاء الاتصال أولاً', isError: true);
      return;
    }

    if (connectionState.autoSyncEnabled) {
      ref.read(mongoConnectionProvider.notifier).stopAutoSync();
      _showSnackBar('⏹️ تم إيقاف المزامنة التلقائية');
    } else {
      await ref.read(mongoConnectionProvider.notifier).startAutoSync(
        interval: Duration(minutes: _syncIntervalMinutes),
      );
      _showSnackBar('▶️ تم تفعيل المزامنة التلقائية');
    }
  }

  Future<void> _syncNow() async {
    final connectionState = ref.read(mongoConnectionProvider);
    
    if (!connectionState.isConnected) {
      _showSnackBar('الرجاء الاتصال أولاً', isError: true);
      return;
    }

    _showSnackBar('⏳ جاري المزامنة...');
    
    final result = await ref.read(mongoConnectionProvider.notifier).syncNow();
    
    if (result.success) {
      _showSnackBar('✅ ${result.message}');
      ref.invalidate(syncStatsProvider);
    } else {
      _showSnackBar('❌ ${result.message}', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(mongoConnectionProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final statsAsync = ref.watch(syncStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('التحكم في المزامنة'),
        backgroundColor: AppColors.primary,
        actions: [
          if (connectionState.isConnected)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                ref.invalidate(syncStatsProvider);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConnectionCard(connectionState),
            const SizedBox(height: 16),
            if (!connectionState.isConnected)
              _buildConnectionForm(connectionState)
            else ...[
              _buildSyncStatusCard(syncStatusAsync),
              const SizedBox(height: 16),
              _buildControlButtons(connectionState),
              const SizedBox(height: 16),
              _buildSyncIntervalSelector(connectionState),
              const SizedBox(height: 16),
              _buildStatsCard(statsAsync),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(MongoConnectionState state) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              state.isConnected ? Icons.cloud_done : Icons.cloud_off,
              size: 40,
              color: state.isConnected ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.isConnected ? 'متصل بـ MongoDB' : 'غير متصل',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (state.error != null)
                    Text(
                      state.error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionForm(MongoConnectionState state) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الاتصال بـ MongoDB',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'كلمة مرور MongoDB',
                hintText: 'أدخل كلمة المرور',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: state.isLoading ? null : _connect,
              icon: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(state.isLoading ? 'جاري الاتصال...' : 'اتصل الآن'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard(AsyncValue<SyncStatus> statusAsync) {
    return statusAsync.when(
      data: (status) {
        Color statusColor;
        IconData statusIcon;
        String statusText;

        switch (status.status) {
          case 'connected':
            statusColor = Colors.green;
            statusIcon = Icons.check_circle;
            statusText = 'جاهز للمزامنة';
            break;
          case 'syncing':
            statusColor = Colors.orange;
            statusIcon = Icons.sync;
            statusText = 'جاري المزامنة...';
            break;
          case 'error':
            statusColor = Colors.red;
            statusIcon = Icons.error;
            statusText = 'خطأ: ${status.message ?? "غير معروف"}';
            break;
          default:
            statusColor = Colors.grey;
            statusIcon = Icons.cloud_off;
            statusText = 'غير متصل';
        }

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      if (status.lastSync != null)
                        Text(
                          'آخر مزامنة: ${_formatTime(status.lastSync!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('خطأ: $error'),
        ),
      ),
    );
  }

  Widget _buildControlButtons(MongoConnectionState state) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _syncNow,
          icon: const Icon(Icons.sync),
          label: const Text('مزامنة الآن'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _toggleAutoSync,
          icon: Icon(state.autoSyncEnabled ? Icons.stop : Icons.play_arrow),
          label: Text(
            state.autoSyncEnabled ? 'إيقاف المزامنة التلقائية' : 'تفعيل المزامنة التلقائية',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: state.autoSyncEnabled ? Colors.orange : Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncIntervalSelector(MongoConnectionState state) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'فترة المزامنة التلقائية',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _syncIntervalMinutes.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_syncIntervalMinutes دقيقة',
                    onChanged: (value) {
                      setState(() {
                        _syncIntervalMinutes = value.toInt();
                      });
                    },
                  ),
                ),
                Text(
                  '$_syncIntervalMinutes دقيقة',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (state.autoSyncEnabled)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'قم بإيقاف المزامنة التلقائية ثم أعد تفعيلها لتطبيق التغيير',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(AsyncValue<Map<String, dynamic>> statsAsync) {
    return statsAsync.when(
      data: (stats) {
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إحصائيات المزامنة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(height: 24),
                _buildStatRow('النزلاء المحليين', '${stats['local_guests']}'),
                const SizedBox(height: 8),
                _buildStatRow('النزلاء في MongoDB', '${stats['mongo_guests']}'),
                const SizedBox(height: 8),
                _buildStatRow('آخر مزامنة', stats['last_sync'] ?? 'غير متاح'),
                const SizedBox(height: 8),
                _buildStatRow('معرف الجهاز', stats['device_id'] ?? 'غير متاح'),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('خطأ في جلب الإحصائيات: $error'),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'منذ ${diff.inSeconds} ثانية';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else {
      return 'منذ ${diff.inDays} يوم';
    }
  }
}
