import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/message_templates.dart';

class WhatsAppSettingsScreen extends ConsumerStatefulWidget {
  const WhatsAppSettingsScreen({super.key});

  @override
  ConsumerState<WhatsAppSettingsScreen> createState() =>
      _WhatsAppSettingsScreenState();
}

class _WhatsAppSettingsScreenState
    extends ConsumerState<WhatsAppSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _templateController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _instanceIdController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isSaving = false;
  late TabController _tabController;
  bool _obscureToken = true;

  // القيم الافتراضية
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
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _templateController.text =
          prefs.getString('whatsapp_template') ?? whatsappPaymentTemplate;
      _baseUrlController.text =
          prefs.getString('wa_api_base_url') ?? _defaultBaseUrl;
      _instanceIdController.text =
          prefs.getString('wa_api_instance_id') ?? _defaultInstanceId;
      _tokenController.text =
          prefs.getString('wa_api_token') ?? _defaultToken;
      _isLoading = false;
    });
  }

  Future<void> _saveApiSettings() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wa_api_base_url', _baseUrlController.text.trim());
    await prefs.setString(
      'wa_api_instance_id',
      _instanceIdController.text.trim(),
    );
    await prefs.setString('wa_api_token', _tokenController.text.trim());
    // تحديث الـ provider
    ref.invalidate(whatsappSettingsProvider);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ إعدادات API بنجاح'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _saveTemplate() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('whatsapp_template', _templateController.text);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ إعدادات الرسالة بنجاح'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _resetApiToDefault() async {
    setState(() {
      _baseUrlController.text = _defaultBaseUrl;
      _instanceIdController.text = _defaultInstanceId;
      _tokenController.text = _defaultToken;
    });
  }

  Future<void> _resetTemplateToDefault() async {
    setState(() {
      _templateController.text = whatsappPaymentTemplate;
    });
  }

  Future<void> _resetAllToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wa_api_base_url');
    await prefs.remove('wa_api_instance_id');
    await prefs.remove('wa_api_token');
    await prefs.remove('whatsapp_template');
    ref.invalidate(whatsappSettingsProvider);
    if (!mounted) return;
    setState(() {
      _baseUrlController.text = _defaultBaseUrl;
      _instanceIdController.text = _defaultInstanceId;
      _tokenController.text = _defaultToken;
      _templateController.text = whatsappPaymentTemplate;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم استعادة جميع الإعدادات الافتراضية'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// اختبار اتصال API عبر طلب getState
  Future<void> _testConnection() async {
    final baseUrl = _baseUrlController.text.trim();
    final instanceId = _instanceIdController.text.trim();
    final token = _tokenController.text.trim();

    if (baseUrl.isEmpty || instanceId.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ملء جميع حقول API أولاً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isTesting = true);

    try {
      final testService = WhatsAppService(
        baseUrl: baseUrl,
        instanceId: instanceId,
        token: token,
      );

      final result = await testService.testConnection();

      if (!mounted) return;
      setState(() => _isTesting = false);

      if (result.success) {
        _showTestResult(true, 'API متصل بنجاح', result.body);
      } else if (result.statusCode == 401) {
        _showTestResult(
          false,
          'رمز التوكن غير صالح (401)',
          'تحقق من صحة API Token في لوحة تحكم GreenAPI',
        );
      } else if (result.statusCode == 403) {
        _showTestResult(
          false,
          'وصول مرفوض (403 Forbidden)',
          'الأسباب المحتملة:\n'
              '1. Instance ID أو Token غير صحيح\n'
              '2. انتهت صلاحية الحساب أو الحساب معطّل\n'
              '3. الرقم الخاص بالخطة المجانية تم تجاوزه\n'
              '4. عنوان IP محظور من قبل الخادم\n\n'
              'الحل: سجّل دخول في greenapi.com وتحقق من حالة الـ Instance',
        );
      } else if (result.statusCode == 404) {
        _showTestResult(
          false,
          'Instance ID غير موجود (404)',
          'تحقق من Instance ID والرابط في لوحة تحكم GreenAPI',
        );
      } else if (result.statusCode == 429) {
        _showTestResult(
          false,
          'تجاوز عدد الطلبات (429 Too Many)',
          'تم تجاوز حد الطلبات المسموح. انتظر قليلاً وحاول مرة أخرى.',
        );
      } else if (result.statusCode == 500 || result.statusCode == 502 || result.statusCode == 503) {
        _showTestResult(
          false,
          'خطأ في خادم GreenAPI (${result.statusCode})',
          'الخادم يواجه مشكلة مؤقتة. حاول مرة أخرى بعد قليل.',
        );
      } else if (result.statusCode == 0) {
        _showTestResult(
          false,
          'فشل الاتصال بالخادم',
          'تأكد من اتصالك بالإنترنت وأن الرابط (Base URL) صحيح\n\nالرابط الحالي: $baseUrl',
        );
      } else {
        final cleanBody = _sanitizeResponseBody(result.body);
        _showTestResult(
          false,
          'خطأ غير متوقع (${result.statusCode})',
          cleanBody.isNotEmpty ? cleanBody : 'حدث خطأ غير معروف. تحقق من الإعدادات وحاول مرة أخرى.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTesting = false);
      _showTestResult(false, 'فشل الاتصال', e.toString());
    }
  }

  /// تنظيف استجابة الخادم من HTML الخام
  String _sanitizeResponseBody(String body) {
    // إزالة أكواد HTML
    var cleaned = body.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    // إزالة الأسطر الفارغة المتعددة
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // إذا كانت النتيجة تحتوي على كلمات HTML فقط، أرجع نص فارغ
    if (RegExp(r'^[\s\n]*$').hasMatch(cleaned)) return '';
    return cleaned;
  }

  void _showTestResult(bool success, String title, String detail) {
    showDialog(
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (success ? Colors.green : Colors.red).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (success ? Colors.green : Colors.red).withOpacity(0.3),
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
            if (!success) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _launchGreenApi();
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text(
                    'فتح لوحة تحكم GreenAPI',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
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

  /// فتح لوحة تحكم GreenAPI في المتصفح
  Future<void> _launchGreenApi() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('افتح greenapi.com من المتصفح وتحقق من حالة الـ Instance'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات الواتساب',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tab bar
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
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
                    unselectedLabelColor:
                        Theme.of(context).colorScheme.primary,
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

                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildApiSettingsTab(),
                      _buildTemplateTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ─── تبويب إعدادات API ───
  Widget _buildApiSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // بطاقة معلومات
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'كيفية الحصول على بيانات API',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildStepItem('1', 'سجّل في greenapi.com وأنشئ instance'),
                  _buildStepItem('2', 'انسخ Base URL من لوحة التحكم'),
                  _buildStepItem('3', 'انسخ Instance ID و API Token'),
                  _buildStepItem(
                    '4',
                    'ألصقها في الحقول أدناه واختبر الاتصال',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // حقل Base URL
          _buildLabel('رابط API (Base URL)'),
          TextField(
            controller: _baseUrlController,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https://xxx.api.greenapi.com',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste, size: 18),
                tooltip: 'لصق',
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    setState(() => _baseUrlController.text = data!.text!);
                  }
                },
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

          const SizedBox(height: 16),

          // حقل Instance ID
          _buildLabel('معرّف الحساب (Instance ID)'),
          TextField(
            controller: _instanceIdController,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'waInstanceXXXXXXXXXX',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.fingerprint, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste, size: 18),
                tooltip: 'لصق',
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    setState(() => _instanceIdController.text = data!.text!);
                  }
                },
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

          const SizedBox(height: 16),

          // حقل Token
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
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                  ),
                  IconButton(
                    icon: const Icon(Icons.paste, size: 18),
                    tooltip: 'لصق',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        setState(() => _tokenController.text = data!.text!);
                      }
                    },
                  ),
                ],
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

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
                    _isSaving ? 'جاري الحفظ...' : 'حفظ API',
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

          // استعادة الافتراضي
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetApiToDefault,
              icon: const Icon(Icons.restore, size: 16),
              label: const Text(
                'استعادة القيم الافتراضية لـ API',
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
        ],
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
          // بطاقة المتغيرات
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
                  _buildVariableChip('{extra_nights}', 'تفاصيل الليالي الإضافية'),
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

          // استعادة كل شيء
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
