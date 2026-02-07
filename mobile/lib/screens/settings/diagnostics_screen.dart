import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/diagnostics/diagnostics_logger.dart';
import '../../services/logging/log_models.dart';
import '../../services/sync_guardian.dart';
import '../../utils/env.dart';
import '../../services/appwrite_config.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  static const _dbFileName = 'marina_hotel.db';

  Map<String, dynamic>? _snapshot;
  Map<String, int> _counts = {};
  bool _loading = false;
  String? _error;
  String _selectedTable = 'all';

  Map<String, String> _deviceInfo = {};
  Map<String, String> _appInfo = {};
  Map<String, String> _storageInfo = {};
  String _connectivity = 'unknown';
  int? _batteryLevel;
  String? _batteryState;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([
        _loadSnapshot(),
        _loadDeviceInfo(),
        _loadAppInfo(),
        _loadConnectivity(),
        _loadBattery(),
        _loadStorage(),
      ]);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadSnapshot() async {
    final db = ref.read(databaseProvider);
    final data = await db.getAllTablesAsJson();
    final counts = <String, int>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List) {
        counts[entry.key] = value.length;
      } else if (value is Map) {
        counts[entry.key] = value.length;
      } else {
        counts[entry.key] = 0;
      }
    }
    setState(() {
      _snapshot = data;
      _counts = counts;
      _selectedTable = 'all';
    });
  }

  Future<void> _loadDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    Map<String, String> info = {};
    if (Platform.isAndroid) {
      final data = await plugin.androidInfo;
      info = {
        'platform': 'Android',
        'brand': data.brand,
        'model': data.model,
        'device': data.device,
        'manufacturer': data.manufacturer,
        'sdk': data.version.sdkInt.toString(),
        'release': data.version.release,
      };
    } else if (Platform.isIOS) {
      final data = await plugin.iosInfo;
      info = {
        'platform': 'iOS',
        'name': data.name,
        'model': data.model,
        'systemName': data.systemName,
        'systemVersion': data.systemVersion,
      };
    } else {
      final data = await plugin.deviceInfo;
      info = data.data.map((key, value) => MapEntry(key, '$value'));
    }
    setState(() {
      _deviceInfo = info;
    });
  }

  Future<void> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _appInfo = {
        'appName': info.appName,
        'packageName': info.packageName,
        'version': info.version,
        'buildNumber': info.buildNumber,
        'baseApiUrl': Env.baseApiUrl,
        'appwriteEndpoint': AppwriteConfig.endpoint,
        'appwriteProjectId': AppwriteConfig.projectId,
        'appwriteDatabaseId': AppwriteConfig.databaseId,
      };
    });
  }

  Future<void> _loadConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _connectivity = result.name;
    });
  }

  Future<void> _loadBattery() async {
    final battery = Battery();
    final level = await battery.batteryLevel;
    final state = await battery.batteryState;
    setState(() {
      _batteryLevel = level;
      _batteryState = state.name;
    });
  }

  Future<void> _loadStorage() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = await sqflite.getDatabasesPath();
    final dbFile = File('$dbPath/${_dbFileName}');
    final dbSize = await _fileSize(dbFile);
    final docsSize = await _directorySize(docsDir);
    setState(() {
      _storageInfo = {
        'documentsDir': docsDir.path,
        'documentsSize': _formatBytes(docsSize),
        'databasePath': dbFile.path,
        'databaseSize': _formatBytes(dbSize),
      };
    });
  }

  Future<int> _fileSize(File file) async {
    try {
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  Future<int> _directorySize(Directory directory) async {
    int total = 0;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (_) {}
    return total;
  }

  String _formatBytes(int bytes) {
    const sizes = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int index = 0;
    while (size >= 1024 && index < sizes.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(2)} ${sizes[index]}';
  }

  int _totalRecords() {
    return _counts.values.fold<int>(0, (sum, v) => sum + v);
  }

  Future<void> _copyJson() async {
    final jsonStr = _buildDiagnosticsJson();
    if (jsonStr == null) return;
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ تقرير التشخيص')),
    );
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

  String? _buildDiagnosticsJson() {
    final health = ref.read(syncHealthProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    final logs = DiagnosticsLogger.instance.getLogs();
    final encoder = const JsonEncoder.withIndent('  ');
    final payload = {
      'generatedAt': DateTime.now().toIso8601String(),
      'app': _appInfo,
      'device': _deviceInfo,
      'storage': _storageInfo,
      'connectivity': _connectivity,
      'battery': {
        'level': _batteryLevel,
        'state': _batteryState,
      },
      'sync': _syncToMap(health),
      'counts': _counts,
      'data': _selectedTable == 'all'
          ? _snapshot
          : {_selectedTable: _snapshot?[_selectedTable]},
      'logs': logs.map((e) => e.toJson()).toList(),
    };
    return encoder.convert(payload);
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
            Text(_error ?? ''),
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
      length: 6,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'ملخص'),
              Tab(text: 'النظام'),
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
                _buildSystemTab(),
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

  Widget _buildSummaryTab() {
    final tablesCount = _counts.length;
    final totalRecords = _totalRecords();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatCard('عدد الجداول', tablesCount.toString()),
        const SizedBox(height: 12),
        _buildStatCard('إجمالي السجلات', totalRecords.toString()),
        const SizedBox(height: 12),
        _buildStatCard('قاعدة البيانات', _storageInfo['databaseSize'] ?? '-'),
        const SizedBox(height: 12),
        _buildStatCard('ملفات التطبيق', _storageInfo['documentsSize'] ?? '-'),
        const SizedBox(height: 12),
        _buildStatCard('الاتصال', _connectivity),
        const SizedBox(height: 12),
        _buildStatCard(
          'البطارية',
          _batteryLevel == null
              ? '-'
              : '${_batteryLevel}% (${_batteryState ?? '-'})',
        ),
        const SizedBox(height: 16),
        Text(
          'آخر تحديث: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildSystemTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('معلومات التطبيق'),
        ..._appInfo.entries.map((e) => _buildKeyValue(e.key, e.value)),
        const SizedBox(height: 16),
        _buildSectionTitle('معلومات الجهاز'),
        ..._deviceInfo.entries.map((e) => _buildKeyValue(e.key, e.value)),
        const SizedBox(height: 16),
        _buildSectionTitle('التخزين'),
        ..._storageInfo.entries.map((e) => _buildKeyValue(e.key, e.value)),
        const SizedBox(height: 16),
        _buildSectionTitle('الاتصال والبطارية'),
        _buildKeyValue('connectivity', _connectivity),
        _buildKeyValue('battery', _batteryLevel == null
            ? '-'
            : '${_batteryLevel}% (${_batteryState ?? '-'})'),
      ],
    );
  }

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

  Widget _buildTablesTab() {
    final entries = _counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
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
    );
  }

  Future<void> _openTableDetails(String table) async {
    final data = _snapshot?[table];
    if (data == null) return;
    final encoder = const JsonEncoder.withIndent('  ');
    final jsonStr = encoder.convert({table: data});
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        table,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: jsonStr),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ الجدول')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonStr,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogsTab() {
    final logger = ref.watch(diagnosticsLoggerProvider);
    final logs = logger.getLogs();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: logs.isEmpty ? null : _exportLogs,
                  icon: const Icon(Icons.share),
                  label: const Text('تصدير السجلات'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: logs.isEmpty ? null : _clearLogs,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('مسح السجلات'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? const Center(child: Text('لا توجد سجلات'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final log = logs[logs.length - index - 1];
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

  Future<void> _exportLogs() async {
    final file = await DiagnosticsLogger.instance.exportLogs();
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تصدير السجلات')),
      );
      return;
    }
    await Share.shareXFiles([XFile(file.path)], text: 'سجلات التشخيص');
  }

  void _clearLogs() {
    DiagnosticsLogger.instance.clear();
  }

  Future<void> _openLogDetails(LogEntry log) async {
    final details = log.toFormattedString();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('تفاصيل السجل',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: details),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ السجل')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      details,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildJsonTab() {
    final tables = ['all', ..._counts.keys.toList()..sort()];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _selectedTable,
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
              });
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
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
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildKeyValue(String key, String value) {
    return Card(
      child: ListTile(
        title: Text(key),
        subtitle: Text(value),
      ),
    );
  }
}
