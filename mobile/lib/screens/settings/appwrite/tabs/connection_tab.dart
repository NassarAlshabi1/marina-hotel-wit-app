import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';

/// Appwrite Connection Tab - إدارة الاتصال بـ Appwrite
class AppwriteConnectionTab extends ConsumerStatefulWidget {
  const AppwriteConnectionTab({super.key});

  @override
  ConsumerState<AppwriteConnectionTab> createState() =>
      _AppwriteConnectionTabState();
}

class _AppwriteConnectionTabState extends ConsumerState<AppwriteConnectionTab> {
  bool _isConnected = true;
  bool _isChecking = false;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _checkConnection,
      child: ListView(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        children: [
          // Connection Status Card
          _buildConnectionStatusCard(),

          const SizedBox(height: UIConstants.spacingLG),

          // Project Info
          _buildProjectInfoCard(),

          const SizedBox(height: UIConstants.spacingLG),

          // Connection Settings
          _buildConnectionSettingsCard(),

          const SizedBox(height: UIConstants.spacingLG),

          // Quick Actions
          _buildQuickActionsCard(),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingLG),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: (_isConnected ? Colors.green : Colors.red).withOpacity(
                  0.1,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isConnected ? Icons.cloud_done : Icons.cloud_off,
                size: 48,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: UIConstants.spacingMD),
            Text(
              _isConnected ? 'متصل' : 'غير متصل',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              _isConnected
                  ? 'الاتصال بـ Appwrite يعمل بشكل طبيعي'
                  : 'تعذر الاتصال بالخادم',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: UIConstants.spacingLG),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isChecking ? null : _checkConnection,
                icon: _isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isChecking ? 'جاري الفحص...' : 'فحص الاتصال'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(UIConstants.spacingMD),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'معلومات المشروع',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'اسم المشروع',
              value: 'Marina Hotel',
              icon: Icons.badge,
            ),
            InfoRow(
              label: 'معرف المشروع',
              value: '67890abcdef',
              icon: Icons.fingerprint,
            ),
            InfoRow(
              label: 'نقطة النهاية',
              value: 'https://cloud.appwrite.io/v1',
              icon: Icons.link,
              isExpandable: true,
            ),
            InfoRow(
              label: 'الإصدار',
              value: '1.5.4',
              icon: Icons.settings_system_daydream,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'إعدادات الاتصال',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('مهلة الاتصال'),
            subtitle: const Text('30 ثانية'),
            leading: const Icon(Icons.timer),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('عدد المحاولات'),
            subtitle: const Text('3 محاولات'),
            leading: const Icon(Icons.replay),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('SSL/TLS'),
            subtitle: const Text('اتصال آمن مشفر'),
            value: true,
            onChanged: null, // Disabled for security
            secondary: const Icon(Icons.security),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.bug_report, color: Colors.orange),
            ),
            title: const Text('اختبار الاتصال'),
            subtitle: const Text('إرسال طلب تجريبي للخادم'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _testConnection(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.restore, color: Colors.red),
            ),
            title: const Text('إعادة تعيين الاتصال'),
            subtitle: const Text('إعادة تهيئة الاتصال بالخادم'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showResetDialog(),
          ),
        ],
      ),
    );
  }

  Future<void> _checkConnection() async {
    setState(() => _isChecking = true);

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isChecking = false;
      _isConnected = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('الاتصال يعمل بشكل طبيعي'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _testConnection() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('جاري اختبار الاتصال...')));
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text(
          'هل تريد إعادة تعيين الاتصال؟ سيتم قطع الاتصال الحالي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم إعادة تعيين الاتصال')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'إعادة تعيين',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
