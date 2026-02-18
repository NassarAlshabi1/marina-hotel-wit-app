# دليل التنفيذ - إصلاحات نظام المزامنة
## Implementation Guide - Step by Step

**التاريخ:** 2026-01-14  
**الهدف:** تطبيق الإصلاحات الحرجة من Expert Code Review

---

## 🎯 الخطوة 1: إنشاء CentralSyncCoordinator

### 1.1 إنشاء الملف الجديد

**المسار:** `lib/services/central_sync_coordinator.dart`

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_sync_manager.dart';
import 'google_drive_unified_sync_coordinator.dart';
import 'appwrite_service.dart';
import 'google_drive_backup_service.dart';
import 'local_db.dart';

/// منسق مركزي لجميع عمليات المزامنة
/// يمنع التعارضات والعمليات المكررة
class CentralSyncCoordinator {
  static final CentralSyncCoordinator _instance = CentralSyncCoordinator._internal();
  factory CentralSyncCoordinator() => _instance;
  static CentralSyncCoordinator get instance => _instance;
  
  CentralSyncCoordinator._internal();
  
  Timer? _debounceTimer;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  
  // Debounce موحد لجميع العمليات
  static const Duration unifiedDebounce = Duration(seconds: 3);
  
  // Cooldown لمنع المزامنة المتكررة جداً
  static const Duration syncCooldown = Duration(seconds: 10);
  
  /// إشعار بتغيير محلي - يبدأ debounced sync
  void notifyLocalChange({
    required String table,
    required String operation,
  }) {
    debugPrint('🔔 CentralSyncCoordinator: تغيير في $table ($operation)');
    
    // إلغاء timer السابق وبدء واحد جديد
    _debounceTimer?.cancel();
    _debounceTimer = Timer(unifiedDebounce, () async {
      await _performSync(reason: 'local_change:$table:$operation');
    });
  }
  
  /// مزامنة فورية (بدون debounce)
  Future<bool> syncNow({
    bool push = true,
    bool pull = true,
    String reason = 'manual',
  }) async {
    _debounceTimer?.cancel();  // إلغاء أي debounce معلق
    return await _performSync(
      push: push,
      pull: pull,
      reason: reason,
    );
  }
  
