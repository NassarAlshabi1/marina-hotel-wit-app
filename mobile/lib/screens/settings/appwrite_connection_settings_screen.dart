import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart' as ap;
import '../../services/appwrite_config.dart';
import '../../services/appwrite_config_manager.dart';
import '../../services/appwrite_realtime_sync.dart';
import '../../services/appwrite_service.dart';
import '../../services/appwrite_sync_manager.dart';
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
      final previousIdentity = AppwriteConfigManager.targetIdentity;
      final previousApiKey = AppwriteConfigManager.apiKey;

      // القيم تُطبَّع داخل saveConfig، فلا حاجة لـ trim هنا (وإلا اختلف ما
      // تختبره الشاشة عمّا يُحفظ فعلاً).
      await AppwriteConfigManager.saveConfig(
        endpoint: _endpointController.text,
        projectId: _projectIdController.text,
        databaseId: _databaseIdController.text,
        apiKey: _apiKeyController.text,
      );

      final identityChanged =
          AppwriteConfigManager.targetIdentity != previousIdentity;
      final credentialsChanged =
          identityChanged || AppwriteConfigManager.apiKey != previousApiKey;

      final applyError = await _applySavedConfig(
        credentialsChanged: credentialsChanged,
      );

      if (!mounted) {
        return;
      }

      _syncControllersWithSavedConfig();
      setState(() => _hasChanges = false);

      if (applyError != null) {
        // الحفظ نجح لكن التطبيق الفوري تعذّر — لا نُخفي ذلك خلف "تم الحفظ".
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حفظ الإعدادات، لكن لم تُطبَّق فوراً: $applyError',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الإعدادات وتطبيقها فوراً'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }

      if (identityChanged) {
        _showTargetChangedDialog();
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

  /// ✅ (2026-11-06) تطبيق الإعدادات المحفوظة على الخدمات العاملة فوراً.
  ///
  /// **العطل المؤكد**: كان الحفظ يكتفي بكتابة SharedPreferences ثم يُظهر حوار
  /// "إعادة تشغيل مطلوبة"، لأن `AppwriteService.initialize()` يبني عميل
  /// Appwrite مرة واحدة ويحرسه بـ `_initialized` بلا أي مسار لإعادة البناء.
  /// أي أن كل ما يعمل في هذه الأثناء (المزامنة التلقائية، الرفع اليدوي،
  /// السحب، الـ Realtime) يظل يخاطب **المشروع القديم** بعد "حفظ ناجح".
  ///
  /// الترتيب مقصود: إعادة بناء العميل ← إعادة بناء الـ Realtime (يُبنى من
  /// نفس العميل ويُسقط عند التوقف) ← إبلاغ مدير المزامنة ليعيد فحص هوية
  /// الهدف (وإلا سحب بمؤشرات قديمة على هدف جديد = نقص صامت).
  ///
  /// تعيد `null` عند النجاح، أو الخطأ عند الفشل (الحفظ يبقى ناجحاً).
  Future<String?> _applySavedConfig({required bool credentialsChanged}) async {
    try {
      // ⚠️ لا نُبدّل العميل في منتصف دورة مزامنة جارية: الصفوف التي رُفعت
      // فعلاً إلى الهدف **القديم** تُحذف من outbox عند النجاح، فلو بدّلنا
      // الهدف في منتصف الدورة لبقي نصف التغييرات في المشروع القديم ونصفها
      // في الجديد — انحراف بيانات لا يُكتشف لاحقاً. ننتظر انتهاء الدورة.
      final manager = AppwriteSyncManager.instance;
      if (manager != null && manager.isSyncing) {
        final idle = await _waitForSyncIdle(manager);
        if (!idle) {
          return 'المزامنة جارية الآن؛ أُجِّل تطبيق الإعدادات. '
              'أعد المحاولة بعد انتهائها (أو أعد تشغيل التطبيق).';
        }
      }

      // عبر الـ singleton مباشرةً (لا `ref`) لأن التطبيق يجب أن يُنجَز حتى لو
      // أُغلقت الشاشة أثناء الحفظ — و`ref` بعد dispose يرمي استثناءً.
      await AppwriteService().reinitialize();

      if (credentialsChanged && AppwriteRealtimeSync().isListening) {
        await AppwriteRealtimeSync().stop();
        await AppwriteRealtimeSync().start();
      }

      await AppwriteSyncManager.notifyConfigChanged();

      if (credentialsChanged && mounted) {
        // تحديث مؤشر الحالة في الشاشة السابقة بلا حجب زر الحفظ.
        unawaited(
          ref.read(ap.connectionStatusProvider.notifier).checkConnection(),
        );
      }
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// ينتظر انتهاء دورة المزامنة الجارية (فحص كل 250ms بحد أقصى 20 ثانية).
  /// يعيد `false` إن لم تنتهِ الدورة في الوقت المحدد — فلا نُطبّق في المنتصف.
  Future<bool> _waitForSyncIdle(
    AppwriteSyncManager manager, {
    Duration limit = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(limit);
    while (manager.isSyncing) {
      if (DateTime.now().isAfter(deadline)) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return true;
  }

  /// إعادة حقول النموذج إلى القيم المحفوظة المطبَّعة فعلياً (بلا شرطة مائلة
  /// نهائية أو فراغات) حتى لا تُظهر الشاشة نصاً غير الذي حُفظ.
  void _syncControllersWithSavedConfig() {
    _endpointController.text = AppwriteConfigManager.endpoint;
    _projectIdController.text = AppwriteConfigManager.projectId;
    _databaseIdController.text = AppwriteConfigManager.databaseId;
    _apiKeyController.text = AppwriteConfigManager.apiKey;
  }

  /// تحذير عند تغيير هدف المزامنة: المؤشرات القديمة لا تُستخدم، والدورة
  /// القادمة سحب كامل (upsert) من الهدف الجديد — وهذا سلوك مقصود لا خطأ.
  void _showTargetChangedDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.blue),
            SizedBox(width: 8),
            Text('تم التبديل إلى هدف مزامنة جديد'),
          ],
        ),
        content: const Text(
          'طُبّقت الإعدادات فوراً. لأن Endpoint أو Project أو Database تغيّر، '
          'ستبدأ المزامنة القادمة بسحب كامل من الهدف الجديد (إدراج/تحديث '
          'idempotent) بدل الاعتماد على مؤشرات السحب القديمة.',
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
            onPressed: () => Navigator.pop<bool>(context, false),
            child: const Text('إلغاء'),
          ),
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

    final previousIdentity = AppwriteConfigManager.targetIdentity;

    await AppwriteConfigManager.resetToDefaults();

    // ✅ (2026-11-06) إعادة التعيين تُطبَّق فوراً أيضاً — كانت تُظهر نفس
    // حوار "إعادة تشغيل مطلوبة" وتبقي العميل على الإعدادات المخصّصة القديمة.
    final applyError = await _applySavedConfig(credentialsChanged: true);

    if (!mounted) {
      return;
    }
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
        SnackBar(
          content: Text(
            applyError == null
                ? 'تم إعادة تعيين الإعدادات وتطبيقها فوراً'
                : 'تم إعادة تعيين الإعدادات، لكن لم تُطبَّق فوراً: '
                      '$applyError',
          ),
          backgroundColor: applyError == null ? Colors.green : Colors.orange,
          duration: Duration(seconds: applyError == null ? 3 : 6),
        ),
      );

      if (AppwriteConfigManager.targetIdentity != previousIdentity) {
        _showTargetChangedDialog();
      }
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isTesting = true);

    // ✅ (2026-11-06) نختبر **المفتاح الفعّال** لا الحقل كما هو: ترك الحقل
    // فارغاً يعني استخدام المفتاح المدمج عند التشغيل (انظر
    // AppwriteConfigManager.saveConfig)، لكن الاختبار كان يرسل بلا مفتاح
    // فيقيس وصولاً "زائراً" لا الإعدادات التي ستُحفظ فعلاً — فينجح الاختبار
    // ثم تفشل المزامنة بـ 401 (أو العكس).
    final enteredApiKey = _apiKeyController.text.trim();
    final usingBuiltinKey = enteredApiKey.isEmpty;
    final effectiveApiKey = usingBuiltinKey
        ? AppwriteConfig.defaultApiKey
        : enteredApiKey;

    try {
      final result = await ref
          .read(ap.appwriteServiceProvider)
          .testConnectionWithConfig(
            endpoint: _endpointController.text,
            projectId: _projectIdController.text,
            databaseId: _databaseIdController.text,
            apiKey: effectiveApiKey,
          );
      if (!mounted) {
        return;
      }

      final success = result['overall_success'] == true;
      final error = result['error']?.toString();
      // ✅ (2026-11-06) التسمية كانت تقول "القيم الحالية" وهي تختبر القيم
      // المُدخلة غير المحفوظة؛ والتشخيص كان سطراً واحداً لا يفرّق بين
      // Endpoint خاطئ وProject خاطئ وDatabase غير موجود ومفتاح بلا صلاحية.
      final hint = result['hint']?.toString();
      final keyNote = !success && usingBuiltinKey && effectiveApiKey.isEmpty
          ? '\nلا يوجد API Key مُدخل ولا مفتاح مدمج — الطلب بلا مصادقة.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'نجح اختبار الاتصال بالقيم المُدخلة (لم تُحفظ بعد)'
                : 'فشل اختبار الاتصال: ${hint ?? error ?? 'سبب غير معروف'}'
                      '$keyNote',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: Duration(seconds: success ? 4 : 7),
        ),
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'فشل اختبار الاتصال: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      } else {
        _isTesting = false;
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
                // ✅ (2026-11-06) النص كان يصف الإعدادات بلا ذكر أثرها؛ الآن
                // تُطبَّق فوراً بلا إعادة تشغيل (انظر _applySavedConfig).
                'يمكنك تغيير إعدادات الاتصال بـ Appwrite Cloud هنا. تأكد من '
                'إدخال البيانات الصحيحة من لوحة تحكم Appwrite. '
                'تُطبَّق التغييرات فوراً على المزامنة بلا إعادة تشغيل التطبيق.',
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
                if (!value.startsWith('http://') &&
                    !value.startsWith('https://')) {
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
                // ✅ (2026-11-06) كان النص يَعِد بأن المفتاح الافتراضي يُستخدم
                // "تلقائياً" بينما حفظ الحقل فارغاً كان يطمس المفتاح المدمج
                // نهائياً (see AppwriteConfigManager.saveConfig).
                helperText: AppwriteConfig.defaultApiKey.isEmpty
                    ? 'لم يُمرَّر مفتاح مدمج في بناء التطبيق — أدخل مفتاحاً '
                          'يملك صلاحية قراءة/كتابة المجموعات.'
                    : 'اتركه فارغاً لاستخدام المفتاح الافتراضي المدمج، أو '
                          'أدخل مفتاحاً بديلاً.',
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
                  isCustom ? 'إعدادات مخصصة' : 'الإعدادات الافتراضية',
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
            _buildConfigRow('Endpoint', AppwriteConfigManager.endpoint),
            _buildConfigRow('Project ID', AppwriteConfigManager.projectId),
            _buildConfigRow('Database ID', AppwriteConfigManager.databaseId),
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
