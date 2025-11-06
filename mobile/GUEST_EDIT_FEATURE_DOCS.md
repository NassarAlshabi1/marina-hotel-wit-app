# ميزة تعديل بيانات النزيل - دليل شامل

## نظرة عامة

تم إضافة ميزة تعديل كامل بيانات النزيل في شاشة "إدارة الضيوف" مع معالجة متقدمة للبيانات المالية والغرف.

## الملفات المضافة/المعدلة

### 1. الملفات الجديدة
- `/mobile/lib/screens/settings/guest_edit_screen.dart` - شاشة تعديل بيانات النزيل الكاملة

### 2. الملفات المعدلة
- `/mobile/lib/screens/settings/settings_guests.dart` - إضافة زر "تعديل" ودالة التنقل

## الميزات الرئيسية

### 1. واجهة مستخدم كاملة لتعديل البيانات

#### بيانات النزيل الأساسية:
- ✅ اسم النزيل (guestName)
- ✅ رقم الهاتف (guestPhone) مع التنسيق التلقائي
- ✅ نوع الهوية (guestIdType) - dropdown
- ✅ رقم الهوية (guestIdNumber)
- ✅ تاريخ إصدار الهوية (guestIdIssueDate)
- ✅ جهة الإصدار (guestIdIssuePlace)
- ✅ الجنسية (guestNationality)
- ✅ العنوان (guestAddress)

#### بيانات الحجز:
- ✅ رقم الغرفة (roomNumber) - dropdown مع الغرف المتاحة فقط
- ✅ تاريخ الوصول (checkinDate) مع date/time picker
- ✅ تاريخ المغادرة المخطط (checkoutDate) مع date/time picker
- ✅ عدد الليالي المتوقع (expectedNights) مع حساب تلقائي
- ✅ حالة الحجز (status) - dropdown
- ✅ ملاحظات (notes)

### 2. معالجة متقدمة لتغيير رقم الغرفة

#### عند تغيير رقم الغرفة من (مثلاً 101 إلى 202)، يتم تلقائياً:

**A. تحديث بيانات الحجز:**
```dart
await bookingsRepo.update(
  bookingId,
  roomNumber: newRoomNumber,
  // جميع البيانات المعدلة الأخرى
);
```

**B. تحديث البيانات المالية:**
- تحديث جميع المدفوعات المرتبطة بالحجز لتظهر تحت رقم الغرفة الجديد
- يتم البحث عن كل مدفوعات الحجز وتحديث `roomNumber` فيها

**C. تحديث حالة الغرف:**
- تحرير الغرفة القديمة → تحويلها إلى "شاغرة"
- تحديث الغرفة الجديدة → تحويلها إلى "محجوزة" (إذا كان الحجز نشط)
- استخدام `StatusUtils.isActiveBooking()` للتحقق من حالة الحجز

**D. التحقق من صحة البيانات:**
- التأكد من أن الغرفة الجديدة متاحة
- عرض رسالة خطأ إذا كانت الغرفة محجوزة

### 3. إعادة حساب الليالي والتكاليف تلقائياً

#### حساب الليالي:
```dart
final checkinDt = DateTime.parse(checkinDate);
final checkoutDt = checkoutDate != null ? DateTime.parse(checkoutDate) : null;
final calculatedNights = Time.nightsWithCutoff(checkinDt, checkout: checkoutDt);
```

#### قاعدة حساب الليالي (14:00):
- يُحتسب اليوم الواحد من وقت الدخول حتى الساعة 14:00 من اليوم التالي
- أي مغادرة بعد 14:00 (حتى بدقيقة واحدة) تُحتسب كيوم إضافي كامل
- يتم استخدام `Time.nightsWithCutoff()` من `/mobile/lib/utils/time.dart`

#### التحديث التلقائي:
- عند تغيير تاريخ الوصول أو المغادرة
- يتم حساب عدد الليالي تلقائياً وتحديث الحقل

### 4. معالجة الأخطاء والتنبيهات

#### تنبيهات تغيير الغرفة:
```dart
AlertDialog مع:
- عرض الغرفة القديمة والجديدة
- توضيح التغييرات التي ستحدث:
  • تحديث بيانات الحجز
  • تحديث جميع المدفوعات المرتبطة
  • تحديث حالة الغرفة القديمة (شاغرة)
  • تحديث حالة الغرفة الجديدة (محجوزة)
- تحذير حول تأثير التغيير على البيانات المالية
```

#### تنبيهات الحجوزات المكتملة:
- عرض تحذير برتقالي في AppBar
- عرض بطاقة تحذير في أعلى الشاشة
- توضيح أن التعديلات قد تؤثر على التقارير المالية

#### رسائل النجاح/الفشل:
- رسالة نجاح خضراء عند الحفظ: "تم تحديث بيانات النزيل بنجاح"
- رسالة خطأ حمراء عند الفشل مع تفاصيل الخطأ
- رسالة تحذير إذا كانت الغرفة غير متاحة

### 5. التحقق من صحة البيانات

