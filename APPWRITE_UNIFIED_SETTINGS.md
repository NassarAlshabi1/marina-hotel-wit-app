# توحيد إعدادات Appwrite - وثائق شاملة

## 1. ملخص الوضع الحالي

تم العثور على **موقعين منفصلين** لإعدادات Appwrite في التطبيق:

### الموقع الأول: `AppwriteConnectionSettingsScreen`
**المسار:** `mobile/lib/screens/settings/appwrite_connection_settings_screen.dart`

يحتوي على:
- تعديل `Endpoint URL`
- تعديل `Project ID`
- تعديل `Database ID`
- تعديل `API Key`
- زر اختبار الاتصال
- زر إعادة تعيين الإعدادات

### الموقع الثاني: `AppwriteSettingsScreenV2` (مع 4 تبويبات)
**المسار:** `mobile/lib/screens/settings/appwrite/appwrite_settings_screen_v2.dart`

يحتوي على 4 تبويبات:
1. **الاتصال (ConnectionTab):** عرض معلومات الاتصال وحالته
2. **المزامنة (SyncTab):** إعدادات المزامنة والـ Cache
3. **الأجهزة (DevicesTab):** إدارة الأجهزة المتصلة
4. **الأدوات (ToolsTab):** أدوات الاختبار والصيانة

---

## 2. الجداول والحقول المزامنة مع Appwrite

### 2.1 قائمة الجداول الكاملة (17 جدول)

| # | اسم الجدول | الوصف | النوع |
|---|-----------|-------|-------|
| 1 | `rooms` | الغرف الفندقية | بيانات أساسية |
| 2 | `bookings` | الحجوزات | بيانات أساسية |
| 3 | `booking_notes` | ملاحظات الحجوزات | بيانات مساعدة |
| 4 | `booking_nights` | ليالي الحجوزات | بيانات مساعدة |
| 5 | `payments` | المدفوعات | بيانات مالية |
| 6 | `expenses` | المصروفات | بيانات مالية |
| 7 | `cash_transactions` | المعاملات النقدية | بيانات مالية |
| 8 | `debts` | الديون | بيانات مالية |
| 9 | `employees` | الموظفون | بيانات الموارد البشرية |
| 10 | `salary_cycles` | دورات الرواتب | بيانات الموارد البشرية |
| 11 | `salary_payments` | دفعات الرواتب | بيانات الموارد البشرية |
| 12 | `hotel_day_ledger` | دفتر اليومية | بيانات محاسبية |
| 13 | `shift_notes` | ملاحظات النوبة | بيانات تشغيلية |
| 14 | `price_adjustments` | تعديلات الأسعار | بيانات التسعير |
| 15 | `booking_price_adjustments` | تعديلات أسعار الحجوزات | بيانات التسعير |
| 16 | `audit_logs` | سجلات التدقيق | بيانات الأمان |
| 17 | `payment_voids` | إلغاءات الدفع | بيانات مالية |

### 2.2 الحقول المزامنة

**جميع الحقول** الموجودة في كل جدول يتم مزامنتها مع Appwrite، باستثناء:

**الحقول المستثناة (لا يتم رفعها):**
- `$id` - معرف Appwrite التلقائي
- `$createdAt` - تاريخ الإنشاء (Appwrite)
- `$updatedAt` - تاريخ التحديث (Appwrite)
- `$permissions` - الصلاحيات (Appwrite)
- `$collectionId` - معرف المجموعة (Appwrite)
- `$databaseId` - معرف قاعدة البيانات (Appwrite)
- `id` - معرف Drift/SQLite المحلي

---

## 3. إعدادات Appwrite المركزية

### 3.1 البيانات الثابتة (من `AppwriteConfig`)

```dart
// نقطة النهاية
static const String endpoint = 'https://fra.cloud.appwrite.io/v1';

// معرفات المشروع والقاعدة
static const String projectId = '690ff0da0025518570c1';
static const String databaseId = 'hotel_db';
```

### 3.2 البيانات الديناميكية (من `AppwriteConfigManager`)

يتم حفظها في `SharedPreferences` ويمكن تغييرها:
- `appwrite_endpoint` - نقطة النهاية
- `appwrite_project_id` - معرف المشروع
- `appwrite_database_id` - معرف قاعدة البيانات
- `appwrite_api_key` - مفتاح API

### 3.3 إعدادات المزامنة

