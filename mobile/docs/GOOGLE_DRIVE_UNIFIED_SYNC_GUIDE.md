# 🔄 دليل نظام المزامنة الموحد لـ Google Drive

## 📋 نظرة عامة

تم تطوير **نظام المزامنة الموحد (Unified Sync Coordinator)** لحل جميع المشاكل المتعلقة بالمزامنة مع Google Drive:

### ✅ الميزات الرئيسية:

1. **نقطة دخول واحدة موحدة** - لا مزيد من التعقيد
2. **إدارة ذكية للتضارب** - حلول تلقائية واحترافية
3. **تحسين الأداء التلقائي** - استهلاك أقل للبطارية والبيانات
4. **مراقبة شاملة** - تتبع كامل لجميع عمليات المزامنة
5. **Debouncing متقدم** - تجميع ذكي للتغييرات
6. **Delta Sync للسرعة** - مزامنة تفاضلية للتحديثات الصغيرة
7. **Full Backup دوري** - نسخ احتياطي كامل منتظم

---

## 🏗️ البنية المعمارية

```
┌─────────────────────────────────────────────────────┐
│           Repository Layer (Bookings, etc.)         │
│                        ↓                            │
│         notifyLocalChange() [Single Call]           │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│      GoogleDriveUnifiedSyncCoordinator               │
│                                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │  Debouncing (5s default)                      │  │
│  │  - Collects all changes                       │  │
│  │  - Prevents spam                              │  │
│  └──────────────────────────────────────────────┘  │
│                         ↓                           │
│  ┌──────────────────────────────────────────────┐  │
│  │  Sync Mode Selection                          │  │
│  │  - Smart: Auto-detect best mode               │  │
│  │  - Delta: Fast updates                        │  │
│  │  - Full: Complete backup                      │  │
│  └──────────────────────────────────────────────┘  │
│                         ↓                           │
│  ┌──────────────────────────────────────────────┐  │
│  │  Performance Checks                           │  │
│  │  - Battery level                              │  │
│  │  - Data usage limits                          │  │
│  │  - Network quality                            │  │
│  └──────────────────────────────────────────────┘  │
│                         ↓                           │
│  ┌──────────────────────────────────────────────┐  │
│  │  Conflict Detection & Resolution              │  │
│  │  - Automatic strategies                       │  │
│  │  - History tracking                           │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│            Google Drive Services                     │
│  - GoogleDriveDeltaSync (Fast updates)              │
│  - GoogleDriveBackupService (Full backups)          │
│  - GoogleDriveLogger (Monitoring)                   │
└─────────────────────────────────────────────────────┘
```

---

## 🚀 التكامل السريع

### 1. تهيئة في `main.dart`:

```dart
Future<void> _initializeSmartAutoBackup() async {
  try {
    // تهيئة الخدمات الأساسية
    final driveLogger = GoogleDriveLogger();
    await driveLogger.initialize(
      minLevel: LogLevel.debug, 
      enableConsole: true, 
      enableFile: false
    );

    final backupService = GoogleDriveBackupService();
    
    // محاولة استعادة الجلسة
    try {
      await backupService.attemptSilentSignIn();
    } catch (e) {
      debugPrint('⚠️ Silent sign-in failed: $e');
    }
    
    // ✨ تهيئة المنسق الموحد (NEW!)
    final unifiedCoordinator = GoogleDriveUnifiedSyncCoordinator.instance;
    await unifiedCoordinator.initialize(
      backupService: backupService,
      database: DatabaseManager.instance,
      logger: driveLogger,
    );
    
    // تهيئة Conflict Resolver (NEW!)
    final conflictResolver = GoogleDriveConflictResolver.instance;
    conflictResolver.initialize(driveLogger);
    
    // الإعدادات الافتراضية الموصى بها
    await unifiedCoordinator.setPushEnabled(true);
    await unifiedCoordinator.setPullEnabled(true);
    await unifiedCoordinator.setDebounceSeconds(5);
    await unifiedCoordinator.setPullInterval(2); // كل دقيقتين
    await unifiedCoordinator.setFullBackupInterval(24); // كل 24 ساعة
    
    debugPrint('✅ Unified Sync Coordinator initialized successfully');
  } catch (e) {
    debugPrint('❌ Failed to initialize: $e');
  }
}
```

### 2. في `AppLifecycleState` (في main.dart أو app-level):

