import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/appwrite_config_manager.dart';
import '../../services/appwrite_config.dart';
import '../../utils/snackbar_helper.dart';

class AppwriteConnectionSettingsScreen extends ConsumerStatefulWidget {
  const AppwriteConnectionSettingsScreen({super.key});

  @override
  ConsumerState<AppwriteConnectionSettingsScreen> createState() =>
      _AppwriteConnectionSettingsScreenState();
}

class _AppwriteConnectionSettingsScreenState
    extends ConsumerState<AppwriteConnectionSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _endpointController;
  late TextEditingController _projectIdController;
  late TextEditingController _databaseIdController;
  late TextEditingController _apiKeyController;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _hasChanges = false;
  bool _showApiKey = false;

  /// ✅ Debounce timer لمنع إعادة البناء المتكررة
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(
      text: AppwriteConfigManager.endpoint,
    );
    _projectIdController = TextEditingController(
      text: AppwriteConfigManager.projectId,
    );
    _databaseIdController = TextEditingController(
      text: AppwriteConfigManager.databaseId,
    );
    _apiKeyController = TextEditingController(
      text: AppwriteConfigManager.apiKey,
    );

    _endpointController.addListener(_onChanged);
    _projectIdController.addListener(_onChanged);
    _databaseIdController.addListener(_onChanged);
    _apiKeyController.addListener(_onChanged);
  }

  /// ✅ Debounced listener — ينتظر 300ms قبل تحديث حالة التغييرات
  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final hasChanges =
          _endpointController.text != AppwriteConfigManager.endpoint ||
          _projectIdController.text != AppwriteConfigManager.projectId ||
          _databaseIdController.text != AppwriteConfigManager.databaseId ||
          _apiKeyController.text != AppwriteConfigManager.apiKey;

      if (hasChanges != _hasChanges) {
        setState(() => _hasChanges = hasChanges);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _endpointController.dispose();
    _projectIdController.dispose();
    _databaseIdController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

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
          SnackBar(
            content: const Text('تم حفظ الإعدادات بنجاح'),
            backgroundColor: Colors.green,
            // ✅ مدة SnackBar: 2 ثانية للنجاح
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'إغلاق',
              textColor: Colors.white,
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            ),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.blue),
            SizedBox(width: 8),
            Text('إعادة تشغيل مطلوبة'),
          ],
        ),
        content: const Text(
          'لتطبيق الإعدادات الجديدة، يرجى إغلاق التطبيق وإعادة فتحه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تعيين الإعدادات'),
        content: const Text(
          'هل تريد إعادة تعيين إعدادات الاتصال إلى القيم الافتراضية؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AppwriteConfigManager.resetToDefaults();

    setState(() {
      _endpointController.text = AppwriteConfig.endpoint;
      _projectIdController.text = AppwriteConfig.projectId;
      _databaseIdController.text = AppwriteConfig.databaseId;
      _apiKeyController.text = '';
      _hasChanges = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم إعادة تعيين الإعدادات'),
          backgroundColor: Colors.green,
          // ✅ مدة SnackBar: 2 ثانية
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'إغلاق',
            textColor: Colors.white,
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );

      _showRestartDialog();
    }
  }

  /// ✅ اختبار اتصال حقيقي باستخدام HTTP HEAD على الـ Endpoint
  /// يختبر الإعدادات المُدخلة حتى لو لم تُحفظ بعد
  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isTesting = true);

    try {
      final endpoint = _endpointController.text.trim();
      final projectId = _projectIdController.text.trim();
      final sw = Stopwatch()..start();

      // ✅ محاولة فعلية باستخدام http — GET /health endpoint
      // Appwrite SDK لا يوفر health check مباشر، لذا نستخدم HTTP
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);

      try {
        final request = await client.getUrl(Uri.parse('$endpoint/health'));
        // إضافة headers للتأكد من صحة المشروع
        request.headers.set('X-Appwrite-Project', projectId);
        final response = await request.close();
        sw.stop();

        final latencyMs = sw.elapsedMilliseconds;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.statusCode == 200
                    ? '✅ الاتصال ناجح (${latencyMs}ms)'
                    : '⚠️ الخادم يستجيب (${response.statusCode}) — تأكد من صحة Project ID',
              ),
              backgroundColor: response.statusCode == 200
                  ? Colors.green
                  : Colors.orange,
              // ✅ مدة SnackBar: 3 ثوانٍ للنتائج
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } on SocketException {
        sw.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ فشل الاتصال — تحقق من عنوان Endpoint والإنترنت'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } on HttpException catch (e) {
        sw.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ خطأ في الاتصال: ${e.message}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ غير متوقع: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  /// ✅ نسخ قيمة إلى Clipboard
  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ $label'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ WillPopScope — حماية من فقدان التغييرات عند الخروج
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_hasChanges) {
          Navigator.of(context).pop();
          return;
        }

        final action = await showDialog<_UnsavedAction>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تغييرات غير محفوظة'),
            content: const Text(
              'لديك تغييرات لم تُحفظ بعد. هل تريد حفظها قبل الخروج؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _UnsavedAction.discard),
                child: const Text('تجاهل'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _UnsavedAction.cancel),
                child: const Text('البقاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, _UnsavedAction.save),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('حفظ وخروج'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        switch (action) {
          case _UnsavedAction.save:
            await _saveConfig();
            if (mounted) Navigator.of(context).pop();
          case _UnsavedAction.discard:
            Navigator.of(context).pop();
          case _UnsavedAction.cancel:
          case null:
            break;
        }
      },
      child: AppScaffold(
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
            const Text(
              'بيانات الاتصال',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // ✅ Endpoint URL مع validation قوي
            TextFormField(
              controller: _endpointController,
              decoration: InputDecoration(
                labelText: 'Endpoint URL',
                hintText: 'https://fra.cloud.appwrite.io/v1',
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
                // ✅ زر لصق القيمة الحالية
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste, size: 18),
                  onPressed: () {
                    if (AppwriteConfigManager.endpoint.isNotEmpty) {
                      _endpointController.text = AppwriteConfigManager.endpoint;
                    }
                  },
                  tooltip: 'استعادة القيمة الحالية',
                ),
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال عنوان Endpoint';
                }
                final trimmed = value.trim();

                // ✅ التحقق من صيغة URL
                final uri = Uri.tryParse(trimmed);
                if (uri == null) {
                  return 'عنوان URL غير صالح';
                }
                if (!uri.hasScheme ||
                    (!uri.isScheme('HTTP') && !uri.isScheme('HTTPS'))) {
                  return 'يجب أن يبدأ بـ http:// أو https://';
                }
                if (!uri.hasAuthority) {
                  return 'يجب أن يحتوي على نطاق (domain)';
                }
                // ✅ تنبيه إذا لم يحتوِ /v1 (المسار المعتاد لـ Appwrite)
                if (!uri.path.contains('/v1')) {
                  return 'عادة يجب أن يحتوي على /v1 في نهاية العنوان';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _projectIdController,
              decoration: InputDecoration(
                labelText: 'Project ID',
                hintText: 'معرف المشروع',
                prefixIcon: const Icon(Icons.folder),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste, size: 18),
                  onPressed: () {
                    if (AppwriteConfigManager.projectId.isNotEmpty) {
                      _projectIdController.text =
                          AppwriteConfigManager.projectId;
                    }
                  },
                  tooltip: 'استعادة القيمة الحالية',
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال معرف المشروع';
                }
                if (value.trim().length < 10) {
                  return 'معرف المشروع قصير جداً';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _databaseIdController,
              decoration: InputDecoration(
                labelText: 'Database ID',
                hintText: 'معرف قاعدة البيانات',
                prefixIcon: const Icon(Icons.storage),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste, size: 18),
                  onPressed: () {
                    if (AppwriteConfigManager.databaseId.isNotEmpty) {
                      _databaseIdController.text =
                          AppwriteConfigManager.databaseId;
                    }
                  },
                  tooltip: 'استعادة القيمة الحالية',
                ),
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
                labelText: 'API Key (اختياري)',
                hintText: 'مفتاح API من Appwrite',
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showApiKey = !_showApiKey),
                  icon: Icon(
                    _showApiKey ? Icons.visibility_off : Icons.visibility,
                  ),
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
                Icon(
                  isCustom ? Icons.settings : Icons.check_circle,
                  color: isCustom ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  isCustom
                      ? 'الإعدادات الحالية (مخصصة)'
                      : 'الإعدادات الافتراضية',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isCustom
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildConfigRow(
              'Endpoint',
              AppwriteConfigManager.endpoint,
              copyable: true,
              copyLabel: 'Endpoint',
            ),
            _buildConfigRow(
              'Project ID',
              AppwriteConfigManager.projectId,
              copyable: true,
              copyLabel: 'Project ID',
            ),
            _buildConfigRow(
              'Database ID',
              AppwriteConfigManager.databaseId,
              copyable: true,
              copyLabel: 'Database ID',
            ),
            _buildConfigRow(
              'API Key',
              _maskApiKey(AppwriteConfigManager.apiKey),
            ),
          ],
        ),
      ),
    );
  }

  String _maskApiKey(String value) {
    if (value.isEmpty) return 'غير مضبوط';
    if (value.length <= 6) return '••••••';
    final tail = value.substring(value.length - 4);
    return '••••••$tail';
  }

  /// ✅ إضافة زر نسخ مع toast سريع
  Widget _buildConfigRow(
    String label,
    String value, {
    bool copyable = false,
    String? copyLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
          // ✅ زر نسخ
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => _copyToClipboard(value, copyLabel ?? label),
              tooltip: 'نسخ',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
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
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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

/// ✅ Enum لخيارات Dialog التغييرات غير المحفوظة
enum _UnsavedAction { save, discard, cancel }