  /// تنفيذ المزامنة الفعلي
  Future<bool> _performSync({
    bool push = true,
    bool pull = true,
    required String reason,
  }) async {
    // التحقق من cooldown
    if (_lastSyncTime != null) {
      final elapsed = DateTime.now().difference(_lastSyncTime!);
      if (elapsed < syncCooldown) {
        debugPrint('⏸️ Sync في cooldown ($elapsed < $syncCooldown)');
        return false;
      }
    }
    
    // منع المزامنة المتزامنة
    if (_isSyncing) {
      debugPrint('⏸️ Sync قيد التنفيذ بالفعل');
      return false;
    }
    
    _isSyncing = true;
    debugPrint('🔄 بدء المزامنة: $reason (push: $push, pull: $pull)');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      final googleDriveEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;
      
      bool success = true;
      
      // اختيار نظام المزامنة بناءً على التفضيلات
      if (appwriteEnabled) {
        success = await _syncWithAppwrite(push: push, pull: pull);
      } else if (googleDriveEnabled) {
        success = await _syncWithGoogleDrive(push: push, pull: pull);
      } else {
        debugPrint('⚠️ لا توجد أنظمة مزامنة مفعلة');
        return false;
      }
      
      if (success) {
        _lastSyncTime = DateTime.now();
        debugPrint('✅ المزامنة نجحت: $reason');
      } else {
        debugPrint('❌ المزامنة فشلت: $reason');
      }
      
      return success;
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في المزامنة: $e');
      debugPrint(stackTrace.toString());
      return false;
    } finally {
      _isSyncing = false;
    }
  }
  
  /// مزامنة مع Appwrite
  Future<bool> _syncWithAppwrite({
    required bool push,
    required bool pull,
  }) async {
    try {
      final database = DatabaseManager.instance;
      final appwriteService = AppwriteService();
      final syncManager = AppwriteSyncManager(
        appwriteService: appwriteService,
        database: database,
      );
      
      // التأكد من التهيئة
      await syncManager.initialize();
      
      // تنفيذ المزامنة
      final result = await syncManager.sync(push: push, pull: pull);
      return result.isSuccess;
    } catch (e) {
      debugPrint('❌ خطأ في المزامنة مع Appwrite: $e');
      return false;
    }
  }
  
  /// مزامنة مع Google Drive
  Future<bool> _syncWithGoogleDrive({
    required bool push,
    required bool pull,
  }) async {
    try {
      final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
      
      if (push) {
        final pushResult = await coordinator.pushChanges();
        if (!pushResult) return false;
      }
      
      if (pull) {
        final pullResult = await coordinator.pullChanges();
        if (!pullResult) return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في المزامنة مع Google Drive: $e');
      return false;
    }
  }
  
  /// إلغاء جميع العمليات المعلقة
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
  
  /// الحصول على حالة المزامنة
  Map<String, dynamic> getStatus() {
    return {
      'is_syncing': _isSyncing,
      'last_sync': _lastSyncTime?.toIso8601String(),
      'has_pending_debounce': _debounceTimer?.isActive ?? false,
    };
  }
}
```

---

## 🎯 الخطوة 2: تعديل OutboxDao

### 2.1 تحديث الإشعارات

**الملف:** `lib/services/daos/outbox_dao.dart`

**ابحث عن السطور 110-112:**

```dart
// ❌ القديم (يُنبه 3 أنظمة!)
unawaited(SyncGuardian.instance.notifyLocalChange(table: entity, operation: op));
GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(table: entity, operation: op);
AutoSyncEngine.instance.notifyDataChange(table: entity, operation: op);
```

**استبدلها بـ:**

```dart
// ✅ الجديد (نقطة دخول واحدة)
CentralSyncCoordinator.instance.notifyLocalChange(
  table: entity,
  operation: op,
);
```

### 2.2 إضافة Import

**في أول الملف، أضف:**

```dart
import '../central_sync_coordinator.dart';
```

---

## 🎯 الخطوة 3: إضافة Processing Status في Outbox

### 3.1 تحديث Schema

**الملف:** `lib/services/local_db.dart`

**ابحث عن `class Outbox extends Table` وأضف:**

```dart
class Outbox extends Table {
  // ... existing fields
  
  // حالة المعالجة
  TextColumn get processingStatus => text()
    .withDefault(const Constant('pending'))();
  
  // وقت بدء المعالجة
  DateTimeColumn get processingStartedAt => dateTime().nullable()();
  
  // معرف العامل الذي يعالج هذا الـ entry
  TextColumn get processingWorker => text().nullable()();
}
```

### 3.2 إنشاء Migration

**الملف:** `lib/services/migrations/add_outbox_processing_status.dart`

```dart
import 'package:drift/drift.dart';

class AddOutboxProcessingStatusMigration {
  static Future<void> migrate(DatabaseConnectionUser db) async {
    // إضافة عمود processing_status
    await db.customStatement(
      'ALTER TABLE outbox ADD COLUMN processing_status TEXT DEFAULT "pending" NOT NULL'
    );
    
    // إضافة عمود processing_started_at
    await db.customStatement(
      'ALTER TABLE outbox ADD COLUMN processing_started_at INTEGER'
    );
    
    // إضافة عمود processing_worker
    await db.customStatement(
      'ALTER TABLE outbox ADD COLUMN processing_worker TEXT'
    );
    
    // إنشاء index للأداء
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_outbox_processing_status ON outbox(processing_status)'
    );
  }
}
```

### 3.3 تحديث takeBatch في OutboxDao

**الملف:** `lib/services/daos/outbox_dao.dart`

**استبدل دالة `takeBatch()`:**

```dart
import 'package:uuid/uuid.dart';

Future<List<OutboxData>> takeBatch(int limit, {String? workerId}) async {
  final worker = workerId ?? const Uuid().v4();
  
  return transaction(() async {
    // أخذ entries معلقة فقط
    final entries = await (select(outbox)
      ..where((t) => t.processingStatus.equals('pending'))
      ..orderBy([
        (t) => OrderingTerm.asc(t.clientTs),
      ])
      ..limit(limit)
    ).get();
    
    if (entries.isEmpty) {
      return [];
    }
    
    final ids = entries.map((e) => e.id).toList();
    
    // تحديث الحالة إلى "processing" ذريًا
    await (update(outbox)
      ..where((t) => t.id.isIn(ids))
    ).write(OutboxCompanion(
      processingStatus: const Value('processing'),
      processingStartedAt: Value(DateTime.now()),
      processingWorker: Value(worker),
    ));
    
    return entries;
  });
}

