# توثيق ترحيل منهجية حساب الأيام من فرع A33 إلى capy/test2

## ملخص التغيير

تم استبدال منهجية **الشرائح الفندقية** (hotel-day segments: 14:00→14:00) بمنهجية **الأيام التقويمية** (calendar-day difference + cutoff rule) المعتمدة في فرع A33.

---

## المنهجية القديمة (الشرائح الفندقية)

```dart
// كل "يوم فندقي" يبدأ من 14:00 وينتهي 14:00 اليوم التالي
// يتم عد عدد الشرائح التي يمر بها النزيل
while (cursor.isBefore(effectiveEnd)) {
  final dayStart = hotelDayStart(cursor, cutoffHour: cutoffHour);
  final dayEnd = dayStart.add(const Duration(days: 1));
  count += 1;
  cursor = segmentEnd;
}
```

**المشاكل:**
- الحساب يعتمد على وقت الدخول الدقيق (قبل/بعد 14:00)
- قد ينتج عدد أيام أكثر من المتوقع (مثال: دخول 13:00 خروج 15:00 اليوم التالي = 3 شرائح)
- منطق معقد يصعب تتبعه وصيانته

---

## المنهجية الجديدة (A33 - الأيام التقويمية)

```dart
// 1. حساب فرق التواريخ التقويمية (بدون ساعات)
final checkinDate = DateTime(checkin.year, checkin.month, checkin.day);
final checkoutDate = DateTime(end.year, end.month, end.day);
int days = checkoutDate.difference(checkinDate).inDays;

// 2. نفس اليوم = يوم واحد على الأقل
if (days == 0) {
  days = 1;
}

// 3. المغادرة بعد ساعة القطع (14:00) = يوم إضافي
if (end.hour > cutoffHour ||
    (end.hour == cutoffHour && end.minute > 0) ||
    (end.hour == cutoffHour && end.minute == 0 && end.second > 0)) {
  days += 1;
}
```

**القواعد:**
| الحالة | النتيجة |
|--------|---------|
| نفس اليوم | يوم واحد |
| فرق يوم + خروج قبل 14:00 | يوم واحد |
| فرق يوم + خروج بعد 14:00 | يومان |
| فرق يومين + خروج قبل 14:00 | يومان |
| فرق يومين + خروج بعد 14:00 | ثلاثة أيام |
| خروج بالضبط 14:00:00 | **لا** يوم إضافي |

---

## الملفات المعدّلة

### 1. `mobile/lib/utils/time.dart`

**الدالة:** `Time.nightsWithCutoff()`

```dart
/// حساب عدد الأيام مع قاعدة الساعة 14:00
/// قاعدة احتساب اليوم: يُحتسب اليوم الواحد بدءاً من وقت تسجيل الدخول الفعلي
/// وحتى الساعة 14:00 من اليوم التالي.
/// أي مغادرة بعد الساعة 14:00، حتى لو بدقيقة واحدة، تؤدي إلى احتساب يوم إضافي كامل.
static int nightsWithCutoff(
  DateTime checkin, {
  DateTime? checkout,
  int cutoffHour = 14,
}) {
  final end = checkout ?? DateTime.now();

  final checkinDate = DateTime(checkin.year, checkin.month, checkin.day);
  final checkoutDate = DateTime(end.year, end.month, end.day);
  int days = checkoutDate.difference(checkinDate).inDays;

  if (days == 0) {
    days = 1;
  }

  if (end.hour > cutoffHour ||
      (end.hour == cutoffHour && end.minute > 0) ||
      (end.hour == cutoffHour && end.minute == 0 && end.second > 0)) {
    days += 1;
  }

  return days;
}
```

**ملاحظة:** الدوال المساعدة (`hotelDayStart`, `hotelDayKey`, `hotelDayStartForNewBooking`, إلخ) بقيت موجودة لأنها تُستخدم في أماكن أخرى غير حساب الأيام (مثل `salary_cycles_adapter`، `local_db` fields).

---

### 2. `mobile/lib/services/enhanced_booking_calculation_service.dart`

#### `_buildNightSegments()` — بناء شرائح الليالي للتسعير

**قبل:** حلقة `while` تستخدم `Time.hotelDayStart()` لتقسيم الإقامة إلى شرائح فندقية (14:00→14:00)

**بعد:** حلقة `for` تبني شريحة لكل يوم تقويمي:

