import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart' as ap;
import 'appwrite_logs_screen.dart';

class AppwriteSettingsScreen extends ConsumerStatefulWidget {
  const AppwriteSettingsScreen({super.key});

  @override
  ConsumerState<AppwriteSettingsScreen> createState() =>
      _AppwriteSettingsScreenState();
}

class _AppwriteSettingsScreenState
    extends ConsumerState<AppwriteSettingsScreen> {
  bool _syncEnabled = false;
  bool _isLoading = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkConnection();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _syncEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;
    });
  }

  Future<void> _toggleSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appwrite_sync_enabled', value);
    setState(() => _syncEnabled = value);

    final syncManager = ref.read(ap.appwriteSyncManagerProvider);
    if (value) {
      syncManager.startAutoSync(interval: const Duration(minutes: 15));
      _showSnackBar('تم تفعيل المزامنة التلقائية', Colors.green);
    } else {
      syncManager.stopAutoSync();
      _showSnackBar('تم إيقاف المزامنة التلقائية', Colors.orange);
    }
  }

  Future<void> _checkConnection() async {
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(ap.connectionStatusProvider);
    final syncStatsAsync = ref.watch(ap.syncStatsProvider);
    final outboxCountAsync = ref.watch(ap.outboxCountProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Appwrite',
      actions: [
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'السجلات',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AppwriteLogsScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
          onPressed: () {
            _checkConnection();
            ref.invalidate(ap.syncStatsProvider);
          },
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkConnection();
          ref.invalidate(ap.syncStatsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(connectionState, outboxCountAsync, theme),
            const SizedBox(height: 16),
            _buildSyncActions(connectionState, theme),
            const SizedBox(height: 16),
            _buildStatsSection(syncStatsAsync, theme),
            const SizedBox(height: 16),
            _buildAdvancedSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    ap.ConnectionState connectionState,
    AsyncValue<int> outboxCountAsync,
    ThemeData theme,
  ) {
    final isConnected = connectionState.isConnected;
    final isChecking = connectionState.isChecking;
    final outboxCount = outboxCountAsync.value ?? 0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (isConnected ? Colors.green : Colors.grey)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isChecking
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isConnected ? Icons.cloud_done : Icons.cloud_off,
                          color: isConnected ? Colors.green : Colors.grey,
                          size: 28,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isChecking
                            ? 'جاري الفحص...'
                            : (isConnected ? 'متصل' : 'غير متصل'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                      if (connectionState.errorMessage != null)
                        Text(
                          connectionState.errorMessage!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.red),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: _syncEnabled,
                  onChanged: _toggleSync,
                  activeColor: Colors.green,
                ),
              ],
            ),
            if (outboxCount > 0 || _isLoading) ...[
              const Divider(height: 24),
              Row(
                children: [
                  if (_isLoading) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('جاري المزامنة...')),
                  ] else ...[
                    const Icon(Icons.pending_actions,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '$outboxCount عملية معلقة',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.orange),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncActions(ap.ConnectionState connectionState, ThemeData theme) {
    final isSyncing = _isLoading;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المزامنة',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SyncButton(
                    icon: Icons.cloud_upload,
                    label: 'رفع',
                    color: Colors.blue,
                    isLoading: isSyncing,
                    onPressed: () => _runSync('push'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SyncButton(
                    icon: Icons.cloud_download,
                    label: 'تنزيل',
                    color: Colors.green,
                    isLoading: isSyncing,
                    onPressed: () => _runSync('pull'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SyncButton(
                    icon: Icons.sync,
                    label: 'كامل',
                    color: Colors.purple,
                    isLoading: isSyncing,
                    onPressed: () => _runSync('full'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(
      AsyncValue<Map<String, dynamic>> syncStatsAsync, ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إحصائيات المزامنة',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            syncStatsAsync.when(
              data: (stats) {
                final lastSync = stats['lastSyncTime'] as DateTime?;
                final totalPushed = stats['totalPushed'] ?? 0;
                final totalPulled = stats['totalPulled'] ?? 0;
                final conflicts = stats['conflicts'] ?? 0;

                return Column(
                  children: [
                    _StatRow(
                      'آخر مزامنة',
                      lastSync != null
                          ? DateFormat('yyyy/MM/dd HH:mm').format(lastSync)
                          : '---',
                    ),
                    _StatRow('إجمالي المرفوعات', '$totalPushed'),
                    _StatRow('إجمالي المسحوبات', '$totalPulled'),
                    _StatRow('التعارضات', '$conflicts'),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('خطأ في تحميل الإحصائيات: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSection(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.build),
            title: const Text('أدوات متقدمة'),
            trailing: Icon(
              _showAdvanced ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          ),
          if (_showAdvanced) ...[
            const Divider(height: 1),
            _ToolTile(
              icon: Icons.cleaning_services,
              title: 'تنظيف العمليات المعلقة',
              subtitle: 'حذف العمليات الفاشلة',
              onTap: _clearPendingOperations,
            ),
            _ToolTile(
              icon: Icons.delete_sweep,
              title: 'مسح الذاكرة المؤقتة',
              subtitle: 'تنظيف البيانات المؤقتة',
              onTap: _clearCache,
            ),
            _ToolTile(
              icon: Icons.refresh,
              title: 'إعادة تعيين المزامنة',
              subtitle: 'مسح حالة المزامنة والبدء من جديد',
              onTap: _resetSync,
              isDestructive: true,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runSync(String type) async {
    setState(() => _isLoading = true);
    try {
      final syncManager = ref.read(ap.appwriteSyncManagerProvider);
      switch (type) {
        case 'push':
          await syncManager.pushLocalChanges();
          _showSnackBar('تم رفع البيانات بنجاح', Colors.green);
          break;
        case 'pull':
          await syncManager.pullRemoteChanges();
          _showSnackBar('تم تنزيل البيانات بنجاح', Colors.green);
          break;
        case 'full':
          await syncManager.sync(push: true, pull: true);
          _showSnackBar('تمت المزامنة الكاملة بنجاح', Colors.green);
          break;
      }
      ref.invalidate(ap.syncStatsProvider);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearPendingOperations() async {
    final confirm = await _showConfirmDialog(
      'تنظيف العمليات المعلقة',
      'سيتم حذف جميع العمليات المعلقة. هل أنت متأكد؟',
    );
    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      final syncManager = ref.read(ap.appwriteSyncManagerProvider);
      await syncManager.clearOutbox();
      _showSnackBar('تم تنظيف العمليات المعلقة', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isLoading = true);
    try {
      final cacheManager = ref.read(ap.appwriteCacheManagerProvider);
      await cacheManager.clearAll();
      _showSnackBar('تم مسح الذاكرة المؤقتة', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetSync() async {
    final confirm = await _showConfirmDialog(
      'إعادة تعيين المزامنة',
      'سيتم مسح جميع بيانات المزامنة وإعادة البدء. هل أنت متأكد؟',
      isDestructive: true,
    );
    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('appwrite_last_sync');
      await prefs.remove('appwrite_sync_enabled');

      final syncManager = ref.read(ap.appwriteSyncManagerProvider);
      syncManager.stopAutoSync();
      await syncManager.clearOutbox();

      setState(() => _syncEnabled = false);
      _showSnackBar('تم إعادة تعيين المزامنة', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmDialog(
    String title,
    String message, {
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _SyncButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  const _SyncButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
