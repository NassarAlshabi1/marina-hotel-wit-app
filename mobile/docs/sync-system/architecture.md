# المعمارية - نظام المزامنة

## البنية العامة

```
┌─────────────────────────────────────────────────────────┐
│                    التطبيق (UI)                         │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────▼────────────┐
         │  BaseSyncManager       │ ← المدير الموحد
         │  (التنسيق العام)       │
         └───────────┬────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ↓                       ↓
┌────────────────┐      ┌────────────────┐
│ SyncScheduler  │      │ ConflictResolver│
│ (الجدولة)     │      │ (حل التضارب)   │
└────────────────┘      └────────────────┘
         │                       │
         ↓                       ↓
┌────────────────┐      ┌────────────────┐
│  SyncMetrics   │      │ Monitoring     │
│ (القياسات)     │      │ System         │
└────────────────┘      └────────────────┘
         │
         ↓
┌────────────────────────┐
│   Local Database       │
│   (SQLite + Drift)     │
└────────────────────────┘
```

---

## المكونات بالتفصيل

### 1. BaseSyncManager

**المسؤولية**: التنسيق العام بين جميع المكونات

**الملف**: `lib/services/sync_core/base_sync_manager.dart`

**الوظائف الرئيسية**:
- `initialize()` - التهيئة الأولية
- `enable()` / `disable()` - تفعيل/تعطيل المزامنة
- `syncNow()` - مزامنة فورية
- `setConflictStrategy()` - تغيير استراتيجية حل التضارب

**المعتمدات**:
- SyncScheduler
- ConflictResolver
- SyncMetrics
- GoogleDriveBackupService

---

### 2. SyncScheduler

**المسؤولية**: جدولة المزامنة فقط

**الملف**: `lib/services/sync_core/sync_scheduler.dart`

**الوظائف الرئيسية**:
- `start()` - بدء الجدولة
- `stop()` - إيقاف الجدولة
- `triggerNow()` - تشغيل فوري

**الإعدادات**:
- `quickCheckInterval`: فحص سريع كل دقيقة
- `fullSyncInterval`: مزامنة كاملة كل 24 ساعة

**لا يعرف**: تفاصيل المزامنة، كيفية حل التضارب

---

### 3. ConflictResolver

**المسؤولية**: كشف وحل التضارب فقط

**الملف**: `lib/services/sync_core/conflict_resolver.dart`

**الاستراتيجيات**:
1. **newerWins**: الأحدث يفوز (افتراضي)
2. **devicePriority**: أولوية الجهاز
3. **manualResolve**: يدوي (يحتاج تدخل المستخدم)

**الوظائف الرئيسية**:
- `detectConflicts()` - كشف التضارب
- `resolveConflicts()` - حل التضارب

**لا يعرف**: الجدولة، القياسات

---

### 4. SyncMetrics

**المسؤولية**: القياسات والإحصائيات فقط

**الملف**: `lib/services/sync_core/sync_metrics.dart`

**البيانات المتتبعة**:
- عدد المزامنات الناجحة/الفاشلة
- متوسط وقت المزامنة
- معدل النجاح
- عدد السجلات المزامنة
- عدد التضاربات المحلولة

**الوظائف الرئيسية**:
- `startSync()` - بدء تتبع
- `recordSuccess()` - تسجيل نجاح
- `recordFailure()` - تسجيل فشل
- `calculateStats()` - حساب الإحصائيات

**Stream**:
- `statsStream` - بث حي للإحصائيات

---

### 5. SyncMonitoringSystem

**المسؤولية**: المراقبة الشاملة

**الملف**: `lib/services/monitoring/sync_monitoring_system.dart`

**الأحداث المتتبعة**:
- started: بدأت المزامنة
- completed: اكتملت بنجاح
- failed: فشلت
- conflict: تضارب
- retry: إعادة محاولة
- timeout: انتهى الوقت
- networkError: خطأ شبكة