```dart
List<_NightSegment> _buildNightSegments(
  DateTime checkin,
  DateTime checkout, {
  int cutoffHour = 14,
  bool isNewBooking = true,
}) {
  final segments = <_NightSegment>[];

  final checkinDate = DateTime(checkin.year, checkin.month, checkin.day);
  final checkoutDate = DateTime(checkout.year, checkout.month, checkout.day);
  int days = checkoutDate.difference(checkinDate).inDays;

  if (days == 0) days = 1;

  if (checkout.hour > cutoffHour || ...) {
    days += 1;
  }

  for (int i = 0; i < days; i++) {
    final dayDate = checkinDate.add(Duration(days: i));
    final dayKey = Time.dateToString(dayDate);
    // كل شريحة = يوم تقويمي واحد
    segments.add(_NightSegment(hotelDayKey: dayKey, start: segStart, end: segEnd));
  }
  return segments;
}
```

#### `_isLegacyDiscountApplicable()` — تطبيق التخفيض القديم

**قبل:**
```dart
final hotelDay = Time.hotelDayStart(nightDate);
final discountDay = Time.hotelDayStart(discountStartDate);
return !hotelDay.isBefore(discountDay);
```

**بعد:**
```dart
final nightDay = DateTime(nightDate.year, nightDate.month, nightDate.day);
final discountDay = DateTime(discountStartDate.year, discountStartDate.month, discountStartDate.day);
return !nightDay.isBefore(discountDay);
```

**الأثر:** التخفيض يُطبّق بناءً على التاريخ التقويمي لليلة (مثلاً: تخفيض يبدأ من 15 يناير يُطبّق على كل ليلة تاريخها التقويمي ≥ 15 يناير)، بدلاً من اليوم الفندقي (14:00→14:00).

#### Fallback في `_buildNightlyBreakdown()`

**قبل:** `Time.hotelDayStart(context.checkin)` → **بعد:** `DateTime(context.checkin.year, context.checkin.month, context.checkin.day)`

---

### 3. `mobile/lib/services/booking_derived_fields_service.dart`

#### `_buildNightSegments()` — نفس التعديل بالضبط

نفس التحويل من شرائح فندقية إلى أيام تقويمية.

#### `_calculateNightlyRate()` — حساب سعر الليلة مع التخفيض

**قبل:**
```dart
final hotelDay = Time.hotelDayStart(segmentStart);
final hotelDayDate = DateTime(hotelDay.year, hotelDay.month, hotelDay.day);
// ...
if (!hotelDayDate.isBefore(discountDay)) {
  rate = (baseRate - discount).clamp(0.0, baseRate);
}
```

**بعد:**
```dart
final segDay = DateTime(segmentStart.year, segmentStart.month, segmentStart.day);
// ...
if (!segDay.isBefore(discountDay)) {
  rate = (baseRate - discount).clamp(0.0, baseRate);
}
```

**الأثر:** التخفيض يُطبّق على الليلة بناءً على تاريخها التقويمي مباشرة.

---

### 4. `mobile/lib/services/restore_fix_service.dart`

#### `_buildNightSegments()` (unused) + `_hotelDayKey()`

**قبل:** `_hotelDayKey` يستخدم `_hotelDayStart` (14:00 shift)
**بعد:** `_hotelDayKey` يستخدم التاريخ التقويمي مباشرة

```dart
String _hotelDayKey(DateTime value) =>
    Time.dateToString(DateTime(value.year, value.month, value.day));
```

**الأثر:** مفاتيح دفتر اليومية (ledger) للمدفوعات والمصروفات تعتمد على التاريخ التقويمي.

**ملاحظة:** `_buildNightSegments` مؤشّرة كـ `unused_element` — إعادة بناء الليالي الفعلية تتم عبر `EnhancedBookingCalculationService.calculateForBooking()` (سطر 786-788).

---

### 5. `mobile/test/time_utils_test.dart`

تم تحديث اختبار `nightsWithCutoff` ليتوافق مع المنهجية الجديدة:

```dart
test('nightsWithCutoff uses date difference + cutoff rule', () {
  // checkin 1 يناير 13:00, checkout 2 يناير 15:00
  // فرق التواريخ = 1 يوم، المغادرة 15:00 > 14:00 → +1 = 2
  expect(Time.nightsWithCutoff(checkin, checkout: checkout, cutoffHour: 14), 2);

  // نفس اليوم → 1
  expect(sameDay, 1);

  // فرق يومين + خروج 13:00 < 14:00 → 2
  expect(multi, 2);

  // فرق يومين + خروج 14:01 > 14:00 → 3
  expect(afterCutoff, 3);

  // خروج بالضبط 14:00:00 → لا يوم إضافي → 2
  expect(exactCutoff, 2);
});
```

---

## كيف تعمل التخفيضات والزيادات مع المنهجية الجديدة

### تدفق العمل:

