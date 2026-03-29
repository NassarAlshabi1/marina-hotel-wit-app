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
  /// ✅ Debounce guard: prevents rapid connection check taps
  bool _isChecking = false;

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
            // ✅ AnimatedSwitcher for smooth status icon transition
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Container(
                key: ValueKey(isConnected),
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
            ),
            const SizedBox(height: UIConstants.spacingMD),
            // ✅ AnimatedSwitcher for status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                key: ValueKey(isConnected),
                isConnected ? 'متصل' : 'غير متصل',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isConnected ? Colors.green : Colors.red,
                ),
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
                onPressed: (state.isChecking || _isChecking)
                    ? null
                    : _checkConnection,
                icon: (state.isChecking || _isChecking)
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  (state.isChecking || _isChecking)
                      ? 'جاري الفحص...'
                      : 'فحص الاتصال',
                ),
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
            _InfoRow(
              label: 'معرف المشروع',
              value: info['projectId'] ?? '---',
              icon: Icons.fingerprint,
            ),
            const SizedBox(height: UIConstants.spacingSM),
            _InfoRow(
              label: 'قاعدة البيانات',
              value: info['databaseId'] ?? '---',
              icon: Icons.storage,
            ),
            const SizedBox(height: UIConstants.spacingSM),
            _InfoRow(
              label: 'نقطة النهاية',
              value: info['endpoint'] ?? '---',
              icon: Icons.link,
              isExpandable: true,
            ),
            const SizedBox(height: UIConstants.spacingSM),
            _InfoRow(
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
            // ✅ Removed const — uses string interpolation
            subtitle:
                Text('${AppwriteConfig.defaultTimeout.inSeconds} ثانية'),
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
            // ✅ Fixed: removed const — cannot use string interpolation in const
            subtitle: Text('${AppwriteConfig.maxRetries} محاولات'),
            leading: const Icon(Icons.replay),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showInfoDialog(
              'عدد المحاولات',
              '${AppwriteConfig.maxRetries} محاولات',
            ),
          ),
          const Divider(height: 1),
          // ✅ Fixed: SwitchListTile always on with AbsorbPointer
          // Prevents user confusion — switch looks interactive but is clearly disabled
          AbsorbPointer(
            absorbing: true,
            child: SwitchListTile(
              title: const Text('SSL/TLS'),
              subtitle: const Text('اتصال آمن مشفر (مُفعّل دائماً)'),
              value: true,
              onChanged: (_) {},
              secondary: const Icon(Icons.security),
            ),
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
            onTap: _isChecking ? null : _checkConnection,
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

  /// ✅ Enhanced _checkConnection with:
  /// - Debounce guard (_isChecking)
  /// - try-catch error handling
  /// - mounted check before showing SnackBar
  Future<void> _checkConnection() async {
    // ✅ Debounce: prevent rapid consecutive taps
    if (_isChecking) return;
    _isChecking = true;

    try {
      await ref
          .read(ap.connectionStatusProvider.notifier)
          .checkConnection();
    } catch (e) {
      // ✅ Error handling — show error instead of crashing
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل فحص الاتصال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text('هل تريد إعادة تهيئة الاتصال؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              try {
                // ✅ Error handling for initialize()
                await ref
                    .read(ap.appwriteServiceProvider)
                    .initialize();

                // ✅ mounted check before calling _checkConnection
                if (mounted) {
                  await _checkConnection();
                }
              } catch (e) {
                // ✅ mounted check before showing SnackBar after async gap
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('فشلت إعادة التعيين: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
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

/// ✅ Critical fix: InfoRow widget definition
/// Previously used but never defined/imported — caused compilation error
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isExpandable;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.isExpandable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UIConstants.spacingXS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: UIConstants.spacingSM),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: isExpandable
                ? Text(
                    value,
                    style: TextStyle(color: Colors.grey.shade700),
                    softWrap: true,
                  )
                : Text(
                    value,
                    style: TextStyle(color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      ),
    );
  }
}
