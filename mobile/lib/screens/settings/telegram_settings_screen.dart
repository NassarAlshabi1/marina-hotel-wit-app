import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/telegram_provider.dart';

/// شاشة إعدادات Telegram Bot
/// تتيح للمستخدم إعداد Telegram للإشعارات والتقارير اليومية
class TelegramSettingsScreen extends ConsumerStatefulWidget {
  const TelegramSettingsScreen({super.key});

  @override
  ConsumerState<TelegramSettingsScreen> createState() => _TelegramSettingsScreenState();
}

class _TelegramSettingsScreenState extends ConsumerState<TelegramSettingsScreen> {
  final _botTokenController = TextEditingController();
  final _chatIdController = TextEditingController();
  final _reportTimeController = TextEditingController();

  bool _showToken = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // انتظار حتى ينهي Provider التهيئة
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final state = ref.read(telegramProvider);
    _botTokenController.text = state.botToken;
    _chatIdController.text = state.chatId;
    _reportTimeController.text = state.dailyReportTime;
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _chatIdController.dispose();
    _reportTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tgState = ref.watch(telegramProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'إعدادات Telegram Bot',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─────────────────────────────────
                // بطاقة التفعيل الرئيسية
                // ─────────────────────────────────
                _buildMainToggleCard(context, tgState, theme),

                const SizedBox(height: 16),

                if (tgState.isEnabled) ...[
                  // ─────────────────────────────────
                  // قسم إعداد الاتصال
                  // ─────────────────────────────────
                  _buildSectionTitle('إعداد الاتصال', Icons.link, theme),
                  _buildConnectionSection(tgState, theme),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم الإشعارات الفورية
                  // ─────────────────────────────────
                  _buildSectionTitle('الإشعارات الفورية', Icons.notifications_active, theme),
                  _buildNotificationsCard(tgState, theme),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم التقرير اليومي
                  // ─────────────────────────────────
                  _buildSectionTitle('التقرير اليومي التلقائي', Icons.assessment, theme),
                  _buildDailyReportCard(tgState, theme),
                  const SizedBox(height: 16),

                  // ─────────────────────────────────
                  // قسم الإجراءات
                  // ─────────────────────────────────
                  _buildSectionTitle('إجراءات', Icons.settings, theme),
                  _buildActionsCard(tgState, theme),
                  const SizedBox(height: 16),
                ],

                // رسالة الحالة
                if (tgState.message != null)
                  _buildStatusMessage(tgState, theme),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────
  // بطاقة التفعيل الرئيسية
  // ─────────────────────────────────────────────────
  Widget _buildMainToggleCard(BuildContext context, TelegramState state, ThemeData theme) {
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
                        ? const Color(0xFF0088cc).withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.telegram,
                    color: state.isEnabled ? const Color(0xFF0088cc) : Colors.grey,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Telegram Bot',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.isEnabled
                            ? 'مفعّل — الإشعارات والتقارير نشطة'
                            : 'معطّل — لن يتم إرسال أي شيء',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isEnabled,
                  onChanged: (value) => ref.read(telegramProvider.notifier).setEnabled(value),
                  activeThumbColor: const Color(0xFF0088cc),
                ),
              ],
            ),

            if (!state.isEnabled) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'فعّل Telegram Bot لإرسال إشعارات فورية وتقارير يومية تلقائية لموظفي الفندق',
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
  // قسم إعداد الاتصال
  // ─────────────────────────────────────────────────
  Widget _buildConnectionSection(TelegramState state, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Bot Token
            _buildInfoRow(
              icon: Icons.vpn_key,
              label: 'Bot Token',
              subtitle: 'من @BotFather في Telegram',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _botTokenController,
              obscureText: !_showToken,
              decoration: InputDecoration(
                hintText: '7602573830:AAHxxxxxxxxxxxxxxxxxxx',
                prefixIcon: const Icon(Icons.password, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility, size: 20),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Chat ID
            _buildInfoRow(
              icon: Icons.tag,
              label: 'Chat ID',
              subtitle: 'من @userinfobot في Telegram',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _chatIdController,
              decoration: const InputDecoration(
                hintText: '5944227208',
                prefixIcon: Icon(Icons.person, size: 20),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),

            // مؤشر حالة الاتصال
            const SizedBox(height: 16),
            Row(
              children: [
                if (state.isConfigured)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'مُعدّ',
                          style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, color: Colors.grey, size: 14),
                        const SizedBox(width: 4),
                        Text('غير مُعدّ', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ],
                    ),
                  ),
              ],
            ),

            // زر حفظ
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0088cc),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            // طريقة الإعداد
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _showSetupGuide(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0088cc).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0088cc).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.help_outline, color: Color(0xFF0088cc), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'كيف تحصل على Bot Token و Chat ID؟ اضغط هنا',
                        style: TextStyle(fontSize: 12, color: const Color(0xFF0088cc).withValues(alpha: 0.8)),
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
  Widget _buildNotificationsCard(TelegramState state, ThemeData theme) {
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
                    color: state.isNotificationsEnabled ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
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
                        state.isNotificationsEnabled ? 'يتم إرسال إشعارات عند الأحداث' : 'الإشعارات معطّلة',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.isNotificationsEnabled,
                  onChanged: (value) => ref.read(telegramProvider.notifier).setNotificationsEnabled(value),
                  activeThumbColor: Colors.green,
                ),
              ],
            ),

            if (state.isNotificationsEnabled) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('الأحداث المُراقَبة:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
  Widget _buildDailyReportCard(TelegramState state, ThemeData theme) {
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
                    color: state.isDailyReportEnabled ? const Color(0xFF0088cc).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.assessment,
                    color: state.isDailyReportEnabled ? const Color(0xFF0088cc) : Colors.grey,
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
                  onChanged: (value) => ref.read(telegramProvider.notifier).setDailyReportEnabled(value),
                  activeThumbColor: const Color(0xFF0088cc),
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
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text('آخر تقرير: ${state.lastReportSent}', style: TextStyle(color: Colors.green[700], fontSize: 12))),
                      TextButton(
                        onPressed: () => ref.read(telegramProvider.notifier).resetLastReport(),
                        child: const Text('إعادة إرسال', style: TextStyle(color: Color(0xFF0088cc), fontSize: 11)),
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
  Widget _buildActionsCard(TelegramState state, ThemeData theme) {
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
                onPressed: state.status == TelegramSetupStatus.testing
                    ? null
                    : () => ref.read(telegramProvider.notifier).testConnection(),
                icon: state.status == TelegramSetupStatus.testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: Text(state.status == TelegramSetupStatus.testing ? 'جاري الاختبار...' : 'اختبار الاتصال'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0088cc),
                  side: const BorderSide(color: Color(0xFF0088cc)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // إرسال تقرير تجريبي
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.status == TelegramSetupStatus.sendingReport
                    ? null
                    : () => ref.read(telegramProvider.notifier).sendTestReport(),
                icon: state.status == TelegramSetupStatus.sendingReport
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(state.status == TelegramSetupStatus.sendingReport ? 'جاري الإرسال...' : 'إرسال تقرير تجريبي'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0088cc),
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

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(telegramProvider.notifier);
      await notifier.setBotToken(_botTokenController.text.trim());
      await notifier.setChatId(_chatIdController.text.trim());

      setState(() => _isSaving = false);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('تم حفظ الإعدادات بنجاح ✅'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() => _isSaving = false);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Text('خطأ في الحفظ: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _selectReportTime(BuildContext context) async {
    final state = ref.read(telegramProvider);
    final parts = state.dailyReportTime.split(':');
    final int hour = int.parse(parts[0]);
    final int minute = int.parse(parts[1]);

    if (!context.mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) => Directionality(textDirection: TextDirection.ltr, child: child!),
    );

    if (time != null) {
      final formatted = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      _reportTimeController.text = formatted;
      unawaited(ref.read(telegramProvider.notifier).setDailyReportTime(formatted));
    }
  }

  void _showSetupGuide(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('كيف تحصل على Bot Token و Chat ID؟'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔐 الحصول على Bot Token:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text('1. افتح Telegram وابحث عن @BotFather'),
            Text('2. أرسل /newbot'),
            Text('3. اختر اسم البوت (مثلاً: Marina Hotel)'),
            Text('4. اختر username (مثلاً: marina_hotel_bot)'),
            Text('5. انسخ Token من الرد'),
            SizedBox(height: 12),
            Text('👤 الحصول على Chat ID:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text('1. افتح Telegram وابحث عن @userinfobot'),
            Text('2. اضغط Start'),
            Text('3. انسخ رقم ID'),
            SizedBox(height: 12),
            Text('✅ اختبار:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text('بعد الحفظ اضغط "اختبار الاتصال" وتحقق من وصول رسالة في Telegram'),
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

  Widget _buildSectionTitle(String title, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0088cc), size: 20),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[800])),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String subtitle}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ],
    );
  }

  Widget _buildEventChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildStatusMessage(TelegramState state, ThemeData theme) {
    final isSuccess = state.status == TelegramSetupStatus.success;
    final isError = state.status == TelegramSetupStatus.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess
            ? Colors.green.withValues(alpha: 0.1)
            : isError
                ? Colors.red.withValues(alpha: 0.1)
                : Colors.blue.withValues(alpha: 0.1),
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
