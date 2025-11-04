# ⚡ Supabase Quick Start Guide
# دليل البدء السريع لـ Supabase

<div dir="rtl">

## 🎯 للبدء فوراً | To Start Immediately

هذا دليل مختصر لمن يريد البدء بسرعة. للتفاصيل الكاملة، راجع [SUPABASE_MIGRATION_GUIDE.md](SUPABASE_MIGRATION_GUIDE.md).

</div>

---

## 📋 المتطلبات | Prerequisites

```bash
✅ Flutter installed
✅ Dart installed
✅ Supabase account (free)
✅ Supabase CLI installed
```

<div dir="rtl">

### تثبيت Supabase CLI

</div>

```bash
# macOS/Linux
brew install supabase/tap/supabase

# Windows
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# أو عبر npm
npm install -g supabase
```

---

## 🚀 البدء في 5 خطوات | Get Started in 5 Steps

<div dir="rtl">

### الخطوة 1: إنشاء مشروع Supabase (5 دقائق)

</div>

```bash
# 1. اذهب إلى https://supabase.com
# 2. انقر "New Project"
# 3. اختر اسم المشروع: marina-hotel
# 4. اختر كلمة مرور قوية
# 5. اختر المنطقة الأقرب
# 6. انقر "Create new project"
```

<div dir="rtl">

### الخطوة 2: إعداد Database (10 دقائق)

</div>

```bash
# في Supabase Dashboard:
# 1. اذهب إلى "SQL Editor"
# 2. انقر "New query"
# 3. انسخ محتويات: supabase/migrations/001_initial_schema.sql
# 4. الصق واضغط "Run"
# 5. كرر للملف: supabase/migrations/002_rls_policies.sql
```

<div dir="rtl">

### الخطوة 3: نشر Edge Functions (5 دقائق)

</div>

```bash
# تسجيل الدخول
supabase login

# ربط المشروع
supabase link --project-ref YOUR_PROJECT_ID

# نشر Functions
supabase functions deploy sync-push
supabase functions deploy sync-pull

# ✅ Done!
```

<div dir="rtl">

### الخطوة 4: تحديث الكود (10 دقائق)

</div>

```bash
# 1. تثبيت Package
cd mobile
flutter pub add supabase_flutter

# 2. تحديث supabase_config.dart
# عدّل السطور:
#   supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co'
#   supabaseAnonKey = 'YOUR_ANON_KEY'

# 3. تحديث main.dart
```

```dart
// في main.dart، أضف:
import 'utils/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(MyApp());
}
```

<div dir="rtl">

### الخطوة 5: اختبار (5 دقائق)

</div>

```bash
# 1. إنشاء مستخدم في Supabase Dashboard:
#    Authentication > Users > Add user
#    Email: test@marina-hotel.com
#    Password: test123456

# 2. تشغيل التطبيق
flutter run

# 3. تسجيل الدخول واختبار المزامنة
# ✅ Done!
```

---

## 📝 أمثلة سريعة | Quick Examples

<div dir="rtl">

### مثال 1: تسجيل الدخول

</div>

```dart
import 'package:marina_hotel/utils/supabase_config.dart';

// تسجيل الدخول
await SupabaseConfig.signInWithEmail(
  email: 'test@marina-hotel.com',
  password: 'test123456',
);

// التحقق من تسجيل الدخول
if (SupabaseConfig.isLoggedIn) {
  print('✅ Logged in as ${SupabaseConfig.currentUser?.email}');
}
```

<div dir="rtl">

### مثال 2: المزامنة

</div>

```dart
import 'package:marina_hotel/services/supabase_sync_service.dart';

// الحصول على SyncService
final syncService = ref.read(supabaseSyncServiceProvider);

// تشغيل المزامنة
try {
  await syncService.runSync();
  print('✅ Sync completed');
} catch (e) {
  print('❌ Sync failed: $e');
}
```

<div dir="rtl">

### مثال 3: الاستماع لحالة المزامنة

</div>

```dart
// في Widget
ref.listen(supabaseSyncStatusProvider, (previous, next) {
  next.when(
    data: (status) {
      switch (status) {
        case SyncStatus.pushing:
          print('📤 Pushing changes...');
          break;
        case SyncStatus.pulling:
          print('📥 Pulling changes...');
          break;
        case SyncStatus.idle:
          print('✅ Sync completed');
          break;
        case SyncStatus.error:
          print('❌ Sync error');
          break;
      }
    },
    loading: () => print('⏳ Loading...'),
    error: (error, stack) => print('❌ Error: $error'),
  );
});
```

