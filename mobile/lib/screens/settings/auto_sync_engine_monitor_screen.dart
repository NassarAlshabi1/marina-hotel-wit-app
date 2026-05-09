import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/auto_sync_engine_providers.dart';
import '../../services/google_drive_auto_sync_engine.dart';
import '../../services/google_drive_conflict_resolver.dart';

class AutoSyncEngineMonitorScreen extends ConsumerStatefulWidget {
  const AutoSyncEngineMonitorScreen({super.key});

  @override
  ConsumerState<AutoSyncEngineMonitorScreen> createState() =>
      _AutoSyncEngineMonitorScreenState();
}

class _AutoSyncEngineMonitorScreenState
    extends ConsumerState<AutoSyncEngineMonitorScreen> {
  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(autoSyncEngineStateProvider);
    final syncHealth = ref.watch(autoSyncHealthSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('محرك المزامنة التلقائي'),
        backgroundColor: Colors.blue.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(autoSyncEngineStatusProvider);
              ref.invalidate(conflictStatisticsProvider);
            },
          ),
        ],
      ),
      body: engineState.when(
        data: (state) => _buildContent(context, state, syncHealth),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('خطأ: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(autoSyncEngineStateProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AutoSyncEngineState state,
    String health,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(autoSyncEngineStatusProvider);
        ref.invalidate(conflictStatisticsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHealthBanner(state, health),
          const SizedBox(height: 16),
          _buildStatusCard(state),
          const SizedBox(height: 16),
          _buildPendingChangesCard(state),
          const SizedBox(height: 16),
          if (state.failedAttempts > 0) ...[
            _buildRetryCard(state),
            const SizedBox(height: 16),
          ],
          _buildTimestampsCard(state),
          const SizedBox(height: 16),
          _buildConflictStatsCard(),
          const SizedBox(height: 16),
          _buildActionsCard(context, state),
          const SizedBox(height: 16),
          _buildSettingsCard(context),
        ],
      ),
    );
  }

  Widget _buildHealthBanner(AutoSyncEngineState state, String health) {
    Color bannerColor;
    IconData bannerIcon;

    if (!state.isRunning) {
      bannerColor = Colors.red;
      bannerIcon = Icons.stop_circle;
    } else if (!state.hasNetworkConnection) {
      bannerColor = Colors.orange;
      bannerIcon = Icons.wifi_off;
    } else if (!state.isSignedIn) {
      bannerColor = Colors.orange;
      bannerIcon = Icons.lock;
    } else if (state.failedAttempts > 0) {
      bannerColor = Colors.orange;
      bannerIcon = Icons.warning;
    } else if (state.pendingChangesCount > 0) {
      bannerColor = Colors.blue;
      bannerIcon = Icons.pending_actions;
    } else {
      bannerColor = Colors.green;
      bannerIcon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(bannerIcon, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'حالة المحرك',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  health,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(AutoSyncEngineState state) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'الحالة العامة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildStatusRow('المحرك يعمل', state.isRunning, Icons.settings),
            _buildStatusRow(
              'متصل بالشبكة',
              state.hasNetworkConnection,
              Icons.wifi,
            ),
            _buildStatusRow('مسجل الدخول', state.isSignedIn, Icons.login),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool value, IconData icon) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        value ? Icons.check_circle : Icons.cancel,
        color: value ? Colors.green : Colors.red,
      ),
      title: Text(label),
      trailing: Icon(icon, color: Colors.grey.shade400, size: 20),
    );
  }

  Widget _buildPendingChangesCard(AutoSyncEngineState state) {
    final hasPending = state.pendingChangesCount > 0;

    return Card(
      elevation: 2,
      color: hasPending ? Colors.orange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasPending ? Icons.pending_actions : Icons.check_circle,
                  color: hasPending ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                const Text(
                  'التغييرات المعلقة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            Center(
              child: Text(
                '${state.pendingChangesCount}',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: hasPending ? Colors.orange : Colors.green,
                ),
              ),
            ),
            if (state.lastSuccessfulSync != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'آخر مزامنة ناجحة: ${_formatRelativeTime(state.lastSuccessfulSync!)}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRetryCard(AutoSyncEngineState state) {
    return Card(
      elevation: 2,
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'إعادة المحاولة التلقائية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            LinearProgressIndicator(
              value: state.failedAttempts / 5,
              backgroundColor: Colors.red.shade100,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              'محاولات فاشلة: ${state.failedAttempts} / 5',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (state.nextRetryAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.timer, size: 16, color: Colors.red),
                  const SizedBox(width: 4),
                  Text(
                    'إعادة المحاولة التالية: ${_formatRelativeTime(state.nextRetryAt!)}',
                  ),
                ],
              ),
            ],
            if (state.lastError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.lastError!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await AutoSyncEngine.instance.resetFailedAttempts();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ تم إعادة تعيين المحاولات')),
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة تعيين'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimestampsCard(AutoSyncEngineState state) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.access_time, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'الطوابع الزمنية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildTimestampRow(
              'آخر مزامنة ناجحة',
              state.lastSuccessfulSync,
              Icons.check_circle,
              Colors.green,
            ),
            if (state.nextRetryAt != null)
              _buildTimestampRow(
                'إعادة المحاولة التالية',
                state.nextRetryAt,
                Icons.timer,
                Colors.orange,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimestampRow(
    String label,
    DateTime? timestamp,
    IconData icon,
    Color color,
  ) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(label),
      trailing: Text(
        timestamp != null ? _formatRelativeTime(timestamp) : 'لم يحدث بعد',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }

  Widget _buildConflictStatsCard() {
    final conflictStatsAsync = ref.watch(conflictStatisticsProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.merge, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'إحصائيات التضارب',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            conflictStatsAsync.when(
              data: (stats) {
                final totalConflicts = stats['total_conflicts'] as int? ?? 0;
                final byTable = stats['by_table'] as Map<String, int>? ?? {};
                final avgTimeDiff =
                    stats['avg_time_diff_seconds'] as double? ?? 0.0;
                final manualReviews =
                    stats['manual_reviews_needed'] as int? ?? 0;

                if (totalConflicts == 0) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 48,
                            color: Colors.green,
                          ),
                          SizedBox(height: 8),
                          Text('لا توجد تضاربات مسجلة'),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('إجمالي التضاربات'),
                      trailing: Chip(
                        label: Text('$totalConflicts'),
                        backgroundColor: Colors.purple.shade100,
                      ),
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('متوسط الفرق الزمني'),
                      trailing: Text('${avgTimeDiff.toStringAsFixed(1)} ثانية'),
                    ),
                    if (manualReviews > 0)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('يحتاج مراجعة يدوية'),
                        trailing: Chip(
                          label: Text('$manualReviews'),
                          backgroundColor: Colors.orange.shade100,
                        ),
                      ),
                    if (byTable.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'التضاربات حسب الجدول:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      ...byTable.entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade300,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(entry.key)),
                              Chip(
                                label: Text('${entry.value}'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Colors.purple.shade50,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showConflictHistory(context),
                        icon: const Icon(Icons.history),
                        label: const Text('عرض السجل الكامل'),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Center(child: Text('خطأ: $error')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context, AutoSyncEngineState state) {
    final canSync =
        state.isRunning && state.hasNetworkConnection && state.isSignedIn;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.touch_app, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'الإجراءات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            ElevatedButton.icon(
              onPressed: canSync ? () => _performManualSync(context) : null,
              icon: const Icon(Icons.sync),
              label: const Text('مزامنة يدوية'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: state.failedAttempts > 0
                  ? () => _resetFailedAttempts(context)
                  : null,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة تعيين المحاولات'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showFullStatus(context),
              icon: const Icon(Icons.code),
              label: const Text('عرض JSON الكامل'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.settings, color: Colors.grey),
                SizedBox(width: 8),
                Text(
                  'الإعدادات السريعة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Debouncing'),
              subtitle: const Text('فترة تجميع التغييرات'),
              trailing: const Text('5 ثوانٍ'),
              onTap: () => _showDebounceSettings(context),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Pull Interval'),
              subtitle: const Text('فترة فحص التحديثات'),
              trailing: const Text('2 دقيقة'),
              onTap: () => _showPullIntervalSettings(context),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('استراتيجية التضارب'),
              subtitle: const Text('كيفية حل التضاربات'),
              trailing: const Text('الأحدث يفوز'),
              onTap: () => _showConflictStrategySettings(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performManualSync(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جارٍ المزامنة...'),
          ],
        ),
      ),
    );

    try {
      final result = await AutoSyncEngine.instance.forceSyncNow();

      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        final message = result.success
            ? '✅ ${result.message}\n'
                  '📤 مرفوع: ${result.pushedChanges ?? 0}\n'
                  '📥 مسحوب: ${result.pulledChanges ?? 0}'
            : '❌ ${result.message}\n'
                  '${result.error ?? ""}';

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result.success ? 'نجح!' : 'فشل'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }

      ref.invalidate(autoSyncEngineStateProvider);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resetFailedAttempts(BuildContext context) async {
    await AutoSyncEngine.instance.resetFailedAttempts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم إعادة تعيين المحاولات الفاشلة'),
          backgroundColor: Colors.green,
        ),
      );
    }
    ref.invalidate(autoSyncEngineStateProvider);
  }

  Future<void> _showFullStatus(BuildContext context) async {
    final statusAsync = ref.read(autoSyncEngineStatusProvider);

    statusAsync.when(
      data: (status) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('الحالة الكاملة (JSON)'),
            content: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(status),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      },
      loading: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('جارٍ التحميل...')));
      },
      error: (error, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر تحميل الحالة الكاملة. حاول مرة أخرى'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: () => _showFullStatus(context),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showConflictHistory(BuildContext context) async {
    final historyAsync = ref.read(conflictHistoryProvider);

    historyAsync.when(
      data: (history) {
        if (history.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('لا يوجد سجل تضاربات')));
          return;
        }

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade700,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.history, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'سجل التضاربات',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final entry = history[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.shade100,
                          child: Text('${index + 1}'),
                        ),
                        title: Text('${entry['table'] as String} / ${entry['uuid'] as String}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry['resolution'] as String? ?? ''),
                            Text(
                              'الفرق الزمني: ${entry['time_diff_seconds'] as String? ?? ''} ثانية',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        trailing: Text(
                          _formatTimestamp(entry['timestamp'] as String?),
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () {
        showDialog(
          context: context,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('جارٍ التحميل...'),
              ],
            ),
          ),
        );
      },
      error: (error, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر تحميل سجل التضاربات. حاول مرة أخرى'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: () => _showConflictHistory(context),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDebounceSettings(BuildContext context) async {
    final current = await AutoSyncEngine.instance.getEngineStatus();
    final currentDebounce =
        (current['coordinator']?['debounce_seconds'] as int?) ?? 5;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ضبط Debouncing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('فترة تجميع التغييرات قبل الرفع'),
              const SizedBox(height: 16),
              ...[2, 5, 10, 15].map(
                (seconds) => RadioListTile<int>(
                  title: Text('$seconds ثانية'),
                  subtitle: Text(_getDebounceDescription(seconds)),
                  value: seconds,
                  groupValue: currentDebounce,
                  onChanged: (value) async {
                    if (value != null) {
                      await AutoSyncEngine.instance.setDebounceSeconds(value);
                      if (context.mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ تم تعيين Debounce إلى $value ثانية',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _showPullIntervalSettings(BuildContext context) async {
    final current = await AutoSyncEngine.instance.getEngineStatus();
    final currentInterval =
        (current['coordinator']?['pull_interval_minutes'] as int?) ?? 2;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ضبط فترة Pull'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('فترة فحص التحديثات من الأجهزة الأخرى'),
              const SizedBox(height: 16),
              ...[1, 2, 5, 10, 15].map(
                (minutes) => RadioListTile<int>(
                  title: Text('$minutes دقيقة'),
                  subtitle: Text(_getPullIntervalDescription(minutes)),
                  value: minutes,
                  groupValue: currentInterval,
                  onChanged: (value) async {
                    if (value != null) {
                      await AutoSyncEngine.instance.setPullInterval(value);
                      if (context.mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ تم تعيين Pull Interval إلى $value دقيقة',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _showConflictStrategySettings(BuildContext context) async {
    final resolver = GoogleDriveConflictResolver.instance;
    final currentStrategy = await resolver.getStrategy();

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('استراتيجية حل التضارب'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: ConflictResolutionStrategy.values.map((strategy) {
                return RadioListTile<ConflictResolutionStrategy>(
                  title: Text(_getStrategyName(strategy)),
                  subtitle: Text(_getStrategyDescription(strategy)),
                  value: strategy,
                  groupValue: currentStrategy,
                  onChanged: (value) async {
                    if (value != null) {
                      await AutoSyncEngine.instance.setConflictStrategy(value);
                      if (context.mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ تم تعيين الاستراتيجية: ${_getStrategyName(value)}',
                            ),
                          ),
                        );
                      }
                    }
                  },
                );
              }).toList(),
            ),
          ),
        ),
      );
    }
  }

  String _getDebounceDescription(int seconds) {
    if (seconds <= 2) return 'سريع جداً - استجابة فورية';
    if (seconds <= 5) return 'متوازن - موصى به';
    if (seconds <= 10) return 'بطيء - توفير البطارية';
    return 'بطيء جداً';
  }

  String _getPullIntervalDescription(int minutes) {
    if (minutes <= 1) return 'سريع جداً - تحديثات فورية';
    if (minutes <= 2) return 'سريع - موصى به';
    if (minutes <= 5) return 'متوسط - متوازن';
    return 'بطيء - توفير البيانات';
  }

  String _getStrategyName(ConflictResolutionStrategy strategy) {
    switch (strategy) {
      case ConflictResolutionStrategy.newerWins:
        return 'الأحدث يفوز';
      case ConflictResolutionStrategy.localWins:
        return 'المحلي يفوز دائماً';
      case ConflictResolutionStrategy.remoteWins:
        return 'البعيد يفوز دائماً';
      case ConflictResolutionStrategy.devicePriorityBased:
        return 'حسب أولوية الجهاز';
      case ConflictResolutionStrategy.manualReview:
        return 'مراجعة يدوية';
    }
  }

  String _getStrategyDescription(ConflictResolutionStrategy strategy) {
    switch (strategy) {
      case ConflictResolutionStrategy.newerWins:
        return 'البيانات الأحدث زمنياً تفوز (افتراضي)';
      case ConflictResolutionStrategy.localWins:
        return 'البيانات المحلية تفوز دائماً';
      case ConflictResolutionStrategy.remoteWins:
        return 'البيانات من Google Drive تفوز دائماً';
      case ConflictResolutionStrategy.devicePriorityBased:
        return 'حسب أولوية الجهاز المعرّفة';
      case ConflictResolutionStrategy.manualReview:
        return 'يتطلب تدخل المستخدم';
    }
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.isNegative) {
      final absDiff = diff.abs();
      if (absDiff.inSeconds < 60) {
        return 'بعد ${absDiff.inSeconds} ثانية';
      } else if (absDiff.inMinutes < 60) {
        return 'بعد ${absDiff.inMinutes} دقيقة';
      } else {
        return 'بعد ${absDiff.inHours} ساعة';
      }
    } else {
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

  String _formatTimestamp(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd/MM HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }
}
