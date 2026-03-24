import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../providers/appwrite_providers.dart' as ap;
import '../../../../services/appwrite_config.dart';

/// Appwrite Connection Tab - إدارة الاتصال بـ Appwrite
class AppwriteConnectionTab extends ConsumerStatefulWidget {
  const AppwriteConnectionTab({super.key});

  @override
  ConsumerState<AppwriteConnectionTab> createState() =>
      _AppwriteConnectionTabState();
}

class _AppwriteConnectionTabState extends ConsumerState<AppwriteConnectionTab> {
  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(ap.connectionStatusProvider);
    final projectInfo = ref.watch(ap.projectInfoProvider);

    return RefreshIndicator(
      onRefresh: _checkConnection,
      child: ListView(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        children: [
          _buildConnectionStatusCard(connectionState),
          const SizedBox(height: UIConstants.spacingLG),
          _buildProjectInfoCard(projectInfo),
          const SizedBox(height: UIConstants.spacingLG),
          _buildConnectionSettingsCard(),
          const SizedBox(height: UIConstants.spacingLG),
          _buildQuickActionsCard(),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusCard(ap.ConnectionState state) {
    final isConnected = state.isConnected;
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
                color: (isConnected ? Colors.green : Colors.red).withOpacity(
                  0.1,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isConnected ? Icons.cloud_done : Icons.cloud_off,
                size: 48,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: UIConstants.spacingMD),
            Text(
              isConnected ? 'متصل' : 'غير متصل',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              isConnected
                  ? 'الاتصال بـ Appwrite يعمل بشكل طبيعي'
                  : (state.errorMessage ?? 'تعذر الاتصال بالخادم'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: UIConstants.spacingLG),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isChecking ? null : _checkConnection,
                icon: state.isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(state.isChecking ? 'جاري الفحص...' : 'فحص الاتصال'),
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

  Widget _buildProjectInfoCard(Map<String, String> info) {
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
            const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'معلومات المشروع',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'معرف المشروع',
              value: info['projectId'] ?? '---',
              icon: Icons.fingerprint,
            ),
            InfoRow(
              label: 'قاعدة البيانات',
              value: info['databaseId'] ?? '---',
              icon: Icons.storage,
            ),
            InfoRow(
              label: 'نقطة النهاية',
              value: info['endpoint'] ?? '---',
              icon: Icons.link,
              isExpandable: true,
            ),
            InfoRow(
              label: 'حالة التهيئة',
              value: (info['initialized'] ?? 'false') == 'true'
                  ? 'مهيأ'
                  : 'غير مهيأ',
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
          const Padding(
            padding: EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'إعدادات الاتصال',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('مهلة الاتصال'),
            subtitle: Text('${AppwriteConfig.defaultTimeout.inSeconds} ثانية'),
            leading: const Icon(Icons.timer),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showInfoDialog(
              'مهلة الاتصال',
              '${AppwriteConfig.defaultTimeout.inSeconds} ثانية',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('عدد المحاولات'),
            subtitle: const Text('${AppwriteConfig.maxRetries} محاولات'),
            leading: const Icon(Icons.replay),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showInfoDialog(
              'عدد المحاولات',
              '${AppwriteConfig.maxRetries} محاولات',
            ),
          ),
          const Divider(height: 1),
          const SwitchListTile(
            title: Text('SSL/TLS'),
            subtitle: Text('اتصال آمن مشفر'),
            value: true,
            onChanged: null,
            secondary: Icon(Icons.security),
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
            onTap: _checkConnection,
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
            onTap: _showResetDialog,
          ),
        ],
      ),
    );
  }

  Future<void> _checkConnection() async {
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text('هل تريد إعادة تهيئة الاتصال؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(ap.appwriteServiceProvider).initialize();
              await _checkConnection();
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

  void _showInfoDialog(String title, String value) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(value),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
