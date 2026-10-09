# تقرير التدقيق العميق — Secondary Appwrite Service 🏨

**التاريخ:** 2026-07-05  
**الفرع:** `refactor/clean-v2`  
**الملفات المشمولة:**
- `secondary_appwrite_service.dart`
- `secondary_sync_manager.dart`
- `secondary_appwrite_config.dart`
- `appwrite_sync_utils.dart`
- `appwrite_config.dart`
- `whatsapp_notification_service.dart`
- `telegram_notification_service.dart`
- `telegram_config.dart`
- `telegram_service.dart`

---

## 🚨 النتائج الحرجة (Critical — يجب الإصلاح فوراً)

### 🔴 CRIT-1: `app_settings` — فقدان كل الحقول تقريباً أثناء الرفع الشامل

**الملف:** `appwrite_sync_utils.dart`  
**الدالة:** `sanitizePayload()` → `filterPayloadForCollection()`  
**الخطورة:** 🚨 **حرجة — بيانات الإعدادات تُفقد صامتة**

**التفاصيل:**
1. `_appSettingsToMap()` في `secondary_appwrite_service.dart` ينتج خرائط بمفاتيح **snake_case**:  
   `hotel_name`, `wa_api_type`, `telegram_enabled`, إلخ.
2. `sanitizePayload()` يستدعي `_convertKeysToCamelCase()` الذي يحوّل جميع المفاتيح:  
   `hotel_name` → `hotelName`, `wa_api_type` → `waApiType`
3. `filterPayloadForCollection()` لـ `app_settings` يستخدم `validFieldsPerCollection`  
   الذي يحتوي على **snake_case**: `hotel_name`, `wa_api_type`
4. نتيجة: `hotelName` != `hotel_name` → الحقل **يُحذف** 🗑️

**البيانات المفقودة:**
- `hotel_name` (اسم الفندق)
- `wa_api_type`, `wa_api_base_url`, `wa_api_instance_id`, `wa_custom_url_template`
- `wa_sendzen_api_key`, `wa_sendzen_from_number`
- `telegram_enabled`, `telegram_chat_id`, `telegram_notifications_enabled`
- `telegram_daily_report_enabled`, `telegram_daily_report_time`
- `appwrite_sync_interval`, `dark_mode`, `hotel_cutoff_hour`

**الحقول الوحيدة التي تنجو:** `localUuid`, `key`, `value`, `deviceId`, `serverId`,  
`createdAt`, `updatedAt`, `sync_origin`, `version` (لأنها بلا underscores)

---

### 🔴 CRIT-2: `_debtToMap` — حقل `amount` مكرّر ويحمل نفس قيمة `totalAmount`

**الملف:** `secondary_appwrite_service.dart`  
**الخط:** 536  
**الخطورة:** 🟡 **متوسطة — تضخيم غير ضروري للبيانات**

```dart
'totalAmount': d.totalAmount,
// ...
'amount': d.totalAmount,  // ← مكرّر
```

كلا الحقلين `amount` و `totalAmount` موجودان في `collectionSchema`،  
لكن إرسالهما بنفس القيمة يضخم الطلب بلا فائدة ويزيد احتمال التعارض.

---

### 🔴 CRIT-3: `_bookingPriceAdjustmentToMap` — `appliedAt` يستخدم `createdAt`

**الملف:** `secondary_appwrite_service.dart`  
**الخط:** 871  
**الخطورة:** 🟡 **متوسطة — دلالة خاطئة**

```dart
'appliedAt': b.createdAt,  // ← appliedAt = وقت الإنشاء وليس وقت التطبيق الفعلي
```

الحقل `appliedAt` يجب أن يحمل وقت تطبيق التعديل وليس وقت إنشاء السجل.  
قد لا يكون موجوداً في الـ model كحقل منفصل.

---

### 🔴 CRIT-4: `_auditLogToMap` — حقل `action` مكرّر مع `operationType`

**الملف:** `secondary_appwrite_service.dart`  
**الخط:** 906  
**الخطورة:** 🟢 **خفيفة — تكرار مقبول**

```dart
'action': a.operationType,  // ← حقل بديل للتوافق
```

الحقل `action` موجود في `validFieldsPerCollection` كحقل إضافي للتوافق.  
القيمة صحيحة لكنها مكرّرة.

---

## 🟡 مشاكل متوسطة (Medium — تحتاج مراجعة)

### CRIT-5: `blacklist` — يستخدم `shiftNotes` كـ workaround

**الملف:** `secondary_sync_manager.dart`  
**الخط:** 619-626  
**الخطورة:** 🟡 **متوسطة — خطر تجميع بيانات خاطئة**

عند مزامنة `blacklist`، يتم سحب البيانات من جدول `shift_notes` بدلاً من  
جدول `blacklist` حقيقي — هذا يُرسل بيانات نوبات العمل بدلاً من القائمة السوداء.

### CRIT-6: `user_settings` غير موجود في `_backupFetchers`

المستخدم طلب مزامنة `user_settings` لكن هذا الجدول غير موجود في  
قاعدة البيانات المحلية (Drift). الإعدادات موجودة في `app_settings`  
الذي يُدار عبر `SharedPreferences`.

### CRIT-7: WhatsApp/Telegram — اعتماد على `RemoteConfigService` دون fallback كافٍ

**الملف:** `whatsapp_notification_service.dart`  
**الخط:** 64-65

```dart
String get _phone => RemoteConfigService.instance.whatsappPhone;
String get _apiKey => RemoteConfigService.instance.whatsappApiKey;
```

