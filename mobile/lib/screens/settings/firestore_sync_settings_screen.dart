import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/firestore_sync_provider.dart';
import '../../services/providers.dart';

class FirestoreSyncSettingsScreen extends ConsumerStatefulWidget {
  const FirestoreSyncSettingsScreen({super.key});

  @override
  ConsumerState<FirestoreSyncSettingsScreen> createState() =>
      _FirestoreSyncSettingsScreenState();
}

class _FirestoreSyncSettingsScreenState
    extends ConsumerState<FirestoreSyncSettingsScreen> {
  bool _isLoading = false;

  Future<void> _toggleSync(bool enabled) async {
    setState(() => _isLoading = true);

    try {
      await ref.read(firestoreSyncProvider.notifier).setEnabled(enabled);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled
                ? '✅ تم تفعيل المزامنة اللحظية'
                : '⏸️ تم إيقاف المزامنة اللحظية'),
            backgroundColor: enabled ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في تغيير حالة المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _performManualSync() async {
    setState(() => _isLoading = true);

    try {
      await ref.read(firestoreSyncProvider.notifier).forceSync();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 تمت المزامنة اليدوية بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشلت المزامنة اليدوية: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(firestoreSyncProvider);
    final notesCountAsync = ref.watch(simpleNotesUnreadCountProvider);
    final notesCount = notesCountAsync.maybeWhen(data: (count) => count, orElse: () => 0);

    return AppScaffold(
      title: 'المزامنة اللحظية - Firestore',
      actions: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(syncState),
            const SizedBox(height: 20),
            _buildEnableCard(syncState),
            const SizedBox(height: 20),
            if (syncState.isEnabled) _buildStatisticsCard(syncState, notesCount),
            if (syncState.isEnabled) const SizedBox(height: 20),
            if (syncState.isEnabled) _buildActionButtons(syncState),
            if (syncState.isEnabled) const SizedBox(height: 20),
            if (syncState.isEnabled && syncState.recentEvents.isNotEmpty)
              _buildEventsLog(syncState),
            const SizedBox(height: 20),
            _buildExplanationCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(FirestoreSyncState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: state.isConnected ? Colors.green : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'حالة الاتصال',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatusRow(
              'الحالة',
              state.isEnabled
                  ? (state.isConnected ? 'متصل ✅' : 'غير متصل ❌')
                  : 'معطل ⏸️',
              state.isEnabled
                  ? (state.isConnected ? Colors.green : Colors.red)
                  : Colors.grey,
            ),
            _buildStatusRow(
              'المزامنة',
              state.isEnabled ? 'مفعلة ✅' : 'معطلة ❌',
              state.isEnabled ? Colors.green : Colors.grey,
            ),
            if (state.isSyncing)
              _buildStatusRow(
                'النشاط الحالي',
                'جارِ المزامنة... 🔄',
                Colors.blue,
              ),
            if (state.lastSyncTime != null)
              _buildStatusRow(
                'آخر فحص',
                _formatDateTime(state.lastSyncTime!),
                Colors.grey,
              ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(color: valueColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEnableCard(FirestoreSyncState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تفعيل المزامنة اللحظية',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'عندما تكون مُفعلة، سيتم مزامنة الملاحظات تلقائياً مع Firestore في الوقت الفعلي عبر جميع الأجهزة.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('تفعيل المزامنة اللحظية'),
              subtitle: Text(state.isEnabled
                  ? 'مُفعلة - يتم مزامنة البيانات في الوقت الفعلي'
                  : 'معطلة - لا يتم المزامنة التلقائية'),
              value: state.isEnabled,
              onChanged: !_isLoading ? _toggleSync : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(FirestoreSyncState state, int notesCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                Text(
                  'إحصائيات المزامنة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              Icons.notes,
              'الملاحظات المتزامنة',
              '${state.syncedNotesCount} ملاحظة',
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              Icons.mark_email_unread,
              'الملاحظات غير المقروءة',
              '$notesCount ملاحظة',
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              Icons.access_time,
              'آخر تحديث',
              state.lastSyncTime != null
                  ? _formatDateTime(state.lastSyncTime!)
                  : 'لا يوجد',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(FirestoreSyncState state) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_isLoading || !state.isEnabled)
                ? null
                : _performManualSync,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('مزامنة يدوية الآن'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(firestoreSyncProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث الحالة'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventsLog(FirestoreSyncState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.purple, size: 24),
                const SizedBox(width: 12),
                Text(
                  'سجل الأحداث',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: state.recentEvents.length,
                itemBuilder: (context, index) {
                  final event = state.recentEvents[index];
                  return _buildEventItem(event);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventItem(SyncEvent event) {
    IconData icon;
    Color color;

    switch (event.type) {
      case 'connection':
        icon = Icons.cloud_done;
        color = Colors.green;
        break;
      case 'sync':
        icon = Icons.sync;
        color = Colors.blue;
        break;
      case 'config':
        icon = Icons.settings;
        color = Colors.orange;
        break;
      case 'error':
        icon = Icons.error;
        color = Colors.red;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        event.message,
        style: TextStyle(
          fontSize: 12,
          color: event.isError ? Colors.red : Colors.black87,
        ),
      ),
      trailing: Text(
        _formatTime(event.timestamp),
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    );
  }

  Widget _buildExplanationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'كيف تعمل المزامنة اللحظية؟',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '🔄 1. يتم الاتصال بـ Cloud Firestore في الوقت الفعلي',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '📱 2. أي تغيير تجريه على أي جهاز يظهر فوراً على جميع الأجهزة الأخرى',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '⚡ 3. لا حاجة لتحديث يدوي - البيانات تتحدث تلقائياً',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '✅ 4. العمل دون اتصال - يتم المزامنة عند استعادة الاتصال',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Text(
                '💡 نصيحة: المزامنة اللحظية تعمل على الملاحظات حالياً، وستُوسَّع لتشمل المزيد من البيانات لاحقاً.',
                style: TextStyle(fontSize: 11, color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'الآن';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} د';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} س';
    } else {
      return '${difference.inDays} يوم';
    }
  }
}
