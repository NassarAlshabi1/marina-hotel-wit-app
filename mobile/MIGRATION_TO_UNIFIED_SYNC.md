# 🔄 دليل الترقية إلى Unified Sync Coordinator

## 📋 نظرة عامة

هذا الدليل يوضح خطوة بخطوة كيفية الترقية من النظام الحالي إلى **Unified Sync Coordinator**.

---

## ⚠️ ملاحظات مهمة قبل البدء

1. ✅ النظام الجديد **متوافق تماماً** مع الكود الحالي
2. ✅ لا يتطلب تغييرات في قاعدة البيانات
3. ✅ يمكن التراجع بسهولة إذا احتجت
4. ✅ جميع النسخ الاحتياطية الحالية ستعمل بدون مشاكل
5. ⚠️ يُفضل عمل نسخة احتياطية كاملة قبل الترقية

---

## 🚀 خطوات الترقية

### الخطوة 1: تحديث `main.dart`

#### الكود القديم (الحالي):

```dart
Future<void> _initializeSmartAutoBackup() async {
  try {
    final driveLogger = GoogleDriveLogger();
    await driveLogger.initialize(minLevel: LogLevel.debug, enableConsole: true, enableFile: false);

    final backupService = GoogleDriveBackupService();
    
    try {
      await backupService.attemptSilentSignIn();
    } catch (e) {
      debugPrint('⚠️ لم يتم استعادة جلسة Google Drive: $e');
    }
    
    // AutoBackupManager
    final autoBackupManager = AutoBackupManager.instance;
    await autoBackupManager.initialize(backupService);
    await autoBackupManager.setEnabled(true);
    await autoBackupManager.setMaxBackupCount(10);
    await autoBackupManager.setRetentionDays(14);
    
    // SmartSyncManager
    final smartSyncManager = SmartSyncManager.instance;
    await smartSyncManager.initialize(backupService);
    
    // GoogleDriveDeltaSync
    await GoogleDriveDeltaSync.instance.initialize(backupService, DatabaseManager.instance);
    debugPrint('✅ تم تهيئة Delta Sync للمزامنة السريعة');
    
    // SyncGuardian
    final syncGuardian = SyncGuardian.instance;
    final driveSyncService = GoogleDriveSyncService(googleSignIn: backupService.googleSignIn);
    await syncGuardian.initialize(
      database: DatabaseManager.instance,
      driveService: driveSyncService,
      appwriteSyncManager: null,
    );
    
    await SyncQueueService.instance.initialize();
    debugPrint('✅ تم تهيئة SyncQueueService');
    
    debugPrint('✅ تم تهيئة النسخ التلقائي والمزامنة الذكية عبر Google Drive بنجاح');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة النظام الذكي: $e');
  }
}
```

#### الكود الجديد (الموصى به):

```dart
Future<void> _initializeSmartAutoBackup() async {
  try {
    // 1. تهيئة Logger
    final driveLogger = GoogleDriveLogger();
    await driveLogger.initialize(
      minLevel: LogLevel.debug, 
      enableConsole: true, 
      enableFile: false
    );

    // 2. تهيئة Backup Service
    final backupService = GoogleDriveBackupService();
    
    // 3. محاولة استعادة الجلسة
    try {
      await backupService.attemptSilentSignIn();
    } catch (e) {
      debugPrint('⚠️ لم يتم استعادة جلسة Google Drive: $e');
    }
    
    // 4. ✨ تهيئة Unified Sync Coordinator (NEW!)
    final unifiedCoordinator = GoogleDriveUnifiedSyncCoordinator.instance;
    await unifiedCoordinator.initialize(
      backupService: backupService,
      database: DatabaseManager.instance,
      logger: driveLogger,
    );
    
    // 5. ✨ تهيئة Conflict Resolver (NEW!)
    final conflictResolver = GoogleDriveConflictResolver.instance;
    conflictResolver.initialize(driveLogger);
    
    // 6. الإعدادات الافتراضية الموصى بها
    await unifiedCoordinator.setPushEnabled(true);
    await unifiedCoordinator.setPullEnabled(true);
    await unifiedCoordinator.setDebounceSeconds(5);
    await unifiedCoordinator.setPullInterval(2);
    await unifiedCoordinator.setFullBackupInterval(24);
    
    // 7. استراتيجية حل التضارب (الأحدث يفوز)
    await conflictResolver.setStrategy(ConflictResolutionStrategy.newerWins);
    await conflictResolver.setConflictThreshold(30); // 30 ثانية
    
    // 8. (اختياري) الاحتفاظ بـ AutoBackupManager للنسخ المحلي فقط
    final autoBackupManager = AutoBackupManager.instance;
    await autoBackupManager.initialize(backupService);
    await autoBackupManager.setEnabled(true);
    await autoBackupManager.setMaxBackupCount(10);
    await autoBackupManager.setRetentionDays(14);
    
    // 9. (اختياري) تهيئة SyncQueueService إذا كان مستخدماً
    await SyncQueueService.instance.initialize();
    
    debugPrint('✅ Unified Sync Coordinator initialized successfully');
    debugPrint('✅ Google Drive sync system ready');
    
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة النظام: $e');
    rethrow;
  }
}
```

