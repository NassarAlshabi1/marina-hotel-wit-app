# 📋 تقرير مزامنة جدول App Settings - Appwrite Cloud

**تاريخ التقرير:** 2026-06-27  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** app_settings

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `app_settings` |
| **Rows على Cloud** | 1 سجل (whatsapp_settings) |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

> **مهم:** تم اكتشاف هذه الحقول من فحص فعلي لـ Appwrite Cloud.
> عدد كبير منها لم يكن مُدرجاً في `validFieldsPerCollection['app_settings']`
> مما كان يسبب حذفها بواسطة `filterPayloadForCollection` قبل الرفع.

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `key` | string | 0/100 | "whatsapp_settings" | **REQUIRED** — مفتاح الإعداد |
| `value` | string | 0/5000 | - | **REQUIRED** — قيمة الإعداد |
| `localUuid` | string | 0/100 | - | **REQUIRED** — UUID فريد |

### الحقول الاختيارية (OPTIONAL) على Cloud

#### 📱 إعدادات واتساب (WhatsApp)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `wa_api_type` | string? | 0/50 | "greenapi" | نوع API |
| `wa_api_base_url` | string? | 0/500 | - | عنوان API الأساسي |
| `wa_api_instance_id` | string? | 0/200 | - | معرف المثيل |
| `wa_api_token` | string? | 0/500 | - | رمز API |
| `wa_custom_url_template` | string? | 0/1000 | - | قالب URL المخصص |
| `wa_sendzen_api_key` | string? | 0/500 | - | مفتاح Sendzen API |
| `wa_sendzen_from_number` | string? | 0/30 | - | رقم المرسل Sendzen |
| `wa_template` | string? | 0/500 | - | قالب الرسالة |

#### 📨 إعدادات تيليجرام (Telegram)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `telegram_enabled` | boolean? | - | true | تفعيل تيليجرام |
| `telegram_bot_token` | string? | 0/500 | - | رمز البوت |
| `telegram_chat_id` | string? | 0/100 | - | معرف المحادثة |
| `telegram_notifications_enabled` | boolean? | - | true | تفعيل الإشعارات |
| `telegram_daily_report_enabled` | boolean? | - | true | تفعيل التقرير اليومي |
| `telegram_daily_report_time` | string? | 0/10 | "02:00" | وقت التقرير اليومي |

#### 🏨 إعدادات الفندق

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `hotel_name` | string? | 0/200 | "فندق مارينا بلازا" | اسم الفندق |
| `hotel_cutoff_hour` | integer? | - | 14 | ساعة القطع |
| `dark_mode` | boolean? | - | false | الوضع الليلي |

#### 🐦 إعدادات Lark

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `lark_enabled` | boolean? | - | false | تفعيل Lark |
| `lark_app_id` | string? | 0/200 | - | معرف التطبيق |
| `lark_app_secret` | string? | 0/500 | - | سر التطبيق |
| `lark_webhook_url` | string? | 0/1000 | - | عنوان Webhook |
| `lark_daily_report_enabled` | boolean? | - | false | تفعيل التقرير اليومي |
| `lark_daily_report_time` | string? | 0/10 | "08:00" | وقت التقرير اليومي |
| `lark_daily_report_chat_id` | string? | 0/100 | - | معرف محادثة التقرير |
| `lark_notifications_enabled` | boolean? | - | true | تفعيل الإشعارات |

#### 🔄 إعدادات المزامنة (Appwrite Sync)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `appwrite_sync_interval` | integer? | - | 15 | فاصل المزامنة (دقائق) |
| `appwrite_auto_sync_on_connect` | boolean? | - | true | مزامنة تلقائية عند الاتصال |
| `appwrite_log_level` | string? | 0/20 | "info" | مستوى السجل |
| `appwrite_log_file` | boolean? | - | false | تسجيل في ملف |
| `appwrite_log_console` | boolean? | - | true | تسجيل في الكونسول |
| `conflict_strategy` | string? | 0/50 | "newerWins" | استراتيجية حل التعارض |
| `sync_performance_profile` | string? | 0/50 | "balanced" | ملف الأداء |
| `wifi_only_sync` | boolean? | - | false | مزامنة على WiFi فقط |
| `sync_origin` | string? | 0/64 | "mobile" | مصدر المزامنة |

