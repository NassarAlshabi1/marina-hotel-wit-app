import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart' as ap;
import '../../services/restore_fix_service.dart';
import '../../services/local_db.dart';
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

    if (value) {
      ref.read(ap.appwriteSyncProvider.notifier).startRealtimeSync();
      _showSnackBar('تم تفعيل المزامنة التلقائية', Colors.green);
    } else {
      ref.read(ap.appwriteSyncProvider.notifier).stopRealtimeSync();
      _showSnackBar('تم إيقاف المزامنة التلقائية', Colors.orange);
    }
  }

  void _showSnackBar(String message, Color color) {
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
    final syncState = ref.watch(ap.appwriteSyncProvider);
    final pendingOps = ref.watch(ap.pendingOperationsProvider);
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
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ap.pendingOperationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(syncState, pendingOps, theme),
            const SizedBox(height: 16),
            _buildSyncActions(syncState, theme),
            const SizedBox(height: 16),
            _buildAdvancedSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    ap.AppwriteSyncState syncState,
    AsyncValue<List<Map<String, dynamic>>> pendingOps,
    ThemeData theme,
  ) {
    final isConnected = syncState.isRealtimeConnected;
    final lastSync = syncState.lastSyncTime;
    final pendingCount = pendingOps.value?.length ?? 0;

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
                    color: (isConnected ? Colors.green : Colors.grey).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
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
                        isConnected ? 'متصل' : 'غير متصل',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                      if (lastSync != null)
                        Text(
                          'آخر مزامنة: ${DateFormat('yyyy/MM/dd HH:mm').format(lastSync)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
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
            if (pendingCount > 0 || syncState.isSyncing) ...[
              const Divider(height: 24),
              Row(
                children: [
                  if (syncState.isSyncing) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncState.currentOperation ?? 'جاري المزامنة...',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ] else ...[
                    Icon(Icons.pending_actions, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '$pendingCount عملية معلقة',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange,
                      ),
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

  Widget _buildSyncActions(ap.AppwriteSyncState syncState, ThemeData theme) {
    final isSyncing = syncState.isSyncing || _isLoading;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المزامنة',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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

  Future<void> _runSync(String type) async {
    setState(() => _isLoading = true);
    try {
      final syncNotifier = ref.read(ap.appwriteSyncProvider.notifier);
      switch (type) {
        case 'push':
          await syncNotifier.pushToAppwrite();
          _showSnackBar('تم رفع البيانات بنجاح', Colors.green);
          break;
        case 'pull':
          await syncNotifier.pullFromAppwrite();
          _showSnackBar('تم تنزيل البيانات بنجاح', Colors.green);
          break;
        case 'full':
          await syncNotifier.fullSync();
          _showSnackBar('تمت المزامنة الكاملة بنجاح', Colors.green);
          break;
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
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
              icon: Icons.build_circle,
              title: 'إصلاح البيانات',
              subtitle: 'إصلاح التعارضات والتكرارات',
              onTap: _runDataRepair,
            ),
            _ToolTile(
              icon: Icons.refresh,
              title: 'إعادة تعيين المزامنة',
              subtitle: 'مسح حالة المزامنة والبدء من جديد',
              onTap: _resetSync,
              isDestructive: true,
            ),
            _ToolTile(
              icon: Icons.delete_sweep,
              title: 'مسح الذاكرة المؤقتة',
              subtitle: 'تنظيف البيانات المؤقتة',
              onTap: _clearCache,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _clearPendingOperations() async {
    final confirm = await _showConfirmDialog(
      'تنظيف العمليات المعلقة',
      'سيتم حذف جميع العمليات المعلقة. هل أنت متأكد؟',
    );
    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      final db = LocalDb.instance.database;
      await db.delete('sync_queue');
      ref.invalidate(ap.pendingOperationsProvider);
      _showSnackBar('تم تنظيف العمليات المعلقة', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runDataRepair() async {
    setState(() => _isLoading = true);
    try {
      final service = RestoreFixService();
      final result = await service.fixAllData();
      _showSnackBar(
        'تم الإصلاح: ${result['fixed'] ?? 0} عنصر',
        Colors.green,
      );
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
      await prefs.remove('last_sync_time');
      await prefs.remove('appwrite_sync_enabled');

      final db = LocalDb.instance.database;
      await db.delete('sync_queue');

      ref.read(ap.appwriteSyncProvider.notifier).stopRealtimeSync();

      setState(() => _syncEnabled = false);
      _showSnackBar('تم إعادة تعيين المزامنة', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('cache_')).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
      _showSnackBar('تم مسح الذاكرة المؤقتة (${keys.length} عنصر)', Colors.green);
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
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
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
