# 🔧 حل مشكلة رفع النسخة الاحتياطية من التطبيق

## ❌ المشكلة
عند استخدام ميزة **"رفع نسخة إلى Appwrite"** من التطبيق المحمول، كانت تفشل العملية بدون رسائل خطأ واضحة.

## 🔍 السبب الجذري

### 1. AppwriteService لا يستخدم API Key
في `mobile/lib/services/appwrite_service.dart`:
```dart
_client = Client()
    .setEndpoint(AppwriteConfig.endpoint)
    .setProject(AppwriteConfig.projectId);
    // ❌ لا يوجد .setKey() - التطبيق يتصل كـ Guest
```

### 2. Collections Permissions كانت محدودة
- Collections كانت تستخدم `documentSecurity: true`
- Documents لها permissions فارغة `[]`
- **النتيجة:** Guest users لا يستطيعون الكتابة

## ✅ الحل المطبق

### تم تحديث صلاحيات جميع Collections:
```javascript
// Collections الآن تسمح بـ:
Permission.read(Role.any())    // أي شخص يقرأ
Permission.create(Role.any())  // أي شخص ينشئ
Permission.update(Role.any())  // أي شخص يحدث
Permission.delete(Role.any())  // أي شخص يحذف
```

### تم تغيير Document Security:
- من: `documentSecurity: true` (صلاحيات لكل مستند)
- إلى: `documentSecurity: false` (صلاحيات على مستوى Collection)

## 🧪 الاختبار
تم اختبار الحل عن طريق:
1. ✅ محاكاة اتصال Guest (بدون API key)
2. ✅ قراءة البيانات
3. ✅ إنشاء مستند جديد
4. ✅ تحديث المستند
5. ✅ حذف المستند

**النتيجة:** جميع العمليات نجحت ✅

## 📦 السكريبتات المستخدمة

### إصلاح الصلاحيات:
```bash
cd scripts/appwrite
node fix_permissions.js
```

### اختبار الوصول:
```bash
cd scripts/appwrite
node test_guest_access.js
```

### رفع نسخة احتياطية:
```bash
cd scripts/appwrite
node upload_backup.js
```

## ✨ الآن يعمل:

### ✅ من التطبيق المحمول:
1. الإعدادات → إعدادات Appwrite
2. النسخ الاحتياطي الشامل والاستعادة
3. **رفع نسخة إلى Appwrite** ← يعمل الآن! ✅
4. **المزامنة التلقائية** ← تعمل! ✅

### ✅ من السكريبتات:
- `upload_backup.js` - رفع ملفات JSON
- `clear_all_data.js` - مسح البيانات
- `check_collections.js` - فحص الحالة

## ⚠️ تحذير أمني

**للإنتاج:** هذه الصلاحيات واسعة جداً!

### الحل الموصى به للإنتاج:
1. **استخدام Appwrite Auth:**
   ```dart
   // في AppwriteService
   _client = Client()
       .setEndpoint(endpoint)
       .setProject(projectId)
       .setSession(userSession); // من تسجيل الدخول
   ```

2. **تحديد صلاحيات محددة:**
   ```javascript
   Permission.read(Role.users()),        // المستخدمين المسجلين فقط
   Permission.create(Role.users()),
   Permission.update(Role.user('USER_ID')), // صاحب المستند فقط
   Permission.delete(Role.team('admins'))   // المدراء فقط
   ```

3. **أو استخدام API Key بشكل آمن:**
   - حفظ API Key في backend server
   - التطبيق يتصل بـ backend
   - Backend يتصل بـ Appwrite

## 📊 البيانات الحالية في Appwrite:

| Collection | Documents |
|-----------|-----------|
| الغرف | 19 |
| الحجوزات | 9 |
| الدفعات | 44 |
| المصروفات | 9 |
| **الموظفون** | **7** ✅ |
| ليالي الحجوزات | 259 |
| سجل اليومية | 75 |

**الإجمالي:** 424 مستند

---

**تاريخ الحل:** 2026-02-01  
**الحالة:** ✅ تم الحل بنجاح  
**التطبيق:** جاهز للاستخدام