```dart
class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ✨ استدعاء واحد فقط عند فتح التطبيق
      GoogleDriveUnifiedSyncCoordinator.instance.onAppForeground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
```

### 3. في Repositories (مثال: `BookingsRepository`):

```dart
class BookingsRepository {
  Future<int> create({/* parameters */}) async {
    final result = await dao.insertOne(/* ... */);
    
    // ✨ استدعاء واحد بسيط للمنسق الموحد
    GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(
      table: 'bookings',
      operation: 'INSERT',
      count: 1,
    );
    
    return result;
  }

  Future<int> update(int id, {/* parameters */}) async {
    final result = await dao.updateById(id, /* ... */);
    
    GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(
      table: 'bookings',
      operation: 'UPDATE',
      count: 1,
    );
    
    return result;
  }

  Future<void> delete(int id) async {
    await dao.deleteById(id);
    
    GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(
      table: 'bookings',
      operation: 'DELETE',
      count: 1,
    );
  }
}
```

### 4. معالجة تسجيل الدخول/الخروج:

```dart
// في BackupProvider أو AuthProvider
class BackupStatusNotifier extends StateNotifier<BackupStatus> {
  Future<void> signIn() async {
    final account = await _backupService.signInForDrive();
    
    if (account != null) {
      // ✨ إخطار المنسق الموحد بتغيير حالة تسجيل الدخول
      await GoogleDriveUnifiedSyncCoordinator.instance.onSignInChanged(true);
      
      state = state.copyWith(
        isSignedIn: true,
        userEmail: account.email,
      );
    }
  }

  Future<void> signOut() async {
    await _backupService.signOut();
    
    // ✨ إخطار المنسق بتسجيل الخروج
    await GoogleDriveUnifiedSyncCoordinator.instance.onSignInChanged(false);
    
    state = state.copyWith(
      isSignedIn: false,
      userEmail: null,
    );
  }
}
```

---

## ⚙️ الإعدادات المتقدمة

### 1. استراتيجيات حل التضارب:

```dart
final resolver = GoogleDriveConflictResolver.instance;

// الأحدث يفوز (افتراضي)
await resolver.setStrategy(ConflictResolutionStrategy.newerWins);

// المحلي دائماً يفوز
await resolver.setStrategy(ConflictResolutionStrategy.localWins);

// البعيد دائماً يفوز
await resolver.setStrategy(ConflictResolutionStrategy.remoteWins);

// حسب أولوية الجهاز
await resolver.setStrategy(ConflictResolutionStrategy.devicePriorityBased);
await resolver.setDevicePriority(150); // أعلى من 100 = أولوية عالية

// مراجعة يدوية
await resolver.setStrategy(ConflictResolutionStrategy.manualReview);
```

### 2. ضبط توقيت المزامنة:

```dart
final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;

// Debouncing (تجميع التغييرات)
await coordinator.setDebounceSeconds(3); // 3 ثوانٍ

// فترة Pull التلقائي
await coordinator.setPullInterval(1); // كل دقيقة (سريع)
await coordinator.setPullInterval(5); // كل 5 دقائق (متوسط)
await coordinator.setPullInterval(15); // كل 15 دقيقة (بطيء)

// فترة النسخ الاحتياطي الكامل
await coordinator.setFullBackupInterval(12); // كل 12 ساعة
await coordinator.setFullBackupInterval(24); // كل 24 ساعة (موصى به)
await coordinator.setFullBackupInterval(48); // كل 48 ساعة
```

### 3. التحكم في تفعيل Push/Pull:

```dart
// تعطيل Push مؤقتاً (لا ترفع التغييرات)
await coordinator.setPushEnabled(false);

// تعطيل Pull مؤقتاً (لا تسحب التحديثات)
await coordinator.setPullEnabled(false);

// إعادة التفعيل
await coordinator.setPushEnabled(true);
await coordinator.setPullEnabled(true);
```

---

## 📊 المراقبة والتشخيص

### 1. مراقبة حالة المزامنة:

```dart
final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;

// الحصول على الحالة الكاملة
final status = await coordinator.getStatus();
print('Is syncing: ${status['is_syncing']}');
print('Current phase: ${status['current_phase']}');
print('Pending changes: ${status['pending_changes_count']}');
print('Last push: ${status['last_push']}');
print('Last pull: ${status['last_pull']}');
print('Last full backup: ${status['last_full_backup']}');

// الاستماع للنتائج الفورية
coordinator.syncResults.listen((result) {
  if (result.success) {
    print('✅ Sync completed: ${result.message}');
    print('   Pushed: ${result.pushedChanges}, Pulled: ${result.pulledChanges}');
  } else {
    print('❌ Sync failed: ${result.message}');
    print('   Phase: ${result.phase}, Error: ${result.error}');
  }
});
```