/// تحديد entries كـ completed
Future<void> markCompleted(List<int> ids) async {
  await (update(outbox)
    ..where((t) => t.id.isIn(ids))
  ).write(const OutboxCompanion(
    processingStatus: Value('completed'),
    processingStartedAt: Value.absent(),
    processingWorker: Value.absent(),
  ));
}

/// تحديد entries كـ failed
Future<void> markFailed(List<int> ids, String error) async {
  await (update(outbox)
    ..where((t) => t.id.isIn(ids))
  ).write(const OutboxCompanion(
    processingStatus: Value('failed'),
    // يمكن إضافة حقل error_message إذا أردت
  ));
}

/// إعادة محاولة entries failed
Future<void> retryFailed() async {
  await (update(outbox)
    ..where((t) => t.processingStatus.equals('failed'))
  ).write(const OutboxCompanion(
    processingStatus: Value('pending'),
    processingStartedAt: Value.absent(),
    processingWorker: Value.absent(),
  ));
}

/// تنظيف entries عالقة (أكثر من 5 دقائق في processing)
Future<int> cleanupStuckEntries() async {
  final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
  
  return await (update(outbox)
    ..where((t) => 
      t.processingStatus.equals('processing') &
      t.processingStartedAt.isSmallerThanValue(fiveMinutesAgo)
    )
  ).write(const OutboxCompanion(
    processingStatus: Value('pending'),
    processingStartedAt: Value.absent(),
    processingWorker: Value.absent(),
  ));
}
```

---

## 🎯 الخطوة 4: إصلاح Auto Sync Tasks

### 4.1 تحديث Appwrite Auto Sync Task

**الملف:** `lib/tasks/appwrite_auto_sync_task.dart`

**استبدل المحتوى بالكامل:**

```dart
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/central_sync_coordinator.dart';
import '../services/local_db.dart';

const String kAppwriteAutoSyncTaskName = 'appwrite_auto_sync';
const String _kPendingFlagKey = 'appwrite_auto_sync_pending';
const Duration kAppwriteAutoSyncDebounce = Duration(seconds: 8);

@pragma('vm:entry-point')
void appwriteAutoSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('🔄 [AppwriteAutoSync] بدء المزامنة التلقائية');
      
      // التحقق من التفعيل
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      
      if (!enabled) {
        debugPrint('⏸️ [AppwriteAutoSync] المزامنة معطلة');
        return true;
      }
      
      // تنفيذ المزامنة عبر CentralSyncCoordinator
      final success = await CentralSyncCoordinator.instance.syncNow(
        push: true,
        pull: true,
        reason: 'appwrite_background_task',
      );
      
      if (success) {
        debugPrint('✅ [AppwriteAutoSync] المزامنة نجحت');
        await prefs.setBool(_kPendingFlagKey, false);
      } else {
        debugPrint('❌ [AppwriteAutoSync] المزامنة فشلت');
        await prefs.setBool(_kPendingFlagKey, true);
      }
      
      return success;
    } catch (e, stackTrace) {
      debugPrint('❌ [AppwriteAutoSync] خطأ: $e');
      debugPrint(stackTrace.toString());
      return false;
    }
  });
}

/// جدولة المزامنة التلقائية
Future<void> scheduleAppwriteAutoSync() async {
  await Workmanager().registerPeriodicTask(
    'appwrite_auto_sync_periodic',
    kAppwriteAutoSyncTaskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );
  debugPrint('📅 تم جدولة Appwrite Auto Sync (كل 15 دقيقة)');
}

