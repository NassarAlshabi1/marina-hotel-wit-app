import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_local_store.dart';

class SettingsUsersScreen extends ConsumerWidget {
  const SettingsUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isAdmin = auth.currentUser?.isAdmin == true;

    return AppScaffold(
      title: 'إدارة المستخدمين والصلاحيات',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.account_circle, size: 32, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(auth.currentUser?.name ?? 'غير معروف', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(isAdmin ? 'مدير النظام' : (auth.currentUser?.userType ?? '')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!isAdmin) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(child: Text('هذه الصفحة مخصصة للمسؤول فقط')),
                  ],
                ),
              ),
            ] else ...[
              const Text('صلاحيات المستخدمين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const UserPermissionsCard(username: 'admin', displayName: 'المدير (admin)'),
              const UserPermissionsCard(username: 'mohammed', displayName: 'محمد (mohammed)'),
              const UserPermissionsCard(username: 'ahmed', displayName: 'أحمد (ahmed)'),
            ],
          ],
        ),
      ),
    );
  }
}

class UserPermissionsCard extends ConsumerStatefulWidget {
  const UserPermissionsCard({super.key, required this.username, required this.displayName});
  final String username;
  final String displayName;

  @override
  ConsumerState<UserPermissionsCard> createState() => _UserPermissionsCardState();
}

class _UserPermissionsCardState extends ConsumerState<UserPermissionsCard> {
  List<String> _perms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = AuthLocalStore();
    final p = await store.getPermissions(widget.username);
    setState(() {
      _perms = List<String>.from(p);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdminUser = widget.username == 'admin';
    final allKeys = AuthLocalStore.permissionKeys;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person),
                const SizedBox(width: 8),
                Text(widget.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isAdminUser)
                  const Chip(label: Text('جميع الصلاحيات')),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: allKeys.map((k) {
                  final checked = isAdminUser ? true : _perms.contains(k);
                  return FilterChip(
                    label: Text(_permLabel(k)),
                    selected: checked,
                    onSelected: isAdminUser
                        ? null
                        : (v) async {
                            setState(() {
                              if (v) {
                                _perms.add(k);
                              } else {
                                _perms.remove(k);
                              }
                            });
                            await ref.read(authProvider.notifier).updateUserPermissions(widget.username, _perms);
                          },
                  );
                }).toList(),
              ),
              if (!isAdminUser)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      setState(() => _perms = []);
                      await ref.read(authProvider.notifier).updateUserPermissions(widget.username, _perms);
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('إزالة جميع الصلاحيات'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _permLabel(String key) {
    switch (key) {
      case 'dashboard':
        return 'لوحة التحكم';
      case 'rooms':
        return 'الغرف';
      case 'bookings':
        return 'الحجوزات';
      case 'payments':
        return 'المدفوعات';
      case 'employees':
        return 'الموظفون';
      case 'expenses':
        return 'المصروفات';
      case 'finance':
        return 'المالية';
      case 'reports':
        return 'التقارير';
      case 'notes':
        return 'الملاحظات';
      case 'settings':
        return 'الإعدادات';
      default:
        return key;
    }
  }
}