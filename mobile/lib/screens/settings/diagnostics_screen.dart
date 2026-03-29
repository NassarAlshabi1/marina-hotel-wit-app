import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/diagnostics/diagnostics_logger.dart';
import '../../services/logging/log_models.dart';
import '../../services/sync_guardian.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _snapshot;
  Map<String, int> _counts = {};
  bool _loading = false;
  String? _error;
  String _selectedTable = 'all';

  // ✅ منع فتح أكثر من Modal في نفس الوقت
  bool _isModalOpen = false;

  // ✅ Memoization لـ JSON — يُحسب مرة واحدة ويُخزَّن
  String? _cachedJson;
  String _cachedJsonTable = '';

  // ✅ البحث في الجداول
  String _tableSearchQuery = '';

  // ✅ فلترة مستوى السجلات
  final Set<String> _selectedLogLevels = {'INFO', 'WARNING', 'ERROR'};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// ✅ إبطال الكاش عند التحميل
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _cachedJson = null; // ✅ invalidate cache
    });
    try {
      await _loadSnapshot();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSnapshot() async {
    final db = ref.read(databaseProvider);
    final data = await db.getAllTablesAsJson();
    final counts = <String, int>{};
    for (final entry in data.entries) {
      final value = entry.value;
      // ✅ Type Safety: safe casting لكل الأنواع المحتملة
      if (value is List) {
        counts[entry.key] = value.length;
      } else if (value is Map) {
        counts[entry.key] = value.length;
      } else {
        counts[entry.key] = 0;
      }
    }
    if (mounted) {
      setState(() {
        _snapshot = data;
        _counts = counts;
        _selectedTable = 'all';
      });
    }
  }

  int _totalRecords() {
    return _counts.values.fold<int>(0, (sum, v) => sum + v);
  }

  Future<void> _copyJson() async {
    final jsonStr = _buildDiagnosticsJson();
    if (jsonStr == null) return;
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ تقرير التشخيص')));
  }

  Future<void> _exportJson() async {
    final jsonStr = _buildDiagnosticsJson();
    if (jsonStr == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/diagnostics_$timestamp.json');
    await file.writeAsString(jsonStr);
    await Share.shareXFiles([XFile(file.path)], text: 'تقرير التشخيص');
  }

  /// ✅ Memoized JSON — لا يُعاد حسابه في كل build
  String? _buildDiagnosticsJson() {
    if (_cachedJson != null && _cachedJsonTable == _selectedTable) {
      return _cachedJson;
    }

    final health = ref
        .read(syncHealthProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final logs = DiagnosticsLogger.instance.getLogs();
    const encoder = JsonEncoder.withIndent('  ');
    final payload = {
      'generatedAt': DateTime.now().toIso8601String(),
      'sync': _syncToMap(health),
      'counts': _counts,
      'data': _selectedTable == 'all'
          ? _snapshot
          : {_selectedTable: _snapshot?[_selectedTable]},
      'logs': logs.map((e) => e.toJson()).toList(),
    };

    _cachedJsonTable = _selectedTable;
    _cachedJson = encoder.convert(payload);
    return _cachedJson;
  }

  /// ✅ تقدير حجم JSON بالكيلوبايت
  int _estimateJsonSizeKb() {
    final json = _buildDiagnosticsJson();
    if (json == null) return 0;
    // UTF-8 bytes per character ≈ 1-4, avg ~1.2 for JSON
    return (json.length * 1.2 / 1024).ceil();
  }

  Map<String, dynamic>? _syncToMap(SyncHealthSnapshot? health) {
    if (health == null) return null;
    return {
      'lastSyncAt': health.lastSyncAt?.toIso8601String(),
      'failedAttempts': health.failedAttempts,
      'pendingEvents': health.pendingEvents,
      'isInitialized': health.isInitialized,
      'lastError': health.lastError,
      'monitoringActive': health.monitoringActive,
      'priorityOverridden': health.priorityOverridden,
      'status': health.status,
    };
  }

  // ==================== Generic Bottom Sheet ====================

  /// ✅ Generic method لتقليل التكرار بين _openTableDetails و _openLogDetails
  Future<void> _showDetailsSheet({
    required String title,
    required String content,
    required String copyMessage,
  }) async {
    // ✅ منع فتح أكثر من Modal في نفس الوقت
    if (_isModalOpen || !mounted) return;
    _isModalOpen = true;

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: content),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(copyMessage)),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                const Divider(),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _isModalOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تشخيص شامل',
      actions: [
        IconButton(
          onPressed: _loading ? null : _loadAll,
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
        ),
        IconButton(
          onPressed: _snapshot == null ? null : _copyJson,
          icon: const Icon(Icons.copy),
          tooltip: 'نسخ التقرير',
        ),
        IconButton(
          onPressed: _snapshot == null ? null : _exportJson,
          icon: const Icon(Icons.share),
          tooltip: 'تصدير التقرير',
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _snapshot == null
                  ? const Center(child: Text('لا توجد بيانات'))
                  : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            const Text('فشل تحميل بيانات التشخيص'),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAll,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'ملخص'),
              Tab(text: 'المزامنة'),
              Tab(text: 'الجداول'),
              Tab(text: 'السجلات'),
              Tab(text: 'JSON'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSummaryTab(),
                _buildSyncTab(),
                _buildTablesTab(),
                _buildLogsTab(),
                _buildJsonTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ملخص ====================

  Widget _buildSummaryTab() {
    final tablesCount = _counts.length;
    final totalRecords = _totalRecords();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatCard('عدد الجداول', tablesCount.toString()),
        const SizedBox(height: 12),
        _buildStatCard('إجمالي السجلات', totalRecords.toString()),
        const SizedBox(height: 16),
        Text(
          'آخر تحديث: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  // ==================== المزامنة ====================

  Widget _buildSyncTab() {
    final syncAsync = ref.watch(syncHealthProvider);
    return syncAsync.when(
      data: (health) {
        final map = _syncToMap(health);
        if (map == null) {
          return const Center(child: Text('لا توجد بيانات مزامنة'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionTitle('حالة المزامنة'),
            ...map.entries.map(
              (e) => _buildKeyValue(e.key, e.value?.toString() ?? '-'),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ في المزامنة: $e')),
    );
  }

  // ==================== الجداول ====================

  Widget _buildTablesTab() {
    final query = _tableSearchQuery.toLowerCase();
    final entries = _counts.entries
        .where((e) => e.key.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      children: [
        // ✅ شريط البحث
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'البحث في الجداول...',
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _tableSearchQuery = '');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: (v) => setState(() => _tableSearchQuery = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${entries.length} جدول',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('لا توجد نتائج'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Card(
                      child: ListTile(
                        title: Text(entry.key),
                        subtitle: Text('عدد السجلات: ${entry.value}'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _openTableDetails(entry.key),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// ✅ يستخدم Generic _showDetailsSheet بدل تكرار الكود
  Future<void> _openTableDetails(String table) async {
    final data = _snapshot?[table];
    if (data == null) return;
    const encoder = JsonEncoder.withIndent('  ');
    final jsonStr = encoder.convert({table: data});
    await _showDetailsSheet(
      title: table,
      content: jsonStr,
      copyMessage: 'تم نسخ الجدول',
    );
  }

  // ==================== السجلات ====================

  Widget _buildLogsTab() {
    final logger = ref.watch(diagnosticsLoggerProvider);
    final allLogs = logger.getLogs();

    // ✅ فلترة حسب المستوى المُختار
    final filteredLogs = allLogs
        .where((l) => _selectedLogLevels.contains(l.level.name.toUpperCase()))
        .toList();

    return Column(
      children: [
        // ✅ Filter Chips لمستوى السجلات
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('DEBUG', 'Debug', Colors.grey),
                const SizedBox(width: 6),
                _buildFilterChip('INFO', 'Info', Colors.blue),
                const SizedBox(width: 6),
                _buildFilterChip('WARNING', 'تحذير', Colors.orange),
                const SizedBox(width: 6),
                _buildFilterChip('ERROR', 'خطأ', Colors.red),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: filteredLogs.isEmpty ? null : _exportLogs,
                  icon: const Icon(Icons.share),
                  label: const Text('تصدير السجلات'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: filteredLogs.isEmpty ? null : _clearLogs,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('مسح السجلات'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredLogs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      allLogs.isEmpty
                          ? 'لا توجد سجلات'
                          : 'لا توجد سجلات بالمستوى المُختار',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredLogs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final log = filteredLogs[filteredLogs.length - index - 1];
                    final levelColor = _logLevelColor(log.level.name);
                    return Card(
                      child: ListTile(
                        title: Text(
                          log.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp)} • ${log.level.name.toUpperCase()} • ${log.tag}',
                        ),
                        leading: Container(
                          width: 4,
                          height: 32,
                          decoration: BoxDecoration(
                            color: levelColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openLogDetails(log),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// ✅ Filter Chip لمستوى السجلات
  Widget _buildFilterChip(String level, String label, Color color) {
    final isSelected = _selectedLogLevels.contains(level);
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      checkmarkColor: Colors.white,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedLogLevels.add(level);
          } else {
            _selectedLogLevels.remove(level);
          }
        });
      },
    );
  }

  Color _logLevelColor(String level) {
    return switch (level.toUpperCase()) {
      'ERROR' => Colors.red,
      'WARNING' => Colors.orange,
      'DEBUG' => Colors.grey,
      _ => Colors.blue,
    };
  }

  Future<void> _exportLogs() async {
    final file = await DiagnosticsLogger.instance.exportLogs();
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر تصدير السجلات')));
      return;
    }
    await Share.shareXFiles([XFile(file.path)], text: 'سجلات التشخيص');
  }

  /// ✅ إصلاح Race Condition — تأكيد قبل المسح + setState بعد التنفيذ
  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هل تريد مسح جميع سجلات التشخيص؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    DiagnosticsLogger.instance.clear();

    // ✅ إعادة بناء UI لأن السجلات تُعرض عبر ref.watch
    // لا حاجة لـ setState لأن Riverpod يعيد البناء تلقائياً
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم مسح جميع السجلات')),
      );
    }
  }

  /// ✅ يستخدم Generic _showDetailsSheet
  Future<void> _openLogDetails(LogEntry log) async {
    await _showDetailsSheet(
      title: 'تفاصيل السجل',
      content: log.toFormattedString(),
      copyMessage: 'تم نسخ السجل',
    );
  }

  // ==================== JSON ====================

  Widget _buildJsonTab() {
    final tables = ['all', ..._counts.keys.toList()..sort()];

    // ✅ Large JSON Warning
    final jsonSizeKb = _estimateJsonSizeKb();
    final isLargeJson = jsonSizeKb > 1024; // > 1MB

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: tables.contains(_selectedTable) ? _selectedTable : 'all',
            decoration: const InputDecoration(
              labelText: 'عرض البيانات',
              border: OutlineInputBorder(),
            ),
            items: tables
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(t == 'all' ? 'كل الجداول' : t),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedTable = value;
                _cachedJson = null; // ✅ إبطال الكاش عند تغيير الجدول
              });
            },
          ),
          const SizedBox(height: 8),

          // ✅ تحذير حجم JSON
          if (isLargeJson)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'حجم التقرير ~${jsonSizeKb ~/ 1024}MB — يُنصح باستخدام تصدير الملف بدلاً من العرض المباشر',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isLargeJson
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.data_object, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'التقرير كبير جداً للعرض المباشر',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _exportJson,
                            icon: const Icon(Icons.file_download),
                            label: const Text('تصدير كملف'),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        _buildDiagnosticsJson() ?? '',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== مكونات مساعدة ====================

  Widget _buildStatCard(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildKeyValue(String key, String value) {
    return Card(
      child: ListTile(title: Text(key), subtitle: Text(value)),
    );
  }

  @override
  void dispose() {
    _cachedJson = null;
    super.dispose();
  }
}
