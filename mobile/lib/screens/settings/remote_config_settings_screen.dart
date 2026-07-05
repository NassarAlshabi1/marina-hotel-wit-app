// lib/screens/settings/remote_config_settings_screen.dart
// شاشة عرض وإدارة Firebase Remote Config

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/remote_config_provider.dart';
import '../../services/remote_config_service.dart';

class RemoteConfigSettingsScreen extends ConsumerStatefulWidget {
  const RemoteConfigSettingsScreen({super.key});

  @override
  ConsumerState<RemoteConfigSettingsScreen> createState() =>
      _RemoteConfigSettingsScreenState();
}

class _RemoteConfigSettingsScreenState
    extends ConsumerState<RemoteConfigSettingsScreen> {
  bool _isFetching = false;

  Future<void> _forceFetch() async {
    setState(() => _isFetching = true);
    final success = await RemoteConfigService.instance.forceFetch();
    if (mounted) {
      setState(() => _isFetching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'تم تحديث الإعدادات بنجاح'
                : 'فشل التحديث — يُستخدم الإعدادات المحلية',
          ),
          backgroundColor: success ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final values = ref.watch(remoteConfigValuesProvider);
    final diag = ref.watch(remoteConfigDiagnosticsProvider);

    return AppScaffold(
      title: 'Remote Config',
      actions: [
        IconButton(
          onPressed: _isFetching ? null : _forceFetch,
          icon: _isFetching
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'تحديث من السيرفر',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // حالة الاتصال
          _buildStatusCard(diag),

          const SizedBox(height: 16),

          // الإشعارات والاتصال
          _buildSection(
            '🔑 الإشعارات والاتصال',
            Icons.notifications,
            Colors.blue,
            [
              _buildConfigRow(
                'رقم WhatsApp',
                values['whatsapp_phone'] as String? ?? '---',
                'whatsapp_phone',
              ),
              _buildConfigRow(
                'مفتاح API',
                _maskKey(values['whatsapp_api_key'] as String? ?? '---'),
                'whatsapp_api_key',
              ),
              _buildConfigRow(
                'WhatsApp مفعّل',
                (values['whatsapp_enabled'] as bool?)?.toString() ?? '---',
                'whatsapp_enabled',
                isBool: true,
              ),
              _buildConfigRow(
                isBool: true,
              ),
              _buildConfigRow(
                'هاتف الفندق',
                values['hotel_contact_phone'] as String? ?? '---',
                'hotel_contact_phone',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // مواعيد التقارير
          _buildSection(
            '⏰ مواعيد التقارير',
            Icons.schedule,
            Colors.orange,
            [
              _buildConfigRow(
                'النسخ الاحتياطي',
                values['daily_backup_time'] as String? ?? '---',
                'daily_backup_time',
              ),
              _buildConfigRow(
                'تقرير WhatsApp',
                values['whatsapp_report_time'] as String? ?? '---',
                'whatsapp_report_time',
              ),
              _buildConfigRow(
                'تقرير Telegram',
                values['telegram_report_time'] as String? ?? '---',
                'telegram_report_time',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // قواعد الحجوزات
          _buildSection(
            '🏨 قواعد الحجوزات',
            Icons.hotel,
            Colors.green,
            [
              _buildConfigRow(
                'ساعة الخروج',
                '${values['checkout_hour'] as int? ?? 14}:00',
                'checkout_hour',
              ),
              _buildConfigRow(
                'حد الديون المتأخرة',
                '${values['late_payment_threshold_days'] as int? ?? 30} يوم',
                'late_payment_threshold_days',
              ),
              _buildConfigRow(
                'دفعات صحيحة فقط',
                (values['whole_number_payments_only'] as bool?)?.toString() ?? '---',
                'whole_number_payments_only',
                isBool: true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // الحسابات
          _buildSection(
            '💰 الحسابات',
            Icons.attach_money,
            Colors.purple,
            [
              _buildConfigRow(
                'نوع الخصم الافتراضي',
                _translateDiscountType(
                  values['default_discount_type'] as String? ?? '---',
                ),
                'default_discount_type',
              ),
              _buildConfigRow(
                'سقف مضاعف السعر',
                '${(values['max_rate_multiplier'] as double?)?.toStringAsFixed(1) ?? '3.0'}x',
                'max_rate_multiplier',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // النسخ الاحتياطي
          _buildSection(
            '💾 النسخ الاحتياطي',
            Icons.backup,
            Colors.teal,
            [
              _buildConfigRow(
                'عدد النسخ القصوى',
                '${values['max_backup_count'] as int? ?? 10}',
                'max_backup_count',
              ),
              _buildConfigRow(
                'فترة الاحتفاظ',
                '${values['backup_retention_days'] as int? ?? 14} يوم',
                'backup_retention_days',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // الأداء والإعدادات
          _buildSection(
            '⚡ الأداء والإعدادات',
            Icons.speed,
            Colors.indigo,
            [
              _buildConfigRow(
                'طول الرسالة',
                '${values['whatsapp_message_max_length'] as int? ?? 1000} حرف',
                'whatsapp_message_max_length',
              ),
              _buildConfigRow(
                'مهلة WhatsApp API',
                '${values['whatsapp_api_timeout'] as int? ?? 15} ثانية',
                'whatsapp_api_timeout',
              ),
              _buildConfigRow(
                'كود الدولة',
                values['country_code_default'] as String? ?? '---',
                'country_code_default',
              ),
              _buildConfigRow(
                'مهلة API العامة',
                '${values['api_timeout_seconds'] as int? ?? 30} ثانية',
                'api_timeout_seconds',
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ملاحظة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'هذه القيم تُتحكم بها من Firebase Console بدون الحاجة لتحديث التطبيق. اضغط زر التحديث لجلب أحدث القيم.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> diag) {
    final isInit = diag['isInitialized'] == true;
    final isFirebaseConnected = diag['isFirebaseConnected'] == true;
    final lastFetch = diag['lastFetchTime'] as String?;
    final status = diag['lastFetchStatus'] as String?;

    // تحديد النص والأيقونة واللون حسب الحالة
    final String statusText;
    final IconData statusIcon;
    final Color statusColor;

    if (!isInit) {
      statusText = 'لم يتم التهيئة';
      statusIcon = Icons.cloud_off;
      statusColor = Colors.red;
    } else if (isFirebaseConnected) {
      statusText = 'متصل بـ Firebase';
      statusIcon = Icons.cloud_done;
      statusColor = Colors.green;
    } else {
      statusText = 'يعمل بالإعدادات المحلية';
      statusIcon = Icons.cloud_queue;
      statusColor = Colors.orange;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  statusIcon,
                  color: statusColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (!isFirebaseConnected && isInit) ...[
              const SizedBox(height: 8),
              Text(
                'جميع القيم تعمل بالقيم الافتراضية المُعرّفة مسبقاً. الاتصال بـ Firebase غير متوفر حالياً.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
              ),
            ],
            if (lastFetch != null) ...[
              const SizedBox(height: 8),
              Text(
                'آخر تحديث: ${_formatTimestamp(lastFetch)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            if (status != null) ...[
              const SizedBox(height: 4),
              Text(
                'الحالة: $_translateStatus(status)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 1,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildConfigRow(
    String label,
    String value,
    String key, {
    bool isBool = false,
  }) {
    final displayValue = isBool ? (value == 'true' ? 'مفعّل' : 'معطّل') : value;
    final valueColor = isBool
        ? (value == 'true' ? Colors.green : Colors.red)
        : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            displayValue,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor,
              fontFamily: isBool ? null : 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _maskKey(String key) {
    if (key.length <= 4) {
      return '****';
    }
    return '${key.substring(0, 3)}${'*' * (key.length - 4)}${key.substring(key.length - 1)}';
  }

  String _translateDiscountType(String type) {
    switch (type) {
      case 'per_night':
        return 'لكل ليلة';
      case 'total':
        return 'إجمالي';
      default:
        return type;
    }
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'true':
        return 'تم التحديث من السيرفر';
      case 'false':
        return 'لم تتغير القيم';
      case 'fetch_failed':
        return 'فشل الجلب — يُستخدم الافتراضي';
      case 'local_defaults':
        return 'يعمل بالإعدادات المحلية';
      default:
        return status;
    }
  }

  String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} — ${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
