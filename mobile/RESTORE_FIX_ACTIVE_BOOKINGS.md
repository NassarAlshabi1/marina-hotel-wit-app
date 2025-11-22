# إصلاح حساب الليالي للحجوزات النشطة بعد الاستعادة

## المشكلة

عند استعادة نسخة احتياطية قديمة، الحجوزات النشطة (بدون `actualCheckout`) كانت تُحسب بناءً على `checkoutDate` المخطط بدلاً من التاريخ الحالي.

### مثال على السيناريو:

```
📅 يوم 12 يناير (تاريخ النسخة الاحتياطية):
├─ نزيل دخل يوم 10 يناير (checked_in)
├─ checkoutDate = 2025-01-15 (تاريخ مخطط)
├─ actualCheckout = null (لا يزال في الفندق)
├─ الليالي حتى الآن: 2 ليلة
└─ المبلغ: 2 × 15,000 = 30,000 ريال

📅 يوم 13 يناير (بعد الاستعادة):
├─ النزيل لا يزال موجوداً
├─ الليالي الصحيحة: 3 ليالي (10→11, 11→12, 12→13)
└─ المبلغ الصحيح: 3 × 15,000 = 45,000 ريال ✅
```

### المشكلة السابقة:
```dart
// ❌ كان يستخدم checkoutDate المخطط (2025-01-15)
final checkoutDate = booking.actualCheckout != null 
    ? DateTime.parse(booking.actualCheckout!)
    : DateTime.parse(booking.checkoutDate!);

// النتيجة: حساب خاطئ = 5 ليالي!
```

## الحل المُطبق

### 1. تعديل `RestoreFixService`

في `/mobile/lib/services/restore_fix_service.dart`:

```dart
/// إصلاح تواريخ وليالي الحجز
Future<List<String>> _fixBookingDatesAndNights(Booking booking, DateTime now, String fixId) async {
  // ...
  
  // ✅ للحجوزات النشطة: استخدم التاريخ الحالي
  final checkoutDate = booking.actualCheckout != null 
      ? DateTime.parse(booking.actualCheckout!)
      : now;  // استخدم التاريخ الحالي بدلاً من المخطط
  
  // حساب الليالي باستخدام قاعدة الساعة 14:00
  final calculatedNights = Time.nightsWithCutoff(checkinDate, checkout: checkoutDate);
  
  // ...
}
```

### 2. اختبار السيناريو

في `/mobile/test/restore_fix_service_test.dart`:

```dart
test('حجز نشط بدون checkout - يجب حساب الليالي حتى التاريخ الحالي', () async {
  // إنشاء حجز نشط
  final checkin = DateTime(2024, 1, 10);
  final plannedCheckout = DateTime(2024, 1, 15);
  
  // النسخة الاحتياطية كانت في يوم 12 (ليلتان)
  expectedNights: 2,
  calculatedNights: 2,
  
  // الاستعادة في يوم 13
  final restoreDate = DateTime(2024, 1, 13);
  
  // النتيجة: يجب أن تصبح 3 ليالي ✅
  expect(updatedBooking.calculatedNights, equals(3));
});
```

## النتيجة

✅ **للحجوزات المكتملة** (مع `actualCheckout`): 
   - يستخدم تاريخ الخروج الفعلي (كما كان)

✅ **للحجوزات النشطة** (بدون `actualCheckout`):
   - يستخدم التاريخ الحالي `now` ← **هذا هو الإصلاح**
   - يحسب الليالي من `checkinDate` حتى الآن
   - يحدث `calculatedNights` و `expectedNights` تلقائياً

✅ **المدفوعات**:
   - `_recalculateBookingFinancials` يتحقق من التطابق بناءً على `calculatedNights` الجديد
   - يسجل تحذير إذا كان هناك فرق

## ملاحظات

### ما لم يتم تعديله:
- **`checkoutDate`** في قاعدة البيانات يبقى كما هو (التاريخ المخطط)
- **المصروفات والرواتب** تبقى كما هي (بيانات تاريخية)
- **تواريخ المدفوعات** تبقى كما هي

### ما يحتاج مراجعة:
- **UI في `bookings_list.dart`**: لا يزال يستخدم الطريقة القديمة
- **UI في `booking_checkout_screen.dart`**: لا يزال يستخدم الطريقة القديمة
- **UI في `booking_payment_screen.dart`**: لا يزال يستخدم الطريقة القديمة

### التوصية:
لكي يكون النظام متسقاً بالكامل، يُنصح بتطبيق نفس المنطق في UI:

```dart
// في UI، بدلاً من:
final actualNights = Time.nightsWithCutoff(checkin, 
  checkout: actualCheckout ?? plannedCheckout);

// استخدم:
final actualNights = Time.nightsWithCutoff(checkin, 
  checkout: actualCheckout ?? DateTime.now());
```

## الاختبار

لتشغيل الاختبارات:
```bash
cd mobile
flutter test test/restore_fix_service_test.dart
```

تحقق من "الاختبار الثامن" للسيناريو المحدد.

## التاريخ
- **التاريخ**: 2025-01-22
- **المطور**: Capy AI
- **المراجع**: Yaser Nassar
