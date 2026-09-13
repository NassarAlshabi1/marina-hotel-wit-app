import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../services/appwrite_config.dart';
import '../../services/appwrite_config_manager.dart';
import '../../utils/snackbar_helper.dart';

class AppwriteConnectionSettingsScreen extends ConsumerStatefulWidget {
  const AppwriteConnectionSettingsScreen({super.key});

  @override
  ConsumerState<AppwriteConnectionSettingsScreen> createState() => _AppwriteConnectionSettingsScreenState();
}

class _AppwriteConnectionSettingsScreenState extends ConsumerState<AppwriteConnectionSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _endpointController;
  late TextEditingController _projectIdController;
  late TextEditingController _databaseIdController;
  late TextEditingController _apiKeyController;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _hasChanges = false;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(text: AppwriteConfigManager.endpoint);
    _projectIdController = TextEditingController(text: AppwriteConfigManager.projectId);
    _databaseIdController = TextEditingController(text: AppwriteConfigManager.databaseId);
    _apiKeyController = TextEditingController(text: AppwriteConfigManager.apiKey);

    _endpointController.addListener(_onChanged);
    _projectIdController.addListener(_onChanged);
    _databaseIdController.addListener(_onChanged);
    _apiKeyController.addListener(_onChanged);
  }

  void _onChanged() {
    final hasChanges =
        _endpointController.text != AppwriteConfigManager.endpoint ||
        _projectIdController.text != AppwriteConfigManager.projectId ||
        _databaseIdController.text != AppwriteConfigManager.databaseId ||
        _apiKeyController.text != AppwriteConfigManager.apiKey;

    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _projectIdController.dispose();
    _databaseIdController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      await AppwriteConfigManager.saveConfig(
        endpoint: _endpointController.text.trim(),
        projectId: _projectIdController.text.trim(),
        databaseId: _databaseIdController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الإعدادات بنجاح'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        setState(() => _hasChanges = false);

        _showRestartDialog();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'خطأ في حفظ الإعدادات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showRestartDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.blue),
            SizedBox(width: 8),
            Text('إعادة تشغيل مطلوبة'),
          ],
        ),
        content: const Text('لتطبيق الإعدادات الجديدة، يرجى إغلاق التطبيق وإعادة فتحه.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تعيين الإعدادات'),
        content: const Text('هل تريد إعادة تعيين إعدادات الاتصال إلى القيم الافتراضية؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop<bool>(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop<bool>(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    await AppwriteConfigManager.resetToDefaults();

    setState(() {
      _endpointController.text = AppwriteConfig.endpoint;
      _projectIdController.text = AppwriteConfig.projectId;
      _databaseIdController.text = AppwriteConfig.databaseId;
      // ✅ استعادة المفتاح الافتراضي المُدمج، لا مسحه
      _apiKeyController.text = AppwriteConfig.defaultApiKey;
      _hasChanges = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إعادة تعيين الإعدادات'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      _showRestartDialog();
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اختبار الاتصال: يرجى حفظ الإعدادات أولاً ثم إعادة تشغيل التطبيق'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات الاتصال بـ Appwrite',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            _buildConnectionFields(),
            const SizedBox(height: 16),
            _buildCurrentConfigCard(),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'يمكنك تغيير إعدادات الاتصال بـ Appwrite Cloud هنا. تأكد من إدخال البيانات الصحيحة من لوحة تحكم Appwrite.',
                style: TextStyle(color: Colors.blue.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionFields() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('بيانات الاتصال', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _endpointController,
              decoration: const InputDecoration(
                labelText: 'Endpoint URL',
                hintText: 'https://cloud.appwrite.io/v1',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال عنوان Endpoint';
                }
                if (!value.startsWith('http://') && !value.startsWith('https://')) {
                  return 'يجب أن يبدأ العنوان بـ http:// أو https://';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _projectIdController,
              decoration: const InputDecoration(
                labelText: 'Project ID',
                hintText: 'معرف المشروع',
                prefixIcon: Icon(Icons.folder),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال معرف المشروع';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _databaseIdController,
              decoration: const InputDecoration(
                labelText: 'Database ID',
                hintText: 'معرف قاعدة البيانات',
                prefixIcon: Icon(Icons.storage),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال معرف قاعدة البيانات';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'مفتاح API من Appwrite (افتراضي مُدمج)',
                helperText: 'يُستخدم المفتاح الافتراضي تلقائياً. يمكنك استبداله بأي وقت.',
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showApiKey = !_showApiKey),
                  icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
                ),
              ),
              obscureText: !_showApiKey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentConfigCard() {
    final isCustom = AppwriteConfigManager.isUsingCustomConfig;

    return Card(
      color: isCustom ? Colors.orange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isCustom ? Icons.settings : Icons.check_circle, color: isCustom ? Colors.orange : Colors.green),
                const SizedBox(width: 8),
                Text(
                  isCustom ? 'إعدادات مخصصة' : 'الإعدادات الافتراضية',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isCustom ? Colors.orange.shade700 : Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildConfigRow('Endpoint', AppwriteConfigManager.endpoint),
            _buildConfigRow('Project ID', AppwriteConfigManager.projectId),
            _buildConfigRow('Database ID', AppwriteConfigManager.databaseId),
            _buildConfigRow('API Key', _maskApiKey(AppwriteConfigManager.apiKey)),
          ],
        ),
      ),
    );
  }

  String _maskApiKey(String value) {
    if (value.isEmpty) {
      return 'غير مضبوط';
    }
    if (value.length <= 6) {
      return '••••••';
    }
    final tail = value.substring(value.length - 4);
    return '••••••$tail';
  }

  Widget _buildConfigRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving || !_hasChanges ? null : _saveConfig,
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_find),
                label: const Text('اختبار الاتصال'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resetToDefaults,
                icon: const Icon(Icons.restart_alt),
                label: const Text('إعادة تعيين'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
