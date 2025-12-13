import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../utils/database_health_checker.dart';

class DatabaseHealthScreen extends ConsumerStatefulWidget {
  const DatabaseHealthScreen({super.key});

  @override
  ConsumerState<DatabaseHealthScreen> createState() => _DatabaseHealthScreenState();
}

class _DatabaseHealthScreenState extends ConsumerState<DatabaseHealthScreen> {
  Map<String, dynamic>? _healthData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _runHealthCheck();
  }

  Future<void> _runHealthCheck() async {
    setState(() => _isLoading = true);
    
    final db = ref.read(databaseProvider);
    final checker = DatabaseHealthChecker(db);
    
    try {
      final health = await checker.performHealthCheck();
      setState(() {
        _healthData = health;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _healthData = {'overall': 'error', 'error': e.toString()};
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'سلامة قاعدة البيانات',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _runHealthCheck,
          tooltip: 'إعادة الفحص',
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _healthData == null
              ? const Center(child: Text('جاري الفحص...'))
              : _buildHealthReport(),
    );
  }

  Widget _buildHealthReport() {
    final overall = _healthData!['overall'] as String;
    final isHealthy = overall == 'healthy';

    return RefreshIndicator(
      onRefresh: _runHealthCheck,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverallStatusCard(isHealthy),
          const SizedBox(height: 16),
          _buildSchemaVersionCard(),
          const SizedBox(height: 16),
          _buildForeignKeysCard(),
          const SizedBox(height: 16),
          _buildTablesCard(),
          const SizedBox(height: 16),
          _buildIndexesCard(),
          const SizedBox(height: 16),
          _buildSyncFieldsCard(),
          const SizedBox(height: 16),
          _buildOutboxCard(),
          const SizedBox(height: 16),
          _buildSyncStateCard(),
          const SizedBox(height: 16),
          _buildDataIntegrityCard(),
          const SizedBox(height: 16),
          _buildActionsCard(),
        ],
      ),
    );
  }

  Widget _buildOverallStatusCard(bool isHealthy) {
    return Card(
      color: isHealthy ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              isHealthy ? Icons.check_circle : Icons.error,
              size: 64,
              color: isHealthy ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 12),
            Text(
              isHealthy ? 'قاعدة البيانات سليمة' : 'توجد مشاكل',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isHealthy ? Colors.green.shade900 : Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _healthData!['timestamp'] as String,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchemaVersionCard() {
    final schema = _healthData!['schemaVersion'] as Map<String, dynamic>;
    final status = schema['status'] as String;
    final isOk = status == 'ok';

    return _buildInfoCard(
      title: 'إصدار Schema',
      icon: Icons.storage,
      color: isOk ? Colors.blue : Colors.orange,
      children: [
        _buildInfoRow('الإصدار الحالي', '${schema['version']}'),
        _buildInfoRow('الإصدار المتوقع', '${schema['expected']}'),
        _buildStatusBadge(status),
      ],
    );
  }

  Widget _buildForeignKeysCard() {
    final fk = _healthData!['foreignKeys'] as Map<String, dynamic>;
    final enabled = fk['enabled'] as bool;

    return _buildInfoCard(
      title: 'المفاتيح الأجنبية',
      icon: Icons.key,
      color: enabled ? Colors.green : Colors.red,
      children: [
        _buildInfoRow('الحالة', enabled ? 'مفعّلة' : 'معطّلة'),
        _buildStatusBadge(fk['status'] as String),
      ],
    );
  }

  Widget _buildTablesCard() {
    final tables = _healthData!['tables'] as Map<String, dynamic>;
    final missing = tables['missing'] as List;
    final isOk = missing.isEmpty;

    return _buildInfoCard(
      title: 'الجداول',
      icon: Icons.table_chart,
      color: isOk ? Colors.blue : Colors.orange,
      children: [
        _buildInfoRow('المتوقعة', '${tables['expected']}'),
        _buildInfoRow('الموجودة', '${tables['found']}'),
        if (!isOk) ...[
          const SizedBox(height: 8),
          Text(
            'الناقصة: ${missing.join(', ')}',
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ],
        _buildStatusBadge(tables['status'] as String),
      ],
    );
  }

  Widget _buildIndexesCard() {
    final indexes = _healthData!['indexes'] as Map<String, dynamic>;
    final byTable = indexes['byTable'] as Map;

    return _buildInfoCard(
      title: 'الفهارس',
      icon: Icons.speed,
      color: Colors.purple,
      children: [
        _buildInfoRow('العدد الكلي', '${indexes['total']}'),
        const SizedBox(height: 8),
        Text(
          'الجداول المفهرسة: ${byTable.length}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        _buildStatusBadge(indexes['status'] as String),
      ],
    );
  }

  Widget _buildSyncFieldsCard() {
    final syncFields = _healthData!['syncFields'] as Map<String, dynamic>;
    final tables = syncFields['tables'] as Map;
    final validCount = syncFields['valid'] as int;
    final invalidCount = syncFields['invalid'] as int;

    return _buildInfoCard(
      title: 'حقول المزامنة',
      icon: Icons.sync,
      color: invalidCount == 0 ? Colors.green : Colors.orange,
      children: [
        _buildInfoRow('الصالحة', '$validCount'),
        _buildInfoRow('غير الصالحة', '$invalidCount'),
        if (invalidCount > 0) ...[
          const SizedBox(height: 8),
          ...tables.entries
              .where((e) => e.value == false)
              .map((e) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '⚠ ${e.key}',
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  )),
        ],
        _buildStatusBadge(syncFields['status'] as String),
      ],
    );
  }

  Widget _buildOutboxCard() {
    final outbox = _healthData!['outbox'] as Map<String, dynamic>;
    final pending = outbox['pending'] as int;
    final failed = outbox['failed'] as int;
    final status = outbox['status'] as String;

    return _buildInfoCard(
      title: 'صندوق الصادر (Outbox)',
      icon: Icons.outbox,
      color: failed > 0 ? Colors.orange : Colors.blue,
      children: [
        _buildInfoRow('المعلقة', '$pending'),
        _buildInfoRow('الفاشلة (>5 محاولات)', '$failed'),
        _buildStatusBadge(status),
      ],
    );
  }

  Widget _buildSyncStateCard() {
    final syncState = _healthData!['syncState'] as Map<String, dynamic>;
    final initialized = syncState['initialized'] as bool;

    if (!initialized) {
      return _buildInfoCard(
        title: 'حالة المزامنة',
        icon: Icons.sync_problem,
        color: Colors.orange,
        children: [
          const Text('المزامنة غير مهيأة'),
          _buildStatusBadge('not_initialized'),
        ],
      );
    }

    final isSyncing = syncState['isSyncing'] as bool;
    final hoursSince = syncState['hoursSinceLastSync'] as String;

    return _buildInfoCard(
      title: 'حالة المزامنة',
      icon: Icons.sync,
      color: isSyncing ? Colors.blue : Colors.green,
      children: [
        _buildInfoRow('مهيأة', initialized ? 'نعم' : 'لا'),
        _buildInfoRow('جارية', isSyncing ? 'نعم' : 'لا'),
        _buildInfoRow('منذ آخر مزامنة', '$hoursSince ساعة'),
        _buildStatusBadge(syncState['status'] as String),
      ],
    );
  }

  Widget _buildDataIntegrityCard() {
    final integrity = _healthData!['dataIntegrity'] as Map<String, dynamic>;
    final issues = integrity['issues'] as List;
    final hasIssues = issues.isNotEmpty;

    return _buildInfoCard(
      title: 'سلامة البيانات',
      icon: Icons.verified_user,
      color: hasIssues ? Colors.orange : Colors.green,
      children: [
        if (hasIssues) ...[
          const Text(
            'المشاكل المكتشفة:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...issues.map((issue) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.orange)),
                    Expanded(
                      child: Text(
                        issue as String,
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              )),
        ] else ...[
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text('لا توجد مشاكل'),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _buildStatusBadge(integrity['status'] as String),
      ],
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
              'الإجراءات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _copyReportToClipboard,
                icon: const Icon(Icons.copy),
                label: const Text('نسخ التقرير'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _runHealthCheck,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة الفحص'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyReportToClipboard() async {
    final db = ref.read(databaseProvider);
    final checker = DatabaseHealthChecker(db);
    final report = await checker.generateHealthReport();
    
    await Clipboard.setData(ClipboardData(text: report));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ التقرير'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'ok':
        color = Colors.green;
        label = 'سليم';
        break;
      case 'warning':
        color = Colors.orange;
        label = 'تحذير';
        break;
      case 'error':
        color = Colors.red;
        label = 'خطأ';
        break;
      case 'incomplete':
        color = Colors.orange;
        label = 'غير مكتمل';
        break;
      case 'not_initialized':
        color = Colors.grey;
        label = 'غير مهيأ';
        break;
      case 'stale':
        color = Colors.orange;
        label = 'قديم';
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == 'ok' ? Icons.check : Icons.warning,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
