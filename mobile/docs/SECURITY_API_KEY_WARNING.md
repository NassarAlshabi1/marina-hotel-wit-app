# ⚠️ تحذير أمني مهم - API Key Usage

## المشكلة
تم تضمين API Key في الكود:
```
standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da
```

## ⚠️ لماذا هذا خطير؟
- **API Keys في تطبيقات Mobile يمكن استخراجها** من APK/IPA
- أي شخص يحصل على الـ API Key يمكنه الوصول الكامل لقاعدة البيانات
- قد يؤدي إلى حذف أو تعديل أو سرقة البيانات

## ✅ الحل الصحيح

### للتطبيقات Mobile (Flutter/React Native/etc)

#### الخيار 1: استخدام صلاحيات Appwrite المدمجة (الموصى به)
```dart
// لا حاجة لـ API Key في Client
Client client = Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1');

// في Appwrite Console:
// Settings > Permissions
// أضف للـ Collections:
// - Role: Any (للقراءة العامة)
// - Role: Users (للمستخدمين المصادقين)
```

#### الخيار 2: استخدام Anonymous Sessions
```dart
Account account = Account(client);

// إنشاء جلسة مجهولة
await account.createAnonymousSession();

// الآن يمكن الوصول للبيانات بصلاحيات Guest
```

#### الخيار 3: استخدام Email/Password Authentication
```dart
Account account = Account(client);

// تسجيل دخول
await account.createEmailPasswordSession(
  email: 'user@example.com',
  password: 'password',
);

// في Appwrite Console، حدد صلاحيات:
// - Role: Users (للمستخدمين المسجلين)
```

### للخوادم فقط (Backend/Server-Side)
```dart
// API Key يُستخدم فقط في Server-Side
Client client = Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('your_api_key_here'); // ✅ آمن في الخادم فقط
```

## 🔧 الخطوات للتطبيق الحالي

### 1. إزالة API Key من الكود (إذا كان موجوداً)
```dart
// mobile/lib/services/appwrite_service.dart
_client = Client()
    .setEndpoint(AppwriteConfig.endpoint)
    .setProject(AppwriteConfig.projectId);
    // .setKey() ❌ لا تستخدم هذا في Mobile
```

### 2. ضبط صلاحيات المجموعات في Appwrite Console

لكل Collection (rooms, bookings, payments, etc):

#### أ. انتقل إلى:
```
Appwrite Console > Databases > hotel_db > [Collection Name] > Settings > Permissions
```

#### ب. أضف الصلاحيات التالية:

**للقراءة (Read):**
```
Role: Any
Permissions: [read]
```

**للكتابة (Create/Update/Delete):**
```
Option 1: للجميع (للاختبار فقط)
Role: Any
Permissions: [create, update, delete]

Option 2: للمستخدمين المسجلين فقط (الموصى به للإنتاج)
Role: Users
Permissions: [create, update, delete]
```

### 3. (اختياري) إنشاء مستخدم للاختبار

```dart
// في التطبيق، أضف صفحة تسجيل دخول بسيطة
Account account = Account(client);

try {
  // تسجيل مستخدم جديد
  await account.create(
    userId: 'unique()',
    email: 'admin@marinahotel.local',
    password: 'securePassword123',
    name: 'Admin',
  );
  
  // تسجيل الدخول
  await account.createEmailPasswordSession(
    email: 'admin@marinahotel.local',
    password: 'securePassword123',
  );
  
  print('تم تسجيل الدخول بنجاح');
} catch (e) {
  print('خطأ: $e');
}
```

## 🔐 أفضل الممارسات

### 1. لا تُدرج API Keys في:
- ❌ كود التطبيق (Dart/Flutter)
- ❌ Git repository
- ❌ APK/IPA files
- ❌ Frontend code

### 2. استخدم API Keys فقط في:
- ✅ Backend servers
- ✅ Cloud Functions
- ✅ Server-side scripts
- ✅ Environment variables (في الخادم)

### 3. استخدم في Mobile:
- ✅ Anonymous Sessions
- ✅ Email/Password Auth
- ✅ OAuth (Google, Apple, etc)
- ✅ JWT Tokens من Backend
- ✅ Permissions (Any/Users/Teams)

## 📝 التطبيق الحالي

حالياً، النظام معد **بدون API Key** ويستخدم:
- ✅ صلاحيات Appwrite المباشرة
- ✅ Role: Any (للوصول العام)

**للإنتاج**، يُنصح بإضافة نظام مصادقة:
1. تسجيل دخول المستخدمين
2. تغيير الصلاحيات إلى `Role: Users`
3. حماية البيانات الحساسة

## 🚨 إذا تم كشف API Key

إذا تم نشر API Key عن طريق الخطأ:

1. **احذف الـ API Key فوراً** من Appwrite Console
   ```
   Settings > API Keys > [Your Key] > Delete
   ```

2. **أنشئ API Key جديد** (للخادم فقط)

3. **راجع السجلات** للتحقق من عدم وجود نشاط مشبوه
   ```
   Appwrite Console > Logs
   ```

4. **غيّر جميع كلمات المرور** إذا لزم الأمر

## 📞 المزيد من المعلومات

- [Appwrite Security Best Practices](https://appwrite.io/docs/security)
- [Appwrite Permissions](https://appwrite.io/docs/permissions)
- [Appwrite Authentication](https://appwrite.io/docs/authentication)

---

**الملخص:** استخدم صلاحيات Appwrite المدمجة بدلاً من API Keys في التطبيقات Mobile.