#### 💾 إعدادات النسخ الاحتياطي التلقائي

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `auto_backup_time` | string? | 0/10 | "21:00" | وقت النسخ الاحتياطي |
| `auto_backup_frequency` | string? | 0/50 | "daily" | تردد النسخ الاحتياطي |
| `scheduled_backup_enabled` | boolean? | - | true | تفعيل النسخ المجدول |

#### ☁️ إعدادات الوجهة الثانوية (Secondary Appwrite)

> **ملاحظة:** هذه الحقول تُخزّن إعدادات الوجهة الثانوية كـ JSON string
> في حقل `secondary_appwrite_config`، لكنها متاحة أيضاً كحقول منفصلة.

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `secondary_appwrite_config` | string? | 0/500 | - | إعدادات الثانوي (JSON) |
| `enabled` | string? | 0/10 | - | تفعيل الثانوي |
| `endpoint` | string? | 0/500 | - | عنوان الثانوي |
| `project_id` | string? | 0/100 | - | معرف مشروع الثانوي |
| `database_id` | string? | 0/100 | - | معرف قاعدة بيانات الثانوي |
| `api_key` | string? | 0/500 | - | مفتاح API للثانوي |
| `push_enabled` | string? | 0/10 | - | تفعيل الرفع |
| `pull_enabled` | string? | 0/10 | - | تفعيل السحب |

#### 📅 حقول التواريخ العامة

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `createdAt` | string? | 0/30 | - | تاريخ الإنشاء |
| `updatedAt` | string? | 0/30 | - | تاريخ التحديث |

#### 🔄 حقول المزامنة (SyncFields)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف الناعم |
| `lastModified` | integer? | - | NULL | آخر تعديل |
| `version` | integer? | - | 1 | الإصدار |
| `origin` | string? | 0/50 | "local" | المصدر |
| `vectorClock` | string? | 0/500 | "{}" | ساعة المتجهات |
| `deviceId` | string? | 0/255 | - | معرف الجهاز |
| `createdAtEpoch` | integer? | - | 0 | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | 0 | epoch التعديل |
| `createdAtIso` | string? | 0/50 | NULL | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 0/50 | NULL | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | NULL | تاريخ ISO للحذف |
| `syncTimestamp` | integer? | - | NULL | طابع زمني للمزامنة |

### حقول Appwrite التلقائية (لا تُرسل من الكود)

| الحقل | الوصف |
|-------|--------|
| `$id` | معرف المستند التلقائي |
| `$createdAt` | تاريخ الإنشاء التلقائي |
| `$updatedAt` | تاريخ التحديث التلقائي |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول على Cloud** | 50+ حقل |
| **إجمالي السجلات على Cloud** | 1 سجل (whatsapp_settings) |
| **الحقل المفتاحي (Key)** | `key` = "whatsapp_settings" |

---

## ✅ مقارنة: الكود المحلي vs Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المُدرجة في `validFieldsPerCollection['app_settings']`

