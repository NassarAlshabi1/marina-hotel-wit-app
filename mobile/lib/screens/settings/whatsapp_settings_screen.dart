import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/appwrite_config.dart';
import '../../services/whatsapp_service.dart';
import '../../services/whatsapp_settings_sync.dart';
import '../../utils/message_templates.dart';
import '../../utils/snackbar_helper.dart';

class WhatsAppSettingsScreen extends ConsumerStatefulWidget {
  const WhatsAppSettingsScreen({super.key});

  @override
  ConsumerState<WhatsAppSettingsScreen> createState() =>
      _WhatsAppSettingsScreenState();
}

class _WhatsAppSettingsScreenState extends ConsumerState<WhatsAppSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _templateController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _instanceIdController = TextEditingController();
  final _tokenController = TextEditingController();
  final _customUrlController = TextEditingController();
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _isSyncing = false;
  late TabController _tabController;
  bool _obscureToken = true;

  WhatsAppApiType _selectedApiType = WhatsAppApiType.custom;

  static const _defaultBaseUrl = 'https://7103.api.greenapi.com';
  static const _defaultInstanceId = 'waInstance7103894450';
  static const _defaultToken =
      'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _templateController.dispose();
    _baseUrlController.dispose();
    _instanceIdController.dispose();
    _tokenController.dispose();
    _customUrlController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      // ✅ حمّل القالب المحفوظ من prefs (إن وُجد) بدل الكتابة فوقه بالـ default
      // دائماً — كان هذا bug يُفقِد المستخدم تخصيصاته بعد إعادة فتح الشاشة.
      _templateController.text =
          prefs.getString('wa_template') ?? whatsappPaymentTemplate;
      _baseUrlController.text =
          prefs.getString('wa_api_base_url') ?? _defaultBaseUrl;
      _instanceIdController.text =
          prefs.getString('wa_api_instance_id') ?? _defaultInstanceId;
      _tokenController.text = prefs.getString('wa_api_token') ?? _defaultToken;
      _customUrlController.text =
          prefs.getString('wa_custom_url_template') ?? '';
      final typeStr = prefs.getString('wa_api_type');
      _selectedApiType = typeStr == 'greenapi'
          ? WhatsAppApiType.greenapi
          : WhatsAppApiType.custom;
      _isLoading = false;
    });
  }

  Future<void> _saveApiSettings() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'wa_api_type',
      _selectedApiType == WhatsAppApiType.greenapi ? 'greenapi' : 'custom',
    );
    await prefs.setString('wa_api_base_url', _baseUrlController.text.trim());
    await prefs.setString(
      'wa_api_instance_id',
      _instanceIdController.text.trim(),
    );
    await prefs.setString('wa_api_token', _tokenController.text.trim());
    await prefs.setString(
      'wa_custom_url_template',
      _customUrlController.text.trim(),
    );
    ref.invalidate(whatsappSettingsProvider);
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    SnackBarHelper.showSuccess(context, 'تم حفظ إعدادات API بنجاح');
  }

  Future<void> _saveTemplate() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    // ✅ BUG FIX: كان الكود يُظهر رسالة "تم الحفظ بنجاح" دون حفظ أي شيء فعلياً!
    // نحفظ القالب تحت مفتاح 'wa_template' (مطابق لما يقرأه _loadSettings).
    // ✅ نفحص نتيجة الكتابة — لا نُظهر رسالة نجاح إن فشلت فعلاً.
    final ok = await prefs.setString(
      'wa_template',
      _templateController.text.trim(),
    );

    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    if (!ok) {
      SnackBarHelper.showError(
        context,
        'تعذّر حفظ إعدادات الرسالة، حاول مرة أخرى',
      );
      return;
    }
    SnackBarHelper.showSuccess(context, 'تم حفظ إعدادات الرسالة بنجاح');
  }

  Future<void> _resetApiToDefault() async {
    setState(() {
      _baseUrlController.text = _defaultBaseUrl;
      _instanceIdController.text = _defaultInstanceId;
      _tokenController.text = _defaultToken;
      _customUrlController.text = '';
      _selectedApiType = WhatsAppApiType.custom;
    });
  }

  Future<void> _resetTemplateToDefault() async {
    setState(() {
      _templateController.text = whatsappPaymentTemplate;
    });
  }

  Future<void> _resetAllToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ نتحقق من نجاح كل عملية حذف — إن فشل أي منها نُنبّه المستخدم بدل
    // إظهار "تمت الاستعادة" بينما بقيت بعض القيم القديمة مخزّنة.
    final results = await Future.wait<bool>([
      prefs.remove('wa_api_type'),
      prefs.remove('wa_api_base_url'),
      prefs.remove('wa_api_instance_id'),
      prefs.remove('wa_api_token'),
      prefs.remove('wa_custom_url_template'),
    ]);
    final allRemoved = results.every((r) => r);

    ref.invalidate(whatsappSettingsProvider);
    if (!mounted) {
      return;
    }
    if (!allRemoved) {
      SnackBarHelper.showError(
        context,
        'تعذّرت استعادة بعض الإعدادات، حاول مرة أخرى',
      );
      return;
    }
    setState(() {
      _baseUrlController.text = _defaultBaseUrl;
      _instanceIdController.text = _defaultInstanceId;
      _tokenController.text = _defaultToken;
      _templateController.text = whatsappPaymentTemplate;
      _customUrlController.text = '';
      _selectedApiType = WhatsAppApiType.custom;
    });
    SnackBarHelper.showWarning(context, 'تم استعادة جميع الإعدادات الافتراضية');
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      final testService = WhatsAppService(
        apiType: _selectedApiType,
        baseUrl: _baseUrlController.text.trim(),
        instanceId: _instanceIdController.text.trim(),
        token: _tokenController.text.trim(),
        customUrlTemplate: _customUrlController.text.trim(),
      );

      final result = await testService.testConnection();

      if (!mounted) {
        return;
      }
      setState(() => _isTesting = false);

      if (result.success) {
        _showTestResult(true, 'API متصل بنجاح', result.body);
      } else if (result.statusCode == 0) {
        _showTestResult(
          false,
          'فشل الاتصال بالخادم',
          'تأكد من اتصالك بالإنترنت وأن الرابط صحيح',
        );
      } else if (result.statusCode == 401) {
        _showTestResult(
          false,
          'مفتاح API غير صالح (401)',
          'تحقق من صحة المفتاح في لوحة التحكم',
        );
      } else {
        final cleanBody = _sanitizeResponseBody(result.body);
        _showTestResult(
          false,
          'خطأ (${result.statusCode})',
          cleanBody.isNotEmpty
              ? cleanBody
              : 'تحقق من الإعدادات وحاول مرة أخرى.',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isTesting = false);
      _showTestResult(false, 'فشل الاتصال', e.toString());
    }
  }

  String _sanitizeResponseBody(String body) {
    var cleaned = body.replaceAll(RegExp('<[^>]*>'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (RegExp(r'^[\s\n]*$').hasMatch(cleaned)) {
      return '';
    }
    return cleaned;
  }

  void _showTestResult(bool success, String title, String detail) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (success ? Colors.green : Colors.red).withValues(
                    alpha: 0.08,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (success ? Colors.green : Colors.red).withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
                child: SelectableText(
                  detail,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// رفع الإعدادات إلى Appwrite Console
  Future<void> _uploadToCloud() async {
    setState(() => _isSyncing = true);
    try {
      final appwrite = ref.read(appwriteServiceProvider);
      final sync = WhatsAppSettingsSync(appwrite);
      final result = await sync.uploadToCloud();
      if (!mounted) {
        return;
      }
      setState(() => _isSyncing = false);
      if (result.success) {
        _showSyncResult(
          success: true,
          title: 'تم رفع الإعدادات إلى السحابة بنجاح',
          subtitle: 'يمكنك تنزيلها على أي جهاز آخر من هنا',
        );
      } else {
        _showSyncResult(
          success: false,
          title: 'فشل رفع الإعدادات',
          subtitle: result.error ?? 'حدث خطأ غير معروف',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isSyncing = false);
      _showSyncResult(
        success: false,
        title: 'خطأ غير متوقع',
        subtitle: e.toString(),
      );
    }
  }

  /// تأكيد تنزيل الإعدادات من السحابة
  Future<void> _confirmDownloadFromCloud() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_download, color: Colors.indigo, size: 28),
            SizedBox(width: 10),
            Text('تنزيل الإعدادات من السحابة'),
          ],
        ),
        content: const Text(
          'سيتم استبدال إعدادات الواتساب الحالية على هذا الجهاز بالإعدادات المحفوظة في السحابة.\n\nهل تريد المتابعة؟',
          textAlign: TextAlign.right,
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('تنزيل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _downloadFromCloud();
    }
  }

  /// تنزيل الإعدادات من Appwrite Console
  Future<void> _downloadFromCloud() async {
    setState(() => _isSyncing = true);
    try {
      final appwrite = ref.read(appwriteServiceProvider);
      final sync = WhatsAppSettingsSync(appwrite);
      final result = await sync.downloadFromCloud();
      if (!mounted) {
        return;
      }
      setState(() => _isSyncing = false);
      if (result.success) {
        // إعادة تحميل الإعدادات من SharedPreferences
        await _loadSettings();
        ref.invalidate(whatsappSettingsProvider);
        _showSyncResult(
          success: true,
          title: 'تم تنزيل الإعدادات من السحابة بنجاح',
          subtitle: 'تم تحديث الإعدادات المحلية',
        );
      } else {
        _showSyncResult(
          success: false,
          title: 'فشل تنزيل الإعدادات',
          subtitle: result.error ?? 'حدث خطأ غير معروف',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isSyncing = false);
      _showSyncResult(
        success: false,
        title: 'خطأ غير متوقع',
        subtitle: e.toString(),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await Process.run('xdg-open', [url]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات الواتساب',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Theme.of(context).colorScheme.primary,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: const [
                      Tab(text: 'إعدادات API'),
                      Tab(text: 'قالب الرسالة'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildApiSettingsTab(), _buildTemplateTab()],
                  ),
                ),
              ],
            ),
    );
  }

  // ─── تبويب إعدادات API ───
  Widget _buildApiSettingsTab() {
    final apiColor = _getApiColor();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── اختيار نوع API ───
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: apiColor.withValues(alpha: 0.4)),
            ),
            color: apiColor.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 20, color: apiColor),
                      const SizedBox(width: 8),
                      Text(
                        'نوع خدمة الواتساب',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: apiColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<WhatsAppApiType>(
                    segments: const [
                      ButtonSegment(
                        value: WhatsAppApiType.greenapi,
                        label: Text('GreenAPI', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.cloud, size: 16),
                      ),
                      ButtonSegment(
                        value: WhatsAppApiType.custom,
                        label: Text('مخصص', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.link, size: 16),
                      ),
                    ],
                    selected: {_selectedApiType},
                    onSelectionChanged: (selection) {
                      setState(() => _selectedApiType = selection.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildApiDescription(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── حقول حسب النوع المختار ───
          if (_selectedApiType == WhatsAppApiType.greenapi)
            _buildGreenApiFields(),
          if (_selectedApiType == WhatsAppApiType.custom)
            _buildCustomApiFields(),

          const SizedBox(height: 24),

          // أزرار الحفظ والاختبار
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveApiSettings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save, size: 18),
                  label: Text(
                    _isSaving ? 'جاري الحفظ...' : 'حفظ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(
                    _isTesting ? 'جاري الاختبار...' : 'اختبار الاتصال',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetApiToDefault,
              icon: const Icon(Icons.restore, size: 16),
              label: const Text(
                'استعادة القيم الافتراضية',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ─── مزامنة مع Appwrite Console ───
          _buildCloudSyncSection(),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Color _getApiColor() {
    switch (_selectedApiType) {
      case WhatsAppApiType.greenapi:
        return Colors.green;
      case WhatsAppApiType.custom:
        return Colors.teal;
    }
  }

  Widget _buildApiDescription() {
    switch (_selectedApiType) {
      case WhatsAppApiType.greenapi:
        return Text(
          'GreenAPI — خدمة واتساب عبر حساب مجاني (3 أرقام فقط)',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        );
      case WhatsAppApiType.custom:
        return Text(
          'رابط مخصص — أي خدمة واتساب تدعم GET مع [number] و [text] أو [message]',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        );
    }
  }

  // ─── حقول GreenAPI ───
  Widget _buildGreenApiFields() {
    return Column(
      children: [
        Card(
          color: Colors.green.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.green.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepItem('1', 'سجّل في greenapi.com وأنشئ instance'),
                _buildStepItem('2', 'انسخ Base URL و Instance ID و Token'),
                _buildStepItem('3', 'ألصقها في الحقول أدناه واختبر الاتصال'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLabel('رابط API (Base URL)'),
        TextField(
          controller: _baseUrlController,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'https://xxx.api.greenapi.com',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.link, size: 20),
            suffixIcon: _buildPasteButton(_baseUrlController),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 14),
        _buildLabel('معرّف الحساب (Instance ID)'),
        TextField(
          controller: _instanceIdController,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'waInstanceXXXXXXXXXX',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.fingerprint, size: 20),
            suffixIcon: _buildPasteButton(_instanceIdController),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 14),
        _buildLabel('رمز التوكن (API Token)'),
        TextField(
          controller: _tokenController,
          obscureText: _obscureToken,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'أدخل رمز التوكن',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.vpn_key, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _obscureToken ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  tooltip: _obscureToken ? 'إظهار' : 'إخفاء',
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                ),
                _buildPasteButton(_tokenController),
              ],
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ],
    );
  }

  // ─── حقول الرابط المخصص ───
  Widget _buildCustomApiFields() {
    return Column(
      children: [
        Card(
          color: Colors.teal.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.teal.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.teal, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'رابط API مخصص',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildVariableChip('[number]', 'رقم الهاتف'),
                _buildVariableChip('[text]', 'نص الرسالة'),
                _buildVariableChip('[message]', 'نص الرسالة'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'مثال: https://wa.nux.my.id/api/sendWA?to=[number]&msg=[message]&secret=xxx',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.teal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLabel('رابط API المخصص'),
        TextField(
          controller: _customUrlController,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
          maxLines: 3,
          decoration: InputDecoration(
            hintText:
                'https://example.com/api/send?to=[number]&msg=[message]&key=xxx',
            border: const OutlineInputBorder(),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(Icons.link, size: 20),
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: _buildPasteButton(_customUrlController),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            alignLabelWithHint: true,
          ),
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
        ),
      ],
    );
  }

  /// عرض نتيجة المزامنة
  void _showSyncResult({
    required bool success,
    required String title,
    required String subtitle,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: Colors.grey.shade700,
          ),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ─── قسم مزامنة السحابة ───
  Widget _buildCloudSyncSection() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade200),
      ),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_sync, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text(
                  'مزامنة مع Appwrite Console',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'احفظ إعدادات الواتساب في السحابة واسترجعها على أي جهاز',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'يتم إنشاء المجموعة تلقائياً عند أول رفع',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _uploadToCloud,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload, size: 18),
                    label: Text(
                      _isSyncing ? 'جاري المزامنة...' : 'رفع إلى السحابة',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSyncing ? null : _confirmDownloadFromCloud,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download, size: 18),
                    label: const Text(
                      'تنزيل من السحابة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _openUrl(
                'https://fra.cloud.appwrite.io/project/${AppwriteConfig.projectId}/database/${AppwriteConfig.databaseId}/collection/app_settings',
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: Colors.blue.shade400,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'فتح في Appwrite Console',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade400,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── تبويب قالب الرسالة ───
  Widget _buildTemplateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.code, color: Colors.purple, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'المتغيرات المتاحة:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildVariableChip('{name}', 'اسم الضيف'),
                  _buildVariableChip('{amount}', 'المبلغ المدفوع'),
                  _buildVariableChip('{room}', 'رقم الغرفة'),
                  _buildVariableChip('{remaining}', 'المبلغ المتبقي'),
                  _buildVariableChip(
                    '{extra_nights}',
                    'تفاصيل الليالي الإضافية',
                  ),
                  _buildVariableChip('{new_checkout}', 'تاريخ المغادرة الجديد'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'نص الرسالة:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _templateController,
            maxLines: 10,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'أدخل نص الرسالة هنا...',
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveTemplate,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text(
                    'حفظ القالب',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetTemplateToDefault,
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text(
                    'القالب الافتراضي',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetAllToDefault,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text(
                'استعادة جميع الإعدادات الافتراضية',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPasteButton(TextEditingController controller) {
    return IconButton(
      icon: const Icon(Icons.paste, size: 18),
      tooltip: 'لصق',
      onPressed: () async {
        final data = await Clipboard.getData('text/plain');
        if (data?.text != null) {
          setState(() => controller.text = data!.text!);
        }
      },
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildStepItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariableChip(String variable, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Text(
              variable,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