/// إلغاء الجدولة
Future<void> cancelAppwriteAutoSync() async {
  await Workmanager().cancelByUniqueName('appwrite_auto_sync_periodic');
  debugPrint('🚫 تم إلغاء Appwrite Auto Sync');
}
```

### 4.2 تحديث Google Drive Auto Sync Task

**الملف:** `lib/tasks/auto_sync_task.dart`

**استبدل callback بـ:**

```dart
@pragma('vm:entry-point')
void autoSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('🔄 [GoogleDriveAutoSync] بدء المزامنة التلقائية');
      
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('google_drive_sync_enabled') ?? false;
      
      if (!enabled) {
        debugPrint('⏸️ [GoogleDriveAutoSync] المزامنة معطلة');
        return true;
      }
      
      // تنفيذ المزامنة
      final success = await CentralSyncCoordinator.instance.syncNow(
        push: true,
        pull: true,
        reason: 'google_drive_background_task',
      );
      
      if (success) {
        debugPrint('✅ [GoogleDriveAutoSync] المزامنة نجحت');
        await prefs.setBool(_kPendingFlagKey, false);
      } else {
        debugPrint('❌ [GoogleDriveAutoSync] المزامنة فشلت');
        await prefs.setBool(_kPendingFlagKey, true);
      }
      
      return success;
    } catch (e, stackTrace) {
      debugPrint('❌ [GoogleDriveAutoSync] خطأ: $e');
      debugPrint(stackTrace.toString());
      return false;
    }
  });
}
```

---

## 🎯 الخطوة 5: إصلاح Empty Catch Blocks

### 5.1 في sync_manager.dart

**ابحث عن السطر 705:**

```dart
// ❌ القديم
try {
  localVc = VectorClock.fromJson(localVc);
} catch (_) {}

// ✅ الجديد
try {
  localVc = VectorClock.fromJson(localVc);
} catch (e, stackTrace) {
  debugPrint('⚠️ فشل تحليل VectorClock: $e');
  // استخدام قيمة افتراضية
  localVc = {'_root': 0};
}
```

### 5.2 في google_drive_conflict_resolver.dart

**ابحث عن السطر 437:**

```dart
// ❌ القديم
} catch (_) {}

// ✅ الجديد
} catch (e) {
  debugPrint('⚠️ فشل تحليل metadata: $e');
  return null;  // أو قيمة افتراضية مناسبة
}
```

### 5.3 في auth_local_store.dart

**استبدل جميع `catch (_) {}` بـ:**

```dart
} catch (e) {
  debugPrint('⚠️ خطأ في قراءة البيانات: $e');
  return null;  // أو قيمة افتراضية
}
```

---

## 🎯 الخطوة 6: تحديث SyncManagers لاستخدام CentralCoordinator

### 6.1 تعطيل الإشعارات المباشرة

**في `sync_guardian.dart`:**

```dart
// تعليق أو إزالة:
// unawaited(SyncGuardian.instance.notifyLocalChange(...))

// تم استبداله بـ CentralSyncCoordinator في outbox_dao.dart
```

**في `google_drive_unified_sync_coordinator.dart`:**

```dart
// في دالة notifyLocalChange()، أضف في البداية:
void notifyLocalChange({required String table, required String operation}) {
  // تم استبداله بـ CentralSyncCoordinator
  debugPrint('⚠️ notifyLocalChange deprecated, use CentralSyncCoordinator');
  return;
}
```

**في `google_drive_auto_sync_engine.dart`:**

```dart
// في notifyDataChange()
void notifyDataChange({required String table, required String operation}) {
  // تم استبداله بـ CentralSyncCoordinator
  debugPrint('⚠️ notifyDataChange deprecated, use CentralSyncCoordinator');
  return;
}
```

---

## 🎯 الخطوة 7: تحديث main.dart

### 7.1 تهيئة CentralSyncCoordinator

**في `main.dart`، بعد تهيئة Database وقبل AutoSyncEngine:**

```dart
debugPrint('🎯 [8/8] Initializing CentralSyncCoordinator...');
final centralCoordinator = CentralSyncCoordinator.instance;
debugPrint('✅ CentralSyncCoordinator ready');
```

---

## 🎯 الخطوة 8: تحديث Version Number

**في `local_db.dart`:**

```dart
@DriftDatabase(...)
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  // زيادة schema version
  @override
  int get schemaVersion => 3;  // كان 2، الآن 3
  
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 3) {
        // تطبيق migration للـ processing_status
        await AddOutboxProcessingStatusMigration.migrate(this);
      }
    },
  );
}
```

---

## 🎯 الخطوة 9: Testing

### 9.1 Manual Testing Checklist

```
✅ 1. تشغيل التطبيق بدون أخطاء
✅ 2. إنشاء booking جديد
✅ 3. التحقق من أن المزامنة تتم مرة واحدة فقط
✅ 4. فحص logs للتأكد من CentralSyncCoordinator يعمل
✅ 5. تعطيل الشبكة والتحقق من Outbox
✅ 6. إعادة تفعيل الشبكة والتحقق من المزامنة
✅ 7. اختبار Background sync (wait 15 minutes)
```

### 9.2 Unit Test Example

**ملف:** `test/central_sync_coordinator_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/central_sync_coordinator.dart';

