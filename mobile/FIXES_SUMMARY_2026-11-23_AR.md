# توثيق الإصلاحات الهندسية والمالية الشاملة — تطبيق مارينا هوتيل (`mobile/`)

**التاريخ:** 2026-11-23  
**الفرع المرجعي:** `arena/7968950d-marina-hotel-wit-app` / `arena/d0784b53-marina-hotel-wit-app` (متفرع من `guest-adjustment-edit-end`)  
**نطاق العمل:** معالجة تضخم وتكرار ليالي الحجز (`booking_nights`)، الحفاظ على التعديلات السعرية التاريخية لليالي المسحوبة، توحيد الربط المالي عبر `UUID`، سد ثغرات الفقدان الصامت في المزامنة (`AppwriteSyncManager`)، وتوحيد حسابات الرصيد واستعادة النسخ الاحتياطية.

---

## 1. مراجعة الالتزام الجديد على الفرع البعيد (`f3d0308` ودمجه `513c649`)

### الالتزام `f3d0308`: `fix(mobile): preserve nightly adjustments and repair stay tests`
عالج هذا الالتزام ثلاث نقاط جوهرية متكاملة مع إصلاحات المزامنة:

1. **حماية التعديلات السعرية التاريخية المخزنة على الليالي (`EnhancedBookingCalculationService._syncExistingNightsWithAdjustments`):**
   - **المشكلة التي يعالجها:** في بيانات الإنتاج (`nights_snapshot_2026-11-23.json`)، توجد **438 ليلة** تحتوي على `adjustment != 0` مخزنة مباشرة على سجل الليلة نفسها دون وجود سجل مقابل في جدول `booking_price_adjustments` المحلي أو `booking.discount` على الجهاز المستقبِل أثناء السحب.
   - **الإصلاح:** إضافة متغير `hasCurrentAdjustmentSource = adjustments.isNotEmpty || legacyDiscount > 0`؛ فإذا لم يوجد مصدر تعديل نشط حالياً على الجهاز، يحتفظ المحرك بقيمة `night.adjustment.round()` التاريخية المخزنة في الليلة ولا يمسحها إلى الصفر أثناء التحديث اللاحق للسحب، كما يترك `appliedAdjustmentUuid` و`appliedAdjustmentsJson` دون مسح (`Value.absent()`).

2. **إصلاح تواريخ وبيانات الاختبارات في `silent_loss_remaining_entities_regression_test.dart`:**
   - تعديل `checkinDate` من `'2026-11-01T14:00:00'` إلى `'2026-11-01T14:01:00'` ليقع بعد حد اليوم الفندقي (`14:01`) فلا يُصنَّف في اليوم الفندقي السابق (`2026-10-31`).
   - استخدام المفتاح القياسي `'voidedAmount': 15000.0` في مستند `payment_voids` ليتطابق مع `PaymentVoidAdapter`.
   - إنشاء الغرفة `102` والحجز `booking-night-sync-101` قبل اختبار دمج مستندات `booking_nights` المكررة (`dup-night-newer` و`dup-night-older`)، والتحقق من أن الليلة الناتجة بعد الدفعة الأولى تحمل السعر الأحدث (`8500.0`).

3. **ضبط ساعة الاختبار في `restore_fix_service_test.dart`:**
   - تعديل `checkinDate` إلى `'2026-10-01T15:00:00'` ولحظة `now` في `calculateForBooking` إلى `DateTime(2026, 10, 3, 14)` ليتطابق حساب الليالي الفعلية (`actualDaysSpent == 2`) مع حد اليوم الفندقي `14:01`.
   - تحديث التواريخ الثابتة القديمة (`DateTime(2024, 9, 1)`) في اختبار الأداء لـ 50 حجزاً نشطاً إلى تواريخ ديناميكية حديثة (`DateTime.now().subtract(...)`) حتى لا يحسب المحرك الموحد أكثر من 800 ليلة لكل حجز نشط ويتجاوز سقف الـ `4000ms` في CI.

