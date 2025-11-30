import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../providers/api_integration_provider.dart';

class ApiIntegrationsScreen extends ConsumerStatefulWidget {
  const ApiIntegrationsScreen({super.key});

  @override
  ConsumerState<ApiIntegrationsScreen> createState() => _ApiIntegrationsScreenState();
}

class _ApiIntegrationsScreenState extends ConsumerState<ApiIntegrationsScreen> {
  late TextEditingController _waBaseUrl;
  late TextEditingController _waInstance;
  late TextEditingController _waToken;
  late TextEditingController _waCountryCode;
  late TextEditingController _appwriteEndpoint;
  late TextEditingController _appwriteProjectId;
  late TextEditingController _appwriteDatabaseId;
  late TextEditingController _appwriteApiKey;
  late TextEditingController _supabaseUrl;
  late TextEditingController _supabaseAnonKey;
  late TextEditingController _supabaseServiceKey;
  late TextEditingController _supabaseProjectRef;
  late ProviderSubscription<ApiIntegrationSettings> _settingsSubscription;

  bool _waEnabled = true;
  bool _appwriteEnabled = false;
  bool _supabaseEnabled = false;
  bool _waSaving = false;
  bool _appwriteSaving = false;
  bool _supabaseSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(apiIntegrationSettingsProvider);
    _initControllers(initial);
    _settingsSubscription = ref.listen<ApiIntegrationSettings>(
      apiIntegrationSettingsProvider,
      (previous, next) {
        _applySettings(next);
      },
    );
  }

  void _initControllers(ApiIntegrationSettings settings) {
    _waBaseUrl = TextEditingController(text: settings.whatsapp.baseUrl);
    _waInstance = TextEditingController(text: settings.whatsapp.instanceId);
    _waToken = TextEditingController(text: settings.whatsapp.token);
    _waCountryCode = TextEditingController(text: settings.whatsapp.defaultCountryCode);
    _appwriteEndpoint = TextEditingController(text: settings.appwrite.endpoint);
    _appwriteProjectId = TextEditingController(text: settings.appwrite.projectId);
    _appwriteDatabaseId = TextEditingController(text: settings.appwrite.databaseId);
    _appwriteApiKey = TextEditingController(text: settings.appwrite.apiKey);
    _supabaseUrl = TextEditingController(text: settings.supabase.apiUrl);
    _supabaseAnonKey = TextEditingController(text: settings.supabase.anonKey);
    _supabaseServiceKey = TextEditingController(text: settings.supabase.serviceRoleKey);
    _supabaseProjectRef = TextEditingController(text: settings.supabase.projectRef);
    _waEnabled = settings.whatsapp.enabled;
    _appwriteEnabled = settings.appwrite.enabled;
    _supabaseEnabled = settings.supabase.enabled;
  }

  void _applySettings(ApiIntegrationSettings settings) {
    if (!mounted) {
      return;
    }
    setState(() {
      _waEnabled = settings.whatsapp.enabled;
      _appwriteEnabled = settings.appwrite.enabled;
      _supabaseEnabled = settings.supabase.enabled;
    });
  }

  @override
  void dispose() {
    _settingsSubscription.close();
    _waBaseUrl.dispose();
    _waInstance.dispose();
    _waToken.dispose();
    _waCountryCode.dispose();
    _appwriteEndpoint.dispose();
    _appwriteProjectId.dispose();
    _appwriteDatabaseId.dispose();
    _appwriteApiKey.dispose();
    _supabaseUrl.dispose();
    _supabaseAnonKey.dispose();
    _supabaseServiceKey.dispose();
    _supabaseProjectRef.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(apiIntegrationSettingsProvider);
    return AppScaffold(
      title: 'تكاملات واجهات البرمجة',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWhatsAppSection(context, settings.whatsapp),
          const SizedBox(height: 16),
          _buildAppwriteSection(context, settings.appwrite),
          const SizedBox(height: 16),
          _buildSupabaseSection(context, settings.supabase),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(apiIntegrationSettingsProvider.notifier).reset();
              _showSnack(context, 'تمت استعادة الإعدادات الافتراضية');
            },
            icon: const Icon(Icons.replay),
            label: const Text('استعادة الإعدادات الافتراضية'),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppSection(BuildContext context, WhatsAppIntegrationSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.chat, color: Colors.green),
                SizedBox(width: 8),
                Text('تكامل WhatsApp', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            SwitchListTile(
              value: _waEnabled,
              onChanged: (value) => setState(() => _waEnabled = value),
              title: const Text('تفعيل خدمة WhatsApp'),
              subtitle: const Text('تمكين إرسال الرسائل والمستندات عبر Whatsapp API'),
            ),
            TextField(
              controller: _waBaseUrl,
              decoration: const InputDecoration(labelText: 'Base URL', prefixIcon: Icon(Icons.link)),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: _waInstance,
              decoration: const InputDecoration(labelText: 'Instance ID', prefixIcon: Icon(Icons.devices_other)),
            ),
            TextField(
              controller: _waToken,
              decoration: const InputDecoration(labelText: 'Token', prefixIcon: Icon(Icons.vpn_key)),
              obscureText: true,
            ),
            TextField(
              controller: _waCountryCode,
              decoration: const InputDecoration(labelText: 'رمز الدولة الافتراضي', prefixIcon: Icon(Icons.flag)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _waSaving ? null : () => _saveWhatsApp(context),
                    icon: _waSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_waSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _testWhatsApp(context),
                    icon: const Icon(Icons.bolt),
                    label: const Text('اختبار الاتصال'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppwriteSection(BuildContext context, AppwriteIntegrationSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.cloud_sync, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('تكامل Appwrite', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            SwitchListTile(
              value: _appwriteEnabled,
              onChanged: (value) => setState(() => _appwriteEnabled = value),
              title: const Text('تفعيل اتصال Appwrite'),
              subtitle: const Text('إدارة نقطة النهاية ومعرفات المشروع من داخل التطبيق'),
            ),
            TextField(
              controller: _appwriteEndpoint,
              decoration: const InputDecoration(labelText: 'Endpoint', prefixIcon: Icon(Icons.public)),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: _appwriteProjectId,
              decoration: const InputDecoration(labelText: 'Project ID', prefixIcon: Icon(Icons.badge)),
            ),
            TextField(
              controller: _appwriteDatabaseId,
              decoration: const InputDecoration(labelText: 'Database ID', prefixIcon: Icon(Icons.storage)),
            ),
            TextField(
              controller: _appwriteApiKey,
              decoration: const InputDecoration(labelText: 'API Key (سرية)', prefixIcon: Icon(Icons.key)),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _appwriteSaving ? null : () => _saveAppwrite(context),
                    icon: _appwriteSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_appwriteSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSnack(context, 'سيتم دعم اختبار الاتصال لاحقاً'),
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('اختبار الاتصال'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupabaseSection(BuildContext context, SupabaseIntegrationSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.api, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('تكامل Supabase', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            SwitchListTile(
              value: _supabaseEnabled,
              onChanged: (value) => setState(() => _supabaseEnabled = value),
              title: const Text('تفعيل اتصال Supabase'),
              subtitle: const Text('إرسال واستقبال البيانات من قاعدة Supabase'),
            ),
            TextField(
              controller: _supabaseUrl,
              decoration: const InputDecoration(labelText: 'API URL', prefixIcon: Icon(Icons.link)),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: _supabaseAnonKey,
              decoration: const InputDecoration(labelText: 'Anon Key', prefixIcon: Icon(Icons.shield)),
              obscureText: true,
            ),
            TextField(
              controller: _supabaseServiceKey,
              decoration: const InputDecoration(labelText: 'Service Role Key', prefixIcon: Icon(Icons.security)),
              obscureText: true,
            ),
            TextField(
              controller: _supabaseProjectRef,
              decoration: const InputDecoration(labelText: 'Project Reference', prefixIcon: Icon(Icons.code)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _supabaseSaving ? null : () => _saveSupabase(context),
                    icon: _supabaseSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_supabaseSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSnack(context, 'سيتم إضافة اختبار Supabase لاحقاً'),
                    icon: const Icon(Icons.waves),
                    label: const Text('اختبار الاتصال'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveWhatsApp(BuildContext context) async {
    setState(() => _waSaving = true);
    final notifier = ref.read(apiIntegrationSettingsProvider.notifier);
    final config = WhatsAppIntegrationSettings(
      enabled: _waEnabled,
      baseUrl: _waBaseUrl.text.trim(),
      instanceId: _waInstance.text.trim(),
      token: _waToken.text.trim(),
      defaultCountryCode: _waCountryCode.text.trim(),
    );
    await notifier.updateWhatsApp(config);
    setState(() => _waSaving = false);
    _showSnack(context, 'تم حفظ إعدادات WhatsApp');
  }

  Future<void> _saveAppwrite(BuildContext context) async {
    setState(() => _appwriteSaving = true);
    final notifier = ref.read(apiIntegrationSettingsProvider.notifier);
    final config = AppwriteIntegrationSettings(
      enabled: _appwriteEnabled,
      endpoint: _appwriteEndpoint.text.trim(),
      projectId: _appwriteProjectId.text.trim(),
      databaseId: _appwriteDatabaseId.text.trim(),
      apiKey: _appwriteApiKey.text.trim(),
    );
    await notifier.updateAppwrite(config);
    setState(() => _appwriteSaving = false);
    _showSnack(context, 'تم حفظ إعدادات Appwrite');
  }

  Future<void> _saveSupabase(BuildContext context) async {
    setState(() => _supabaseSaving = true);
    final notifier = ref.read(apiIntegrationSettingsProvider.notifier);
    final config = SupabaseIntegrationSettings(
      enabled: _supabaseEnabled,
      apiUrl: _supabaseUrl.text.trim(),
      anonKey: _supabaseAnonKey.text.trim(),
      serviceRoleKey: _supabaseServiceKey.text.trim(),
      projectRef: _supabaseProjectRef.text.trim(),
    );
    await notifier.updateSupabase(config);
    setState(() => _supabaseSaving = false);
    _showSnack(context, 'تم حفظ إعدادات Supabase');
  }

  Future<void> _testWhatsApp(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastTestKey = 'whatsapp_test_timestamp';
    await prefs.setInt(lastTestKey, DateTime.now().millisecondsSinceEpoch);
    _showSnack(context, 'تم تسجيل اختبار الاتصال (تحقق من لوحة الاتصالات)');
  }

  void _showSnack(BuildContext context, String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
