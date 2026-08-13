// ignore_for_file: use_build_context_synchronously
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

    // عرض رسالة قطع الجلسة
    if (auth.sessionInvalidated) {
      return AppScaffold(
        title: 'إدارة المستخدمين',
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'تم تغيير بيانات الدخول من جهاز آخر',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                auth.error ?? 'يرجى تسجيل الدخول مجدداً',
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

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
                          isCloudUser: account.isCloud,
                          docId: account.docId,
                          onDeleted: _refreshAccounts,
                          onUpdated: _refreshAccounts,
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

    await showDialog<void>(
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
                            await ref
                                .read(authProvider.notifier)
                                .addUser(
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
    this.isCloud = false,
    this.docId,
  });

  factory _UserAccountSummary.fromMap(Map<String, dynamic> map) {
    return _UserAccountSummary(
      username: map['username']?.toString() ?? '',
      displayName: (map['full_name'] ?? map['username'] ?? '').toString(),
      userType: (map['user_type'] ?? '').toString(),
      isFixed: map['is_fixed'] == true,
      isCloud: map['is_cloud'] == true,
      docId: map['doc_id']?.toString(),
    );
  }
  final String username;
  final String displayName;
  final String userType;
  final bool isFixed;
  final bool isCloud;
  final String? docId;
}

class UserPermissionsCard extends ConsumerStatefulWidget {
  const UserPermissionsCard({
    required this.username,
    required this.displayName,
    required this.userType,
    required this.isFixedAccount,
    super.key,
    this.isCloudUser = false,
    this.docId,
    this.onDeleted,
    this.onUpdated,
  });
  final String username;
  final String displayName;
  final String userType;
  final bool isFixedAccount;
  final bool isCloudUser;
  final String? docId;
  final VoidCallback? onDeleted;
  final VoidCallback? onUpdated;

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

  Future<void> _openEditDialog() async {
    final formKey = GlobalKey<FormState>();
    final fullNameCtrl = TextEditingController(text: widget.displayName);
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String userType = widget.userType;
    final selectedPerms = List<String>.from(_perms);
    String? localError;
    bool saving = false;
    bool deleteRequested = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialog) {
            return AlertDialog(
              title: Text('تعديل مستخدم: ${widget.username}'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── معلومات أساسية ──
                      const Text(
                        'المعلومات الأساسية',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: fullNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الاسم الكامل',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPerms.contains('all')
                            ? 'admin'
                            : userType,
                        decoration: const InputDecoration(
                          labelText: 'نوع المستخدم',
                          prefixIcon: Icon(Icons.badge),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('مدير (كل الصلاحيات)'),
                          ),
                          DropdownMenuItem(
                            value: 'manager',
                            child: Text('مدير فرعي'),
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
                            value: 'employee',
                            child: Text('موظف'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialog(() => userType = v);
                            if (v == 'admin') {
                              setDialog(() {
                                selectedPerms.clear();
                                selectedPerms.addAll(
                                  AuthLocalStore.permissionKeys,
                                );
                              });
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── تغيير كلمة المرور ──
                      const Text(
                        'تغيير كلمة المرور (اختياري)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: passwordCtrl,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور الجديدة',
                          prefixIcon: Icon(Icons.lock),
                          hintText: 'اتركه فارغاً لعدم التغيير',
                        ),
                        obscureText: true,
                        validator: (v) {
                          if (v != null && v.isNotEmpty && v.length < 4) {
                            return 'أدخل 4 أرقام/رموز على الأقل';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmCtrl,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: (v) {
                          if (passwordCtrl.text.isNotEmpty &&
                              passwordCtrl.text != v) {
                            return 'كلمتا المرور غير متطابقتين';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── الصلاحيات ──
                      if (userType != 'admin') ...[
                        const Text(
                          'الصلاحيات',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: AuthLocalStore.permissionKeys.map((k) {
                            final selected = selectedPerms.contains(k);
                            return FilterChip(
                              label: Text(_permLabel(k)),
                              selected: selected,
                              onSelected: (v) {
                                setDialog(() {
                                  if (v) {
                                    selectedPerms.add(k);
                                  } else if (selectedPerms.length > 1) {
                                    selectedPerms.remove(k);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // ── تحذير / رسالة ──
                      if (passwordCtrl.text.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'سيتم قطع الجلسة على الأجهزة الأخرى عند حفظ كلمة المرور',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                // حذف
                if (!widget.isFixedAccount)
                  TextButton.icon(
                    onPressed: deleteRequested
                        ? null
                        : () async {
                            setDialog(() => deleteRequested = true);
                          },
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text(
                      'حذف',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                if (deleteRequested) ...[
                  TextButton(
                    onPressed: () => setDialog(() => deleteRequested = false),
                    child: const Text('إلغاء الحذف'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: () async {
                      setDialog(() => saving = true);
                      try {
                        final success = await ref
                            .read(authProvider.notifier)
                            .deleteCloudUser(docId: widget.docId!);
                        if (mounted && success) {
                          Navigator.pop(dialogContext);
                          widget.onDeleted?.call();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم حذف المستخدم ${widget.username}',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialog(() {
                          saving = false;
                          deleteRequested = false;
                          localError = 'فشل الحذف: $e';
                        });
                      }
                    },
                    child: saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('تأكيد الحذف'),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(dialogContext),
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
                              setDialog(
                                () =>
                                    localError = 'اختر صلاحية واحدة على الأقل',
                              );
                              return;
                            }
                            setDialog(() {
                              saving = true;
                              localError = null;
                            });
                            try {
                              final success = await ref
                                  .read(authProvider.notifier)
                                  .updateCloudUser(
                                    username: widget.username,
                                    docId: widget.docId!,
                                    newFullName: fullNameCtrl.text.trim(),
                                    newPassword: passwordCtrl.text.isNotEmpty
                                        ? passwordCtrl.text
                                        : null,
                                    newUserType: userType,
                                    newPermissions: userType == 'admin'
                                        ? AuthLocalStore.permissionKeys
                                        : selectedPerms,
                                  );
                              if (mounted && success) {
                                Navigator.pop(dialogContext);
                                widget.onUpdated?.call();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      passwordCtrl.text.isNotEmpty
                                          ? 'تم تحديث بيانات ${widget.username} — سيتم قطع الجلسة على الأجهزة الأخرى'
                                          : 'تم تحديث بيانات ${widget.username}',
                                    ),
                                  ),
                                );
                              } else {
                                setDialog(() {
                                  saving = false;
                                  localError = 'فشل التحديث — تحقق من الاتصال';
                                });
                              }
                            } catch (e) {
                              setDialog(() {
                                saving = false;
                                localError = e.toString();
                              });
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('حفظ التغييرات'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );

    fullNameCtrl.dispose();
    passwordCtrl.dispose();
    confirmCtrl.dispose();
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
                if (widget.isCloudUser)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: const Text(
                      'سحابي',
                      style: TextStyle(color: Colors.blue, fontSize: 11),
                    ),
                  ),
                const SizedBox(width: 6),
                Chip(
                  label: Text(
                    widget.userType.isEmpty
                        ? 'مستخدم'
                        : _typeLabel(widget.userType),
                  ),
                ),
                if (widget.isFixedAccount)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.lock, size: 16),
                  ),
                // زر التعديل للمستخدمين غير الثابتين
                if (!widget.isFixedAccount)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'تعديل',
                    onPressed: _openEditDialog,
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
      return 'المعلومية';
    case 'settings':
      return 'الإعدادات';
    default:
      return key;
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'admin':
      return 'مدير';
    case 'manager':
      return 'مدير فرعي';
    case 'supervisor':
      return 'مشرف';
    case 'accountant':
      return 'محاسب';
    case 'employee':
      return 'موظف';
    default:
      return type;
  }
}