---

## 2. التشخيص الجنائي لمشكلة تضخم وتكرار `booking_nights` (3,495 ليلة مقابل 356 حجزاً)

أظهر الفحص الجنائي لبيانات `Appwrite Cloud` (`nights_snapshot_2026-11-23.json`) وجود **3,495 سجل ليلة** مقابل **356 حجزاً فقط** موزعة على ثلاث مجموعات:

1. **المجموعة الأولى (`1,320` ليلة — `rebuild_2026_10`):**
   - تحتوي على `bookingUuidCache != null` و`bookingLocalId == null`.
   - أُنشئت أثناء إعادة البناء بتاريخ `2026-10-14`، وجميعها تحمل `adjustment == 0`.
2. **المجموعة الثانية (`1,975` ليلة — `server` / `secondary_backup`):**
   - تحتوي على `bookingUuidCache == null` و`bookingLocalId != null` (`115` رقم محلي متصادم بين أجهزة متعددة).
3. **المجموعة الثالثة (`200` ليلة — `derived` / `server`):**
   - يتيمة بالكامل (`bookingUuidCache == null` و`bookingLocalId == null`).

### الأسباب الجذرية الأربعة التي تم إصلاحها:
1. **معرّف عشوائي (`IdGen.uuid()` — v4) عند بناء الليالي:** كل جهاز يعيد حساب ليالي نفس الحجز كان يولّد `localUuid` عشوائياً جديداً لنفس `(booking, hotelDayKey)` بدلاً من معرّف حتمي موحّد.
2. **غياب رفع الإنشاء والتحديث إلى `outbox` في `_replaceBookingNights`:** كان الكود يسجّل عمليات الحذف (`op: 'delete'`) فقط في `outbox` ويتجاهل إدراج أو تحديث الليالي الفعالة (`create`/`update`).
3. **الاعتماد على `bookingLocalId` المتصادم في `NightsAdapter`:** استيراد `bookingLocalId` من السحابة مباشرة كان يربط الليالي بحجوزات خاطئة على الأجهزة الأخرى عند فشل مطابقة `UUID`.
4. **غياب التطهير التلقائي للمكررات السحابية أثناء السحب (`_syncBookingNights`):** عند وجود أكثر من مستند سحابي لنفس `(bookingLocalId, hotelDayKey)` بمعرّفات مختلفة، لم يكن هناك دمج يحتفظ بالأحدث ويدفن المكرر الأقدم.

---

## 3. سجل الإصلاحات التفصيلي حسب الملفات (`20` ملفاً)

### أولاً: هوية حتمية لليالي الحجز ومنع التكرار ومزامنتها
- **`mobile/lib/utils/id.dart`**:
  - إضافة `IdGen.bookingNightUuid(String bookingLocalUuid, String hotelDayKey)` لتوليد **UUID حتمي (UUID v5)** موحّد عبر جميع الأجهزة لنفس الحجز ونفس اليوم الفندقي.
- **`mobile/lib/services/enhanced_booking_calculation_service.dart`**:
  - استخدام `IdGen.bookingNightUuid` عند بناء الليالي مع الحفاظ على `existing.localUuid` للسجلات الموجودة مسبقاً.
  - تفعيل إشعار `outbox` (`_notifyNightOutbox`) عند الإنشاء (`create`) والتحديث (`update`) والحذف (`delete`).
  - الحفاظ على `night.adjustment` التاريخي عند عدم وجود مصدر تعديل سعري محلي نشط (`hasCurrentAdjustmentSource == false`).
- **`mobile/lib/services/adapters/nights_adapter.dart`**:
  - إيقاف تمرير `bookingLocalId` الأجنبي عند فشل حل الحجز عبر UUID، والاعتماد على `bookingUuidCache` + `IdGen.bookingNightUuid`.