**التنبيهات**:
- info: معلوماتية
- warning: تحذير
- critical: حرج

**الوظائف الرئيسية**:
- `recordSyncStart()` - بدء المزامنة
- `recordSyncSuccess()` - نجاح
- `recordSyncFailure()` - فشل
- `recordConflict()` - تضارب
- `exportReport()` - تصدير تقرير

---

## تدفق المزامنة

```
1. المستخدم يحفظ بيانات
        ↓
2. BaseSyncManager.syncNow()
        ↓
3. SyncMetrics.startSync()
   SyncMonitoringSystem.recordSyncStart()
        ↓
4. تحميل البيانات من Google Drive
        ↓
5. ConflictResolver.detectConflicts()
        ↓
6. إذا وجدت تضاربات:
   ConflictResolver.resolveConflicts()
   SyncMonitoringSystem.recordConflict()
        ↓
7. دمج البيانات
        ↓
8. SyncMetrics.recordSuccess()
   SyncMonitoringSystem.recordSyncSuccess()
        ↓
9. تحديث الإحصائيات
```

---

## مقارنة قبل وبعد

### قبل التحسين

```
smart_sync_manager.dart (813 سطر)
  ├── الجدولة
  ├── حل التضارب
  ├── القياسات
  ├── الإشعارات
  ├── المزامنة
  └── كل شيء آخر!
```

**المشاكل**:
- ❌ ملف ضخم جداً
- ❌ صعوبة القراءة
- ❌ صعوبة الاختبار
- ❌ صعوبة الصيانة

### بعد التحسين

```
sync_core/
  ├── base_sync_manager.dart (280 سطر)
  ├── sync_scheduler.dart (95 سطر)
  ├── conflict_resolver.dart (180 سطر)
  └── sync_metrics.dart (250 سطر)

monitoring/
  └── sync_monitoring_system.dart (350 سطر)
```

**الفوائد**:
- ✅ كل ملف < 400 سطر
- ✅ مسؤولية واحدة واضحة
- ✅ سهل القراءة
- ✅ سهل الاختبار
- ✅ سهل الصيانة

---

## التبعيات

```
BaseSyncManager
  ├─► SyncScheduler
  ├─► ConflictResolver
  ├─► SyncMetrics
  └─► GoogleDriveBackupService

SyncScheduler
  └─► (لا توجد تبعيات داخلية)

ConflictResolver
  └─► (لا توجد تبعيات داخلية)

SyncMetrics
  └─► SharedPreferences

SyncMonitoringSystem
  └─► SharedPreferences
```

---

## الأنماط المعمارية المستخدمة

### 1. Single Responsibility Principle
كل class له مسؤولية واحدة فقط.

### 2. Dependency Injection
المكونات تحقن التبعيات، لا تنشئها.

### 3. Observer Pattern
استخدام Streams للإحصائيات والتنبيهات.

### 4. Strategy Pattern
استراتيجيات مختلفة لحل التضارب.

### 5. Singleton Pattern
مديرين منفردين (instance).

---

## التوسعات المستقبلية

### إضافة استراتيجية جديدة

```dart
// إضافة في ConflictStrategy enum
enum ConflictStrategy {
  newerWins,
  devicePriority,
  manualResolve,
  lastModifiedWins, // جديد!
}

// تطبيق في ConflictResolver._selectWinner
case ConflictStrategy.lastModifiedWins:
  // المنطق هنا
```

### إضافة مصدر مزامنة جديد

1. إنشاء Strategy جديد
2. تسجيله في BaseSyncManager
3. لا حاجة لتعديل المكونات الأخرى!

---

## الخلاصة

المعمارية الجديدة:
- 🎯 **واضحة**: كل مكون له مسؤولية واحدة
- 🔧 **قابلة للصيانة**: سهل التعديل والتحديث
- 🧪 **قابلة للاختبار**: كل مكون يختبر منفصلاً
- 🚀 **قابلة للتوسع**: سهل إضافة ميزات جديدة
