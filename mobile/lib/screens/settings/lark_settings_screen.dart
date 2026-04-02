import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/lark_provider.dart';

/// شاشة إعدادات Lark Suite
/// تتيح للمستخدم إعداد Lark للإشعارات والتقارير اليومية
class LarkSettingsScreen extends ConsumerStatefulWidget {
  const LarkSettingsScreen({super.key});

  @override
  ConsumerState<LarkSettingsScreen> createState() => _LarkSettingsScreenState();
}

class _LarkSettingsScreenState extends ConsumerState<LarkSettingsScreen> {
  final _webhookController = TextEditingController();
  final _appIdController = TextEditingController();
  final _appSecretController = TextEditingController();
  final _reportTimeController = TextEditingController();

  bool _showSecret = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final state = ref.read(larkProvider);
    _webhookController.text = state.webhookUrl;
    _appIdController.text = state.appId;
    _reportTimeController.text = state.dailyReportTime;
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _webhookController.dispose();
    _appIdController.dispose();
    _appSecretController.dispose();
    _reportTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final larkState = ref.watch(larkProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'إعدادات Lark Suite',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─────────────────────────────────
                // بطاقة التفعيل الرئيسية
                // ─────────────────────────────────
                _buildMainToggleCard(context, larkState, theme),

                const SizedBox(height: 16),

                // ─────────────────────────────────
                // قسم إعداد الاتصال
                // ─────────────────────────────────
                if (larkState.isEnabled) ...[
                  _buildSectionTitle('إعداد الاتصال', Icons.link, theme),
                  _buildConnectionSection(larkState, theme),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم الإشعارات الفورية
                  // ─────────────────────────────────
                  _buildSectionTitle('الإشعارات الفورية', Icons.notifications_active, theme),
                  _buildNotificationsCard(larkState, theme),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم التقرير اليومي
                  // ─────────────────────────────────
                  _buildSectionTitle('التقرير اليومي التلقائي', Icons.assessment, theme),
                  _buildDailyReportCard(larkState, theme),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم الإجراءات
                  // ─────────────────────────────────
                  _buildSectionTitle('إجراءات', Icons.settings, theme),
                  _buildActionsCard(larkState, theme),
                  const SizedBox(height: 16),
                ],

                // ─────────────────────────────────
                // رسالة الحالة
                // ─────────────────────────────────
                if (larkState.message != null)
                  _buildStatusMessage(larkState, theme),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة التفعيل الرئيسية
  // ─────────────────────────────────────────────────
  Widget _buildMainToggleCard(
    BuildContext context,
    LarkState state,
    ThemeData theme,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: state.isEnabled
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.integration_instructions,
                    color: state.isEnabled ? Colors.blue : Colors.grey,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Lark Suite',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.isEnabled
                            ? 'مفعّل — الإشعارات والتقارير نشطة'
                            : 'معطّل — لن يتم إرسال أي شيء',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isEnabled,
                  onChanged: (value) =>
                      ref.read(larkProvider.notifier).setEnabled(value),
                  activeColor: Colors.blue,
                ),
              ],
            ),

            if (!state.isEnabled) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'فعّل Lark Suite لإرسال إشعارات فورية وتقارير يومية تلقائية لموظفي الفندق',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // قسم إعداد الاتصال
  // ─────────────────────────────────────────────────
  Widget _buildConnectionSection(LarkState state, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Webhook URL (الطريقة الأسهل)
            _buildInfoRow(
              icon: Icons.webhook,
              label: 'Incoming Webhook URL',
              subtitle: 'الطريقة الأسهل — لا تحتاج App ID',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _webhookController,
              decoration: InputDecoration(
                hintText: 'https://open.larksuite.com/open-apis/bot/v2/hook/...',
                prefixIcon: const Icon(Icons.link, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste, size: 20),
                  onPressed: () {
                    // يمكن إضافة لصق من الحافظة لاحقاً
                  },
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              onChanged: (value) {
                ref.read(larkProvider.notifier).setWebhookUrl(value.trim());
              },
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // App ID
            _buildInfoRow(
              icon: Icons.apps,
              label: 'App ID',
              subtitle: 'من Lark Open Platform',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _appIdController,
              decoration: const InputDecoration(
                hintText: 'cli_xxxxxxxxxx',
                prefixIcon: Icon(Icons.vpn_key, size: 20),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              onChanged: (value) {
                ref.read(larkProvider.notifier).setAppId(value.trim());
              },
            ),

            const SizedBox(height: 16),

            // App Secret
            _buildInfoRow(
              icon: Icons.lock,
              label: 'App Secret',
              subtitle: 'من Lark Open Platform',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _appSecretController,
              obscureText: !_showSecret,
              decoration: InputDecoration(
                hintText: 'xxxxxxxxxxxxxxxxxxxxxxxx',
                prefixIcon: const Icon(Icons.password, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showSecret ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showSecret = !_showSecret),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              onChanged: (value) {
                ref.read(larkProvider.notifier).setAppSecret(value.trim());
              },
            ),

            // مؤشر حالة الاتصال
            const SizedBox(height: 16),
            Row(
              children: [
                if (state.hasValidToken)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'متصل',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, color: Colors.grey, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'غير متصل',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.isConfigured) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'مُعدّ',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة الإشعارات الفورية
  // ─────────────────────────────────────────────────
  Widget _buildNotificationsCard(LarkState state, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: state.isNotificationsEnabled
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.notifications_active,
                    color: state.isNotificationsEnabled
                        ? Colors.green
                        : Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الإشعارات الفورية',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.isNotificationsEnabled
                            ? 'يتم إرسال إشعارات عند الأحداث'
                            : 'الإشعارات معطّلة',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isNotificationsEnabled,
                  onChanged: (value) => ref
                      .read(larkProvider.notifier)
                      .setNotificationsEnabled(value),
                  activeColor: Colors.green,
                ),
              ],
            ),

            // قائمة أنواع الإشعارات
            if (state.isNotificationsEnabled) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'الأحداث المُراقَبة:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildEventChip('📋 حجز جديد', Colors.green),
                  _buildEventChip('🔑 تسجيل دخول', Colors.blue),
                  _buildEventChip('🚪 تسجيل خروج', Colors.orange),
                  _buildEventChip('💰 دفعة', Colors.teal),
                  _buildEventChip('🔧 صيانة', Colors.amber),
                  _buildEventChip('❌ إلغاء', Colors.red),
                  _buildEventChip('⏰ تأخير', Colors.redAccent),
                  _buildEventChip('💸 مصروف', Colors.deepOrange),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة التقرير اليومي
  // ─────────────────────────────────────────────────
  Widget _buildDailyReportCard(LarkState state, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: state.isDailyReportEnabled
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.assessment,
                    color: state.isDailyReportEnabled
                        ? Colors.blue
                        : Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'التقرير اليومي التلقائي',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.isDailyReportEnabled
                            ? 'يُرسل تلقائياً في ${state.dailyReportTime}'
                            : 'التقارير اليومية معطّلة',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isDailyReportEnabled,
                  onChanged: (value) => ref
                      .read(larkProvider.notifier)
                      .setDailyReportEnabled(value),
                  activeColor: Colors.blue,
                ),
              ],
            ),

            if (state.isDailyReportEnabled) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),

              // اختيار وقت الإرسال
              Row(
                children: [
                  const Icon(Icons.schedule, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'وقت الإرسال:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectReportTime(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          state.dailyReportTime,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // آخر تقرير تم إرساله
              if (state.lastReportSent != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'آخر تقرير: ${state.lastReportSent}',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(larkProvider.notifier)
                            .resetLastReport(),
                        child: Text(
                          'إعادة إرسال',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // محتوى التقرير المتوقع
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'محتوى التقرير:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('📊 حالة الغرف (مشغولة/متاحة/تنظيف/صيانة)'),
                    SizedBox(height: 4),
                    Text('📋 حجوزات اليوم (جديدة/دخول/خروج/نشطة)'),
                    SizedBox(height: 4),
                    Text('💰 ملخص مالي (إيرادات/مصروفات/صافي ربح)'),
                    SizedBox(height: 4),
                    Text('⚠️ تنبيهات (تأخير مغادرة/ديون)'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة الإجراءات
  // ─────────────────────────────────────────────────
  Widget _buildActionsCard(LarkState state, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // اختبار الاتصال
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.status == LarkSetupStatus.testing
                    ? null
                    : () => ref.read(larkProvider.notifier).testConnection(),
                icon: state.status == LarkSetupStatus.testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(state.status == LarkSetupStatus.testing
                    ? 'جاري الاختبار...'
                    : 'اختبار الاتصال'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // إرسال تقرير تجريبي
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.status == LarkSetupStatus.sendingReport
                    ? null
                    : () => ref.read(larkProvider.notifier).sendTestReport(),
                icon: state.status == LarkSetupStatus.sendingReport
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(state.status == LarkSetupStatus.sendingReport
                    ? 'جاري الإرسال...'
                    : 'إرسال تقرير تجريبي'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // أدوات مساعدة
  // ─────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEventChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStatusMessage(LarkState state, ThemeData theme) {
    final isSuccess = state.status == LarkSetupStatus.success;
    final isError = state.status == LarkSetupStatus.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess
            ? Colors.green.withOpacity(0.1)
            : isError
                ? Colors.red.withOpacity(0.1)
                : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle
                : isError
                    ? Icons.error
                    : Icons.info,
            color: isSuccess
                ? Colors.green
                : isError
                    ? Colors.red
                    : Colors.blue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.message ?? '',
              style: TextStyle(
                fontSize: 13,
                color: isSuccess
                    ? Colors.green[800]
                    : isError
                        ? Colors.red[800]
                        : Colors.blue[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectReportTime(BuildContext context) async {
    final state = ref.read(larkProvider);
    final parts = state.dailyReportTime.split(':');
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    if (!context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.ltr,
        child: child!,
      ),
    );

    if (time != null) {
      final formatted =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      _reportTimeController.text = formatted;
      ref.read(larkProvider.notifier).setDailyReportTime(formatted);
    }
  }
}
