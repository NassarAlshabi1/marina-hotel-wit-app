import 'package:flutter/material.dart';
import '../../components/app_scaffold.dart';
import '../../utils/whatsapp_template_manager.dart';

/// شاشة إدارة نماذج رسائل الواتساب
/// تتيح للمستخدم تفعيل/تعطيل وتعديل كل نموذج رسالة
class WhatsAppTemplatesScreen extends StatefulWidget {
  const WhatsAppTemplatesScreen({super.key});

  @override
  State<WhatsAppTemplatesScreen> createState() =>
      _WhatsAppTemplatesScreenState();
}

class _WhatsAppTemplatesScreenState extends State<WhatsAppTemplatesScreen> {
  List<_TemplateItem> _templates = [];
  bool _isLoading = true;
  String _hotelPhone = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final phone = await WhatsAppTemplateManager.getHotelPhone();
    final all = await WhatsAppTemplateManager.getAllTemplates();
    if (!mounted) return;
    setState(() {
      _hotelPhone = phone;
      _templates = all
          .map((t) => _TemplateItem(
                type: t.type,
                enabled: t.enabled,
                content: t.content,
                isCustom: t.content != t.type.defaultContent,
              ))
          .toList();
      _isLoading = false;
    });
  }

  Future<void> _toggleTemplate(int index) async {
    final item = _templates[index];
    final newValue = !item.enabled;
    await WhatsAppTemplateManager.setTemplateEnabled(item.type, newValue);
    setState(() => _templates[index].enabled = newValue);
  }

  Future<void> _editTemplate(int index) async {
    final item = _templates[index];
    final controller = TextEditingController(text: item.content);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(item.type.icon, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(item.type.name, style: const TextStyle(fontSize: 16))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.type.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 12),
              const Text('المتغيرات المتاحة:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getAvailableVariables(item.type),
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 12,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'محتوى الرسالة...',
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await WhatsAppTemplateManager.resetTemplate(item.type);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('إعادة افتراضي', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.save, size: 16),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await WhatsAppTemplateManager.saveTemplateContent(item.type, controller.text);
      _loadData(); // إعادة التحميل
    }

    controller.dispose();
  }

  Future<void> _showHotelPhoneDialog() async {
    final controller = TextEditingController(text: _hotelPhone);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('رقم هاتف الفندق'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('هذا الرقم يظهر في جميع رسائل الواتساب',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  prefixText: '+',
                  border: OutlineInputBorder(),
                  hintText: '9677734587456',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      await WhatsAppTemplateManager.setHotelPhone(result);
      _loadData();
    }
    controller.dispose();
  }

  Future<void> _resetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('إعادة جميع النماذج'),
            ],
          ),
          content: const Text('سيتم إعادة جميع النماذج إلى محتواها الافتراضي وتفعيلها جميعاً. هل تريد المتابعة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('إعادة الكل'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await WhatsAppTemplateManager.resetAllTemplates();
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إعادة جميع النماذج للافتراضي'), backgroundColor: Colors.green),
        );
      }
    }
  }

  String _getAvailableVariables(WhatsAppTemplateType type) {
    switch (type) {
      case WhatsAppTemplateType.paymentConfirmation:
        return '{guestName} {amount} {roomNumber} {extra} {remaining}';
      case WhatsAppTemplateType.extendedStayPayment:
        return '{guestName} {amount} {roomNumber} {nightsPaid} {remaining}';
      case WhatsAppTemplateType.refundConfirmation:
        return '{guestName} {roomNumber} {refundAmount} {unusedNights}';
      case WhatsAppTemplateType.accountStatement:
        return '{guestName} {roomNumber} {nights} {checkin} {checkout} {total} {discountInfo} {paid} {remaining} {status} {payments} {debtInfo}';
      case WhatsAppTemplateType.paymentReminder:
        return '{guestName} {roomNumber} {totalAmount} {paidAmount} {remainingAmount}';
      case WhatsAppTemplateType.extensionConfirmation:
        return '{guestName} {roomNumber} {additionalNights} {amount} {newCheckout}';
      case WhatsAppTemplateType.latePaymentAlert:
        return '{guestName} {daysOverdueInfo} {roomNumber} {checkin} {checkout} {totalAmount} {paidAmount} {remainingAmount} {debtReason}';
      case WhatsAppTemplateType.activeBookingReminder:
        return '{guestName} {roomNumber} {checkin} {checkout} {nights} {total} {paid} {remaining} {overdueWarning}';
      case WhatsAppTemplateType.salaryNotification:
        return '{employeeName} {actionText} {amount} {date} {remainingText}';
      case WhatsAppTemplateType.standalonePaymentAlert:
        return '{amount} {method} {date} {hotelDay} {notes}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'نماذج رسائل الواتساب',
      actions: [
        IconButton(
          onPressed: _showHotelPhoneDialog,
          icon: const Icon(Icons.phone),
          tooltip: 'رقم هاتف الفندق',
        ),
        IconButton(
          onPressed: _resetAll,
          icon: const Icon(Icons.restart_alt),
          tooltip: 'إعادة افتراضي',
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // بطاقة رقم الفندق
                _buildHotelPhoneCard(),
                const SizedBox(height: 12),

                // عنوان
                Text(
                  'نماذج الرسائل (${_templates.where((t) => t.enabled).length}/${_templates.length} مفعّل)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),

                // قائمة النماذج
                ...List.generate(_templates.length, (i) => _buildTemplateCard(i)),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildHotelPhoneCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: _showHotelPhoneDialog,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('رقم هاتف الفندق', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '+$_hotelPhone',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateCard(int index) {
    final item = _templates[index];
    final type = item.type;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: item.enabled ? Colors.green.shade300 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // أيقونة
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (item.enabled ? Colors.green : Colors.grey).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(type.icon, color: item.enabled ? Colors.green : Colors.grey, size: 20),
                ),
                const SizedBox(width: 10),

                // الاسم + الوصف
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(type.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(type.description, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                ),

                // شارة مخصص
                if (item.isCustom)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('مخصص', style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),

                const SizedBox(width: 8),

                // مفتاح التفعيل
                Switch(
                  value: item.enabled,
                  onChanged: (_) => _toggleTemplate(index),
                  activeColor: Colors.green,
                ),
              ],
            ),

            // زر تعديل
            if (item.enabled) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _editTemplate(index),
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('تعديل النموذج', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TemplateItem {
  final WhatsAppTemplateType type;
  bool enabled;
  String content;
  final bool isCustom;

  _TemplateItem({
    required this.type,
    required this.enabled,
    required this.content,
    required this.isCustom,
  });
}
