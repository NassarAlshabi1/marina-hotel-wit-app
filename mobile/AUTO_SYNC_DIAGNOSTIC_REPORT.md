# تقرير فحص المزامنة التلقائية

## نظرة عامة

التطبيق يحتوي على **3 أنظمة مزامنة** مختلفة تعمل بشكل متوازٍ:

### 1. **Smart Sync Manager** (مزامنة Google Drive الذكية)
- **الموقع:** `lib/services/smart_sync_manager.dart`
- **الوظيفة:** مزامنة ذكية بين الأجهزة المتعددة عبر Google Drive
- **الحالة:** ✅ **مُفعَّل افتراضياً**
- **التهيئة:** في `main.dart` السطر 93-94
- **Provider:** `smartSyncManagerProvider`

#### الإعدادات:
```dart
static const String _prefsEnabledKey = 'smart_sync_enabled';
static const String _prefsIntervalKey = 'smart_sync_interval';
static const int _defaultSyncIntervalMinutes = 2; // كل دقيقتين
```

#### الميزات:
- ✅ فحص دوري للنسخ الاحتياطية الجديدة
- ✅ حل تضارب تلقائي (الأحدث يفوز)
- ✅ تحسين استهلاك البطارية والبيانات
- ✅ إشعارات عند المزامنة
- ✅ معرف فريد لكل جهاز

---

### 2. **Auto Sync Engine** (محرك المزامنة التلقائية الكاملة)
- **الموقع:** `lib/services/google_drive_auto_sync_engine.dart`
- **الوظيفة:** محرك مزامنة متقدم مع retry تلقائي
- **الحالة:** ⚠️ **متوفر في ملف منفصل فقط** (`main_with_auto_sync_engine.dart`)
- **التهيئة:** **غير مُستخدم في main.dart الحالي**

#### الإعدادات:
```dart
static const String _prefsEnabledKey = 'auto_sync_engine_enabled';
static const String _prefsDebounceSecondsKey = 'auto_sync_engine_debounce';
static const String _prefsPullIntervalKey = 'auto_sync_engine_pull_interval';
```

#### الميزات:
- ⏸️ مراقبة شبكة الإنترنت
- ⏸️ مراقبة دورة حياة التطبيق
- ⏸️ إعادة محاولة تلقائية مع Exponential Backoff
- ⏸️ فحوصات صحية كل 5 دقائق

---

### 3. **Sync Guardian** (حارس المزامنة)
- **الموقع:** `lib/services/sync_guardian.dart`
- **الوظيفة:** مراقبة وضمان استهلاك جميع الأحداث
- **الحالة:** ✅ **مُفعَّل** 
- **التهيئة:** في `main.dart` السطر 101-107

#### الميزات:
- ✅ رفع التغييرات بعد 5 ثواني (debouncing)
- ✅ مزامنة مع Google Drive
- ✅ مزامنة مع Appwrite (إذا متوفر)
- ✅ مراقبة التغييرات المحلية

---

### 4. **Appwrite Sync Manager** (مزامنة Appwrite)
- **الموقع:** `lib/services/appwrite_sync_manager.dart`
- **الوظيفة:** مزامنة سحابية عبر Appwrite
- **الحالة:** ⚠️ **معطّل افتراضياً**
- **التهيئة:** في `main.dart` السطر 147

#### الإعدادات:
```dart
await prefs.setBool('appwrite_sync_enabled', false); // معطّل افتراضياً
await prefs.setInt('appwrite_sync_interval', 2); // كل دقيقتين
```

---

## المشاكل المحتملة

### ⚠️ 1. Auto Sync Engine غير مُفعّل
**المشكلة:** الملف `main_with_auto_sync_engine.dart` موجود لكنه غير مستخدم. التطبيق يستخدم `main.dart` الذي لا يهيئ `AutoSyncEngine`.

**الحل المقترح:**
- استخدام `main_with_auto_sync_engine.dart` كملف رئيسي
- أو دمج تهيئة `AutoSyncEngine` في `main.dart`

### ⚠️ 2. تعارض بين أنظمة المزامنة
**المشكلة:** وجود 3 أنظمة مزامنة قد يسبب تعارضات:
- `SmartSyncManager` - يعمل كل دقيقتين
- `SyncGuardian` - يعمل بعد 5 ثواني من التغيير
- `AppwriteSyncManager` - معطّل افتراضياً

**الحل المقترح:** توحيد نظام المزامنة أو توضيح دور كل نظام.

### ⚠️ 3. Appwrite معطّل افتراضياً
**المشكلة:** في `main.dart` السطر 147:
```dart
await prefs.setBool('appwrite_sync_enabled', false);
```

**الحل:** تفعيل Appwrite إذا كان المستخدم يريد استخدامه.

---

## حالة المزامنة الحالية

