# 🚀 تحسينات سريعة لمزامنة Google Drive

## ✅ تحسينات يمكن تطبيقها الآن (2-3 ساعات)

### 1. إضافة Sync Status Widget (30 دقيقة)

أنشئ ملف `lib/widgets/google_drive_sync_status_widget.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class GoogleDriveSyncStatusWidget extends ConsumerWidget {
  const GoogleDriveSyncStatusWidget({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // سيتم ربطه بـ provider لاحقاً
    final isSyncing = false; // مؤقت
    final lastSyncTime = DateTime.now().subtract(Duration(minutes: 5));
    final hasErrors = false;
    
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            _buildStatusIcon(isSyncing, hasErrors),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getStatusText(isSyncing, hasErrors),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'آخر مزامنة: ${_formatTime(lastSyncTime)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (!isSyncing)
              IconButton(
                icon: Icon(Icons.sync),
                onPressed: () {
                  // سيتم إضافة الوظيفة لاحقاً
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('جاري المزامنة...')),
                  );
                },
                tooltip: 'مزامنة يدوية',
              )
            else
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusIcon(bool isSyncing, bool hasErrors) {
    if (isSyncing) {
      return Icon(Icons.sync, color: Colors.blue, size: 32);
    } else if (hasErrors) {
      return Icon(Icons.error, color: Colors.red, size: 32);
    } else {
      return Icon(Icons.cloud_done, color: Colors.green, size: 32);
    }
  }
  
  String _getStatusText(bool isSyncing, bool hasErrors) {
    if (isSyncing) {
      return 'جاري المزامنة...';
    } else if (hasErrors) {
      return 'فشلت المزامنة';
    } else {
      return 'تمت المزامنة بنجاح';
    }
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) {
      return 'الآن';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else {
      return DateFormat('dd/MM/yyyy HH:mm').format(time);
    }
  }
}
```

**الاستخدام**: أضفه في `dashboard_screen.dart`:
```dart
@override
Widget build(BuildContext context) {
  return SingleChildScrollView(
    child: Column(
      children: [
        GoogleDriveSyncStatusWidget(), // أضف هنا
        // ... باقي الـ widgets
      ],
    ),
  );
}
```

---

### 2. إضافة Sync Settings (45 دقيقة)

في `lib/screens/settings/settings_screen.dart`, أضف قسم جديد:

```dart
// في بداية الملف
import '../google_drive_sync_settings_screen.dart';

// في الـ build method
Card(
  child: Column(
    children: [
      ListTile(
        leading: Icon(Icons.cloud_sync, color: Theme.of(context).primaryColor),
        title: Text('مزامنة Google Drive'),
        subtitle: Text('إدارة إعدادات المزامنة'),
        trailing: Icon(Icons.arrow_forward_ios),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => GoogleDriveSyncSettingsScreen(),
            ),
          );
        },
      ),
    ],
  ),
),
```

