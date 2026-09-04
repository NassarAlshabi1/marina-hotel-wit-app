import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../states/cloudflare_migration_state.dart';
import '../../services/local_db.dart';

class CloudflareMigrationScreen extends ConsumerStatefulWidget {
  const CloudflareMigrationScreen({super.key});

  @override
  ConsumerState<CloudflareMigrationScreen> createState() =>
      _CloudflareMigrationScreenState();
}

class _CloudflareMigrationScreenState
    extends ConsumerState<CloudflareMigrationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cloudflareMigrationProvider.notifier).checkStatus();
    });
  }

  Future<String> _workerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cf_worker_url') ?? 'cloudflare.workers.dev';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudflareMigrationProvider);
    final notifier = ref.read(cloudflareMigrationProvider.notifier);

    return AppScaffold(
      title: 'ترحيل إلى Cloudflare',
      actions: [
        if (state.status == MigrationStatus.running)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.checkStatus(),
            tooltip: 'تحديث',
          ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(state),
            const SizedBox(height: 20),
            if (state.status == MigrationStatus.measuring) _buildMeasuring(),
            if (state.status == MigrationStatus.running) ...[
              _buildProgress(state),
              const SizedBox(height: 24),
              _buildCurrentTable(state),
            ],
            if (state.status == MigrationStatus.idle ||
                state.status == MigrationStatus.failed ||
                state.status == MigrationStatus.partial)
              _buildRecordCounts(state),
            if (state.status == MigrationStatus.partial ||
                state.status == MigrationStatus.failed)
              _buildErrors(state),
            _buildTableProgress(state),
            const SizedBox(height: 24),
            _buildActions(state, notifier),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(MigrationState state) {
    final color = state.isComplete
        ? Colors.green
        : state.status == MigrationStatus.failed ||
              state.status == MigrationStatus.partial
        ? Colors.red
        : Colors.blue;
    final icon = state.isComplete
        ? Icons.cloud_done
        : state.status == MigrationStatus.failed
        ? Icons.cloud_off
        : Icons.cloud_upload;
    return Card(
      color: color.withOpacity(0.08),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          state.isComplete
              ? 'تم الترحيل بنجاح'
              : state.status == MigrationStatus.failed
                  ? 'فشل الترحيل'
                  : state.status == MigrationStatus.partial
                      ? 'مرحلّي'
                      : 'ترحيل البيانات إلى Cloudflare',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        subtitle: FutureBuilder<String>(
          future: _workerUrl(),
          builder: (_, snap) => Text(
            state.isComplete
                ? '${state.totalPushed} سجل تم رفعه'
                : state.status == MigrationStatus.running
                    ? 'جارٍ الرفع... ${state.totalPushed}/${state.totalRecords}'
                    : 'انقل جميع البيانات المحلية إلى ${snap.data ?? ''}',
            style: TextStyle(color: color.withOpacity(0.75)),
          ),
        ),
      ),
    );
  }

  Widget _buildMeasuring() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text('قياس سرعة الشبكة وحساب حجم الدفعة...'),
            SizedBox(height: 12),
            LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('يرجى الانتظار', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(MigrationState state) {
    final pct = (state.progress * 100).clamp(0, 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('التقدّم: $pct% (${state.totalPushed} / ${state.totalRecords} سجل)'),
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: 8),
        Text('${state.totalPushed} رفعت / ${state.totalFailed} فشلت / ${state.totalRecords} إجمالاً'),
      ],
    );
  }

  Widget _buildCurrentTable(MigrationState state) {
    final order = state.tables;
    final idx = order.indexOf(state.currentTable);
    final pos = idx < 0 ? '' : '${idx + 1}/${order.length}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الجدول الحالي: ${state.currentTable.isEmpty ? '---' : state.currentTable}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (pos.isNotEmpty)
                    Text('جدول $pos', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCounts(MigrationState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('إحصائيات الترحيل', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _statRow('إجمالي السجلات', state.totalRecords, Colors.blue),
            _statRow('تم الرفع', state.totalPushed, Colors.green),
            _statRow('فشل الرفع', state.totalFailed, Colors.red),
            if (state.networkSpeedKbps > 0) _statRow('سرعة الشبكة', '${state.networkSpeedKbps.toStringAsFixed(1)} KB/s', Colors.orange),
            if (state.batchSize > 0) _statRow('حجم الدفعة', '${state.batchSize} سجل', Colors.purple),
            _statRow('الجداول', '${state.tablesDone}/${state.tablesTotal}', Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, dynamic value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTableProgress(MigrationState state) {
    final order = state.tables;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('حالة الجداول (${state.tablesDone}/${state.tablesTotal})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...order.asMap().entries.map((e) {
              final i = e.key;
              final table = e.value;
              final done = state.tableProgress[table] ?? false;
              final isCurrent = state.currentTable == table;
              final icon = done
                  ? Icons.check_circle
                  : isCurrent
                      ? Icons.sync
                      : Icons.radio_button_unchecked;
              final color = done ? Colors.green : isCurrent ? Colors.orange : Colors.grey;
              return ListTile(
                leading: Icon(icon, color: color, size: 20),
                title: Text(table),
                trailing: Text('$i/${order.length}', style: const TextStyle(color: Colors.grey)),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildErrors(MigrationState state) {
    final errors = state.errorMessage;
    if (errors == null || errors.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.red.withOpacity(0.05),
      child: ExpansionTile(
        title: const Text('الأخطاء', style: TextStyle(color: Colors.red)),
        children: errors.split('\n').map((e) => ListTile(
          leading: const Icon(Icons.error, color: Colors.red, size: 16),
          title: Text(e, style: const TextStyle(fontSize: 12)),
        )).toList(),
      ),
    );
  }

  Widget _buildActions(MigrationState state, CloudflareMigrationNotifier notifier) {
    final dbAvailable = DatabaseManager.isInitialized;
    final canStart =
        state.status != MigrationStatus.running &&
        dbAvailable;

    return Column(
      children: [
        if (state.status == MigrationStatus.idle ||
            state.status == MigrationStatus.failed ||
            state.status == MigrationStatus.partial)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canStart
                  ? () async {
                      final db = DatabaseManager.instance;
                      await notifier.startMigration(db);
                    }
                  : null,
              icon: const Icon(Icons.cloud_upload),
              label: Text(state.isComplete ? 'إعادة الترحيل' : 'بدء ترحيل البيانات'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (state.status == MigrationStatus.failed ||
            state.status == MigrationStatus.partial ||
            state.isComplete)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => notifier.reset(),
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة تعيين'),
            ),
          ),
        if (!dbAvailable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('قاعدة البيانات غير جاهزة', style: TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ),
      ],
    );
  }
}