- **`mobile/lib/services/repositories/base_repository.dart`**:
  - إضافة `[bn.bookingLocalId, bn.hotelDayKey]` كـ `conflictTarget` لجدول `booking_nights`.
- **`mobile/lib/services/appwrite_sync_manager.dart`**:
  - دمج السجلات المكررة لنفس `(bookingLocalId, hotelDayKey)` أثناء `_processBookingNightEntry` و`_syncBookingNights` و`_relinkOrphanedBookingNights` بالاحتفاظ بالسجل الأحدث (`lastModified`) وحذف المكرر الأقدم مع تسجيل tombstone في `outbox`.

### ثانياً: توحيد الروابط المالية بالـ `UUID` ومنع انفصال الدفعات والديون والتعديلات
- **`mobile/lib/services/sync_core/financial_link_relink_service.dart`**:
  - ترقية `relinkAll()` لإصلاح الروابط الفاسدة (عندما يشير `bookingLocalId` إلى حجز خاطئ يختلف عن الحجز صاحب `bookingUuidCache`) في الجداول الأربعة (`payments`, `debts`, `booking_nights`, `booking_price_adjustments`) محلياً دون تلويث `outbox`.
- **`mobile/lib/services/daos/payments_dao.dart` و `mobile/lib/services/repositories/payments_repository.dart`**:
  - دعم البحث والمراقبة عبر `bookingUuidCache` (بصيغتيه القياسية والمطبّعة بدون شرطات).
  - حفظ واستيراد أعلام الإلغاء والمناعة (`isVoided`, `voidReason`, `voidedAt`, `voidedBy`, `isPendingBalance`, `linkedDebtUuid`, `bookingUuidCache`, `hotelDayKey`) في `exportToJson` و`importFromJson`.
- **`mobile/lib/services/booking_price_adjustment_service.dart`**:
  - مطابقة الحجز عبر `bookingLocalUuid` (بصيغتيه) أو `bookingLocalId` في جميع استعلامات وعمليات التعديلات السعرية.

### ثالثاً: درع الفقدان الصامت وتحديث الخزائن المشتقة وإصلاح الاستعادة
- **`mobile/lib/services/appwrite_sync_manager.dart`**:
  - تطبيق درع الفقدان الصامت (`failedDocIds` + `throw StateError`) في `_syncInventoryItems`, `_syncCashTransactions`, `_syncPriceAdjustments`, و`_syncPaymentVoids`.
  - تحديث `totalPaidCached` و`remainingBalanceCached` وعلم `isVoided` تلقائياً بعد سحب الدفعات وإلغاءاتها، وحماية `actualCheckout` المحلي من المسح بقيمة سحابية فارغة أقدم.
- **`mobile/lib/services/restore_fix_service.dart`**:
  - الحفاظ على `localUuid` لليالي الحجز أثناء إعادة البناء، واعتماد `StatusUtils.isActiveBooking` لتحديد إشغال الغرف، وعدم قصّ الرصيد الدائن السالب.
- **`mobile/lib/services/guest_payment_calculation_service.dart` و `mobile/lib/screens/reports/guest_payments_detail_report_screen.dart`**:
  - سقف `actualCheckout` المستقبلي عند الوقت الحالي (`now`) وتمرير أسعار الغرف الأساسية والتعديلات المربوطة بـ UUID إلى `StayBalanceCalculator`.

---

## 4. نتائج الفحص والاختبارات على CI

- **`Mobile Quality Gate - Enhanced` (تشغيل `#694` — `45107374980` / `45107381229`):**
  - `Code Analysis & Formatting`: **ناجح (Passed)**
  - `Unit Tests & Coverage`: **ناجح بالكامل (Passed)**
  - `Extended Quality Checks`: **ناجح (Passed)**
- **`Build Flutter Release APK` (`45107905291`):** **ناجح (Passed)**
- **`Enterprise Quality Gate` (`45107381258`) و`Security & Malware Scan` (`45107374852`):** **ناجحان (Passed)**
