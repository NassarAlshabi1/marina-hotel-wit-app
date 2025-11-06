# توحيد المصادقة وإضافة Deep Links - Marina Hotel App

## 📋 ملخص التغييرات

تم بنجاح توحيد عمليات تسجيل الدخول بين الحسابات المحلية وSupabase مع إضافة Deep Links للـ Android وشاشة فحص حالة الاتصال.

## ✅ التعديلات المنجزة

### 1. إضافة Deep Links في AndroidManifest.xml
**الملف:** `mobile/android/app/src/main/AndroidManifest.xml`

تم إضافة intent-filter جديد لدعم Deep Links:
```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="io.supabase.marinahotel"
        android:host="login-callback" />
</intent-filter>
```

**⚠️ ملاحظة مهمة:** يجب تحديث الـ scheme (`io.supabase.marinahotel`) في:
- AndroidManifest.xml
- Supabase Dashboard → Authentication → URL Configuration → Redirect URLs
- أضف الـ URL التالي في Supabase: `io.supabase.marinahotel://login-callback`

### 2. تحديث Env.dart لإضافة بيانات تسجيل الدخول لـ Supabase
**الملف:** `mobile/lib/utils/env.dart`

تم إضافة متغيرات جديدة:
```dart
static String supabaseLoginEmail = const String.fromEnvironment(
  'SUPABASE_LOGIN_EMAIL',
  defaultValue: '',
);
static String supabaseLoginPassword = const String.fromEnvironment(
  'SUPABASE_LOGIN_PASSWORD',
  defaultValue: '',
);
```

**كيفية تعيين القيم:**
يمكنك تعيين قيم البريد الإلكتروني وكلمة المرور بطريقتين:

**الطريقة الأولى: المتغيرات البيئية (الموصى بها)**
```bash
flutter run --dart-define=SUPABASE_LOGIN_EMAIL=your-email@example.com --dart-define=SUPABASE_LOGIN_PASSWORD=your-password
```

**الطريقة الثانية: تعديل القيم الافتراضية**
يمكنك تغيير `defaultValue: ''` إلى بريدك الإلكتروني وكلمة المرور مباشرة (⚠️ غير موصى به في production).

### 3. تحديث auth_local_store.dart
**الملف:** `mobile/lib/services/auth_local_store.dart`

**التعديلات:**
- إضافة `enum AuthType { local, supabase, hybrid }`
- إضافة دوال جديدة:
  - `setRememberMe(bool)` و `getRememberMe()`
  - `setAuthType(AuthType)` و `getAuthType()`
  - `saveSupabaseSession(Map)` و `loadSupabaseSession()`
- تحديث `clearSession()` لمراعاة خيار "تذكرني"

### 4. تحديث auth_provider.dart
**الملف:** `mobile/lib/providers/auth_provider.dart`

**التعديلات:**
- تحديث `AuthState` بإضافة:
  - `bool rememberMe`
  - `AuthType authType`
  - `bool isSupabaseConnected`
- تحديث دالة `login()`:
  - إضافة parameter اختياري: `{bool rememberMe = false}`
  - محاولة تلقائية للاتصال بـ Supabase بعد المصادقة المحلية
  - حفظ جلسة Supabase في SharedPreferences
- تحديث دالة `restoreSession()`:
  - التحقق من خيار "تذكرني" قبل استعادة الجلسة
  - محاولة استعادة جلسة Supabase تلقائياً
- إضافة دالة جديدة: `checkSupabaseConnection()`

### 5. تحديث شاشة تسجيل الدخول
**الملف:** `mobile/lib/screens/auth/login_screen.dart`

**التعديلات:**
- إضافة متغير state: `bool _rememberMe = false`
- إضافة Checkbox "تذكرني" في الواجهة
- تمرير قيمة `rememberMe` إلى دالة `login()`

### 6. إنشاء شاشة حالة الاتصال مع Supabase
**ملف جديد:** `mobile/lib/screens/settings/supabase_connection_screen.dart`

**المميزات:**
- عرض حالة الاتصال (متصل/غير متصل)
- عرض معلومات المشروع والمستخدم
- عرض معلومات المصادقة المحلية
- زر لإعادة فحص الاتصال
- عرض الأخطاء إن وجدت