---

### الخطوة 2: تحديث AppLifecycleState

#### الكود القديم:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    SyncGuardian.instance.onAppForeground();
    SmartSyncManager.instance.pullRemoteChanges();
  }
}
```

#### الكود الجديد:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // ✨ استدعاء واحد فقط
    GoogleDriveUnifiedSyncCoordinator.instance.onAppForeground();
  }
}
```

---

### الخطوة 3: تحديث Repositories

#### مثال: `bookings_repository.dart`

##### الكود القديم:

```dart
Future<int> create({/* params */}) async {
  final result = await dao.insertOne(/* ... */);
  
  // استدعاءات متعددة ومتكررة
  AutoBackupManager.instance.onDataChange('bookings', 'INSERT', recordData: {'guest_name': guestName});
  SyncGuardian.instance.notifyLocalChange(table: 'bookings', operation: 'INSERT');
  
  return result;
}
```

##### الكود الجديد:

```dart
Future<int> create({/* params */}) async {
  final result = await dao.insertOne(/* ... */);
  
  // ✨ استدعاء واحد موحد
  GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(
    table: 'bookings',
    operation: 'INSERT',
    count: 1,
  );
  
  return result;
}
```

كرر هذا التعديل في جميع Repositories:
- ✅ `bookings_repository.dart`
- ✅ `payments_repository.dart`
- ✅ `expenses_repository.dart`
- ✅ `rooms_repository.dart`
- ✅ `debts_repository.dart`
- ✅ `employees_repository.dart`
- ✅ `cash_repository.dart`
- ✅ `notes_repository.dart`

---

### الخطوة 4: تحديث BackupProvider

#### الكود القديم:

```dart
class BackupStatusNotifier extends StateNotifier<BackupStatus> {
  Future<void> signIn() async {
    final account = await _backupService.signInForDrive();
    
    if (account != null) {
      SmartSyncManager.instance.onGoogleDriveSignInChanged(true);
      
      state = state.copyWith(isSignedIn: true, userEmail: account.email);
    }
  }
  
  Future<void> signOut() async {
    await _backupService.signOut();
    SmartSyncManager.instance.onGoogleDriveSignInChanged(false);
    
    state = state.copyWith(isSignedIn: false, userEmail: null);
  }
}
```

#### الكود الجديد:

```dart
class BackupStatusNotifier extends StateNotifier<BackupStatus> {
  Future<void> signIn() async {
    final account = await _backupService.signInForDrive();
    
    if (account != null) {
      // ✨ إخطار المنسق الموحد
      await GoogleDriveUnifiedSyncCoordinator.instance.onSignInChanged(true);
      
      state = state.copyWith(isSignedIn: true, userEmail: account.email);
    }
  }
  
  Future<void> signOut() async {
    await _backupService.signOut();
    
    // ✨ إخطار المنسق بتسجيل الخروج
    await GoogleDriveUnifiedSyncCoordinator.instance.onSignInChanged(false);
    
    state = state.copyWith(isSignedIn: false, userEmail: null);
  }
}
```

