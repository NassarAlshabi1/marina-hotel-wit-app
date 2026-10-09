# 🔍 مراجعة قسم WhatsApp - Marina Hotel Mobile

**تاريخ المراجعة:** 2026-06-28
**الفرع:** `marina`

---

## 📋 الملفات المُراجَعة

| # | الملف | الأسطر | الوظيفة |
|---|------|--------|---------|
| 1 | `lib/screens/settings/whatsapp_settings_screen.dart` | 1245 | شاشة إعدادات WhatsApp API + القوالب |
| 2 | `lib/screens/settings/whatsapp_daily_report_screen.dart` | 736 | شاشة التقرير اليومي عبر WhatsApp |
| 3 | `lib/screens/settings/late_payment_whatsapp_screen.dart` | 969 | شاشة تذكير الديون المتأخرة |
| 4 | `lib/screens/settings/active_bookings_reminder_screen.dart` | 1253 | شاشة تذكير الحجوزات النشطة |
| 5 | `lib/services/whatsapp_service.dart` | 244 | خدمة إرسال WhatsApp (GreenAPI + Custom) |
| 6 | `lib/services/whatsapp_settings_sync.dart` | 142 | مزامنة الإعدادات مع Appwrite |
| 7 | `lib/services/telegram/whatsapp_notification_service.dart` | 479 | إشعارات فورية عبر CallMeBot |

**الإجمالي:** 5068 سطر

---

## 🔴 المشاكل الحرجة (P0)

### P0-1: بيانات اعتماد GreenAPI مُشفّرة في الكود (Hardcoded)

**الموقع:** `whatsapp_settings_screen.dart` الأسطر 41-44

```dart
static const _defaultBaseUrl = 'https://7103.api.greenapi.com';
static const _defaultInstanceId = 'waInstance7103894450';
static const _defaultToken =
    'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1';
```

**المشكلة:**
- Token الخاص بـ GreenAPI مكتوب في الكود المصدري
- أي شخص يصل للكود (GitHub) يصل لـ API token
- يمكنه إرسال رسائل WhatsApp باسم الفندق
- Token يظهر في git history حتى لو حُذف لاحقاً

**التأثير:** 🔴 حرج أمنياً — تسريب بيانات اعتماد

**الإصلاح المُقترح:**
- نقل القيم الافتراضية إلى `RemoteConfigService` (Firebase)
- أو جعلها فارغة وإجبار المستخدم على إدخالها يدوياً
- **إبطال الـ token الحالي فوراً** من لوحة تحكم GreenAPI

---

### P0-2: Token مخزّن كنص صريح في SharedPreferences

**الموقع:** `whatsapp_settings_screen.dart::_saveApiSettings` السطر 100

```dart
await prefs.setString('wa_api_token', _tokenController.text.trim());
```

**المشكلة:**
- API Token مخزّن كنص صريح في SharedPreferences
- على أجهزة rooted/jailbroken، قابل للقراءة
- `whatsapp_settings_sync.dart` يرفع نفس الـ token لـ Appwrite كنص صريح

**الإصلاح المُقترح:**
- استخدام `flutter_secure_storage` (موجود في pubspec.yaml)
- أو تشفير الـ token قبل التخزين

---

### P0-3: Token يُرفع لـ Appwrite كنص صريح

**الموقع:** `whatsapp_settings_sync.dart::uploadToCloud` السطر 28

```dart
'wa_api_token': prefs.getString('wa_api_token') ?? '',
```

**المشكلة:**
- الـ token يُرفع لـ Appwrite Cloud كنص صريح في حقل `wa_api_token`
- أي شخص يصل لـ Appwrite Console يقرأ الـ token
- لو سُرق حساب Appwrite، تُسرق بيانات WhatsApp أيضاً

**الإصلاح المُقترح:**
- عدم رفع `wa_api_token` للسحابة إطلاقاً
- أو تشفيره قبل الرفع (AES-256)

---

## 🟠 مشاكل عالية الأولوية (P1)

### P1-1: `whatsapp_settings_sync.dart` لا يستخدم retry/timeout

**الموقع:** الأسطر 38-54

```dart
// محاولة تحديث المستند الموجود
try {
  await _appwrite.databases.updateDocument(...);
} catch (_) {
  // إذا لم يكن موجوداً، إنشاء مستند جديد
  await _appwrite.databases.createDocument(...);
}
```

**المشكلة:**
- لا retry، لا timeout
- `catch (_) {}` يبتلع كل الأخطاء صامتة — حتى أخطاء الشبكة
- إذا فشل update بسبب شبكة (وليس 404)، يحاول create → خطأ 409
- لا يستخدم `_upsertDocumentInternal` المُصلَّح في Primary

---

### P1-2: `WhatsAppService` لا يستخدم retry

**الموقع:** `whatsapp_service.dart::_sendViaGreenApi` السطر 72

```dart
final response = await _client.post(endpoint, ...);
```

**المشكلة:**
- لا retry على فشل الشبكة
- لا timeout على GreenAPI (فقط على Custom: 15 ثانية)
- رسالة WhatsApp قد تفشل بدون محاولة إعادة

---

### P1-3: `WhatsAppNotificationService` (CallMeBot) لا retry

**الموقع:** `whatsapp_notification_service.dart`

