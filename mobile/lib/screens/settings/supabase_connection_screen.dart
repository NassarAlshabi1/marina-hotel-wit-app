import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/auth_provider.dart';
import '../../utils/supabase_config.dart';
import '../../utils/theme.dart';

class SupabaseConnectionScreen extends ConsumerStatefulWidget {
  const SupabaseConnectionScreen({super.key});

  @override
  ConsumerState<SupabaseConnectionScreen> createState() => _SupabaseConnectionScreenState();
}

class _SupabaseConnectionScreenState extends ConsumerState<SupabaseConnectionScreen> {
  bool _isChecking = false;
  String? _lastCheckTime;
  Map<String, dynamic>? _connectionInfo;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _isChecking = true;
      _lastCheckTime = null;
    });

    try {
      final isConnected = await ref.read(authProvider.notifier).checkSupabaseConnection();
      final projectInfo = SupabaseConfig.getProjectInfo();
      
      setState(() {
        _connectionInfo = {
          'connected': isConnected,
          'url': projectInfo['url'],
          'is_logged_in': projectInfo['is_logged_in'],
          'user_email': projectInfo['user_email'],
          'user_id': projectInfo['user_id'],
        };
        _lastCheckTime = DateTime.now().toString().substring(11, 19);
      });
    } catch (e) {
      setState(() {
        _connectionInfo = {'connected': false, 'error': e.toString()};
      });
    } finally {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return AppScaffold(
      title: 'حالة الاتصال مع Supabase',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    auth.isSupabaseConnected ? Icons.cloud_done : Icons.cloud_off,
                    size: 64,
                    color: auth.isSupabaseConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    auth.isSupabaseConnected ? 'متصل' : 'غير متصل',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: auth.isSupabaseConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  if (_lastCheckTime != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'آخر فحص: $_lastCheckTime',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isChecking ? null : _checkConnection,
                    icon: _isChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_isChecking ? 'جاري الفحص...' : 'إعادة الفحص'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          _buildInfoSection('معلومات الاتصال', [
            _InfoItem(
              icon: Icons.link,
              title: 'رابط المشروع',
              value: _connectionInfo?['url'] ?? 'غير متوفر',
            ),
            _InfoItem(
              icon: Icons.login,
              title: 'حالة تسجيل الدخول',
              value: (_connectionInfo?['is_logged_in'] ?? false) ? 'مسجل' : 'غير مسجل',
              valueColor: (_connectionInfo?['is_logged_in'] ?? false) ? Colors.green : Colors.orange,
            ),
            if (_connectionInfo?['user_email'] != null)
              _InfoItem(
                icon: Icons.email,
                title: 'البريد الإلكتروني',
                value: _connectionInfo!['user_email'],
              ),
            if (_connectionInfo?['user_id'] != null)
              _InfoItem(
                icon: Icons.fingerprint,
                title: 'معرف المستخدم',
                value: _connectionInfo!['user_id'],
                isMonospace: true,
              ),
          ]),

          const SizedBox(height: 20),

          _buildInfoSection('معلومات المصادقة', [
            _InfoItem(
              icon: Icons.person,
              title: 'المستخدم الحالي',
              value: auth.currentUser?.username ?? 'غير معروف',
            ),
            _InfoItem(
              icon: Icons.admin_panel_settings,
              title: 'نوع المستخدم',
              value: auth.currentUser?.userType ?? 'غير معروف',
            ),
            _InfoItem(
              icon: Icons.remember_me,
              title: 'تذكرني',
              value: auth.rememberMe ? 'مفعّل' : 'معطّل',
              valueColor: auth.rememberMe ? Colors.green : Colors.grey,
            ),
            _InfoItem(
              icon: Icons.sync_alt,
              title: 'نوع المصادقة',
              value: _getAuthTypeLabel(auth.authType),
            ),
          ]),

          const SizedBox(height: 20),

          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'يتم حفظ البيانات محلياً ومزامنتها مع Supabase عند توفر الاتصال بالإنترنت.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_connectionInfo?['error'] != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'خطأ: ${_connectionInfo!['error']}',
                        style: const TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<_InfoItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
        ),
        Card(
          child: Column(
            children: items.map((item) {
              return ListTile(
                leading: Icon(item.icon, color: AppColors.primaryColor),
                title: Text(item.title),
                subtitle: Text(
                  item.value,
                  style: TextStyle(
                    color: item.valueColor ?? Colors.black87,
                    fontFamily: item.isMonospace ? 'monospace' : null,
                    fontSize: item.isMonospace ? 11 : 14,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _getAuthTypeLabel(AuthType type) {
    switch (type) {
      case AuthType.local:
        return 'محلي فقط';
      case AuthType.supabase:
        return 'Supabase فقط';
      case AuthType.hybrid:
        return 'مختلط (محلي + Supabase)';
    }
  }
}

class _InfoItem {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;
  final bool isMonospace;

  const _InfoItem({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
    this.isMonospace = false,
  });
}