#### التحقق من الحقول المطلوبة:
- اسم النزيل *
- رقم الهاتف *
- الجنسية *
- رقم الغرفة *
- تاريخ الوصول *
- عدد الليالي المتوقع * (يجب أن يكون >= 1)

#### التحقق من توفر الغرفة:
- عند تغيير رقم الغرفة، يتم التحقق من أن الغرفة الجديدة متاحة
- يتم استخدام `StatusUtils.isRoomAvailable()` للتحقق
- الغرفة الحالية تظهر دائماً حتى لو كانت محجوزة

### 6. معالجة رقم الهاتف

```dart
String _normalizePhone(String value) {
  // إزالة جميع الرموز غير الرقمية
  final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return value.trim();
  
  var normalized = digitsOnly;
  
  // إزالة 00 من البداية
  if (normalized.startsWith('00') && normalized.length > 2) {
    normalized = normalized.substring(2);
  }
  
  // إزالة 0 من البداية للأرقام المحلية (10 أرقام)
  if (normalized.startsWith('0') && normalized.length == 10) {
    normalized = normalized.substring(1);
  }
  
  // إضافة كود الدولة 967 إذا لم يكن موجوداً
  if (!normalized.startsWith('967')) {
    normalized = '967$normalized';
  }
  
  return normalized;
}
```

## سير العمل (Workflow)

### 1. الوصول إلى شاشة التعديل
```
شاشة إدارة الضيوف → بطاقة الضيف → زر "تعديل" → GuestEditScreen
```

### 2. تعديل البيانات
```
المستخدم يعدل البيانات → التحقق من الصحة → حفظ
```

### 3. معالجة تغيير الغرفة
```
المستخدم يغير رقم الغرفة → كشف التغيير (_roomChanged = true)
→ عرض تحذير تأكيد → المستخدم يؤكد
→ التحقق من توفر الغرفة → تحديث البيانات
→ _updateGuestData() → _handleRoomChange()
→ تحديث المدفوعات + تحديث حالة الغرف
```

### 4. حفظ التعديلات
```
_saveChanges() → التحقق من الصحة
→ تأكيد تغيير الغرفة (إذا لزم)
→ التحقق من توفر الغرفة (إذا لزم)
→ _updateGuestData()
  → تحديث الحجز
  → _handleRoomChange() (إذا تم تغيير الغرفة)
    → تحديث المدفوعات
    → _refreshRoomOccupancy()
      → تحديث حالة الغرفة القديمة
      → تحديث حالة الغرفة الجديدة
→ عرض رسالة نجاح → الرجوع للشاشة السابقة
```

## الدوال الرئيسية

### في `guest_edit_screen.dart`:

#### `_saveChanges()`
- التحقق من صحة النموذج
- عرض تأكيد تغيير الغرفة إذا لزم
- التحقق من توفر الغرفة الجديدة
- استدعاء `_updateGuestData()`
- عرض رسائل النجاح/الفشل

#### `_updateGuestData()`
- جمع جميع البيانات من النموذج
- حساب الليالي باستخدام `Time.nightsWithCutoff()`
- تحديث الحجز عبر `bookingsRepo.update()`
- استدعاء `_handleRoomChange()` إذا تم تغيير الغرفة
- استدعاء `_refreshRoomOccupancy()` في جميع الحالات

#### `_handleRoomChange(String newRoomNumber)`
- جلب جميع المدفوعات المرتبطة بالحجز
- تحديث `roomNumber` في كل دفعة
- استدعاء `_refreshRoomOccupancy()`

#### `_refreshRoomOccupancy()`
- جلب جميع الحجوزات النشطة
- تحديد الغرف المحجوزة
- تحديث حالة الغرفة القديمة (شاغرة إذا لم تعد محجوزة)
- تحديث حالة الغرفة الجديدة (محجوزة إذا كان الحجز نشط)

#### `_recalculateExpectedNights()`
- استخراج تواريخ الوصول والمغادرة
- حساب الليالي باستخدام `Time.nightsWithCutoff()`
- تحديث حقل عدد الليالي تلقائياً

#### `_buildRoomSelector()`
- عرض dropdown للغرف المتاحة
- إضافة الغرفة الحالية دائماً
- عرض تحذير عند تغيير الغرفة
- معالجة حالات الخطأ وعدم توفر الغرف

### في `settings_guests.dart`:

#### `_editGuestData(BuildContext context, _GuestInfo guest)`
- استخراج أحدث حجز للضيف (`guest.bookings.first`)
- التنقل إلى `GuestEditScreen`
- تمرير الحجز كمعامل

## الأنماط والممارسات المستخدمة

### 1. استخدام Providers (Riverpod)
```dart
final bookingsRepo = ref.watch(bookingsRepoProvider);
final paymentsRepo = ref.watch(paymentsRepoProvider);
final roomsRepo = ref.watch(roomsRepoProvider);
final db = ref.read(databaseProvider);
```