---

### الخطوة 5: (اختياري) إضافة شاشة مراقبة

إنشاء ملف جديد: `lib/screens/settings/unified_sync_monitor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/google_drive_unified_sync_coordinator.dart';
import '../../services/google_drive_conflict_resolver.dart';

class UnifiedSyncMonitorScreen extends ConsumerStatefulWidget {
  const UnifiedSyncMonitorScreen({super.key});

  @override
  ConsumerState<UnifiedSyncMonitorScreen> createState() => _UnifiedSyncMonitorScreenState();
}

class _UnifiedSyncMonitorScreenState extends ConsumerState<UnifiedSyncMonitorScreen> {
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _conflictStats;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await GoogleDriveUnifiedSyncCoordinator.instance.getStatus();
    final stats = await GoogleDriveConflictResolver.instance.getConflictStatistics();
    
    setState(() {
      _status = status;
      _conflictStats = stats;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراقبة المزامنة الموحدة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatus,
          ),
        ],
      ),
      body: _status == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildConfigCard(),
                  const SizedBox(height: 16),
                  _buildTimestampsCard(),
                  const SizedBox(height: 16),
                  _buildConflictsCard(),
                  const SizedBox(height: 16),
                  _buildActionsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final isInitialized = _status!['initialized'] as bool;
    final isSignedIn = _status!['signed_in'] as bool;
    final isSyncing = _status!['is_syncing'] as bool;
    final currentPhase = _status!['current_phase'] as String;
    final hasPending = _status!['has_pending_changes'] as bool;
    final pendingCount = _status!['pending_changes_count'] as int;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الحالة العامة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildStatusRow('مهيأ', isInitialized),
            _buildStatusRow('مسجل الدخول', isSignedIn),
            _buildStatusRow('المزامنة جارية', isSyncing),
            ListTile(
              dense: true,
              title: const Text('المرحلة الحالية'),
              trailing: Chip(label: Text(currentPhase)),
            ),
            ListTile(
              dense: true,
              title: const Text('تغييرات معلقة'),
              trailing: Chip(
                label: Text('$pendingCount'),
                backgroundColor: hasPending ? Colors.orange : Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool value) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Icon(
        value ? Icons.check_circle : Icons.cancel,
        color: value ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _buildConfigCard() {
    final pushEnabled = _status!['push_enabled'] as bool;
    final pullEnabled = _status!['pull_enabled'] as bool;
    final debounceSeconds = _status!['debounce_seconds'] as int;
    final pullInterval = _status!['pull_interval_minutes'] as int;
    final backupInterval = _status!['full_backup_interval_hours'] as int;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الإعدادات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildStatusRow('Push مفعّل', pushEnabled),
            _buildStatusRow('Pull مفعّل', pullEnabled),
            ListTile(
              dense: true,
              title: const Text('Debounce'),
              trailing: Text('$debounceSeconds ثانية'),
            ),
            ListTile(
              dense: true,
              title: const Text('فترة Pull'),
              trailing: Text('$pullInterval دقيقة'),
            ),
            ListTile(
              dense: true,
              title: const Text('فترة النسخ الكامل'),
              trailing: Text('$backupInterval ساعة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimestampsCard() {
    final lastPush = _status!['last_push'] as String?;
    final lastPull = _status!['last_pull'] as String?;
    final lastBackup = _status!['last_full_backup'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الطوابع الزمنية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ListTile(
              dense: true,
              title: const Text('آخر Push'),
              trailing: Text(lastPush != null ? _formatTimestamp(lastPush) : 'لم يحدث بعد'),
            ),
            ListTile(
              dense: true,
              title: const Text('آخر Pull'),
              trailing: Text(lastPull != null ? _formatTimestamp(lastPull) : 'لم يحدث بعد'),
            ),
            ListTile(
              dense: true,
              title: const Text('آخر نسخة كاملة'),
              trailing: Text(lastBackup != null ? _formatTimestamp(lastBackup) : 'لم يحدث بعد'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictsCard() {
    if (_conflictStats == null) {
      return const SizedBox();
    }

    final totalConflicts = _conflictStats!['total_conflicts'] as int;
    final byTable = _conflictStats!['by_table'] as Map<String, int>;
    final avgTimeDiff = _conflictStats!['avg_time_diff_seconds'] as double;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إحصائيات التضارب',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ListTile(
              dense: true,
              title: const Text('إجمالي التضاربات'),
              trailing: Text('$totalConflicts'),
            ),
            ListTile(
              dense: true,
              title: const Text('متوسط الفرق الزمني'),
              trailing: Text('${avgTimeDiff.toStringAsFixed(1)} ثانية'),
            ),
            if (byTable.isNotEmpty) ...[
              const Text('التضاربات حسب الجدول:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...byTable.entries.map((entry) => ListTile(
                dense: true,
                title: Text('  ${entry.key}'),
                trailing: Text('${entry.value}'),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الإجراءات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ElevatedButton.icon(
              onPressed: _performManualSync,
              icon: const Icon(Icons.sync),
              label: const Text('مزامنة يدوية'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _viewConflictHistory,
              icon: const Icon(Icons.history),
              label: const Text('سجل التضاربات'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performManualSync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جارٍ المزامنة...'),
          ],
        ),
      ),
    );

    try {
      final result = await GoogleDriveUnifiedSyncCoordinator.instance.performSync(
        trigger: SyncTrigger.manual,
        mode: SyncMode.smart,
      );

      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success ? '✅ ${result.message}' : '❌ ${result.message}'),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }

      await _loadStatus();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _viewConflictHistory() async {
    final history = await GoogleDriveConflictResolver.instance.getConflictHistory(limit: 20);

    if (mounted) {
      showModalBottomSheet(
        context: context,
        builder: (context) => ListView.builder(
          itemCount: history.length,
          itemBuilder: (context, index) {
            final entry = history[index];
            return ListTile(
              title: Text('${entry['table']}/${entry['uuid']}'),
              subtitle: Text(entry['resolution'] ?? ''),
              trailing: Text(_formatTimestamp(entry['timestamp'])),
            );
          },
        ),
      );
    }
  }

  String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
```