| الحقل | الكود المحلي | Appwrite Cloud | validFields | الحالة |
|-------|------------|----------------|-------------|--------|
| `key` | ✅ | ✅ | ✅ | ✅ مطابق |
| `value` | ✅ | ✅ | ✅ | ✅ مطابق |
| `localUuid` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_api_type` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_api_base_url` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_api_instance_id` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_api_token` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_custom_url_template` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_sendzen_api_key` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_sendzen_from_number` | ✅ | ✅ | ✅ | ✅ مطابق |
| `wa_template` | ✅ | ✅ | ✅ | ✅ مطابق |
| `telegram_enabled` | ✅ | ✅ | ✅ | ✅ مطابق |
| `telegram_bot_token` | ✅ | ✅ | ✅ | ✅ مطابق |
| `telegram_chat_id` | ✅ | ✅ | ✅ | ✅ مطابق |
| `telegram_notifications_enabled` | ✅ | ✅ | ✅ | ✅ مطابق |
| `telegram_daily_report_enabled` | ✅ | ✅ | ✅ | ✅ مطابق |
| `telegram_daily_report_time` | ✅ | ✅ | ✅ | ✅ مطابق |
| `hotel_name` | ✅ | ✅ | ✅ | ✅ مطابق |
| `hotel_cutoff_hour` | ✅ | ✅ | ✅ | ✅ مطابق |
| `dark_mode` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_enabled` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_app_id` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_app_secret` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_webhook_url` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_daily_report_enabled` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_daily_report_time` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_daily_report_chat_id` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lark_notifications_enabled` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `appwrite_sync_interval` | ✅ | ✅ | ✅ | ✅ مطابق |
| `appwrite_auto_sync_on_connect` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `appwrite_log_level` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `appwrite_log_file` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `appwrite_log_console` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `conflict_strategy` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `sync_performance_profile` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `wifi_only_sync` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `sync_origin` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `auto_backup_time` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `auto_backup_frequency` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `scheduled_backup_enabled` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `secondary_appwrite_config` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `enabled` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `endpoint` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `project_id` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `database_id` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `api_key` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `push_enabled` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `pull_enabled` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `createdAt` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `updatedAt` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `serverId` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `deletedAt` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `lastModified` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `version` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `origin` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `vectorClock` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `deviceId` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `createdAtEpoch` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `lastModifiedEpoch` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `createdAtIso` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `updatedAtIso` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `deletedAtIso` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `syncTimestamp` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['app_settings']` في `appwrite_sync_utils.dart`.
هذا كان يسبب حذفها بواسطة `filterPayloadForCollection` قبل الرفع.

**تم الإصلاح:**

**إعدادات المزامنة:**
- `appwrite_auto_sync_on_connect`, `appwrite_log_level`, `appwrite_log_file`
- `appwrite_log_console`, `conflict_strategy`, `sync_performance_profile`
- `wifi_only_sync`, `sync_origin`

**النسخ الاحتياطي التلقائي:**
- `auto_backup_time`, `auto_backup_frequency`, `scheduled_backup_enabled`

**الوجهة الثانوية:**
- `secondary_appwrite_config`, `enabled`, `endpoint`, `project_id`
- `database_id`, `api_key`, `push_enabled`, `pull_enabled`

**Lark:**
- `lark_notifications_enabled`

**SyncFields:**
- `createdAt`, `updatedAt`, `serverId`, `deletedAt`, `lastModified`, `version`
- `origin`, `vectorClock`, `deviceId`, `createdAtEpoch`, `lastModifiedEpoch`
- `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `syncTimestamp`

### 2. بنية الجدول

جدول `app_settings` يستخدم نمط **key-value** لتخزين الإعدادات:
- `key`: مفتاح فريد للإعداد (مثل "whatsapp_settings")
- `value`: القيمة المرتبطة (يمكن أن تكون JSON string)

لكنه يحتوي أيضاً على حقول مُحددة لكل نوع إعداد (واتساب، تيليجرام، إلخ).

### 3. إعدادات الوجهة الثانوية

تُخزّن بطريقتين:
- **JSON string** في `secondary_appwrite_config` (للنسخ الاحتياطي)
- **حقول منفصلة** (`enabled`, `endpoint`, `project_id`, `database_id`, `api_key`,
  `push_enabled`, `pull_enabled`) للوصول المباشر

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| WhatsApp Settings Sync | `lib/services/whatsapp_settings_sync.dart` | مزامنة إعدادات واتساب |
| Secondary Sync Settings | `lib/services/whatsapp_settings_sync.dart` (`SecondarySyncSettingsSync`) | مزامنة إعدادات الوجهة الثانوية |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` + `filterPayloadForCollection` |
| Local DB | `lib/services/local_db.dart` | لا يوجد جدول محلي — يُستخدم SharedPreferences |
| Secondary Config | `lib/services/secondary_appwrite_config.dart` | إعدادات الوجهة الثانوية |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إضافة 30+ حقل مفقود إلى `validFieldsPerCollection['app_settings']`: إعدادات المزامنة، النسخ الاحتياطي، الوجهة الثانوية، Lark، و SyncFields كاملة |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**تاريخ الإنشاء:** 2026-06-27