```
1. إنشاء تعديل سعر (BookingPriceAdjustmentService.applyTemporaryAdjustment)
   ↓
2. حفظ في جدول booking_price_adjustments مع:
   - effectiveHotelDay: تاريخ بداية التعديل (yyyy-mm-dd)
   - endHotelDay: تاريخ نهاية التعديل (اختياري)
   - adjustmentType: 0 = تخفيض، 1 = زيادة
   - adjustmentMode: 'per_night' | 'total' | 'percentage'
   - amount: المبلغ
   ↓
3. إعادة حساب الحجز (BookingDerivedFieldsService.refreshForBooking)
   ↓
4. بناء شرائح الليالي (_buildNightSegments) ← المنهجية الجديدة
   - كل شريحة = يوم تقويمي واحد
   - hotelDayKey = التاريخ التقويمي (yyyy-mm-dd)
   ↓
5. لكل ليلة، تُطبّق التعديلات (_buildNightlyBreakdown):
   - يُقارن hotelDayKey مع effectiveHotelDay/endHotelDay
   - إذا الليلة ضمن النطاق → يُطبّق التعديل
   ↓
6. حساب السعر النهائي:
   finalRate = (baseRate + adjustmentTotal).clamp(0, baseRate * 3)
```

### أنواع التعديلات:

| النوع | الوصف | الحساب |
|-------|-------|--------|
| `per_night` | مبلغ ثابت لكل ليلة | `±amount` لكل ليلة في النطاق |
| `total` | مبلغ إجمالي يُوزّع | `±(amount / nightsInRange)` لكل ليلة |
| `percentage` | نسبة من سعر الليلة | `±(baseRate × amount / 100)` لكل ليلة |

### التخفيض القديم (Legacy Discount):

يُطبّق من حقل `booking.discount` مع `booking.discountStartDate`:
- إذا `discountType == 'total'` → يُخصم من الإجمالي النهائي مباشرة
- إذا `discountType != 'total'` → يُخصم لكل ليلة بدءاً من `discountStartDate`
- المقارنة الآن بالتاريخ التقويمي: `nightDate >= discountStartDate`

---

## المزامنة (Sync)

### مزامنة سجلات الليالي (booking_nights):

```
Appwrite ←→ Local DB

Upload: _bookingNightToRemote() يرسل:
  - hotelDayKey (الآن = تاريخ تقويمي)
  - nightStart, nightEnd
  - nightlyRate (السعر النهائي بعد التعديلات)
  - sequence, origin

Download: _syncBookingNights() يستقبل ويحفظ محلياً
```

### مزامنة تعديلات الأسعار (booking_price_adjustments):

```
Appwrite ←→ Local DB

Upload: تعديلات الأسعار تُرفع مع:
  - effectiveHotelDay, endHotelDay
  - adjustmentType, adjustmentMode, amount
  - isActive, reason, appliedBy

Download: _syncBookingPriceAdjustments() يستقبل ثم:
  1. يحفظ التعديل محلياً
  2. يعيد حساب الحجز المتأثر:
     await _bookingsRepository.derivedFields.refreshForBookingId(adj.bookingLocalId!)
```

### إعادة البناء (Restore Fix):

`restore_fix_service.dart` يستخدم `EnhancedBookingCalculationService` لإعادة بناء كل الليالي من الصفر — وهو الآن يعمل بمنهجية A33.

```
restoreAndFix() →
  _rebuildBookingNights() →
    _processBookingForNights() →
      EnhancedBookingCalculationService.calculateForBooking() ← المنهجية الجديدة
```

---

## أمثلة عملية

### مثال 1: إقامة عادية
- **دخول:** 10 يناير 20:00
- **خروج:** 12 يناير 13:00
- **الأيام:** `12 - 10 = 2`، خروج 13:00 < 14:00 → **2 أيام**
- **الشرائح:** `2024-01-10`, `2024-01-11`

### مثال 2: إقامة مع يوم إضافي
- **دخول:** 10 يناير 20:00
- **خروج:** 12 يناير 15:00
- **الأيام:** `12 - 10 = 2`، خروج 15:00 > 14:00 → `2 + 1` = **3 أيام**
- **الشرائح:** `2024-01-10`, `2024-01-11`, `2024-01-12`

### مثال 3: إقامة مع تخفيض
- **سعر الغرفة:** 100
- **تخفيض:** 20 per_night من 11 يناير
- **الشرائح:**
  - `2024-01-10`: سعر 100 (قبل بداية التخفيض)
  - `2024-01-11`: سعر 80 (100 - 20)
  - `2024-01-12`: سعر 80 (100 - 20)
- **الإجمالي:** 260

### مثال 4: إقامة مع زيادة
- **سعر الغرفة:** 100
- **زيادة:** 30 per_night من 11 يناير
- **الشرائح:**
  - `2024-01-10`: سعر 100
  - `2024-01-11`: سعر 130 (100 + 30)
  - `2024-01-12`: سعر 130 (100 + 30)
- **الإجمالي:** 360