### 2. معالجة التواريخ
```dart
// تنسيق: YYYY-MM-DD HH:MM:SS
DateTime? _parseDateTime(String value) {
  if (value.isEmpty) return null;
  final normalized = value.contains('T') ? value : value.replaceAll(' ', 'T');
  final withSeconds = normalized.length == 16 ? '${normalized}:00' : normalized;
  try {
    return DateTime.parse(withSeconds);
  } catch (_) {
    return null;
  }
}

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min:$s';
}
```

### 3. معالجة النصوص الاختيارية
```dart
String? _optionalText(String text) => text.trim().isEmpty ? null : text.trim();
```

### 4. التحقق من الحقول المطلوبة
```dart
String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null;
```

### 5. استخدام Directionality للعربية
```dart
Directionality(
  textDirection: TextDirection.rtl,
  child: Scaffold(...)
)
```

## ضمانات سلامة البيانات

### 1. النسخ الاحتياطي التلقائي
- سيتم تفعيل النسخ الاحتياطي تلقائياً عبر `AutoBackupManager.instance.onDataChange`
- يتم حفظ نسخة احتياطية بعد كل تغيير

### 2. المزامنة
- سيتم إضافة التغييرات إلى Outbox تلقائياً عبر DAOs
- المزامنة مع السيرفر ستحدث في الخلفية

### 3. Transactions (ضمنية)
- Drift يستخدم transactions تلقائياً في DAOs
- جميع التحديثات إما تنجح كلها أو تفشل كلها

### 4. التحقق من الصحة
- التحقق من صحة البيانات على مستوى النموذج
- التحقق من توفر الغرفة قبل الحفظ
- رسائل خطأ واضحة ومحددة

## ملاحظات مهمة

### 1. الحجوزات المكتملة
- يمكن تعديل الحجوزات المكتملة لكن مع تحذير واضح
- التحذير يظهر في AppBar وفي بطاقة أعلى الشاشة
- المستخدم مسؤول عن فهم تأثير التعديلات على التقارير

### 2. تغيير الغرفة
- يتطلب تأكيد من المستخدم
- يحدث dialog يشرح جميع التغييرات التي ستحدث
- يتم تحديث جميع البيانات المرتبطة تلقائياً

### 3. حساب الليالي
- يتم حساب الليالي تلقائياً عند تغيير التواريخ
- يستخدم قاعدة 14:00 للمغادرة
- `calculatedNights` يتم تخزينه في قاعدة البيانات

### 4. رقم الهاتف
- يتم تنسيق الرقم تلقائياً إلى صيغة E.164
- يتم إضافة كود الدولة 967 تلقائياً
- يتم حفظ الرقم منسقاً في قاعدة البيانات

## الاختبار

### سيناريوهات الاختبار الموصى بها:

1. **تعديل بيانات النزيل فقط** (بدون تغيير الغرفة)
   - تعديل الاسم، الهاتف، الجنسية
   - التحقق من حفظ التغييرات
   - التحقق من عدم تأثر حالة الغرف

2. **تعديل تواريخ الإقامة**
   - تغيير تاريخ الوصول
   - تغيير تاريخ المغادرة
   - التحقق من إعادة حساب الليالي تلقائياً

3. **تغيير رقم الغرفة**
   - تغيير من غرفة لأخرى
   - التأكد من ظهور dialog التأكيد
   - التحقق من تحديث المدفوعات
   - التحقق من حالة الغرفة القديمة (شاغرة)
   - التحقق من حالة الغرفة الجديدة (محجوزة)

4. **محاولة تغيير لغرفة محجوزة**
   - اختيار غرفة غير متاحة
   - التحقق من ظهور رسالة خطأ

5. **تعديل حجز مكتمل**
   - التحقق من ظهور التحذيرات
   - التحقق من إمكانية الحفظ

## الملفات المرجعية

- `/mobile/lib/screens/bookings/booking_edit.dart` - النموذج الأصلي للإضافة/التعديل
- `/mobile/lib/utils/time.dart` - دوال حساب الوقت والتواريخ
- `/mobile/lib/utils/status_utils.dart` - دوال إدارة الحالات
- `/mobile/lib/services/repositories/bookings_repository.dart` - عمليات قاعدة البيانات للحجوزات
- `/mobile/lib/services/repositories/payments_repository.dart` - عمليات قاعدة البيانات للمدفوعات
- `/mobile/lib/services/repositories/rooms_repository.dart` - عمليات قاعدة البيانات للغرف

## الخلاصة

تم إضافة نظام كامل لتعديل بيانات النزيل مع:
- ✅ واجهة مستخدم شاملة وسهلة الاستخدام
- ✅ معالجة متقدمة لتغيير الغرفة مع تحديث تلقائي للبيانات المالية
- ✅ إعادة حساب الليالي والتكاليف تلقائياً
- ✅ التحقق من صحة البيانات والتحقق من توفر الغرف
- ✅ معالجة الأخطاء والتنبيهات الواضحة
- ✅ ضمانات سلامة البيانات مع النسخ الاحتياطي والمزامنة

النظام جاهز للاستخدام! 🎉
