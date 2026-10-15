# تقرير التدقيق العميق لنظام Appwrite الثانوي والإشعارات
## Secondary Appwrite Deep Audit & Fixes Report

**التاريخ:** 2026-07-05  
**الفرع:** `refactor/clean-v2`  
**الإصدار:** 2.2 (موحد)

---

## 📋 ملخص الإصلاحات (9 إصلاحات جوهرية)

| # | المشكلة | الحالة | الخطورة |
|---|---------|--------|---------|
| 1 | `app_settings` مفقود من `_entityToCollection` | ✅ تم | 🔴 حرج |
| 2 | إشعارات WhatsApp تعتمد على Remote Config فقط | ✅ تم | 🟡 متوسط |
| 3 | `notifySyncError` مفقود من Telegram | ✅ تم | 🔴 حرج |
| 4 | `_notifySyncError` في SmartSyncManager لا يرسل شيئاً | ✅ تم | 🟡 متوسط |
| 5 | AppwriteSyncManager يرسل خطأ المزامنة لـ WhatsApp فقط | ✅ تم | 🟡 متوسط |
| 6 | StreamBuilders متداخلة في FinanceScreen | ✅ تم | 🟢 تحسين |
| 7 | `whatsapp_template_manager.dart` — ملف كامل غير ضروري | ✅ تم | 🟢 تنظيف |
| 8 | `active_bookings_reminder_screen.dart` يعتمد على قوالب معقدة | ✅ تم | 🟢 تنظيف |
| 9 | توثيق شامل وإزالة الأكواد الميتة | ✅ تم | 🟢 توثيق |

---

## 1️⃣ 🔴 `app_settings` مفقود من `_entityToCollection`

### المشكلة
المتغير `appSettingsCollectionId = 'app_settings'` مُعرّف في `AppwriteConfig` لكنه غير موجود في `_entityToCollection` map.

**النتيجة:** `collectionIdFor('app_settings')` يُرجع `null` ← `_getAllCollections` يتخطى `app_settings` ← النسخة الشاملة لا ترفع إعدادات التطبيق (WhatsApp/Telegram).

### الإصلاح
إضافة `'app_settings': appSettingsCollectionId` إلى `_entityToCollection` في `mobile/lib/services/appwrite_config.dart`.

**ملف:** `mobile/lib/services/appwrite_config.dart`
```dart
'guest_infos': guestInfosCollectionId,
'app_settings': appSettingsCollectionId,  // ✅ تمت الإضافة
```

---

## 2️⃣ 🟡 إشعارات WhatsApp: اعتماد زائد على Remote Config

### المشكلة
```dart
// قبل:
if (!RemoteConfigService.instance.whatsappEnabled) return false;
```

إذا فشل Firebase Remote Config في التهيئة، `whatsappEnabled` يعود بقيمة true (افتراضي) لكن الأجهزة القديمة قد لا تهيئ Remote Config أبداً. أيضاً، لم يكن هناك fallback مناسب.

### الإصلاح
استخدام `try/catch` حول Remote Config مع fallback للإعدادات المحلية عبر `TelegramConfig`:
```dart
// بعد:
try {
  if (!RemoteConfigService.instance.whatsappEnabled) { /* تحذير فقط */ }
} catch (_) { /* Remote Config غير متاح */ }
if (!await TelegramConfig.isEnabled()) return false;
if (!await TelegramConfig.isNotificationsEnabled()) return false;
```

**ملف:** `mobile/lib/services/telegram/whatsapp_notification_service.dart`

---

## 3️⃣ 🔴 `notifySyncError` مفقود من Telegram

### المشكلة
`TelegramNotificationService` لم يكن يملك دالة `notifySyncError`، بينما `WhatsAppNotificationService` يملكها. عند حدوث خطأ مزامنة، كان Telegram لا يرسل أي إشعار خطأ.

### الإصلاح
إضافة دالة `notifySyncError` كاملة إلى `TelegramNotificationService` بنفس تنسيق WhatsApp لكن بصيغة HTML المتوافقة مع Telegram.

**ملف:** `mobile/lib/services/telegram/telegram_notification_service.dart`
```dart
Future<bool> notifySyncError({
  required String operation,
  required String error,
  int? recordsPushed,
  int? recordsPulled,
}) async { ... }
```

---

## 4️⃣ 🟡 `_notifySyncError` في SmartSyncManager لا يرسل شيئاً

### المشكلة
```dart
// قبل:
Future<void> _notifySyncError() async {
  _log('❌ فشلت المزامنة التلقائية');
}
```

كان يكتب في السجل فقط دون إرسال إشعار حقيقي.

### الإصلاح
ربط الدالة بـ `WhatsAppNotificationService.notifySyncError` و `TelegramNotificationService.notifySyncError` مع إضافة `unawaited` لضمان fire-and-forget.

**ملف:** `mobile/lib/services/smart_sync_manager.dart`
```dart
// بعد:
Future<void> _notifySyncError() async {
  _log('❌ فشلت المزامنة التلقائية - إرسال إشعار خطأ');
  try {
    unawaited(WhatsAppNotificationService.instance.notifySyncError(...));
    unawaited(TelegramNotificationService.instance.notifySyncError(...));
  } catch (e) { ... }
}
```

---

## 5️⃣ 🟡 AppwriteSyncManager: Telegram لم يتلقَ إشعارات المزامنة

