# 🔄 نظام مزامنة البيانات الحالي - توثيق شامل

## 📋 المحتويات
1. [نظرة عامة](#نظرة-عامة)
2. [الهيكل المعماري](#الهيكل-المعماري) 
3. [طبقات المزامنة](#طبقات-المزامنة)
4. [تدفق البيانات](#تدفق-البيانات)
5. [إدارة التضارب](#إدارة-التضارب)
6. [التحسين والأداء](#التحسين-والأداء)
7. [الاستخدام العملي](#الاستخدام-العملي)

---

## 🎯 نظرة عامة

**التطبيق لا يستخدم Ditto** - بل يستخدم نظام مزامنة مخصص متطور ومتعدد الطبقات يدعم:

- ✅ **مزامنة مع خادم API** (Push/Pull)
- ✅ **مزامنة بين الأجهزة عبر Google Drive** 
- ✅ **حل التضارب الذكي**
- ✅ **تحسين الأداء والبطارية**
- ✅ **إدارة استهلاك البيانات**
- ✅ **نسخ احتياطي تلقائي**

---

## 🏗️ الهيكل المعماري

### 📁 الملفات الرئيسية

```
services/
├── sync_service.dart              # المزامنة مع الخادم
├── smart_sync_manager.dart        # المزامنة بين الأجهزة  
├── sync_performance_optimizer.dart # تحسين الأداء
├── google_drive_backup_service.dart # النسخ الاحتياطي
├── data_usage_manager.dart        # إدارة استهلاك البيانات
├── api_service.dart               # خدمة API
└── daos/                          # طبقة الوصول للبيانات
    ├── outbox_dao.dart           # قائمة انتظار التغييرات
    ├── rooms_dao.dart            # الغرف
    ├── bookings_dao.dart         # الحجوزات
    ├── payments_dao.dart         # المدفوعات
    └── ...
```

---

## 🔄 طبقات المزامنة

### 1️⃣ **SyncService** - المزامنة مع الخادم

```dart
// الاستخدام
final syncService = ref.read(syncServiceProvider);
await syncService.runSync(); // مزامنة يدوية
```

**الميزات:**
- ✅ Push/Pull مع API server
- ✅ Outbox pattern للتغييرات المحلية
- ✅ Batch processing للأداء
- ✅ Error handling والإعادة التلقائية
- ✅ Timeout optimization حسب نوع الشبكة

**التدفق:**
1. **Push**: رفع التغييرات من `outbox` للخادم
2. **Pull**: جلب التحديثات من الخادم
3. **Apply**: تطبيق التحديثات محلياً مع timestamp

### 2️⃣ **SmartSyncManager** - المزامنة الذكية بين الأجهزة

```dart
// التهيئة
final backupService = GoogleDriveBackupService();
await SmartSyncManager.instance.initialize(backupService);
await SmartSyncManager.instance.setEnabled(true);
```

**الميزات:**
- ✅ مراقبة تلقائية للنسخ الجديدة
- ✅ Device ID فريد لكل جهاز
- ✅ حل التضارب الذكي
- ✅ مزامنة دورية (افتراضي: كل 5 دقائق)
- ✅ Conflict resolution strategies

**استراتيجيات حل التضارب:**
```dart
enum ConflictResolution {
  newerWins,      // الأحدث يفوز (افتراضي)
  manualResolve,  // تدخل المستخدم
  devicePriority, // أولوية الجهاز
}
```

### 3️⃣ **SyncPerformanceOptimizer** - تحسين الأداء

```dart
// إعدادات الأداء
await optimizer.setWifiOnlyMode(true);
await optimizer.setBatteryOptimizationEnabled(true);
```

**التحسينات:**
- ✅ **WiFi Only Mode**: المزامنة على WiFi فقط
- ✅ **Battery Optimization**: توفير البطارية
- ✅ **Adaptive Intervals**: تعديل فترات المزامنة
- ✅ **Network-aware batching**: حجم الدفعات حسب السرعة
- ✅ **Skip logic**: تجاوز المزامنة عند الحاجة

### 4️⃣ **GoogleDriveBackupService** - النسخ الاحتياطي

```dart
// النسخ والاستعادة
await backupService.performBackup();
final backups = await backupService.listBackupFiles();
await backupService.restoreFromBackup(backupData);
```

**الميزات:**
- ✅ تشفير البيانات
- ✅ Metadata مفصلة (device_id, records_count, etc.)
- ✅ Auto backup scheduling
- ✅ Compression
- ✅ Versioning

### 5️⃣ **DataUsageManager** - إدارة البيانات

```dart
// مراقبة الاستهلاك
await DataUsageManager.instance.recordDataUsage(sizeInBytes);
final isExceeded = await DataUsageManager.instance.isLimitExceeded();
```

---

## 📊 تدفق البيانات

### 🔄 المزامنة العادية (مع الخادم)
```
Local Changes → Outbox → API Push → Server
     ↑                                    ↓
  Apply ←←←←← Local DB ←←← API Pull ←← Server Updates
```

### 🔄 المزامنة بين الأجهزة
```
Device A → Google Drive ← Device B
    ↓         ↕️              ↓
Backup → Conflict Detection → Merge
    ↓         ↕️              ↓
 Apply ← Resolution Strategy ← Apply
```

---

## ⚖️ إدارة التضارب

### مثال: حل التضارب "الأحدث يفوز"

```dart
// اكتشاف التضارب
final conflicts = await _detectDataConflicts(localData, remoteData);

// حل التضارب
for (final conflict in conflicts) {
  if (conflict.remoteTimestamp.isAfter(conflict.localTimestamp)) {
    // النسخة البعيدة أحدث - استيرادها
    await _importRecord(conflict.remoteRecord);
  } else {
    // النسخة المحلية أحدث - الاحتفاظ بها
    await _skipRemoteRecord(conflict.recordId);
  }
}
```

---

## ⚡ التحسين والأداء

### إعدادات الشبكة الذكية
```dart
// WiFi: دفعات كبيرة، timeout طويل
if (isWiFi) {
  batchSize = 100;
  timeout = 30; // ثانية
}

// Mobile Data: دفعات صغيرة، timeout قصير  
else {
  batchSize = 20;
  timeout = 10; // ثانية
}
```

### تحسين البطارية
```dart
// تجاوز المزامنة عند انخفاض البطارية
if (batteryLevel < 15 && !isCharging) {
  return; // تخطي المزامنة
}
```

---

## 💻 الاستخدام العملي

### في المكونات (UI)
```dart
// مزامنة يدوية
IconButton(
  onPressed: () async {
    await ref.read(syncServiceProvider).runSync();
  },
  icon: const Icon(Icons.sync),
)

// عرض حالة المزامنة
Consumer(
  builder: (context, ref, child) {
    final status = ref.watch(syncStatusProvider);
    return status.when(
      data: (status) => _buildSyncStatus(status),
      loading: () => CircularProgressIndicator(),
      error: (e, _) => Icon(Icons.sync_problem),
    );
  },
)
```

### في الخدمات
```dart
// تسجيل تغيير في البيانات
await roomsDao.updateByNumber(
  roomNumber,
  RoomsCompanion(
    status: Value(newStatus),
    lastModified: Value(Time.nowEpoch()),
  ),
  // سيتم إضافة التغيير تلقائياً إلى outbox
);
```

---

## 🎛️ إعدادات التحكم

### تفعيل/إلغاء المزامنة الذكية
```dart
await SmartSyncManager.instance.setEnabled(true);
```

### تعديل فترة المزامنة
```dart
await SmartSyncManager.instance.setSyncInterval(10); // 10 دقائق
```

### اختيار استراتيجية حل التضارب
```dart
await SmartSyncManager.instance.setConflictResolution(
  ConflictResolution.newerWins
);
```

### تفعيل تحسين الأداء
```dart
await optimizer.setWifiOnlyMode(true);
await optimizer.setBatteryOptimizationEnabled(true);
```

---

## 📈 مراقبة الحالة

```dart
// حالة المزامنة
final status = await SmartSyncManager.instance.getStatus();
print('مفعلة: ${status['enabled']}');
print('آخر مزامنة: ${status['last_sync_check']}');
print('معرف الجهاز: ${status['device_id']}');

// إحصائيات الأداء
final stats = syncService.getPerformanceStats();
print('نجح: ${stats['successful_syncs']}');
print('فشل: ${stats['failed_syncs']}');
```

---

## ✅ الملخص التقني

| الميزة | الحالة | التفاصيل |
|--------|---------|----------|
| **مزامنة الخادم** | ✅ نشطة | Push/Pull مع API server |
| **مزامنة الأجهزة** | ✅ نشطة | عبر Google Drive |
| **حل التضارب** | ✅ متقدم | 3 استراتيجيات مختلفة |
| **تحسين الأداء** | ✅ ذكي | حسب الشبكة والبطارية |
| **إدارة البيانات** | ✅ مراقبة | حدود يومية |
| **نسخ احتياطي** | ✅ تلقائي | مشفر ومضغوط |
| **المراقبة** | ✅ شاملة | إحصائيات مفصلة |

---

**النتيجة:** نظام مزامنة متطور جداً ومتعدد الطبقات، أكثر تعقيداً وذكاءً من Ditto في كثير من الجوانب!