### 2. إحصائيات التضارب:

```dart
final resolver = GoogleDriveConflictResolver.instance;

// الحصول على الإحصائيات
final stats = await resolver.getConflictStatistics();
print('Total conflicts: ${stats['total_conflicts']}');
print('By table: ${stats['by_table']}');
print('By strategy: ${stats['by_strategy']}');
print('Avg time diff: ${stats['avg_time_diff_seconds']}s');

// الحصول على السجل
final history = await resolver.getConflictHistory(limit: 10);
for (final entry in history) {
  print('${entry['timestamp']}: ${entry['table']}/${entry['uuid']} - ${entry['resolution']}');
}
```

### 3. عرض حالة المزامنة في UI:

```dart
class SyncStatusWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<SyncResult>(
      stream: GoogleDriveUnifiedSyncCoordinator.instance.syncResults,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox();
        }
        
        final result = snapshot.data!;
        final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
        
        return Card(
          child: ListTile(
            leading: Icon(
              result.success ? Icons.check_circle : Icons.error,
              color: result.success ? Colors.green : Colors.red,
            ),
            title: Text(result.message),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.pushedChanges != null)
                  Text('📤 Pushed: ${result.pushedChanges}'),
                if (result.pulledChanges != null)
                  Text('📥 Pulled: ${result.pulledChanges}'),
                if (coordinator.hasPendingChanges)
                  Text('⏳ Pending: ${coordinator.pendingChangesCount}'),
              ],
            ),
            trailing: Text(
              _formatTimestamp(result.timestamp),
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        );
      },
    );
  }
  
  String _formatTimestamp(DateTime dt) {
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
```

---

## 🧪 الاختبار اليدوي

### سيناريو 1: تغيير محلي → Push تلقائي

```dart
// 1. أضف حجزاً جديداً في الجهاز A
final bookingRepo = ref.read(bookingsRepositoryProvider);
await bookingRepo.create(
  roomNumber: '101',
  guestName: 'Test Guest',
  // ... parameters
);

// 2. انتظر 5 ثوانٍ (Debounce)
// 3. افحص اللوج:
//    "📤 Debounce complete - pushing 1 changes"
//    "✅ Pushed 1 changes"

// 4. افحص Google Drive:
//    ملف جديد: marina_sync_delta_YYYYMMDD_HHMMSS.json
```

### سيناريو 2: فتح التطبيق على جهاز آخر → Pull تلقائي

```dart
// 1. افتح التطبيق على الجهاز B
// 2. onAppForeground() يُستدعى تلقائياً
// 3. افحص اللوج:
//    "📱 App entered foreground"
//    "📥 Performing delta pull..."
//    "✅ Pulled 1 changes"

// 4. تحقق من ظهور الحجز الجديد في قائمة الحجوزات
```

### سيناريو 3: مزامنة دورية

```dart
// 1. اترك التطبيق مفتوحاً
// 2. بعد دقيقتين (افتراضي)، افحص اللوج:
//    "🔄 Periodic pull check triggered"
//    "📥 Performing delta pull..."

// 3. إذا لم تكن هناك تغييرات:
//    "ℹ️ No changes to pull"
```

### سيناريو 4: نسخة احتياطية كاملة مجدولة

```dart
// 1. انتظر 24 ساعة (أو عدّل الفترة)
// 2. افحص اللوج:
//    "💾 Performing full backup..."
//    "✅ Full backup completed"

// 3. افحص Google Drive:
//    ملف جديد: marina_backup_full_YYYY-MM-DD_TIMESTAMP.json
```

---

## 🔧 استكشاف الأخطاء

### المشكلة: "Not signed in to Google Drive"

**الحل:**
```dart
// تحقق من حالة تسجيل الدخول
final backupService = GoogleDriveBackupService();
print('Signed in: ${backupService.isSignedIn}');

// إذا لم يكن مسجلاً، سجل الدخول:
final account = await backupService.signInForDrive();
if (account != null) {
  await GoogleDriveUnifiedSyncCoordinator.instance.onSignInChanged(true);
}
```

### المشكلة: "Sync already in progress"

