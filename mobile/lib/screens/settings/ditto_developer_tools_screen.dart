import 'package:flutter/material.dart';
import 'package:ditto_flutter_tools/ditto_flutter_tools.dart';
import '../../utils/ditto_config.dart';
import '../../components/admin_layout.dart';

/// شاشة أدوات Ditto للمطورين
/// تحتوي على جميع أدوات التشخيص والتصحيح من حزمة ditto_flutter_tools
class DittoDeveloperToolsScreen extends StatelessWidget {
  const DittoDeveloperToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'أدوات Ditto للمطورين',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // بطاقة المعلومات
            _buildInfoCard(context),
            
            const SizedBox(height: 20),
            
            // قسم مراقبة الشبكة والمزامنة
            _buildSectionTitle('مراقبة الشبكة والمزامنة', Icons.network_check),
            _buildToolsGrid(context, [
              _DittoToolItem(
                title: 'الأجهزة المتصلة',
                subtitle: 'عرض جميع الأجهزة في شبكة P2P',
                icon: Icons.devices,
                color: Colors.blue,
                onTap: () => _navigateTo(
                  context,
                  'الأجهزة المتصلة',
                  PeerListView(ditto: DittoConfig.instance),
                ),
              ),
              _DittoToolItem(
                title: 'حالة المزامنة مع الأجهزة',
                subtitle: 'مراقبة حالة المزامنة بين الأجهزة',
                icon: Icons.sync_alt,
                color: Colors.green,
                onTap: () => _navigateTo(
                  context,
                  'حالة المزامنة',
                  PeerSyncStatusView(ditto: DittoConfig.instance),
                ),
              ),
              _DittoToolItem(
                title: 'حالة الاشتراكات',
                subtitle: 'مراقبة حالة subscriptions وتحديثاتها',
                icon: Icons.subscriptions,
                color: Colors.orange,
                onTap: () => _showSyncStatusInfo(context),
              ),
            ]),

            const SizedBox(height: 20),
            
            // قسم إدارة البيانات والنظام
            _buildSectionTitle('إدارة البيانات والنظام', Icons.storage),
            _buildToolsGrid(context, [
              _DittoToolItem(
                title: 'استخدام القرص',
                subtitle: 'حجم قاعدة البيانات وتصدير البيانات',
                icon: Icons.sd_storage,
                color: Colors.purple,
                onTap: () => _navigateTo(
                  context,
                  'استخدام القرص',
                  DiskUsageView(ditto: DittoConfig.instance),
                ),
              ),
              _DittoToolItem(
                title: 'محرر الاستعلامات DQL',
                subtitle: 'تنفيذ استعلامات DQL على قاعدة البيانات',
                icon: Icons.code,
                color: Colors.indigo,
                onTap: () => _navigateTo(
                  context,
                  'محرر الاستعلامات',
                  QueryEditorView(ditto: DittoConfig.instance),
                ),
              ),
              _DittoToolItem(
                title: 'إعدادات النظام',
                subtitle: 'عرض جميع إعدادات Ditto الداخلية',
                icon: Icons.settings_applications,
                color: Colors.teal,
                onTap: () => _navigateTo(
                  context,
                  'إعدادات النظام',
                  SystemSettingsView(ditto: DittoConfig.instance),
                ),
              ),
            ]),

            const SizedBox(height: 20),
            
            // قسم الصلاحيات والأذونات
            _buildSectionTitle('الصلاحيات والأذونات', Icons.security),
            _buildToolsGrid(context, [
              _DittoToolItem(
                title: 'حالة الصلاحيات',
                subtitle: 'Bluetooth و Wi-Fi وأذونات الشبكة',
                icon: Icons.verified_user,
                color: Colors.red,
                onTap: () => _navigateTo(
                  context,
                  'حالة الصلاحيات',
                  const PermissionsHealthView(),
                ),
              ),
            ]),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return AdminCard(
      title: 'ℹ️ معلومات',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'أدوات التشخيص والتصحيح لـ Ditto',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'هذه الأدوات مخصصة للمطورين لتشخيص مشاكل المزامنة والشبكة وفحص البيانات. '
            'يمكنك استخدام هذه الأدوات لـ:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buildInfoPoint('• مراقبة الأجهزة المتصلة في شبكة P2P'),
          _buildInfoPoint('• فحص حالة المزامنة بين الأجهزة'),
          _buildInfoPoint('• تنفيذ استعلامات DQL على قاعدة البيانات'),
          _buildInfoPoint('• تصدير البيانات والسجلات'),
          _buildInfoPoint('• فحص صلاحيات Bluetooth و Wi-Fi'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تحذير: هذه الأدوات للمطورين فقط. احرص عند استخدام محرر الاستعلامات.',
                    style: TextStyle(fontSize: 11, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.deepPurple, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsGrid(BuildContext context, List<_DittoToolItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    item.color.withOpacity(0.1),
                    item.color.withOpacity(0.05),
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      item.icon,
                      size: 28,
                      color: item.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _navigateTo(BuildContext context, String title, Widget view) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            body: view,
          ),
        ),
      ),
    );
  }

  void _showSyncStatusInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info, color: Colors.blue),
              SizedBox(width: 8),
              Text('حالة الاشتراكات'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SyncStatusView و SyncStatusHelper',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'تتطلب هذه الأداة تمرير قائمة الاشتراكات (subscriptions) التي تريد مراقبتها.\n\n'
                'يمكنك استخدام SyncStatusHelper للحصول على بيانات حالة المزامنة برمجياً:\n\n'
                '• overallStatus - الحالة الإجمالية\n'
                '• statusFor(subscription) - حالة اشتراك معين\n'
                '• lastUpdatedAt(subscription) - آخر تحديث\n'
                '• isConnected - هل متصل بأقران',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue),
                ),
                child: const Text(
                  'لاستخدام هذه الأداة، يجب إنشاء SyncStatusHelper مع قائمة الاشتراكات الخاصة بك.',
                  style: TextStyle(fontSize: 11, color: Colors.blue),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DittoToolItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DittoToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