**المشكلة:**
- نفس المشكلة — لا retry، timeout محدود
- CallMeBot أقل استقراراً من GreenAPI

---

### P1-4: `_sendViaCustom` يستخدم GET لإرسال رسائل

**الموقع:** `whatsapp_service.dart::_sendViaCustom` السطر 125

```dart
final response = await _client.get(endpoint).timeout(...);
```

**المشكلة:**
- GET يضع الرسالة في URL — تظهر في سجلات الخادم، الـ proxy، الـ CDN
- رسائل WhatsApp حساسة (أسماء نزلاء، هواتف، مبالغ)
- POST أكثر أماناً — الرسالة في body مشفّرة عبر HTTPS

---

## 🟡 مشاكل متوسطة الأولوية (P2)

### P2-1: `whatsapp_notification_service.dart` يستخدم CallMeBot بدون مفتاح مشفّر

**الموقع:** السطر 60-61

```dart
String get _phone => RemoteConfigService.instance.whatsappPhone;
String get _apiKey => RemoteConfigService.instance.whatsappApiKey;
```

**المشكلة:**
- Remote Config values ليست مشفّرة في Firebase
- أي شخص يصل لـ Firebase Console يقرأها
- CallMeBot API key + phone مكشوفان

---

### P2-2: لا التحقق من صحة رقم الهاتف قبل الإرسال

**الموقع:** `whatsapp_service.dart::sendMessage` السطر 45-48

```dart
final digitsOnly = phoneE164.replaceAll(RegExp(r'\D'), '');
if (digitsOnly.length < minPhoneDigits) {
  return (success: false, quotaMessage: null);
}
```

**المشكلة:**
- يفحص فقط الطول (12 رقم)
- لا يتحقق من صحة رمز الدولة
- لا يتحقق من وجود الرقم فعلاً على WhatsApp

---

### P2-3: رسائل SnackBar بدون duration موحّد

**الموقع:** `whatsapp_settings_screen.dart`

بعض SnackBars لها `duration` وبعضها لا. يجب توحيدها على 3 ثوانٍ (مثل بقية التطبيق).

---

### P2-4: `_trimMessage` قد يقطع نصاً عربياً

**الموقع:** `whatsapp_service.dart::_trimMessage` السطر 207-243

**المشكلة:**
- يستخدم `characters.take()` وهو جيد
- لكن البحث عن كلمات معينة ('فندق مارينا', 'green-api') قد يفشل إذا تغيّر القالب

---

## ✅ الجوانب الإيجابية

1. **دعم نوعَي API:** GreenAPI + Custom URL — مرونة جيدة
2. **اختبار الاتصال:** `testConnection()` مع رسائل خطأ واضحة
3. **اقتصاص الرسائل:** `_trimMessage` يحافظ على التذييل (footer)
4. **مزامنة الإعدادات:** `whatsapp_settings_sync.dart` يرفع/ينزّل الإعدادات من Appwrite
5. **قوالب رسائل:** قابلة للتخصيص مع متغيرات
6. **تقارير يومية:** تقرير WhatsApp اليومي
7. **تذكير الديون:** إشعارات تلقائية للديون المتأخرة

---

## 📊 التقييم الإجمالي

| المعيار | التقييم |
|--------|---------|
| الوظائف | ⭐⭐⭐⭐⭐ شامل (إرسال، تقارير، تذكيرات) |
| الأمان | ⭐ خطير (token مكشوف في الكود + SharedPreferences + Appwrite) |
| معالجة الأخطاء | ⭐⭐ ضعيفة (لا retry، catch صامت) |
| جودة الكود | ⭐⭐⭐⭐ جيدة |
| تجربة المستخدم | ⭐⭐⭐⭐ جيدة |

---

## 🎯 توصيات الإصلاح

### 🔴 P0 — فوري

| # | الإصلاح | الجهد |
|---|---------|------|
| P0-1 | إزالة hardcoded token من الكود + إبطال الـ token الحالي | 30 دقيقة |
| P0-2 | استخدام `flutter_secure_storage` لـ token | 45 دقيقة |
| P0-3 | عدم رفع token لـ Appwrite (أو تشفيره) | 30 دقيقة |

### 🟠 P1 — عالي

| # | الإصلاح | الجهد |
|---|---------|------|
| P1-1 | استخدام `_upsertDocumentInternal` في settings_sync | 30 دقيقة |
| P1-2 | إضافة retry/timeout في `WhatsAppService` | 1 ساعة |
| P1-4 | تحويل `_sendViaCustom` من GET إلى POST | 30 دقيقة |

### 🟡 P2 — متوسط

| # | الإصلاح | الجهد |
|---|---------|------|
| P2-1 | تشفير Remote Config values | 1 ساعة |
| P2-3 | توحيد duration على 3 ثوانٍ | 15 دقيقة |

---

## ⚠️ تحذير أمني عاجل

**يجب إبطال token GreenAPI الحالي فوراً:**
```
Token: a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1
```
- اذهب إلى لوحة تحكم GreenAPI
- احذف هذا الـ instance أو أعد توليد الـ token
- أي شخص يصل للكود يمكنه إرسال رسائل باسم الفندق

---

**آخر تحديث:** 2026-06-28
