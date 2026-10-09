# خطوات إعداد صلاحيات Appwrite للتطبيق

## 📋 نظرة عامة

لتشغيل التطبيق بشكل صحيح وآمن بدون استخدام API Keys، يجب إعداد صلاحيات المجموعات في Appwrite Console.

## 🔧 خطوات الإعداد

### الخطوة 1: الوصول إلى Appwrite Console

1. افتح [Appwrite Console](https://cloud.appwrite.io)
2. سجل الدخول إلى حسابك
3. اختر مشروع: **690ff0da0025518570c1**

### الخطوة 2: الانتقال إلى قاعدة البيانات

```
Dashboard > Databases > hotel_db
```

### الخطوة 3: إعداد صلاحيات لكل Collection

يجب تطبيق نفس الصلاحيات على جميع المجموعات التالية:
- ✅ rooms
- ✅ bookings
- ✅ payments
- ✅ expenses
- ✅ employees
- ✅ debts
- ✅ devices
- ✅ sync_logs

---

## 🔐 طريقة إعداد الصلاحيات

### للمجموعة الواحدة (مثال: rooms):

#### 1. انتقل إلى Collection
```
Databases > hotel_db > rooms
```

#### 2. افتح تبويب Settings
```
Settings > Permissions
```

#### 3. أضف صلاحيات القراءة

اضغط **"Add a role"**:
- **Role Type**: اختر `Any`
- **Permissions**: اختر `Read` ✓

**النتيجة:**
```
Role: Any
Permissions: [read]
```

#### 4. أضف صلاحيات الكتابة

اضغط **"Add a role"** مرة أخرى:
- **Role Type**: اختر `Any`
- **Permissions**: اختر:
  - `Create` ✓
  - `Update` ✓
  - `Delete` ✓

**النتيجة:**
```
Role: Any
Permissions: [create, update, delete]
```

#### 5. احفظ التغييرات

---

## 📦 القائمة الكاملة للمجموعات

### ✅ Checklist - تأكد من إعداد كل واحدة:

- [ ] **rooms** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

- [ ] **bookings** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

- [ ] **payments** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

- [ ] **expenses** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

- [ ] **employees** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

- [ ] **debts** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

- [ ] **devices** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

- [ ] **sync_logs** Collection
  - [ ] Role: Any → [read]
  - [ ] Role: Any → [create, update, delete]

---

## 🧪 اختبار الصلاحيات

### من التطبيق:

1. شغّل التطبيق
2. اذهب إلى: **الإعدادات > إعدادات Appwrite**
3. اضغط **"اختبار الاتصال"**
4. يجب أن تظهر: ✅ **"متصل بنجاح"**

### اختبار عمليات CRUD:

1. في شاشة إعدادات Appwrite
2. قسم **"الاختبارات والتشخيص"**
3. اضغط **"اختبار الاتصال"**
4. اضغط **"اختبار المزامنة"**

---

## ⚠️ ملاحظات أمنية

### للتطوير والاختبار (الوضع الحالي):
```
✅ Role: Any
✅ يسمح بالوصول الكامل لأي شخص
✅ مناسب للاختبار
⚠️ غير آمن للإنتاج
```

### للإنتاج (الموصى به):
```
✅ Role: Users (بدلاً من Any)
✅ يتطلب تسجيل دخول
✅ حماية البيانات
✅ تتبع المستخدمين
```

---

## 🔒 الترقية إلى نظام آمن (للإنتاج)

### الخطوة 1: إنشاء نظام مصادقة

أضف في التطبيق صفحة تسجيل دخول:

```dart
import 'package:appwrite/appwrite.dart';

class AuthService {
  final Client client;
  late final Account account;

  AuthService(this.client) {
    account = Account(client);
  }

  // تسجيل مستخدم جديد
  Future<void> register(String email, String password, String name) async {
    await account.create(
      userId: 'unique()',
      email: email,
      password: password,
      name: name,
    );
  }

  // تسجيل الدخول
  Future<void> login(String email, String password) async {
    await account.createEmailPasswordSession(
      email: email,
      password: password,
    );
  }

  // تسجيل الخروج
  Future<void> logout() async {
    await account.deleteSession(sessionId: 'current');
  }

  // التحقق من حالة المستخدم
  Future<bool> isLoggedIn() async {
    try {
      await account.get();
      return true;
    } catch (e) {
      return false;
    }
  }
}
```

### الخطوة 2: تغيير الصلاحيات

في Appwrite Console، غيّر جميع الصلاحيات من:
```
Role: Any → Role: Users
```

### الخطوة 3: حماية الشاشات

```dart
class ProtectedScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // التحقق من تسجيل الدخول قبل الوصول
    final isLoggedIn = ref.watch(authStateProvider);
    
    if (!isLoggedIn) {
      return LoginScreen();
    }
    
    return ActualScreen();
  }
}
```

---

## 📊 مثال على الصلاحيات المتقدمة

### لمزيد من التحكم:

```
Collection: bookings

1. القراءة للجميع:
   Role: Any
   Permissions: [read]

2. الكتابة للمستخدمين فقط:
   Role: Users
   Permissions: [create, update]

3. الحذف للمدراء فقط:
   Role: Team:admins
   Permissions: [delete]
```

---

## ✅ التحقق النهائي

بعد إكمال جميع الخطوات:

1. ✅ جميع الـ 8 Collections لديها صلاحيات
2. ✅ Role: Any → [read]
3. ✅ Role: Any → [create, update, delete]
4. ✅ التطبيق يتصل بنجاح
5. ✅ المزامنة تعمل

---

## 🆘 استكشاف الأخطاء

### خطأ: "403 Forbidden" أو "Missing scope"
**السبب:** لا توجد صلاحيات كافية
**الحل:** تحقق من إضافة Role: Any مع جميع الصلاحيات

### خطأ: "Document not found"
**السبب:** Collection ID خاطئ أو Collection غير موجود
**الحل:** تحقق من أسماء الـ Collections في Database

### خطأ: "Invalid credentials"
**السبب:** API Key تم استخدامه (وهو غير مطلوب)
**الحل:** أزل API Key من الكود

---

## 📞 الدعم

إذا واجهت مشاكل:
1. راجع [Appwrite Documentation](https://appwrite.io/docs/permissions)
2. تحقق من [Appwrite Discord](https://discord.gg/appwrite)
3. ارجع إلى ملف `SECURITY_API_KEY_WARNING.md`

---

**الملخص:** أضف صلاحيات `Role: Any` مع `[read, create, update, delete]` لجميع الـ Collections الثمانية.
