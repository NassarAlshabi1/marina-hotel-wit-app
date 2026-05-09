# إصلاح خطأ استعادة النسخة الاحتياطية

## 🐛 المشكلة

عند استعادة النسخة الاحتياطية، يظهر الخطأ التالي:

```
SqliteException(787): while executing statement, FOREIGN KEY constraint failed, constraint failed (code 787)

Causing statement: INSERT INTO "booking_nights" (...)
```

### الصورة المرفقة من المستخدم:
![الخطأ](./17669723542706142339629332383016.jpg)

---

## 🔍 تحليل المشكلة

### السبب الجذري:
المشكلة في ملف `google_drive_backup_service.dart` في دالة `importDatabaseFromJson()`:

```dart
// الكود القديم (الخاطئ)
await db.customStatement('PRAGMA foreign_keys = OFF');
try {
  // حذف جميع الجداول
  await db.delete(db.rooms).go();
  await db.delete(db.bookings).go();
  // ... المزيد من عمليات الحذف
} finally {
  await db.customStatement('PRAGMA foreign_keys = ON');  // ❌ خطأ هنا!
}

// ثم تبدأ الاستعادة بينما FOREIGN KEYS مفعلة
if (backupData.containsKey('rooms')) {
  // ... استعادة البيانات
}
```

### التسلسل الخاطئ:

1. ✅ تعطيل FOREIGN KEYS
2. ✅ حذف جميع الجداول
3. ❌ **إعادة تشغيل FOREIGN KEYS في finally block**
4. ❌ **البدء في استعادة البيانات بينما FOREIGN KEYS مفعلة**
5. ❌ **فشل عند إدراج booking_nights لأن booking_local_id غير موجود بعد**

### لماذا يفشل؟

جدول `booking_nights` يحتوي على FOREIGN KEY يشير إلى `bookings`:

```sql
CREATE TABLE booking_nights (
  id INTEGER PRIMARY KEY,
  booking_local_id INTEGER NOT NULL,
  -- ... المزيد من الحقول
  FOREIGN KEY (booking_local_id) REFERENCES bookings(id)
);
```

عندما يحاول النظام إدراج بيانات في `booking_nights`، يتحقق SQLite من وجود `booking_local_id` في جدول `bookings`. ولكن لأن FOREIGN KEYS مفعلة، والترتيب قد لا يكون مضموناً في JSON، فإن الإدراج يفشل.

---

## ✅ الحل

### التعديل المطلوب:

```dart
// الكود الجديد (الصحيح)
await db.customStatement('PRAGMA foreign_keys = OFF');
try {
  // حذف جميع الجداول
  await db.delete(db.rooms).go();
  await db.delete(db.bookings).go();
  await db.delete(db.bookingNights).go();
  // ... المزيد من عمليات الحذف

  // استعادة البيانات بالترتيب الصحيح (الجداول الرئيسية أولاً)
  if (backupData.containsKey('rooms')) {
    // ... استعادة الغرف
  }

  if (backupData.containsKey('bookings')) {
    // ... استعادة الحجوزات
  }

  if (backupData.containsKey('booking_nights')) {
    // ... استعادة ليالي الحجز
  }

  // ... باقي الاستعادة

  // تشغيل auto-fix
  final fixService = RestoreFixService(db);
  await fixService.runAutoFixAfterRestore(backupTimestamp: metadata.backupTimestamp);

} finally {
  // ✅ إعادة تشغيل FOREIGN KEYS في النهاية فقط
  await db.customStatement('PRAGMA foreign_keys = ON');
  _log('🔓 تم إعادة تشغيل FOREIGN KEYS');
}
```

### التسلسل الصحيح:

1. ✅ تعطيل FOREIGN KEYS
2. ✅ حذف جميع الجداول
3. ✅ **استعادة جميع البيانات بدون فحص FOREIGN KEYS**
4. ✅ **تشغيل auto-fix لإصلاح أي تعارضات**
5. ✅ **إعادة تشغيل FOREIGN KEYS في النهاية**

---

## 📊 المقارنة بين الفرعين

### النتيجة:
**كلا الفرعين يحتويان على نفس المشكلة!**

| الفرع | المشكلة | الإصلاح |
|------|---------|---------|
| `capy/S` | ✅ تم الإصلاح | ✅ في هذا الـ commit |
| `capy/google-drive-auto-sync-engine` | ❌ نفس المشكلة | ⚠️ يحتاج نفس الإصلاح |

---

## 🧪 الاختبار

### خطوات التحقق من الإصلاح:

1. **إنشاء نسخة احتياطية:**
   ```
   الإعدادات → النسخ الاحتياطي - Google Drive → نسخ احتياطي يدوي
   ```

2. **إضافة بعض البيانات:**
   - إضافة حجز جديد
   - إضافة مدفوعات
   - إضافة ملاحظات

3. **استعادة النسخة:**
   ```
   الإعدادات → النسخ الاحتياطي - Google Drive → استعادة
   ```

4. **النتيجة المتوقعة:**
   - ✅ الاستعادة تتم بنجاح
   - ✅ لا يظهر خطأ FOREIGN KEY
   - ✅ جميع البيانات موجودة

---

## 🔧 الملفات المعدلة

### الملف الرئيسي:
- `mobile/lib/services/google_drive_backup_service.dart`

### التغييرات:
1. إزالة `finally` block من قسم الحذف
2. إضافة `try-finally` block يغطي الحذف والاستعادة معاً
3. إعادة تشغيل FOREIGN KEYS في النهاية فقط

---

## 📝 ملاحظات إضافية

### لماذا لم تظهر المشكلة من قبل؟

1. **النسخ الصغيرة:** إذا كانت النسخة الاحتياطية صغيرة جداً أو فارغة
2. **الترتيب الصحيح:** إذا صادف أن الترتيب في JSON كان صحيحاً
3. **عدم وجود FOREIGN KEYS:** إذا كانت الجداول لا تحتوي على علاقات

### لماذا ظهرت الآن؟

1. **بيانات حقيقية:** وجود بيانات فعلية في جدول booking_nights
2. **FOREIGN KEY constraints:** تفعيل constraints في القاعدة
3. **ترتيب غير متوقع:** JSON لا يضمن ترتيب معين

---

## 🎯 الخلاصة

### المشكلة الأساسية:
- إعادة تشغيل FOREIGN KEYS **قبل** الانتهاء من استعادة البيانات

### الحل:
- إبقاء FOREIGN KEYS معطلة حتى **نهاية** عملية الاستعادة بالكامل

### الفائدة:
- ✅ استعادة ناجحة دون أخطاء
- ✅ حماية سلامة البيانات
- ✅ تجربة مستخدم أفضل

---

**تاريخ الإصلاح:** 29 ديسمبر 2025  
**الفرع:** `capy/S`  
**الملف المعدل:** `google_drive_backup_service.dart`