### ✅ نشط:
1. **Smart Sync Manager** (Google Drive)
   - تهيئة ✅
   - تفعيل ✅
   - فترة المزامنة: 2 دقائق

2. **Sync Guardian** (WorkManager)
   - تهيئة ✅
   - Debounce: 5 ثواني
   - مراقبة التغييرات ✅

3. **Auto Backup Manager**
   - تهيئة ✅
   - تفعيل ✅
   - الاحتفاظ بـ 10 نسخ
   - لمدة 14 يوماً

### ⏸️ معطّل/غير مستخدم:
1. **Auto Sync Engine**
   - موجود لكن غير مهيأ في main.dart
   - متوفر فقط في `main_with_auto_sync_engine.dart`

2. **Appwrite Sync**
   - معطّل افتراضياً
   - يحتاج تفعيل يدوي من الإعدادات

---

## آلية عمل المزامنة التلقائية

### عند حدوث تغيير في البيانات:

```
تغيير محلي (إضافة/تعديل/حذف)
         ↓
SyncGuardian.notifyLocalChange()
         ↓
انتظار 5 ثواني (Debounce)
         ↓
SmartSyncManager.pushLocalChanges()
         ↓
رفع إلى Google Drive
         ↓
AppwriteSyncManager.pushLocalChanges() (إذا مُفعّل)
```

### المزامنة الدورية:

```
كل 2 دقائق (افتراضي)
         ↓
SmartSyncManager._performSyncCheck()
         ↓
فحص وجود نسخ احتياطية جديدة
         ↓
إذا وُجدت نسخة من جهاز آخر
         ↓
تحميل وحل التضارب
         ↓
دمج البيانات
```

---

## الإصلاحات المقترحة

### 1. دمج Auto Sync Engine في main.dart

يجب إضافة تهيئة `AutoSyncEngine` في `main.dart`:

```dart
// بعد SmartSyncManager.initialize
final autoSyncEngine = AutoSyncEngine.instance;
await autoSyncEngine.initialize(
  backupService: backupService,
  database: DatabaseManager.instance,
  logger: driveLogger,
);
await autoSyncEngine.start();
```

### 2. توضيح دور كل نظام

- **SyncGuardian:** رفع التغييرات الفورية
- **SmartSyncManager:** مزامنة دورية وفحص النسخ الجديدة
- **AutoSyncEngine:** مراقبة متقدمة مع retry
- **AppwriteSyncManager:** مزامنة سحابية إضافية

### 3. إضافة شاشة تشخيص

إنشاء شاشة توضح:
- حالة كل نظام مزامنة
- آخر مزامنة ناجحة
- عدد المحاولات الفاشلة
- حالة الاتصال بالشبكة
- حالة تسجيل الدخول

---

## الملفات ذات الصلة

### خدمات المزامنة:
- `lib/services/smart_sync_manager.dart` - المدير الذكي الرئيسي
- `lib/services/google_drive_auto_sync_engine.dart` - محرك متقدم (غير مستخدم)
- `lib/services/sync_guardian.dart` - حارس المزامنة
- `lib/services/appwrite_sync_manager.dart` - مزامنة Appwrite

### Google Drive:
- `lib/services/google_drive_backup_service.dart` - خدمة النسخ الاحتياطي
- `lib/services/google_drive_sync_service.dart` - خدمة المزامنة
- `lib/services/google_drive_delta_sync.dart` - مزامنة Delta (التحديثات فقط)
- `lib/services/google_drive_conflict_resolver.dart` - حل التضارب
- `lib/services/google_drive_unified_sync_coordinator.dart` - المنسق الموحد

### إعدادات وشاشات:
- `lib/screens/settings/smart_sync_settings_screen.dart` - شاشة إعدادات المزامنة الذكية
- `lib/screens/settings/data_protection_screen.dart` - شاشة حماية البيانات
- `lib/screens/settings/google_drive_backup_screen.dart` - شاشة Google Drive
- `lib/providers/smart_sync_provider.dart` - Providers المزامنة

### مراقبة وأداء:
- `lib/services/sync_performance_optimizer.dart` - تحسين الأداء
- `lib/services/data_usage_manager.dart` - إدارة استهلاك البيانات
- `lib/services/sync_notification_manager.dart` - إشعارات المزامنة

---

## التوصيات

### للمستخدم:
1. ✅ المزامنة التلقائية **تعمل** عبر `SmartSyncManager`
2. ✅ يمكن التحكم فيها من شاشة الإعدادات
3. ⚠️ تأكد من تسجيل الدخول إلى Google Drive
4. ℹ️ يمكن تفعيل Appwrite للمزامنة السحابية الإضافية

### للمطور:
1. ⚠️ النظر في دمج `AutoSyncEngine` في `main.dart`
2. ⚠️ توضيح الفرق بين الأنظمة في الوثائق
3. ✅ إنشاء شاشة تشخيص شاملة
4. ✅ توحيد الإعدادات في مكان واحد