<div dir="rtl">

### مثال 4: إنشاء غرفة (مع المزامنة)

</div>

```dart
// الكود الحالي يعمل كما هو! لا تغييرات مطلوبة.
// Current code works as-is! No changes needed.

final roomsDao = ref.read(roomsDaoProvider);

await roomsDao.insertOne(
  RoomsCompanion(
    roomNumber: Value('101'),
    type: Value('مفردة'),
    price: Value(100.0),
    status: Value('شاغرة'),
  ),
);

// سيتم إضافة التغيير تلقائياً إلى Outbox
// ثم مزامنته في المرة القادمة
// Change will be automatically added to Outbox
// Then synced next time
```

---

## 🔧 استكشاف الأخطاء السريع | Quick Troubleshooting

<div dir="rtl">

### مشكلة: "User not authenticated"

</div>

```dart
// الحل: تسجيل الدخول أولاً
await SupabaseConfig.signInWithEmail(
  email: 'your@email.com',
  password: 'your_password',
);
```

<div dir="rtl">

### مشكلة: "Function not found"

</div>

```bash
# الحل: نشر Functions
supabase functions deploy sync-push
supabase functions deploy sync-pull
```

<div dir="rtl">

### مشكلة: "RLS policy violation"

</div>

```sql
-- الحل: تحقق من RLS policies
-- في SQL Editor:
SELECT * FROM pg_policies WHERE schemaname = 'public';

-- إذا لم تجد policies، نفّذ:
-- supabase/migrations/002_rls_policies.sql
```

<div dir="rtl">

### مشكلة: "Connection timeout"

</div>

```dart
// الحل: زيادة المهلة الزمنية
final response = await supabase.functions
  .invoke('sync-push', body: {...})
  .timeout(Duration(seconds: 60)); // زيادة من 10 إلى 60
```

---

## 📊 مقارنة سريعة | Quick Comparison

| الميزة | قبل (PocketBase) | بعد (Supabase) |
|-------|-----------------|----------------|
| Database | SQLite | PostgreSQL ✅ |
| Auth | Basic | JWT + RLS ✅ |
| Scaling | Limited | Unlimited ✅ |
| Backup | Manual | Auto ✅ |
| Monitoring | No | Yes ✅ |

---

## 📚 الخطوات التالية | Next Steps

<div dir="rtl">

بعد إكمال البدء السريع:

1. ✅ اقرأ [دليل الهجرة الكامل](SUPABASE_MIGRATION_GUIDE.md)
2. ✅ نقل البيانات من PocketBase
3. ✅ شغّل الاختبارات الشاملة
4. ✅ حسّن الأداء
5. ✅ أطلق في الإنتاج!

</div>

---

## 🔗 روابط مفيدة | Useful Links

<div dir="rtl">

### الوثائق
- [Supabase Docs](https://supabase.com/docs)
- [Supabase Flutter](https://supabase.com/docs/reference/dart/introduction)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)

### الأدوات
- [Supabase Dashboard](https://app.supabase.com)
- [Supabase CLI Docs](https://supabase.com/docs/guides/cli)
- [Edge Functions Guide](https://supabase.com/docs/guides/functions)

### المجتمع
- [Discord](https://discord.supabase.com/)
- [GitHub](https://github.com/supabase/supabase)
- [Twitter](https://twitter.com/supabase)

</div>

---

## ✅ قائمة التحقق السريعة | Quick Checklist

```
☐ أنشأت مشروع Supabase
☐ نفذت SQL scripts
☐ نشرت Edge Functions
☐ حدّثت supabase_config.dart
☐ حدّثت main.dart
☐ أنشأت مستخدم اختبار
☐ اختبرت المزامنة
☐ كل شيء يعمل! 🎉
```

---

## 🆘 هل تحتاج مساعدة؟ | Need Help?

<div dir="rtl">

1. راجع [دليل استكشاف الأخطاء الكامل](SUPABASE_MIGRATION_GUIDE.md#troubleshooting)
2. شغّل الاختبارات: `flutter test test/supabase_sync_test.dart`
3. تحقق من Supabase Logs
4. اسأل في [Supabase Discord](https://discord.supabase.com/)

</div>

---

<div align="center">

### 🚀 مستعد للبدء؟ | Ready to Start?

### ابدأ بالخطوة 1 الآن! | Start with Step 1 Now!

</div>

---

**آخر تحديث | Last Updated:** 2024-11-04  
**الإصدار | Version:** 1.0.0
