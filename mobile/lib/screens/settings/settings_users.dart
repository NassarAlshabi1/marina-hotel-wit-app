import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_local_store.dart';

class SettingsUsersScreen extends ConsumerStatefulWidget {
  const SettingsUsersScreen({super.key});

  @override
  ConsumerState<SettingsUsersScreen> createState() =>
      _SettingsUsersScreenState();
}

class _SettingsUsersScreenState extends ConsumerState<SettingsUsersScreen> {
  final _store = AuthLocalStore();
  late Future<List<_UserAccountSummary>> _accountsFuture;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _loadAccounts();
  }

  Future<List<_UserAccountSummary>> _loadAccounts() async {
    final raw = await _store.getAllAccountsDetailed();
    return raw.map(_UserAccountSummary.fromMap).toList();
  }

  void _refreshAccounts() {
    setState(() {
      _accountsFuture = _loadAccounts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isAdmin = auth.currentUser?.isAdmin ?? false;

    return AppScaffold(
      title: 'إدارة المستخدمين والصلاحيات',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_circle,
                    size: 32,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.currentUser?.name ?? 'غير معروف',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isAdmin
                              ? 'مدير النظام'
                              : (auth.currentUser?.userType ?? ''),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!isAdmin)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
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
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'صلاحيات المستخدمين',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _openAddUserDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة مستخدم'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<_UserAccountSummary>>(
              future: _accountsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('تعذر تحميل المستخدمين'),
                  );
                }
                final accounts = snapshot.data ?? [];
                if (accounts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا يوجد مستخدمون مسجلون'),
                  );
                }
                return Column(
                  children: accounts
                      .map(
                        (account) => UserPermissionsCard(
                          key: ValueKey(account.username),
                          username: account.username,
                          displayName: account.displayName,
                          userType: account.userType,
                          isFixedAccount: account.isFixed,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAddUserDialog() async {
    final formKey = GlobalKey<FormState>();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController();
    String userType = 'employee';
    final selectedPerms = <String>{'dashboard'};
    String? localError;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('إضافة مستخدم جديد'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: fullNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الاسم الكامل',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'الاسم مطلوب'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: usernameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'اسم المستخدم مطلوب'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordCtrl,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                        ),
                        obscureText: true,
                        validator: (value) =>
                            (value == null || value.length < 4)
                                ? 'أدخل 4 أرقام/رموز على الأقل'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmCtrl,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور',
                        ),
                        obscureText: true,
                        validator: (value) => value != passwordCtrl.text
                            ? 'كلمتا المرور غير متطابقتين'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: userType,
                        decoration: const InputDecoration(
                          labelText: 'نوع المستخدم',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'employee',
                            child: Text('موظف'),
                          ),
                          DropdownMenuItem(
                            value: 'supervisor',
                            child: Text('مشرف'),
                          ),
                          DropdownMenuItem(
                            value: 'accountant',
                            child: Text('محاسب'),
                          ),
                          DropdownMenuItem(
                            value: 'manager',
                            child: Text('مدير'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setStateDialog(() => userType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'الصلاحيات',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: AuthLocalStore.permissionKeys.map((key) {
                          final selected = selectedPerms.contains(key);
                          return FilterChip(
                            label: Text(_permLabel(key)),
                            selected: selected,
                            onSelected: (value) {
                              setStateDialog(() {
                                if (value) {
                                  selectedPerms.add(key);
                                } else if (selectedPerms.length > 1) {
                                  selectedPerms.remove(key);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (localError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            localError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          if (selectedPerms.isEmpty) {
                            setStateDialog(
                              () => localError = 'اختر صلاحية واحدة على الأقل',
                            );
                            return;
                          }
                          setStateDialog(() {
                            saving = true;
                            localError = null;
                          });
                          try {
                            await ref.read(authProvider.notifier).addUser(
                                  username: usernameCtrl.text.trim(),
                                  password: passwordCtrl.text,
                                  fullName: fullNameCtrl.text.trim(),
                                  userType: userType,
                                  permissions: selectedPerms.toList(),
                                );
                            if (mounted) {
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم إضافة المستخدم بنجاح'),
                                ),
                              );
                              _refreshAccounts();
                            }
                          } catch (e) {
                            setStateDialog(() {
                              saving = false;
                              localError = e.toString().replaceAll(
                                    'Exception: ',
                                    '',
                                  );
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameCtrl.dispose();
    passwordCtrl.dispose();
    confirmCtrl.dispose();
    fullNameCtrl.dispose();
  }
}

class _UserAccountSummary {
  const _UserAccountSummary({
    required this.username,
    required this.displayName,
    required this.userType,
    required this.isFixed,
  });

  factory _UserAccountSummary.fromMap(Map<String, dynamic> map) {
    return _UserAccountSummary(
      username: map['username']?.toString() ?? '',
      displayName: (map['full_name'] ?? map['username'] ?? '').toString(),
      userType: (map['user_type'] ?? '').toString(),
      isFixed: map['is_fixed'] == true,
    );
  }
  final String username;
  final String displayName;
  final String userType;
  final bool isFixed;
}

class UserPermissionsCard extends ConsumerStatefulWidget {
  const UserPermissionsCard({
    super.key,
    required this.username,
    required this.displayName,
    required this.userType,
    required this.isFixedAccount,
  });
  final String username;
  final String displayName;
  final String userType;
  final bool isFixedAccount;

  @override
  ConsumerState<UserPermissionsCard> createState() =>
      _UserPermissionsCardState();
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
    const allKeys = AuthLocalStore.permissionKeys;

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '@${widget.username}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    widget.userType.isEmpty ? 'مستخدم' : widget.userType,
                  ),
                ),
                if (widget.isFixedAccount)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.lock, size: 16),
                  ),
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
                            await ref
                                .read(authProvider.notifier)
                                .updateUserPermissions(widget.username, _perms);
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
                      await ref
                          .read(authProvider.notifier)
                          .updateUserPermissions(widget.username, _perms);
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
    case 'debts':
      return 'الديون';
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
    case 'information':
      return 'المعلومات';
    case 'settings':
      return 'الإعدادات';
    // ⭐ صلاحيات التعديل
    case 'edit_expenses':
      return 'تعديل المصروفات';
    case 'edit_payments':
      return 'تعديل المدفوعات';
    case 'edit_salaries':
      return 'تعديل الرواتب';
    default:
      return key;
  }
}