| الإعداد | القيمة | الوصف |
|--------|--------|-------|
| `syncInterval` | 15 دقيقة | الفاصل الزمني للمزامنة التلقائية |
| `cacheExpiry` | 6 ساعات | مدة صلاحية الـ Cache |
| `maxCacheSizeMB` | 20 MB | الحد الأقصى لحجم الـ Cache |
| `maxRetries` | 3 | عدد محاولات إعادة المحاولة |
| `initialRetryDelay` | 2 ثانية | التأخير الأولي لإعادة المحاولة |
| `retryBackoffMultiplier` | 2.0 | معامل Exponential Backoff |
| `defaultTimeout` | 30 ثانية | مهلة الاتصال الافتراضية |
| `longTimeout` | 2 دقيقة | مهلة الاتصال للعمليات الكبيرة |
| `defaultPageSize` | 25 | عدد السجلات في كل صفحة |
| `maxPageSize` | 100 | الحد الأقصى للسجلات |
| `batchSize` | 50 | عدد السجلات في كل دفعة |

---

## 4. إعدادات المزامنة الديناميكية

يتم حفظها في `SharedPreferences`:

| المفتاح | النوع | الوصف |
|--------|-------|-------|
| `appwrite_sync_enabled` | bool | تفعيل/تعطيل المزامنة التلقائية |
| `appwrite_sync_interval` | int | فاصل المزامنة بالدقائق |
| `appwrite_auto_sync_on_connect` | bool | المزامنة التلقائية عند الاتصال |
| `appwrite_cache_enabled` | bool | تفعيل/تعطيل الـ Cache |

---

## 5. الخطة الموصى بها للتوحيد

### المرحلة 1: دمج الشاشتين
- نقل جميع حقول الاتصال من `AppwriteConnectionSettingsScreen` إلى تبويب الاتصال في `AppwriteSettingsScreenV2`
- إزالة `AppwriteConnectionSettingsScreen` القديمة

### المرحلة 2: إضافة تبويب جديد للجداول
- إضافة تبويب خامس **"الجداول والحقول"** يعرض:
  - قائمة الجداول المزامنة (17 جدول)
  - عدد السجلات في كل جدول
  - حالة المزامنة لكل جدول
  - خيارات لتفعيل/تعطيل مزامنة جداول معينة

### المرحلة 3: تحسين واجهة المستخدم
- إضافة رسوم بيانية لإحصائيات المزامنة
- عرض تفاصيل الحقول لكل جدول
- إضافة خيارات متقدمة لإدارة الجداول

---

## 6. ملفات التنفيذ الحالية

### الملفات الرئيسية:
1. `mobile/lib/services/appwrite_config.dart` - الإعدادات الثابتة
2. `mobile/lib/services/appwrite_config_manager.dart` - إدارة الإعدادات الديناميكية
3. `mobile/lib/screens/settings/appwrite_connection_settings_screen.dart` - شاشة الاتصال القديمة
4. `mobile/lib/screens/settings/appwrite/appwrite_settings_screen_v2.dart` - الشاشة الجديدة
5. `mobile/lib/screens/settings/appwrite/tabs/connection_tab.dart` - تبويب الاتصال
6. `mobile/lib/screens/settings/appwrite/tabs/sync_tab.dart` - تبويب المزامنة
7. `mobile/lib/screens/settings/appwrite/tabs/devices_tab.dart` - تبويب الأجهزة
8. `mobile/lib/screens/settings/appwrite/tabs/tools_tab.dart` - تبويب الأدوات

### الملفات المساعدة:
- `mobile/lib/services/comprehensive_appwrite_backup_service.dart` - خدمة النسخ الاحتياطي
- `mobile/lib/services/appwrite_service.dart` - خدمة Appwrite الرئيسية
- `mobile/lib/services/local_db.dart` - قاعدة البيانات المحلية

---

## 7. توصيات للتطبيق

### 7.1 ضمان توافق الحقول
- تحديث `AppwriteConfig` بقائمة شاملة للحقول المتوقعة لكل جدول
- إضافة validation للحقول عند الرفع إلى Appwrite

### 7.2 تحسين المزامنة
- إضافة خيار لاختيار الجداول المراد مزامنتها
- عرض تقارير تفصيلية عن حالة المزامنة
- إضافة خيار للمزامنة الانتقائية (Selective Sync)

### 7.3 تحسين الأمان
- تشفير `API Key` عند التخزين
- إضافة خيار لتعطيل الـ API Key المكشوف
- تسجيل جميع محاولات الوصول إلى الإعدادات

---

## 8. ملاحظات مهمة

1. **الإعدادات الحالية متناثرة:** توجد في موقعين منفصلين يحتاج توحيدهما
2. **الجداول كاملة:** جميع 17 جدول يتم مزامنتها حالياً
3. **الحقول ديناميكية:** يتم مزامنة جميع الحقول باستثناء الحقول المحجوزة
4. **المزامنة قابلة للتخصيص:** يمكن تفعيل/تعطيل المزامنة التلقائية
5. **النسخ الاحتياطي متكامل:** يتم نسخ جميع الجداول احتياطياً واستعادتها

