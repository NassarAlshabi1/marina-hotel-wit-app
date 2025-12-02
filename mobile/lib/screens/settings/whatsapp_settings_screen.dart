import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/app_scaffold.dart';

class WhatsAppSettingsScreen extends ConsumerStatefulWidget {
  const WhatsAppSettingsScreen({super.key});

  @override
  ConsumerState<WhatsAppSettingsScreen> createState() => _WhatsAppSettingsScreenState();
}

class _WhatsAppSettingsScreenState extends ConsumerState<WhatsAppSettingsScreen> {
  final _templateController = TextEditingController();
  bool _isLoading = true;

  static const String _defaultTemplate = 
'''عزيزي {name}
تم استلام دفعتك بقيمة {amount} ريال
رقم الغرفة: {room}
{extra_nights}
المبلغ المتبقي: {remaining} ريال
شكراً لاختيارك فندق مارينا
للاستفسار: 9677734587456''';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _templateController.text = prefs.getString('whatsapp_template') ?? _defaultTemplate;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('whatsapp_template', _templateController.text);
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات الرسالة بنجاح'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _resetToDefault() async {
    setState(() {
      _templateController.text = _defaultTemplate;
    });
  }

  @override
  void dispose() {
    _templateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات رسالة الواتساب',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المتغيرات المتاحة:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          SizedBox(height: 8),
                          Text('{name} : اسم الضيف'),
                          Text('{amount} : المبلغ المدفوع'),
                          Text('{room} : رقم الغرفة'),
                          Text('{remaining} : المبلغ المتبقي'),
                          Text('{extra_nights} : تفاصيل الليالي الإضافية (إن وجد)'),
                          Text('{new_checkout} : تاريخ المغادرة الجديد (إن وجد)'),
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'أدخل نص الرسالة هنا...',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _resetToDefault,
                          icon: const Icon(Icons.restore),
                          label: const Text('استعادة الافتراضي'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveSettings,
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ التغييرات'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