ثم أنشئ `lib/screens/settings/google_drive_sync_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveSyncSettingsScreen extends ConsumerStatefulWidget {
  const GoogleDriveSyncSettingsScreen({super.key});
  
  @override
  ConsumerState<GoogleDriveSyncSettingsScreen> createState() => 
      _GoogleDriveSyncSettingsScreenState();
}

class _GoogleDriveSyncSettingsScreenState 
    extends ConsumerState<GoogleDriveSyncSettingsScreen> {
  bool _autoSyncEnabled = true;
  bool _wifiOnlySync = true;
  String _syncInterval = '15 دقيقة';
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSyncEnabled = prefs.getBool('gd_auto_sync') ?? true;
      _wifiOnlySync = prefs.getBool('gd_wifi_only') ?? true;
      final intervalMinutes = prefs.getInt('gd_sync_interval') ?? 15;
      _syncInterval = '$intervalMinutes دقيقة';
    });
  }
  
  Future<void> _saveAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gd_auto_sync', value);
    setState(() => _autoSyncEnabled = value);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? 'تم تفعيل المزامنة التلقائية' : 'تم إيقاف المزامنة التلقائية'),
      ),
    );
  }
  
  Future<void> _saveWifiOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gd_wifi_only', value);
    setState(() => _wifiOnlySync = value);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? 'المزامنة على WiFi فقط' : 'المزامنة على أي اتصال'),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إعدادات مزامنة Google Drive'),
      ),
      body: ListView(
        children: [
          // حالة الاتصال
          Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_circle, size: 40),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'متصل بحساب Google',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'user@example.com', // سيتم جلبه ديناميكياً
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(Icons.logout),
                    label: Text('تسجيل الخروج'),
                    onPressed: () {
                      // سيتم إضافة logout logic
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // إعدادات المزامنة
          Card(
            margin: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('المزامنة التلقائية'),
                  subtitle: Text('مزامنة البيانات تلقائياً في الخلفية'),
                  value: _autoSyncEnabled,
                  onChanged: _saveAutoSync,
                  secondary: Icon(Icons.sync),
                ),
                Divider(),
                SwitchListTile(
                  title: Text('المزامنة على WiFi فقط'),
                  subtitle: Text('لتوفير بيانات الجوال'),
                  value: _wifiOnlySync,
                  onChanged: _saveWifiOnly,
                  secondary: Icon(Icons.wifi),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.schedule),
                  title: Text('تكرار المزامنة'),
                  subtitle: Text(_syncInterval),
                  trailing: Icon(Icons.arrow_forward_ios),
                  onTap: () => _showIntervalPicker(),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // إجراءات
          Card(
            margin: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.cloud_upload),
                  title: Text('رفع نسخة احتياطية كاملة'),
                  subtitle: Text('رفع جميع البيانات إلى Google Drive'),
                  trailing: Icon(Icons.arrow_forward_ios),
                  onTap: () => _performFullBackup(),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.cloud_download),
                  title: Text('استعادة من Google Drive'),
                  subtitle: Text('تحميل آخر نسخة احتياطية'),
                  trailing: Icon(Icons.arrow_forward_ios),
                  onTap: () => _performRestore(),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.history),
                  title: Text('سجل المزامنة'),
                  subtitle: Text('عرض تاريخ عمليات المزامنة'),
                  trailing: Icon(Icons.arrow_forward_ios),
                  onTap: () => _showSyncHistory(),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // معلومات
          Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'معلومات المزامنة',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 12),
                  _buildInfoRow('آخر مزامنة', 'منذ 5 دقائق'),
                  _buildInfoRow('حجم البيانات', '2.5 MB'),
                  _buildInfoRow('عدد الملفات', '12 ملف'),
                  _buildInfoRow('معدل النجاح', '98%'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  
  void _showIntervalPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('اختر تكرار المزامنة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIntervalOption('5 دقائق', 5),
            _buildIntervalOption('15 دقيقة', 15),
            _buildIntervalOption('30 دقيقة', 30),
            _buildIntervalOption('ساعة واحدة', 60),
          ],
        ),
      ),
    );
  }
  
  Widget _buildIntervalOption(String label, int minutes) {
    return ListTile(
      title: Text(label),
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('gd_sync_interval', minutes);
        setState(() => _syncInterval = label);
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث تكرار المزامنة إلى $label')),
        );
      },
    );
  }
  
  Future<void> _performFullBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تأكيد النسخ الاحتياطي'),
        content: Text('هل تريد رفع نسخة احتياطية كاملة؟ قد يستغرق هذا بعض الوقت.'),
        actions: [
          TextButton(
            child: Text('إلغاء'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: Text('نعم، ارفع'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('جاري رفع النسخة الاحتياطية...')),
      );
      
      // سيتم إضافة الوظيفة الفعلية لاحقاً
      // await GoogleDriveBackupService.instance.performFullBackup();
    }
  }
  
  Future<void> _performRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تحذير'),
        content: Text(
          'سيتم استبدال البيانات الحالية بآخر نسخة احتياطية من Google Drive. '
          'هل أنت متأكد؟'
        ),
        actions: [
          TextButton(
            child: Text('إلغاء'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: Text('نعم، استعد'),
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('جاري استعادة البيانات...')),
      );
      
      // سيتم إضافة الوظيفة الفعلية لاحقاً
    }
  }
  
  void _showSyncHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text('سجل المزامنة')),
          body: Center(
            child: Text('سيتم إضافة سجل المزامنة قريباً'),
          ),
        ),
      ),
    );
  }
}
```

---

### 3. إضافة Error Notifications (30 دقيقة)