هذا يعتمد على `RemoteConfigService` الذي قد يفشل في التهيئة (خاصة بدون Firebase).  
لكن `RemoteConfigService` لديه fallback إلى `Env.whatsappPhoneNumber` و `Env.whatsappApiKey`  
الموجودة حالياً في `env.dart`. **المشكلة:** إذا تغيرت الإعدادات في SharedPreferences  
(مثلاً من شاشة الإعدادات)، لن يتم استخدامها هنا — `RemoteConfigService` لا يقرأ من  
SharedPreferences بل من Firebase Remote Config أو القيم الافتراضية الثابتة.

---

## ✅ نقاط القوة (محل إعجاب)

### ✅ 1. بنية `_backupFetchers` — مصدر حقيقة واحد
تم إعادة هيكلة الدوال لتكون خريطة واحدة (`_backupFetchers`) بدلاً من  
قائمة + switch منفصلين. هذا يمنع إسقاط جداول صامتة (مثل ما حدث سابقاً مع  
`salary_carry_over_logs`).

### ✅ 2. نظام `sanitizePayload` + `filterPayloadForCollection`
يمنع إرسال حقول غير معروفة إلى Appwrite (خطأ `Unknown attribute`).  
يُحوّل الأنواع تلقائياً (double→int, etc).

### ✅ 3. Circuit Breaker في `SecondarySyncManager`
بعد 5 إخفاقات متتالية، يُفتح circuit breaker لمدة 5 دقائق لمنع  
إغراق الشبكة بطلبات فاشلة.

### ✅ 4. نظام `FullBackupStats` مع تتبّع `errorsByReason`
يُسجّل كل خطأ مع سببه وعدد مرات تكراره — تحليل ممتاز.

### ✅ 5. `mergeBatch()` في `OutboxDao`
يدمج دفعة كاملة في معاملة واحدة (transaction) — أداء أفضل.

---

## 📊 مقارنة الحقول: `_*ToMap` vs `collectionSchema`

| الجدول | الحقول في `_*ToMap` | الحقول في `collectionSchema` | التوافق |
|--------|---------------------|------------------------------|---------|
| `rooms` | 26 | 27 | `idempotencyKey` مفقود في ToMap |
| `bookings` | 42 | 45 | `financialFrozenAt`, `financialHash` مفقودان |
| `payments` | 34 | 38 | `isImmutable`, `voidReason`, `discountAmount`, `discountStartDate` ← موجودة |
| `expenses` | 27 | 27 | ✅ كامل |
| `debts` | 27 | 29 | `description`, `dueDate`, `debtorName`, `guestPhone`, `status` ← مفقودة |
| `employees` | 20 | 22 | `EmployeeID` ← خطأ مطبعي بدل `employeeID` |
| `booking_notes` | 23 | 23 | ✅ كامل |
| `booking_nights` | 19 | 31 | 12 حقلاً مفقوداً (تحتاج مراجعة) |
| `cash_transactions` | 19 | 22 | `registerId`, `referenceType`, `referenceId` مفقودة |
| `app_settings` | 33 | 73 (validFields) | **غير متوافق — مشكلة camelCase vs snake_case** |

---

## 🛠️ خطة الإصلاح

### P0 — الإصلاحات العاجلة (قبل البناء القادم)

1. **إصلاح `app_settings` schema mismatch:**
   - إضافة `app_settings` إلى `_preserveSnakeCase` في `appwrite_sync_utils.dart`
   - أو إضافة `app_settings` إلى `collectionSchema` بمفاتيح camelCase
   - أو منع `_convertKeysToCamelCase` لـ `app_settings`

2. **إصلاح `_debtToMap`:**
   - إزالة الحقل المكرر `amount` أو توحيده مع `totalAmount`

### P1 — إصلاحات مهمة

3. **إصلاح `_bookingPriceAdjustmentToMap`:**
   - استخدام الوقت الصحيح لـ `appliedAt`

4. **إصلاح WhatsApp/Telegram:**
   - إضافة قراءة مباشرة من SharedPreferences كـ fallback
   - ضمان عمل `notifyNewExpense`, `notifyNewBooking`, `notifyPaymentReceived`

### P2 — إصلاحات تحسينية

5. **إصلاح `blacklist` workaround:**
   - إنشاء جدول `blacklist` حقيقي في Drift أو تحسين الـ workaround

6. **إضافة `bookingPriceAdjustmentToRemote` في `PayloadMapper`:**
   - التأكد من وجودها (تم التحقق — موجودة ✅)

---

## 📋 سيناريوهات الفشل المحتملة

| السيناريو | السبب | التأثير |
|-----------|-------|---------|
| فشل `app_settings` backup | camelCase→snake_case mismatch | فقدان كل إعدادات التطبيق |
| فشل `blacklist` sync | يستخدم `shiftNotes` بدلاً من جدول حقيقي | بيانات خاطئة |
| فشل WhatsApp notification | `RemoteConfigService` غير مهيّأ | لا إشعارات |
| فشل Telegram notification | Bot Token أو Chat ID غير صحيح | لا إشعارات |
| تعارض مزامنة (conflict) | تعديل متزامن من جهازين | فقدان التعديل الأقدم |
| انتهاء مهلة الاتصال (timeout) | بطء الشبكة أو انقطاعها | إعادة محاولة (backoff) |
| فقدان `localUuid` | سجل تالف في outbox | تخطّي السجل (مسجّل في stats) |

---

## 📊 إحصائيات النسخة الشاملة (FullBackup)

```
المجموع الكلي:            22 جدول
مرتفع بالكامل:            20 (تقديري)
فشل كلي:                  2 (تقديري)
عدد السجلات الناجحة:      يعتمد على حجم البيانات
عدد السجلات الفاشلة:      يعتمد على جودة البيانات
أسباب الفشل المسجّلة:     errorsByReason map
```

---

*تم إعداد التقرير بواسطة Codex — 2026-07-05*