void main() {
  group('CentralSyncCoordinator', () {
    test('debounce يعمل بشكل صحيح', () async {
      final coordinator = CentralSyncCoordinator.instance;
      
      // إشعارات متعددة سريعة
      coordinator.notifyLocalChange(table: 'bookings', operation: 'create');
      coordinator.notifyLocalChange(table: 'bookings', operation: 'update');
      coordinator.notifyLocalChange(table: 'bookings', operation: 'update');
      
      // يجب أن تحدث مزامنة واحدة فقط بعد 3 ثواني
      await Future.delayed(const Duration(seconds: 4));
      
      // تحقق من الحالة
      final status = coordinator.getStatus();
      expect(status['has_pending_debounce'], false);
    });
    
    test('cooldown يمنع المزامنة المتكررة', () async {
      final coordinator = CentralSyncCoordinator.instance;
      
      // مزامنة أولى
      await coordinator.syncNow(reason: 'test1');
      
      // محاولة فورية ثانية يجب أن تُرفض
      final result = await coordinator.syncNow(reason: 'test2');
      expect(result, false);
      
      // بعد 11 ثانية يجب أن تنجح
      await Future.delayed(const Duration(seconds: 11));
      final result2 = await coordinator.syncNow(reason: 'test3');
      expect(result2, true);
    });
  });
}
```

---

## 🎯 الخطوة 10: Rollback Plan

في حالة حدوث مشاكل، يمكن التراجع بسرعة:

### 10.1 Rollback Steps

```bash
# 1. التراجع عن التغييرات في Git
git revert HEAD

# 2. استعادة النسخة القديمة من outbox_dao.dart
git checkout HEAD~1 -- lib/services/daos/outbox_dao.dart

# 3. إزالة CentralSyncCoordinator
rm lib/services/central_sync_coordinator.dart

# 4. تراجع schema version
# في local_db.dart، أعد schemaVersion إلى 2
```

---

## 📊 Expected Results

بعد تطبيق جميع التغييرات:

### Before:
```
[13:45:01] 🔔 OutboxDao: Save booking
[13:45:01] ⚡ SyncGuardian: notifyLocalChange (30s debounce)
[13:45:01] ⚡ GoogleDriveCoordinator: notifyLocalChange (1s debounce)
[13:45:01] ⚡ AutoSyncEngine: notifyDataChange (0s)
[13:45:01] 🔄 AutoSyncEngine: Starting sync...
[13:45:02] 🔄 GoogleDriveCoordinator: Starting sync...  ← تضارب!
[13:45:31] 🔄 SyncGuardian: Starting sync...  ← تضارب!
```

### After:
```
[13:45:01] 🔔 OutboxDao: Save booking
[13:45:01] 🔔 CentralSyncCoordinator: تغيير في bookings (create)
[13:45:04] 🔄 CentralSyncCoordinator: بدء المزامنة (reason: local_change:bookings:create)
[13:45:05] ✅ CentralSyncCoordinator: المزامنة نجحت
[13:45:06] ⏸️ Sync في cooldown  ← لو حاول نظام آخر المزامنة
```

---

## 🎉 الخلاصة

التطبيق التدريجي للخطوات أعلاه سيؤدي إلى:

✅ تقليل عمليات المزامنة من **3x إلى 1x** (تحسين 200%)  
✅ منع التعارضات والعمليات المكررة  
✅ تفعيل Background Sync الفعلي  
✅ تحسين استهلاك Battery والموارد  
✅ تحسين تجربة المستخدم  

**الوقت المتوقع للتطبيق:** 4-6 ساعات  
**المخاطر:** منخفضة (يوجد Rollback Plan)

---

**Next:** ابدأ بالخطوة 1 وتحقق من كل خطوة قبل الانتقال للتالية.