ثم أضف في `settings_screen.dart`:

```dart
ListTile(
  leading: const Icon(Icons.sync_alt),
  title: const Text('مراقبة المزامنة الموحدة'),
  subtitle: const Text('عرض حالة وإحصائيات المزامنة'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UnifiedSyncMonitorScreen()),
    );
  },
),
```

---

## ✅ التحقق من نجاح الترقية

### 1. افحص Logs عند بدء التطبيق:

```
✅ Unified Sync Coordinator initialized successfully
✅ Google Drive sync system ready
```

### 2. أضف بيانات جديدة وافحص:

```
[UnifiedSyncCoordinator] 📤 Debounce complete - pushing 1 changes
[UnifiedSyncCoordinator] ✅ Pushed 1 changes
```

### 3. افتح التطبيق على جهاز آخر:

```
[UnifiedSyncCoordinator] 📱 App entered foreground
[UnifiedSyncCoordinator] 📥 Performing delta pull...
[UnifiedSyncCoordinator] ✅ Pulled 1 changes
```

---

## 🔄 التراجع عن الترقية

إذا احتجت للتراجع:

1. استعد الكود القديم في `main.dart`
2. استعد الكود القديم في Repositories
3. لا حاجة لتغيير قاعدة البيانات
4. النسخ الاحتياطية لا تزال سليمة

---

## 📞 الدعم

إذا واجهت أي مشاكل أثناء الترقية:

1. افحص Logs بحثاً عن أخطاء
2. تحقق من تسجيل الدخول إلى Google Drive
3. تأكد من أن جميع الخدمات مهيئة بشكل صحيح
4. راجع `GOOGLE_DRIVE_UNIFIED_SYNC_GUIDE.md`

---

**🎉 مبروك! تمت الترقية بنجاح!**