### 7. إضافة الشاشة في قائمة الإعدادات
**الملف:** `mobile/lib/screens/settings/settings_screen.dart`

تم إضافة عنصر جديد في قائمة الإعدادات: "حالة اتصال Supabase"

## 🎯 آلية العمل

### تدفق تسجيل الدخول:

1. **المستخدم يدخل البيانات في شاشة تسجيل الدخول**
   - اسم المستخدم
   - كلمة المرور
   - ✅ تذكرني (اختياري)

2. **المصادقة المحلية أولاً**
   - التحقق من البيانات مع الحسابات المحلية (admin, m, ahmed)
   - حفظ المستخدم في SharedPreferences
   - حفظ خيار "تذكرني"
   - تعيين نوع المصادقة إلى `AuthType.local`

3. **محاولة الاتصال بـ Supabase تلقائياً**
   - إذا كانت بيانات Supabase متوفرة في Env
   - تسجيل الدخول إلى Supabase
   - حفظ access_token و refresh_token
   - تحديث نوع المصادقة إلى `AuthType.hybrid`

4. **حالة "تذكرني"**
   - إذا كان مفعّل: يتم حفظ جميع البيانات
   - عند فتح التطبيق: استعادة الجلسة المحلية و Supabase تلقائياً
   - إذا كان معطّل: يتم حذف البيانات عند تسجيل الخروج

### تدفق استعادة الجلسة عند فتح التطبيق:

1. **التحقق من "تذكرني"**
   - إذا كان معطّل: لا يتم استعادة أي جلسة

2. **استعادة المستخدم المحلي**
   - قراءة بيانات المستخدم من SharedPreferences

3. **محاولة استعادة جلسة Supabase**
   - قراءة access_token و refresh_token
   - محاولة استعادة الجلسة باستخدام `recoverSession()`
   - تحديث حالة الاتصال

## 🔒 الأمان

- بيانات المصادقة المحلية (admin, m, ahmed) محفوظة كما هي
- جلسة Supabase محفوظة بشكل مشفر في SharedPreferences
- يمكن استخدام المتغيرات البيئية لإخفاء بيانات تسجيل الدخول
- الحسابات المحلية تعمل بشكل مستقل عن Supabase (offline-first)

## 📱 كيفية الاستخدام

### للمطور:

1. **تعيين بيانات تسجيل الدخول لـ Supabase:**
   ```bash
   flutter run --dart-define=SUPABASE_LOGIN_EMAIL=admin@marina.com --dart-define=SUPABASE_LOGIN_PASSWORD=yourpassword
   ```

2. **تحديث Redirect URL في Supabase:**
   - افتح Supabase Dashboard
   - اذهب إلى Authentication → URL Configuration
   - أضف: `io.supabase.marinahotel://login-callback`

3. **بناء التطبيق:**
   ```bash
   cd mobile
   flutter pub get
   flutter build apk  # أو flutter build ios
   ```

### للمستخدم:

1. **تسجيل الدخول:**
   - أدخل اسم المستخدم (admin, m, أو ahmed)
   - أدخل كلمة المرور
   - ✅ فعّل "تذكرني" للبقاء مسجلاً
   - اضغط "دخول"

2. **فحص حالة الاتصال مع Supabase:**
   - اذهب إلى الإعدادات
   - اضغط على "حالة اتصال Supabase"
   - شاهد حالة الاتصال ومعلومات المستخدم

3. **تسجيل الخروج:**
   - إذا كان "تذكرني" معطّل: سيتم حذف جميع البيانات
   - إذا كان "تذكرني" مفعّل: ستبقى إعدادات "تذكرني" محفوظة

## ✅ معايير النجاح

