# خطة مختصرة لتحديث قاعدة البيانات (الحد الأدنى من التغييرات)

هذه المسودة تلخص النهج المتفق عليه للحفاظ على الجداول الحالية قدر الإمكان، مع إضافة أقل مجموعة ممكنة من الحقول/البنى المساندة لدعم وحدة Smart Sync + Smart Restore + Auto-Fix.

---

## المبادئ الأساسية
- عدم إزالة أو استبدال أي جدول قائم.
- إضافة الحقول الضرورية فقط داخل الجداول الحالية.
- إنشاء جدول جديد واحد فقط (BookingNights) لأن البيانات اليومية لا يمكن تمثيلها بالأعمدة الحالية.
- تشغيل جميع التعديلات ضمن معاملات لضمان السلامة.
- Auto-Fix يستخدم نفس الجداول بعد التحديث، ولا يحتاج بنية منفصلة.

---

## التعديلات المقترحة

### 1. حقول الزمن بصيغة ISO
- تحديث mixin `SyncFields` لتحويل `createdAt`, `updatedAt`, `deletedAt` إلى أعمدة نصية (ISO 8601).
- الاحتفاظ بنسخة رقمية (`createdAtEpoch`, `lastModifiedEpoch`) للفهارس.
- تطبيق التحويل على جميع الجداول التي تعتمد `SyncFields` (bookings, payments, rooms, expenses, debts, …).

### 2. جدول BookingNights (الوحيد الجديد)
- الحقول الرئيسية:
  - `bookingLocalId`, `hotelDayKey`, `nightStartIso`, `nightEndIso`, `nightlyRate`, `sequence`.
  - قيد أساسي مركب `{bookingLocalId, hotelDayKey}` لضمان عدم تكرار الليالي عند إعادة تشغيل Auto-Fix.

### 3. تعديلات طفيفة على الجداول الحالية
#### Bookings
- إضافة أعمدة مشتقة: `totalPaidCached`, `remainingBalanceCached`, `isFullyPaid`, `isOverdue`, `hotelDayCheckin`, `hotelDayCheckout`, `lastNightEpoch`.
- لا حاجة لجداول إضافية لتخزين هذه البيانات.

#### Payments
- إضافة `hotelDayKey`, `isPendingBalance`, `bookingUuidCache` لدعم إعادة الربط وحساب الأرصدة.

#### Rooms
- إضافة أعمدة لحالة التنظيف والإشغال: `cleaningStatus`, `lastCleanedHotelDay`, `lastOccupiedHotelDay`.

#### Expenses / Debts / Salaries
- Expenses: فقط `hotelDayKey`, `categoryUuid` لاستخدامها في التقارير.
- Debts: إضافة `debtUuid`, `hotelDayOpened`, `isFromAutoFix`.
- الرواتب: يمكن الاكتفاء بإضافة أعمدة (`cycleMonth`, `remainingDue`) ضمن الجداول الحالية بدلًا من إنشاء بنية جديدة بالكامل.

---

## تدفق Auto-Fix مع البنية الحالية
1. بعد الاستعادة، تشغيل Auto-Fix.
2. إعادة بناء الليالي وتخزينها في `BookingNights`.
3. تحديث الحقول المشتقة داخل `bookings`, `payments`, `rooms`.
4. لا حاجة لجداول إضافية؛ يتم توظيف الحقول المضافة للتقارير والمزامنة.

---

## خطوات التنفيذ الموجزة
1. كتابة migration في `local_db.dart` لتنفيذ التغييرات المذكورة.
2. تحديث DAOs لدعم الحقول الجديدة.
3. تعديل Auto-Fix ليقرأ ويكتب في الأعمدة/الجدول الجديد.
4. تحديث `DeltaSyncService` ليأخذ الحقول الجديدة بعين الاعتبار دون توسعة كبيرة.
5. إضافة اختبارات للتأكد من نجاح الترحيل وتكامل Auto-Fix.

---

## ملاحظات إضافية
- يمكن الرجوع إلى هذه الخطة عند تنفيذ أي تحديثات مستقبلية أو تقييم الحاجة إلى توسيعات إضافية.
- في حال الحاجة إلى دعم تقارير أكثر تعقيدًا مستقبلًا، يمكن إضافة جداول مساندة لاحقًا دون التأثير على هذا التصميم.
