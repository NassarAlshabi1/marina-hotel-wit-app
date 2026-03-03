# دليل ترحيل نظام المزامنة الموحد

## نظرة عامة

تم إنشاء `MarinaSyncManager` كحل موحد يستبدل 5 مديرين مختلفين للمزامنة:

| المدير القديم | الحالة | البديل الجديد |
|--------------|--------|--------------|
| `SyncOrchestrator` | ⚠️ مهمل | `MarinaSyncManager` |
| `UnifiedSyncOrchestrator` | ⚠️ مهمل | `MarinaSyncManager` |
| `AppwriteSyncManager` | ⚠️ مهمل | `MarinaSyncManager` + `AppwriteDeltaSync` |
| `SmartSyncManager` | ⚠️ مهمل | `MarinaSyncManager` |
| `AppwriteDeltaSync` | ✅ مستخدم داخلياً | يُستخدم بواسطة `MarinaSyncManager` |

## API القديم vs الجديد

### SyncOrchestrator (قديم)
```dart
// ❌ كود قديم
final orchestrator = SyncOrchestrator.instance;
orchestrator.initialize();
orchestrator.submitTask(SyncTask(...));
orchestrator.stateStream.listen(...);
```

### MarinaSyncManager (جديد)
```dart
// ✅ كود جديد
final manager = MarinaSyncManager.instance;
await manager.initialize(database: db);
await manager.sync();
manager.watchStatus().listen(...);
```

---

## خطوات الترحيل

### 1️⃣ استبدال Imports

**القديم:**
```dart
import 'services/sync_orchestrator.dart';
import 'services/unified_sync_orchestrator.dart';
import 'services/appwrite_sync_manager.dart';
import 'services/smart_sync_manager.dart';
```

**الجديد:**
```dart
import 'services/sync/marina_sync_manager.dart';
```

### 2️⃣ استبدال Providers

**القديم:**
```dart
// providers/smart_sync_provider.dart
final smartSyncManagerProvider = Provider<SmartSyncManager>((ref) {
  return SmartSyncManager.instance;
});
```

**الجديد:**
```dart
// providers/marina_sync_provider.dart
final marinaSyncManagerProvider = Provider<MarinaSyncManager>((ref) {
  return MarinaSyncManager.instance;
});
```

### 3️⃣ استبدال استدعاءات المزامنة

| العملية | الكود القديم | الكود الجديد |
|---------|-------------|-------------|
| مزامنة كاملة | `smartSync.forceSyncNow()` | `manager.sync()` |
| رفع فقط | `appwriteManager.pushLocalChanges()` | `manager.push()` |
| سحب فقط | `appwriteManager.pullRemoteChanges()` | `manager.pull()` |
| مزامنة Outbox | `appwriteManager.syncOutbox()` | `manager.syncOutbox()` |
| Snapshot | `smartSync.forceSyncNow()` | `manager.snapshot()` |

### 4️⃣ استبدال الاستماع للحالة

**القديم:**
```dart
SmartSyncManager.instance.onStatusChanged.listen((status) {
  print(status);
});
```

**الجديد:**
```dart
MarinaSyncManager.instance.watchStatus().listen((status) {
  print(status);
});
```

أو باستخدام Riverpod:
```dart
ConsumerWidget build(context, ref) {
  final status = ref.watch(marinaSyncStatusStreamProvider);
  // ...
}
```

---

## مثال كامل: ترحيل شاشة

### قبل الترحيل
```dart
class SyncScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smartSync = ref.watch(smartSyncManagerProvider);
    final appwriteSync = ref.watch(appwriteSyncManagerProvider);
    
    return Column(
      children: [
        ElevatedButton(
          onPressed: () => smartSync.forceSyncNow(),
          child: Text('Sync'),
        ),
        ElevatedButton(
          onPressed: () => appwriteSync.pushLocalChanges(),
          child: Text('Push'),
        ),
      ],
    );
  }
}
```

### بعد الترحيل
```dart
class SyncScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(marinaSyncStateProvider);
    
    return Column(
      children: [
        ElevatedButton(
          onPressed: syncState.isSyncing 
            ? null 
            : () async {
                final result = await ref.read(
                  marinaSyncNowProvider(const SyncParams()).future,
                );
                if (!result.isSuccess) {
                  // Show error
                }
              },
          child: Text(syncState.statusText),
        ),
        ElevatedButton(
          onPressed: () => ref.read(marinaPushProvider.future),
          child: Text('Push'),
        ),
      ],
    );
  }
}
```

---

## ملفات المهملة (Deprecated)

يمكن حذف هذه الملفات بعد اكتمال الترحيل:

```
services/sync_orchestrator.dart          → استخدم MarinaSyncManager
services/unified_sync_orchestrator.dart  → استخدم MarinaSyncManager  
services/appwrite_sync_manager.dart      → يُستخدم داخلياً فقط
services/smart_sync_manager.dart         → استخدم MarinaSyncManager
providers/smart_sync_provider.dart       → استخدم marina_sync_provider.dart
```

---

## مميزات النظام الجديد

| الميزة | MarinaSyncManager | القديم |
|--------|------------------|--------|
| API موحد | ✅ | ❌ (5 APIs مختلفة) |
| خطوط الكود | ~200 | ~2000+ |
| سهولة الصيانة | ✅ عالية | ❌ معقد |
| Auto-sync | ✅ مدمج | ⚠️ في مدير منفصل |
| Conflict Resolution | ✅ مدمج | ⚠️ في مدير منفصل |
| Riverpod Integration | ✅ كامل | ⚠️ جزئي |
| تتبع التقدم | ✅ Stream | ❌ غير موحد |

---

## استكشاف الأخطاء

### الخطأ: "SyncManager not initialized"
**الحل:** تأكد من استدعاء `initialize()` قبل أي عملية مزامنة:
```dart
await MarinaSyncManager.instance.initialize(database: db);
```

### الخطأ: "Sync already in progress"
**الحل:** استخدم `force: true` أو انتظر انتهاء المزامنة الحالية:
```dart
await manager.sync(force: true);
```

### الـ Provider لا يعمل
**الحل:** تأكد من إضافة `marina_sync_provider.dart`:
```dart
import 'providers/marina_sync_provider.dart';
```

---

## دعم

لأي استفسارات أو مشاكل في الترحيل، راجع:
- ملف: `services/sync/marina_sync_manager.dart`
- ملف: `providers/marina_sync_provider.dart`
- هذا الدليل: `SYNC_MIGRATION_GUIDE.md`