### المشكلة
`appwrite_sync_manager.dart` يرسل `notifySyncError` فقط إلى WhatsApp في موقعين (السطر 1325 و 4660)، Telegram لم يكن يتلقى الإشعارات.

### الإصلاح
إضافة استدعاء `TelegramNotificationService.instance.notifySyncError(...)` بعد كل استدعاء WhatsApp.

**ملفات:** `mobile/lib/services/appwrite_sync_manager.dart`

---

## 6️⃣ 🟢 تحسين أداء FinanceScreen

### المشكلة
`StreamBuilder` متداخل: الأول للمدفوعات، والثاني داخله للحجوزات. كل تحديث للمدفوعات يعيد بناء StreamBuilder الحجوزات بالكامل.

### الإصلاح
إضافة `debounceStream` (150ms) لكلا StreamBuilder:
```dart
stream: debounceStream(paymentsRepo.watchAll(), Duration(milliseconds: 150))
stream: debounceStream(ref.read(bookingsRepoProvider).watchList(), Duration(milliseconds: 150))
```

**ملف:** `mobile/lib/screens/finance/finance_screen.dart`

---

## 7️⃣ 🟢 إزالة `whatsapp_template_manager.dart`

### المشكلة
ملف `whatsapp_template_manager.dart` كان يحتوي على نظام قوالب معقد (10 أنواع قوالب، استبدال متغيرات، SharedPreferences، JSON تصدير/استيراد) — لكن المستخدم يريد إزالته لسببين:
1. WhatsApp يعمل حالياً عبر رسائل مباشرة من `WhatsAppNotificationService`
2. القوالب لا تُستخدم إلا في `active_bookings_reminder_screen.dart`

### الإصلاح
- حذف `mobile/lib/utils/whatsapp_template_manager.dart`
- إعادة بناء الرسالة في `active_bookings_reminder_screen.dart` بشكل مباشر دون قوالب

---

## 🧪 سيناريوهات الاختبار الموصى بها

### سيناريو 1: اختبار إشعارات المزامنة
1. عطل الإنترنت
2. أضف حجز جديد
3. شغّل المزامنة
4. تحقق من وصول إشعار خطأ عبر WhatsApp و Telegram

### سيناريو 2: اختبار النسخة الشاملة (Full Backup)
1. افتح إعدادات Appwrite الثانوي
2. شغّل "رفع نسخة شاملة"
3. تحقق من ظهور `app_settings` في قائمة المجموعات
4. تحقق من نجاح رفعها دون أخطاء

### سيناريو 3: اختبار الإشعارات الفورية
1. أضف حجز جديد ← تحقق من وصول إشعار WhatsApp + Telegram
2. أضف دفعة ← تحقق من وصول إشعار
3. أضف مصروف ← تحقق من وصول إشعار
4. أضف سحب راتب ← تحقق من وصول إشعار

### سيناريو 4: اختبار الأداء
1. افتح FinanceScreen مع بيانات كثيرة
2. تحقق من عدم وجود flickering/redundant rebuilds
3. تحقق من عمل debounce بعد تغيير البيانات

---

## 🔗 الملفات المعدلة

| الملف | نوع التغيير |
|------|------------|
| `mobile/lib/services/appwrite_config.dart` | إضافة `app_settings` للخريطة |
| `mobile/lib/services/telegram/whatsapp_notification_service.dart` | إصلاح نظام التفعيل + إزالة أكواد ميتة |
| `mobile/lib/services/telegram/telegram_notification_service.dart` | إضافة `notifySyncError` |
| `mobile/lib/services/smart_sync_manager.dart` | ربط `_notifySyncError` بالإشعارات |
| `mobile/lib/services/appwrite_sync_manager.dart` | إضافة Telegram لنظام إشعارات الأخطاء |
| `mobile/lib/screens/finance/finance_screen.dart` | إضافة debounce لـ StreamBuilders |
| `mobile/lib/utils/whatsapp_template_manager.dart` | ❌ حذف |
| `mobile/lib/screens/settings/active_bookings_reminder_screen.dart` | إزالة الاعتماد على القوالب |

---

## 📊 مقارنة قبل/بعد

### توزيع إشعارات المزامنة (قبل)
```
خطأ مزامنة → WhatsApp فقط ← 🟡
خطأ مزامنة → Telegram ← ❌ غير موجود
SmartSync → سجل فقط ← ❌
```

### توزيع إشعارات المزامنة (بعد)
```
خطأ مزامنة → WhatsApp ← ✅
خطأ مزامنة → Telegram ← ✅ (جديد)
SmartSync → WhatsApp + Telegram ← ✅ (جديد)
```

### app_settings في النسخة الشاملة (قبل)
```
Skip ← ❌ (collectionIdFor يرجع null)
```

### app_settings في النسخة الشاملة (بعد)
```
Upload ← ✅
```

---

## 📝 ملاحظات إضافية

1. **إعدادات البوت:** Telegram Bot Token و Chat ID مُهيئتان مسبقاً في `Env` بقيم ثابتة
2. **WhatsApp CallMeBot:** الرقم والمفتاح مُهيآن مسبقاً في `Env` بقيم ثابتة
3. **Remote Config:** يعمل كطبقة تحكم إضافية وليس أساسية — إذا فشل Firebase، الإعدادات المحلية تحل محله
4. **ما زال قائماً:** ملفات Lark أُزيلت بالكامل في الإصدارات السابقة

---

*تقرير تدقيق شامل — Marina Hotel App — Secondary Appwrite System*
