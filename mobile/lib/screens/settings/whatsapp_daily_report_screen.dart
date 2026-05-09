import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/whatsapp_daily_report_provider.dart';

/// شاشة إعدادات التقرير اليومي عبر WhatsApp (CallMeBot)
/// تتيح للمستخدم إعداد إرسال التقرير اليومي التلقائي عبر واتساب
class WhatsAppDailyReportScreen extends ConsumerStatefulWidget {
  const WhatsAppDailyReportScreen({super.key});

  @override
  ConsumerState<WhatsAppDailyReportScreen> createState() => _WhatsAppDailyReportScreenState();
}

class _WhatsAppDailyReportScreenState extends ConsumerState<WhatsAppDailyReportScreen> {
  final _reportTimeController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final state = ref.read(whatsappDailyReportProvider);
    _reportTimeController.text = state.dailyReportTime;
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _reportTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whatsappDailyReportProvider);
    final theme = Theme.of(context);
    const whatsappGreen = Color(0xFF25D366);

    return AppScaffold(
      title: 'واتساب — الإشعارات والتقارير',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─────────────────────────────────
                // بطاقة التفعيل الرئيسية
                // ─────────────────────────────────
                _buildMainToggleCard(context, state, whatsappGreen),

                const SizedBox(height: 16),

                if (state.isEnabled) ...[
                  // ─────────────────────────────────
                  // قسم إعداد واتساب
                  // ─────────────────────────────────
                  _buildSectionTitle('إعداد واتساب', Icons.link, whatsappGreen),
                  _buildConnectionSection(state, whatsappGreen),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم الإشعارات الفورية
                  // ─────────────────────────────────
                  _buildSectionTitle('الإشعارات الفورية', Icons.notifications_active, whatsappGreen),
                  _buildNotificationsCard(state, whatsappGreen),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم التقرير اليومي
                  // ─────────────────────────────────
                  _buildSectionTitle('التقرير اليومي التلقائي', Icons.assessment, whatsappGreen),
                  _buildDailyReportCard(state, whatsappGreen),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم الإجراءات
                  // ─────────────────────────────────
                  _buildSectionTitle('إجراءات', Icons.settings, whatsappGreen),
                  _buildActionsCard(state, whatsappGreen),
                  const SizedBox(height: 16),
                ],

                // رسالة الحالة
                if (state.message != null)
                  _buildStatusMessage(state),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة التفعيل الرئيسية
  // ─────────────────────────────────────────────────
  Widget _buildMainToggleCard(BuildContext context, WhatsAppDailyReportState state, Color whatsappGreen) {
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
                    color: state.isEnabled ? whatsappGreen.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.chat,
                    color: state.isEnabled ? whatsappGreen : Colors.grey,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'واتساب — الإشعارات والتقارير',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.isEnabled
                            ? 'مفعّل — الإشعارات الفورية والتقارير نشطة'
                            : 'معطّل — لن يتم إرسال أي شيء',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isEnabled,
                  onChanged: (value) => ref.read(whatsappDailyReportProvider.notifier).setEnabled(value),
                  activeThumbColor: whatsappGreen,
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
                        'فعّل واتساب لإرسال إشعارات فورية (حجز، دخول، خروج، دفعة) وتقارير يومية تلقائية عبر واتساب',
                        style: TextStyle(fontSize: 12, color: Colors.orange[800]),
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
  // قسم إعداد واتساب (CallMeBot)
  // ─────────────────────────────────────────────────
  Widget _buildConnectionSection(WhatsAppDailyReportState state, Color whatsappGreen) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // معلومات CallMeBot
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: whatsappGreen.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: whatsappGreen.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: whatsappGreen, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يتم الإرسال عبر CallMeBot WhatsApp API',
                      style: TextStyle(fontSize: 12, color: whatsappGreen.withOpacity(0.8)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // رقم الهاتف
            Row(
              children: [
                Icon(Icons.phone, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('رقم الهاتف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('الرقم المستقبل للرسائل', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  const Text('+', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Text(
                    state.phoneNumber,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text('مُعدّ', style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // API Key
            Row(
              children: [
                Icon(Icons.vpn_key, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('API Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('مفتاح CallMeBot API', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock, color: Colors.grey[400], size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '••••••••',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text('مُعدّ', style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // مؤشر حالة الاتصال
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'الإعدادات مكتملة — جاهز للإرسال',
                    style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // دليل الإعداد
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _showSetupGuide(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: whatsappGreen.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: whatsappGreen.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: whatsappGreen, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'كيف تعمل خدمة CallMeBot؟ اضغط هنا',
                        style: TextStyle(fontSize: 12, color: whatsappGreen.withOpacity(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة الإشعارات الفورية
  // ─────────────────────────────────────────────────
  Widget _buildNotificationsCard(WhatsAppDailyReportState state, Color whatsappGreen) {
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
                    color: state.isNotificationsEnabled ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.notifications_active,
                    color: state.isNotificationsEnabled ? Colors.green : Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الإشعارات الفورية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        state.isNotificationsEnabled ? 'يتم إرسال إشعارات عبر واتساب عند الأحداث' : 'الإشعارات الفورية معطّلة',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isNotificationsEnabled,
                  onChanged: (value) => ref.read(whatsappDailyReportProvider.notifier).setNotificationsEnabled(value),
                  activeThumbColor: whatsappGreen,
                ),
              ],
            ),

            if (state.isNotificationsEnabled) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('الأحداث المُراقَبة عبر واتساب:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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

  Widget _buildEventChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة التقرير اليومي
  // ─────────────────────────────────────────────────
  Widget _buildDailyReportCard(WhatsAppDailyReportState state, Color whatsappGreen) {
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
                    color: state.isDailyReportEnabled ? whatsappGreen.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.assessment,
                    color: state.isDailyReportEnabled ? whatsappGreen : Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('التقرير اليومي التلقائي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        state.isDailyReportEnabled ? 'يُرسل تلقائياً في ${state.dailyReportTime}' : 'التقارير اليومية معطّلة',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isDailyReportEnabled,
                  onChanged: (value) => ref.read(whatsappDailyReportProvider.notifier).setDailyReportEnabled(value),
                  activeThumbColor: whatsappGreen,
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
                  const Text('وقت الإرسال:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectReportTime(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(state.dailyReportTime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ),
                ],
              ),

              // آخر تقرير
              if (state.lastReportSent != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text('آخر تقرير: ${state.lastReportSent}', style: TextStyle(color: Colors.green[700], fontSize: 12))),
                      TextButton(
                        onPressed: () => ref.read(whatsappDailyReportProvider.notifier).resetLastReport(),
                        child: Text('إعادة إرسال', style: TextStyle(color: whatsappGreen, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],

              // محتوى التقرير
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('محتوى التقرير:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📊 حالة الغرف (مشغولة/متاحة/تنظيف/صيانة)'),
                    SizedBox(height: 4),
                    Text('📋 حجوزات اليوم (جديدة/دخول/خروج/نشطة)'),
                    SizedBox(height: 4),
                    Text('💰 ملخص مالي (إيرادات/مصروفات/صافي ربح)'),
                    SizedBox(height: 4),
                    Text('💳 الديون غير المسددة'),
                    SizedBox(height: 4),
                    Text('⚠️ تنبيهات (تأخير مغادرة/صيانة)'),
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
  Widget _buildActionsCard(WhatsAppDailyReportState state, Color whatsappGreen) {
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
                onPressed: state.status == WhatsAppReportStatus.testing
                    ? null
                    : () => ref.read(whatsappDailyReportProvider.notifier).testConnection(),
                icon: state.status == WhatsAppReportStatus.testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: Text(state.status == WhatsAppReportStatus.testing ? 'جاري الاختبار...' : 'اختبار الاتصال بواتساب'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: whatsappGreen,
                  side: BorderSide(color: whatsappGreen),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // إرسال تقرير تجريبي
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.status == WhatsAppReportStatus.sendingReport
                    ? null
                    : () => ref.read(whatsappDailyReportProvider.notifier).sendTestReport(),
                icon: state.status == WhatsAppReportStatus.sendingReport
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(state.status == WhatsAppReportStatus.sendingReport ? 'جاري الإرسال...' : 'إرسال تقرير تجريبي الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: whatsappGreen,
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

  Future<void> _selectReportTime(BuildContext context) async {
    final state = ref.read(whatsappDailyReportProvider);
    final parts = state.dailyReportTime.split(':');
    final int hour = int.parse(parts[0]);
    final int minute = int.parse(parts[1]);

    if (!context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) => Directionality(textDirection: TextDirection.ltr, child: child!),
    );

    if (time != null) {
      final formatted = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      _reportTimeController.text = formatted;
      ref.read(whatsappDailyReportProvider.notifier).setDailyReportTime(formatted);
    }
  }

  void _showSetupGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('كيف تعمل خدمة CallMeBot؟'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📲 خدمة CallMeBot WhatsApp:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text('تتيح لك خدمة CallMeBot إرسال رسائل واتساب تلقائية عبر API مجاني.'),
            SizedBox(height: 8),
            Text('⚙️ الإعدادات مُعدّة مسبقاً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text('• رقم الهاتف +967773749389'),
            Text('• API Key مُعدّ وجاهز'),
            SizedBox(height: 8),
            Text('✅ خطوات التفعيل:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text('1. فعّل مفتاح التقرير اليومي'),
            Text('2. اختر وقت الإرسال المناسب'),
            Text('3. اضغط "اختبار الاتصال" للتحقق'),
            Text('4. سيتم إرسال التقرير تلقائياً كل يوم'),
            SizedBox(height: 8),
            Text('📋 محتوى التقرير:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text('حالة الغرف — حجوزات اليوم — الملخص المالي — الديون — التنبيهات'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[800])),
        ],
      ),
    );
  }

  Widget _buildStatusMessage(WhatsAppDailyReportState state) {
    final isSuccess = state.status == WhatsAppReportStatus.success;
    final isError = state.status == WhatsAppReportStatus.error;

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
            isSuccess ? Icons.check_circle : isError ? Icons.error : Icons.info,
            color: isSuccess ? Colors.green : isError ? Colors.red : Colors.blue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.message ?? '',
              style: TextStyle(
                fontSize: 13,
                color: isSuccess ? Colors.green[800] : isError ? Colors.red[800] : Colors.blue[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