- [x] تحديث AndroidManifest.xml بـ intent-filter للـ Deep Links
- [x] إضافة خيار "تذكرني" في شاشة تسجيل الدخول
- [x] حفظ الجلسة المحلية و Supabase session معاً
- [x] استعادة الجلسة عند فتح التطبيق (فقط إذا كان "تذكرني" مفعل)
- [x] إنشاء شاشة حالة الاتصال مع Supabase في قسم الإعدادات
- [x] عرض معلومات واضحة عن حالة الاتصال (متصل/غير متصل)
- [x] إمكانية إعادة فحص الاتصال
- [x] عرض معلومات المستخدم ونوع المصادقة
- [x] البيانات تُحفظ محلياً حتى بدون انترنت

## 🧪 الاختبار

### سيناريو 1: تسجيل الدخول بدون "تذكرني"
1. سجل الدخول بـ admin/admin بدون تفعيل "تذكرني"
2. أغلق التطبيق
3. افتح التطبيق → يجب أن تظهر شاشة تسجيل الدخول

### سيناريو 2: تسجيل الدخول مع "تذكرني"
1. سجل الدخول بـ admin/admin مع تفعيل "تذكرني"
2. أغلق التطبيق
3. افتح التطبيق → يجب أن تظهر الشاشة الرئيسية مباشرة

### سيناريو 3: فحص حالة اتصال Supabase
1. سجل الدخول
2. اذهب إلى الإعدادات → حالة اتصال Supabase
3. يجب أن تظهر:
   - حالة الاتصال (متصل/غير متصل)
   - رابط المشروع
   - معلومات المستخدم المحلي
   - نوع المصادقة (محلي أو مختلط)

### سيناريو 4: العمل بدون انترنت
1. أغلق الواي فاي/البيانات
2. سجل الدخول بـ m/1
3. يجب أن يعمل التطبيق بشكل طبيعي (المصادقة المحلية فقط)
4. اذهب إلى الإعدادات → حالة اتصال Supabase
5. يجب أن تظهر "غير متصل"

## 📝 ملاحظات مهمة

1. **الحسابات المحلية محفوظة:**
   - admin/admin
   - m/1
   - ahmed/2222

2. **بيانات Supabase:**
   - يمكن تعيينها عبر المتغيرات البيئية
   - إذا لم تكن متوفرة: التطبيق يعمل بالمصادقة المحلية فقط

3. **نظام Offline-First:**
   - نظام حفظ البيانات المحلية (Drift/SQLite) موجود ويعمل بشكل مستقل
   - نظام المزامنة (sync_service.dart) يزامن البيانات تلقائياً عند توفر الاتصال

4. **Deep Links:**
   - تأكد من تطابق الـ scheme في AndroidManifest.xml مع Supabase Dashboard
   - يُستخدم للـ OAuth callbacks و Magic Links

## 🔄 الخطوات التالية (اختياري)

1. **إضافة Magic Link Authentication:**
   - استخدام Deep Links للتسجيل عبر البريد الإلكتروني

2. **إضافة Social Login:**
   - تسجيل الدخول بـ Google/Facebook/Apple

3. **إضافة Two-Factor Authentication:**
   - طبقة أمان إضافية

4. **إضافة Password Reset:**
   - استعادة كلمة المرور عبر البريد الإلكتروني

5. **تحسين UI/UX:**
   - إضافة animations لحالة الاتصال
   - إضافة إشعارات عند فشل الاتصال بـ Supabase

## 🐛 استكشاف الأخطاء

### مشكلة: Supabase لا يتصل
**الحل:**
- تحقق من بيانات تسجيل الدخول في Env.dart
- تحقق من الاتصال بالإنترنت
- تحقق من صحة بيانات الدخول في Supabase

### مشكلة: Deep Links لا تعمل
**الحل:**
- تأكد من تطابق الـ scheme في AndroidManifest.xml و Supabase Dashboard
- أعد بناء التطبيق (flutter clean && flutter build apk)
- تحقق من Redirect URLs في Supabase Dashboard

### مشكلة: الجلسة لا تُستعاد
**الحل:**
- تأكد من تفعيل "تذكرني" عند تسجيل الدخول
- تحقق من وجود بيانات في SharedPreferences
- جرب تسجيل الخروج ثم الدخول مرة أخرى

---

**تاريخ التطوير:** نوفمبر 2025  
**المطور:** Capy AI  
**الإصدار:** 1.0.0
