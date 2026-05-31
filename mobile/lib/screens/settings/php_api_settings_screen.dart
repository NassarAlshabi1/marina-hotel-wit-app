import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../components/app_scaffold.dart';
import '../../services/api_config_service.dart';
import '../../services/php_api_service.dart';

class PhpApiSettingsScreen extends ConsumerStatefulWidget {
  const PhpApiSettingsScreen({super.key});

  @override
  ConsumerState<PhpApiSettingsScreen> createState() =>
      _PhpApiSettingsScreenState();
}

class _PhpApiSettingsScreenState extends ConsumerState<PhpApiSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _connectTimeoutController = TextEditingController();
  final _receiveTimeoutController = TextEditingController();
  final _serverNameController = TextEditingController();

  bool _enableLogging = false;
  bool _useSsl = true;
  bool _isLoading = false;
  bool _isTesting = false;
  PhpApiStatus _connectionStatus = PhpApiStatus.disconnected;
  String? _testMessage;

  // ✅ محسّن: تخزين StreamSubscription لمنع تسرب الذاكرة
  StreamSubscription<PhpApiStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _statusSubscription = PhpApiService.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() => _connectionStatus = status);
      }
    });
  }

  Future<void> _loadSettings() async {
    await ApiConfigService.instance.initialize();
    final config = ApiConfigService.instance.currentConfig;
    setState(() {
      _urlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey ?? '';
      _connectTimeoutController.text = config.connectTimeout.toString();
      _receiveTimeoutController.text = config.receiveTimeout.toString();
      _enableLogging = config.enableLogging;
      _useSsl = config.useSsl;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final config = ApiConfig(
        baseUrl: _urlController.text.trim(),
        apiKey: _apiKeyController.text.trim().isEmpty
            ? null
            : _apiKeyController.text.trim(),
        connectTimeout: int.tryParse(_connectTimeoutController.text) ?? 15,
        receiveTimeout: int.tryParse(_receiveTimeoutController.text) ?? 20,
        enableLogging: _enableLogging,
        useSsl: _useSsl,
      );
      await ApiConfigService.instance.saveConfig(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الإعدادات بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testMessage = null;
    });
    try {
      await _saveSettings();
      final result = await PhpApiService.instance.testConnection();
      setState(() {
        _testMessage = result.message;
      });
      if (mounted && result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ الاتصال ناجح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _addServer() async {
    final result = await showDialog<ServerInfo>(
      context: context,
      builder: (ctx) => _AddServerDialog(
        urlController: _urlController,
        apiKeyController: _apiKeyController,
        nameController: _serverNameController,
      ),
    );
    if (result != null) {
      await ApiConfigService.instance.addServer(result);
      setState(() {});
    }
  }

  Future<void> _selectServer(ServerInfo server) async {
    await ApiConfigService.instance.selectServer(server.id);
    await _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اختيار السيرفر: ${server.name}')),
      );
    }
  }

  Future<void> _deleteServer(ServerInfo server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السيرفر'),
        content: Text('هل تريد حذف السيرفر "${server.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm ?? false) {
      await ApiConfigService.instance.removeServer(server.id);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel(); // ✅ تنظيف الاشتراك
    _urlController.dispose();
    _apiKeyController.dispose();
    _connectTimeoutController.dispose();
    _receiveTimeoutController.dispose();
    _serverNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serverList = ApiConfigService.instance.serverList;

    return AppScaffold(
      title: 'إعدادات PHP API',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusCard(theme),
              const SizedBox(height: 16),
              _buildConnectionCard(theme),
              const SizedBox(height: 16),
              _buildTimeoutCard(theme),
              const SizedBox(height: 16),
              _buildOptionsCard(theme),
              const SizedBox(height: 16),
              _buildServersCard(theme, serverList),
              const SizedBox(height: 16),
              _buildActionsCard(theme),
              const SizedBox(height: 24),
              _buildRequestLogCard(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (_connectionStatus) {
      case PhpApiStatus.connected:
        statusColor = Colors.green;
        statusText = 'متصل';
        statusIcon = Icons.check_circle;
      case PhpApiStatus.connecting:
        statusColor = Colors.orange;
        statusText = 'جاري الاتصال...';
        statusIcon = Icons.sync;
      case PhpApiStatus.error:
        statusColor = Colors.red;
        statusText = 'خطأ في الاتصال';
        statusIcon = Icons.error;
      default:
        statusColor = Colors.grey;
        statusText = 'غير متصل';
        statusIcon = Icons.cloud_off;
    }

    return Card(
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor, size: 32),
        title: Text('حالة الاتصال', style: theme.textTheme.titleMedium),
        subtitle: Text(
          statusText,
          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
        ),
        trailing: _isTesting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _testConnection,
                tooltip: 'اختبار الاتصال',
              ),
      ),
    );
  }

  Widget _buildConnectionCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('إعدادات الاتصال', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'رابط API',
                hintText: 'http://example.com/api/v1',
                prefixIcon: Icon(Icons.language),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'الرابط مطلوب';
                }
                if (!v.startsWith('http://') && !v.startsWith('https://')) {
                  return 'يجب أن يبدأ الرابط بـ http:// أو https://';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'مفتاح API (اختياري)',
                hintText: 'أدخل مفتاح API إن وجد',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('إعدادات المهلة', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _connectTimeoutController,
                    decoration: const InputDecoration(
                      labelText: 'مهلة الاتصال (ثانية)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _receiveTimeoutController,
                    decoration: const InputDecoration(
                      labelText: 'مهلة الاستقبال (ثانية)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('خيارات إضافية', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('تفعيل السجلات'),
              subtitle: const Text('عرض تفاصيل الطلبات في وحدة التحكم'),
              value: _enableLogging,
              onChanged: (v) => setState(() => _enableLogging = v),
            ),
            SwitchListTile(
              title: const Text('استخدام SSL'),
              subtitle: const Text('تأمين الاتصال بالسيرفر'),
              value: _useSsl,
              onChanged: (v) => setState(() => _useSsl = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServersCard(ThemeData theme, List<ServerInfo> servers) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'السيرفرات المحفوظة',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addServer,
                  tooltip: 'إضافة سيرفر',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (servers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'لا توجد سيرفرات محفوظة',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: servers.length,
                itemBuilder: (ctx, i) {
                  final server = servers[i];
                  final isSelected = _urlController.text == server.url;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.computer,
                      color: isSelected ? Colors.green : null,
                    ),
                    title: Text(server.name),
                    subtitle: Text(
                      server.url,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isSelected)
                          IconButton(
                            icon: const Icon(Icons.login),
                            onPressed: () => _selectServer(server),
                            tooltip: 'استخدام',
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteServer(server),
                          tooltip: 'حذف',
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_testMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _testMessage!,
                  style: TextStyle(
                    color: _connectionStatus == PhpApiStatus.connected
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('اختبار الاتصال'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _saveSettings,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: const Text('حفظ الإعدادات'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  await ApiConfigService.instance.resetToDefault();
                  await _loadSettings();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم إعادة الإعدادات الافتراضية'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.restore),
                label: const Text('إعادة الإعدادات الافتراضية'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestLogCard(ThemeData theme) {
    final logs = PhpApiService.instance.requestLog;
    if (logs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.history, color: theme.colorScheme.primary),
        title: const Text('سجل الطلبات'),
        subtitle: Text('${logs.length} طلب'),
        children: [
          SizedBox(
            height: 200,
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (ctx, i) {
                final log = logs[logs.length - 1 - i];
                final isError = log['type'] == 'ERROR';
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isError ? Icons.error : Icons.arrow_right,
                    color: isError ? Colors.red : Colors.green,
                    size: 16,
                  ),
                  title: Text(
                    '${log['method']} ${log['path']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    log['timestamp'].toString().substring(11, 19),
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: log['statusCode'] != null
                      ? Text(
                          '${log['statusCode']}',
                          style: TextStyle(
                            color: (log['statusCode'] as int) < 400
                                ? Colors.green
                                : Colors.red,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
          TextButton(
            onPressed: () {
              PhpApiService.instance.clearRequestLog();
              setState(() {});
            },
            child: const Text('مسح السجل'),
          ),
        ],
      ),
    );
  }
}

class _AddServerDialog extends StatelessWidget {

  const _AddServerDialog({
    required this.urlController,
    required this.apiKeyController,
    required this.nameController,
  });
  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context) {
    nameController.clear();
    return AlertDialog(
      title: const Text('إضافة سيرفر'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'اسم السيرفر',
              hintText: 'مثال: سيرفر الإنتاج',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'سيتم حفظ الرابط الحالي:\n${urlController.text}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (nameController.text.trim().isEmpty) {
              return;
            }
            final server = ServerInfo(
              id: const Uuid().v4(),
              name: nameController.text.trim(),
              url: urlController.text.trim(),
              apiKey: apiKeyController.text.trim().isEmpty
                  ? null
                  : apiKeyController.text.trim(),
              addedAt: DateTime.now(),
            );
            Navigator.pop<ServerInfo>(context, server);
          },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