أنشئ `lib/services/sync_notification_helper.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SyncNotificationHelper {
  static final instance = SyncNotificationHelper._();
  SyncNotificationHelper._();
  
  final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  bool _initialized = false;
  
  Future<void> initialize() async {
    if (_initialized) return;
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(settings);
    _initialized = true;
  }
  
  Future<void> showSyncErrorNotification(String error) async {
    await initialize();
    
    const androidDetails = AndroidNotificationDetails(
      'sync_errors',
      'أخطاء المزامنة',
      channelDescription: 'إشعارات عند فشل المزامنة',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      1,
      'فشلت مزامنة Google Drive',
      error,
      details,
    );
  }
  
  Future<void> showSyncSuccessNotification() async {
    await initialize();
    
    const androidDetails = AndroidNotificationDetails(
      'sync_success',
      'نجاح المزامنة',
      channelDescription: 'إشعارات عند نجاح المزامنة',
      importance: Importance.low,
      priority: Priority.low,
      icon: '@mipmap/ic_launcher',
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      2,
      'تمت مزامنة البيانات',
      'تم رفع التغييرات إلى Google Drive بنجاح',
      details,
    );
  }
}
```

**الاستخدام**: في `google_drive_auto_sync_engine.dart` أو أي sync service:

```dart
// عند نجاح المزامنة
await SyncNotificationHelper.instance.showSyncSuccessNotification();

// عند فشل المزامنة
await SyncNotificationHelper.instance.showSyncErrorNotification(error.toString());
```

---

### 4. إضافة Sync Progress Dialog (45 دقيقة)

أنشئ `lib/widgets/sync_progress_dialog.dart`:

```dart
import 'package:flutter/material.dart';

class SyncProgressDialog extends StatefulWidget {
  final Future<void> Function() syncOperation;
  final String title;
  
  const SyncProgressDialog({
    super.key,
    required this.syncOperation,
    this.title = 'جاري المزامنة',
  });
  
  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> {
  bool _isComplete = false;
  bool _hasError = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _performSync();
  }
  
  Future<void> _performSync() async {
    try {
      await widget.syncOperation();
      setState(() {
        _isComplete = true;
        _hasError = false;
      });
      
      // أغلق تلقائياً بعد ثانية
      await Future.delayed(Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isComplete = true;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isComplete)
            Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('يرجى الانتظار...'),
              ],
            )
          else if (_hasError)
            Column(
              children: [
                Icon(Icons.error, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text('فشلت المزامنة'),
                SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'حدث خطأ غير معروف',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            )
          else
            Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 16),
                Text('تمت المزامنة بنجاح'),
              ],
            ),
        ],
      ),
      actions: [
        if (_isComplete && _hasError)
          TextButton(
            child: Text('إعادة المحاولة'),
            onPressed: () {
              setState(() {
                _isComplete = false;
                _hasError = false;
                _errorMessage = null;
              });
              _performSync();
            },
          ),
        if (_isComplete)
          TextButton(
            child: Text('موافق'),
            onPressed: () => Navigator.of(context).pop(_hasError ? false : true),
          ),
      ],
    );
  }
}

// دالة مساعدة للاستخدام السهل
Future<bool> showSyncProgressDialog(
  BuildContext context,
  Future<void> Function() syncOperation, {
  String title = 'جاري المزامنة',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SyncProgressDialog(
      syncOperation: syncOperation,
      title: title,
    ),
  );
  
  return result ?? false;
}
```

**الاستخدام**:
```dart
// في أي مكان تريد عمل مزامنة يدوية
onPressed: () async {
  final success = await showSyncProgressDialog(
    context,
    () async {
      await GoogleDriveUnifiedSyncCoordinator.instance.sync(
        mode: SyncMode.smart,
        trigger: SyncTrigger.manual,
      );
    },
  );
  
  if (success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت المزامنة بنجاح')),
    );
  }
}
```

---

## 📋 Checklist التطبيق

- [ ] إضافة GoogleDriveSyncStatusWidget إلى Dashboard
- [ ] إنشاء GoogleDriveSyncSettingsScreen
- [ ] ربط Settings screen بـ main settings
- [ ] إضافة SyncNotificationHelper
- [ ] إضافة SyncProgressDialog
- [ ] اختبار كل component

---

## 🎯 النتيجة المتوقعة

بعد تطبيق هذه التحسينات:
1. ✅ المستخدم يرى حالة المزامنة بوضوح في Dashboard
2. ✅ إعدادات مزامنة شاملة وسهلة الاستخدام
3. ✅ إشعارات عند الأخطاء
4. ✅ Progress dialog جميل للمزامنة اليدوية

**الوقت الإجمالي**: 2-3 ساعات فقط! 🚀