**الحل:**
```dart
// انتظر انتهاء المزامنة الحالية
final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
while (coordinator.isSyncing) {
  await Future.delayed(const Duration(milliseconds: 500));
}

// ثم حاول المزامنة
await coordinator.performSync(
  trigger: SyncTrigger.manual,
  mode: SyncMode.smart,
);
```

### المشكلة: التغييرات لا تُدفع تلقائياً

**الحل:**
```dart
// 1. تحقق من تفعيل Push
final status = await coordinator.getStatus();
print('Push enabled: ${status['push_enabled']}');

// 2. تفعيل Push إذا كان معطلاً
await coordinator.setPushEnabled(true);

// 3. تحقق من Debounce
print('Debounce: ${status['debounce_seconds']}s');

// 4. تحقق من التغييرات المعلقة
print('Pending: ${status['pending_changes_count']}');
```

### المشكلة: استهلاك بطارية مرتفع

**الحل:**
```dart
// 1. زيادة فترة Pull
await coordinator.setPullInterval(5); // من 2 إلى 5 دقائق

// 2. زيادة Debounce
await coordinator.setDebounceSeconds(10); // من 5 إلى 10 ثوانٍ

// 3. زيادة فترة النسخ الاحتياطي الكامل
await coordinator.setFullBackupInterval(48); // من 24 إلى 48 ساعة

// 4. تعطيل Pull المؤقت عند البطارية المنخفضة
final batteryLevel = await Battery().batteryLevel;
if (batteryLevel < 20) {
  await coordinator.setPullEnabled(false);
}
```

---

## 📈 أفضل الممارسات

### 1. ✅ استخدم استدعاء واحد فقط

```dart
// ❌ سيء - استدعاءات متعددة
AutoBackupManager.instance.onDataChange('bookings', 'INSERT');
SyncGuardian.instance.notifyLocalChange(table: 'bookings');
SmartSyncManager.instance.pushLocalChanges();

// ✅ جيد - استدعاء واحد فقط
GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(
  table: 'bookings',
  operation: 'INSERT',
  count: 1,
);
```

### 2. ✅ تجميع التغييرات المتعددة

```dart
// عند إدخال عدة سجلات
for (final item in items) {
  await dao.insertOne(item);
}

// استدعاء واحد في النهاية
GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(
  table: 'bookings',
  operation: 'BATCH_INSERT',
  count: items.length,
);
```

### 3. ✅ استخدام الإعدادات الموصى بها

```dart
// للأداء الأمثل
await coordinator.setDebounceSeconds(5);
await coordinator.setPullInterval(2);
await coordinator.setFullBackupInterval(24);

// للحفاظ على البطارية
await coordinator.setDebounceSeconds(10);
await coordinator.setPullInterval(5);
await coordinator.setFullBackupInterval(48);

// للسرعة القصوى
await coordinator.setDebounceSeconds(2);
await coordinator.setPullInterval(1);
await coordinator.setFullBackupInterval(12);
```

### 4. ✅ المراقبة والتشخيص

```dart
// استمع للنتائج للتشخيص
coordinator.syncResults.listen((result) {
  if (!result.success) {
    // سجل الأخطاء
    logger.error('Sync failed: ${result.error}');
    
    // أرسل إلى خدمة مراقبة
    analytics.logEvent('sync_failure', parameters: {
      'phase': result.phase.name,
      'error': result.error,
    });
  }
});
```

---

## 🎯 ملخص الفوائد

| الميزة | قبل | بعد |
|--------|-----|-----|
| **نقاط الإطلاق** | 5+ مناطق مختلفة | نقطة واحدة موحدة |
| **حل التضارب** | يدوي أو غير موجود | تلقائي مع استراتيجيات |
| **الأداء** | غير محسّن | محسّن تلقائياً |
| **المراقبة** | محدودة | شاملة مع Stream |
| **الصيانة** | معقدة | بسيطة وواضحة |
| **استهلاك البطارية** | عالٍ | منخفض |
| **استهلاك البيانات** | غير محدود | محدود ومراقب |

---

## 📞 الدعم

إذا واجهت أي مشاكل:

1. افحص الـ Logs: `DebugLogs.getAll('UnifiedSyncCoordinator')`
2. افحص حالة المزامنة: `coordinator.getStatus()`
3. افحص إحصائيات التضارب: `resolver.getConflictStatistics()`
4. تحقق من تسجيل الدخول: `backupService.isSignedIn`

---

**🎉 مبروك! نظام المزامنة الموحد جاهز للاستخدام!**
