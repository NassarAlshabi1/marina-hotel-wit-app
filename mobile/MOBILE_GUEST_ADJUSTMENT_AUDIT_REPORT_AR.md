# التقرير الهندسي والمحاسبي الشامل لتدقيق مجلد `mobile/`
**الفرع محل الفحص:** `guest-adjustment-edit-end` (حتى الالتزام `16ecc8d114b824a1c7bdf0f564e49c3f8beb8b5b`)  
**نطاق التدقيق:** محركات حساب الليالي والتسعير، مسارات مزامنة المدفوعات، عقود الهوية العابرة للأجهزة (`UUID` مقابل `SQLite ID`)، وبروتوكول المصالحة المالية لبيانات النزلاء.  
**تاريخ التقرير:** `2026-11-23` (توقيت الفندق المعتمد: `Asia/Aden` — حد اليوم الفندقي `14:01`).

---

## ملخص تنفيذي

شهد فرع `guest-adjustment-edit-end` سلسلة إصلاحات جوهرية عالية الأثر (من أبرزها الالتزامات `78faa5c`, `9760a13`, `7bce85a`, `9f4bdda`, `862b0fb`, `6835412`, `16ecc8d`) استهدفت توحيد تسعير الليالي، فرض قاعدة **«لا ليالٍ مجانية»**، منع قصّ الرصيد الدائن السالب للنزيل إلى الصفر، وحماية المدفوعات القادمة من السحابة من التحول إلى دفعات عامة يتيمة.

ومع ذلك، يكشف التدقيق المعمق للكود المصدري في `mobile/lib/` عن **حزمة من الأخطاء التاريخية التي تم إغلاقها مؤخراً** إلى جانب **ثغرات بنيوية متبقية (Residual Bugs)** في مسارات التقارير، المعاينة، استعادة النسخ الاحتياطية، وفحص سلامة المزامنة ما بعد السحب (`_performPostSyncIntegrityCheck`) يمكن أن تؤدي في بيئة متعددة الأجهزة إلى:
1. إخفاء أو حذف ناعم خاطئ لدفعات نزيل إذا تأخر وصول الحجز الأب أو حدث تعارض مفتاح أجنبي.
2. عدم تحديث الكاش المالي للحجز (`totalPaidCached`, `remainingBalanceCached`, `isFullyPaid`) فور سحب دفعات أو إلغاءات دفع (`payment_voids`) من جهاز آخر.
3. إسقاط تعديلات الأسعار الليلية في شاشة «تقرير مدفوعات النزلاء التفصيلي» نتيجة تفعيل حارس الاشتقاق المزدوج عند عدم تمرير `roomRate`.
4. استمرار تراكم الليالي لحجوزات مغلقة/ملغاة تفتقر إلى `actualCheckout` في بعض خدمات التقارير الفرعية.

يقدم هذا التقرير تشريحاً كاملاً للأقسام الستة المطلوبة بالمسارات البرمجية الدقيقة (`file:line`) وخطة المعالجة الجذرية والاختبارات الإلزامية وطريقة المصالحة الآمنة.

---

## 1. الأخطاء المكتشفة في حساب الليالي

يعتمد النظام الفندقي على قاعدة زمنية صارمة في `Time.nightsWithCutoff` (`mobile/lib/utils/time.dart:152-215`) و`HotelTimeEngine` (`mobile/lib/utils/hotel_time_engine.dart:29-85`): **اليوم الفندقي يبدأ عند الساعة `14:01` بتوقيت `Asia/Aden` وينتهي عند `14:00:59` من اليوم التالي**. وقد كشف الفحص عن الأخطاء التالية (شاملةً ما عُولج في الفرع وما يزال كامناً في مسارات فرعية):

### 1.1 خرق قاعدة «لا ليالٍ مجانية» (No-Free-Nights Rule) والقص الصامت إلى الصفر
* **الموقع البرمجي:**
  * `mobile/lib/services/enhanced_booking_calculation_service.dart:332-447` (`calculateNightlyBreakdown`)
  * `mobile/lib/services/stay_balance_calculator.dart:245-384` (`StayBalanceCalculator.calculate`)
  * `mobile/lib/services/booking_price_adjustment_service.dart:80-118` (`_assertNoFreeNights`)
* **تشخيص الخلل:**
  1. كان جمع التعديلات الليلية (`BookingPriceAdjustment` + `booking.discount`) يقصّ السعر النهائي لليلة عند الصفر (`clamp(0, double.infinity)`)، مما يسمح بظهور ليالٍ بسعر `finalRate == 0.0` عند إدخال خصم يساوي أو يفوق سعر الغرفة أو عند تراكب أكثر من تعديل خصم على نفس اليوم الفندقي.
  2. في `StayBalanceCalculator.calculate`، كانت حلقة محاكاة تغطية المدفوعات (`while (remainingMoney > 0 && extraDays < _maxSimulationDays)`) تتوقف بصمت (`break`) عند مصادفة ليلة سعرها `<= 0`، مما كان يُسقط حساب الليالي الإضافية المدفوعة دون إشعار المستخدم بسبب التوقف.
* **الحالة في الفرع (`16ecc8d`):**
  * تم فرض سقف الخصم الليلي `_maxNightDiscount(baseRate) = max(0, baseRate - 0.01)` بحيث لا يقل سعر أي ليلة عن `0.01`، مع تسجيل الليالي التي حاولت التعديلات تصفيرها في قائمة `anomalyNights`.
  * تم تزويد `StayBalanceResult` بحقول `anomalyNights` و`hasAnomaly` و`anomalyReason` وعرض تحذير بصري صريح في `PaymentSummaryCard` (`mobile/lib/screens/payments/widgets/payment_summary_card.dart:226-254`).
  * أُضيف حارس الإدخال `_assertNoFreeNights` في `BookingPriceAdjustmentService` لمنع حفظ خصم ليلي `>= roomRate`.

### 1.2 الاشتقاق المزدوج لتسعير الليلة (Double-Derivation Bug) وثغرة شاشة التقرير التفصيلي
* **الموقع البرمجي:**
  * `mobile/lib/services/stay_balance_calculator.dart:114-169`
  * `mobile/lib/screens/reports/guest_payments_detail_report_screen.dart:145-160` و`230-245` (**ثغرة قائمة**)
* **تشخيص الخلل:**
  1. عندما يُستدعى `StayBalanceCalculator.calculate(booking)` دون تمرير `roomRate` الصريح من جدول `rooms`، يشتق المحرك السعر الأساسي من `booking.totalDueCached / booking.calculatedNights`.
  2. بما أن `totalDueCached` المحسوب بواسطة `EnhancedBookingCalculationService` يتضمن مسبقاً طرح `booking.discount` وتطبيق `booking_price_adjustments`، فإن إعادة تطبيق `booking.discount` و`priceAdjustments` داخل `StayBalanceCalculator` كانت تؤدي إلى **خصم التعديلات مرتين**!
  3. في الالتزام `16ecc8d`، أُضيف حارس `skipDiscountBecauseDerived`: عندما يكون `roomRate == null` و`totalDueCached > 0`، يقوم المحرك بتعطيل `effectiveDiscount = 0` وتفريغ `effectiveAdjustments = const []`.
  4. **الخلل المتبقي حالياً:** في `GuestPaymentsDetailReportScreen._refreshData` (`guest_payments_detail_report_screen.dart:236-243`) وفي `_calculateCoverage` (`سطر 152`)، تجلب الشاشة جميع تعديلات الأسعار النشطة (`allAdjustments`) وتصفيها ثم تستدعي:
     ```dart
     StayBalanceCalculator.calculate(b, priceAdjustments: filtered); // ⚠️ roomRate غير ممرر!
     ```
     ونتيجةً لتفعيل الحارس `skipDiscountBecauseDerived`، يتجاهل `StayBalanceCalculator` قائمة `priceAdjustments` الممررة بالكامل ويعتمد المتوسط المشتق من `totalDueCached / calculatedNights` لكل الليالي، مما يُفقد التقرير التفصيلي دقة التسعير اليومي المتفاوت (مثل ليلة بسعر عادي وليلة تالية بسعر مخفض أو مزاد) ويجعل محاكاة الليالي الإضافية (`extraNightsBeyondManual`) تعتمد على المتوسط بدلاً من سعر الليلة الفعلي!

### 1.3 انحراف التمديد التلقائي للليالي المدفوعة عن مفتاح اليوم الفندقي (`14:01`)
* **الموقع البرمجي:** `mobile/lib/services/stay_balance_calculator.dart:246-322` و`366-412`
* **تشخيص الخلل:**
  * عند دخول النزيل بعد منتصف الليل وقبل الساعة `14:01` ظهراً (مثلاً الساعة `02:30` فجر يوم `2026-11-20`)، فإن اليوم الفندقي الأول لإقامته هو `2026-11-19` وينتهي عند `2026-11-20 14:00`.
  * سابقاً، كان حساب `autoCheckoutDate` يضيف عدد الليالي المدفوعة مباشرةً إلى التاريخ التقويمي لـ `checkin` (`2026-11-20 + 1 day = 2026-11-21 14:00`)، فيمنح النزيل يوماً فندقياً إضافياً مجانياً عن طريق الخطأ.
  * **الحالة في الفرع (`7bce85a`):** تم توحيد المرجع عبر `firstHotelDay = HotelTimeEngine.getHotelDay(checkin)` وبناء `coveredDates` و`autoCheckoutDate` انطلاقاً من `firstHotelDay`، بحيث تنتهي الليلة الواحدة لدخول الفجر عند `14:00` من نفس اليوم التقويمي.

### 1.4 استمرار تراكم الليالي بعد المغادرة أو للحجوزات غير النشطة (Unbounded Night Accumulation)
* **الموقع البرمجي:**
  * `mobile/lib/services/enhanced_booking_calculation_service.dart:318-329` (`_resolveStayEnd`)
  * `mobile/lib/utils/booking_nights_display.dart:37-87` (`BookingNightsDisplay.forList`)
  * `mobile/lib/services/guest_payment_calculation_service.dart:80-95` (**ثغرة قائمة**)
  * `mobile/lib/screens/reports/guest_payments_detail_report_screen.dart:93-100` (**ثغرة قائمة**)
* **تشخيص الخلل:**
  1. **شذوذ المغادرة الفعلية المستقبلية:** إذا سُجّل `actualCheckout` بتاريخ مستقبلي عن طريق خطأ إدخال أو انحراف ساعة جهاز، كان النظام يحتسب كل الليالي حتى ذلك التاريخ المستقبلي. تم إصلاح ذلك في `_resolveStayEnd` و`BookingNightsDisplay` و`StayBalanceCalculator` بقصّ `actualCheckout` المستقبلي إلى `now`.
  2. **الحجوزات التراثية (Legacy) بلا `checkoutDate`:** في قائمة الحجوزات، إذا كان `plannedCheckout == null` و`storedExpectedNights == 0` مع وجود `actualCheckout`، كانت الليالي المتوقعة تُمرر `null` إلى `Time.nightsWithCutoff` فتستمر بالعدّ حتى اللحظة الحالية (`DateTime.now()`). عُولج ذلك في `BookingNightsDisplay.forList` بالرجوع إلى `plannedCheckout ?? actualCheckout`.
  3. **الخلل المتبقي في `GuestPaymentCalculationService.calculateForBooking` (`guest_payment_calculation_service.dart:80-95`):**
     ```dart
     final actualCheckout = booking.actualCheckout != null && booking.actualCheckout!.isNotEmpty
         ? DateTime.tryParse(booking.actualCheckout!)
         : null;
     final effectiveEnd = actualCheckout ?? now;
     final actualNights = Time.nightsWithCutoff(checkin, checkout: effectiveEnd);
     ```
     هنا توجد مشكلتان:
     * أولاً: لا يقصّ `actualCheckout` إذا كان في المستقبل (`actualCheckout.isAfter(now)`).
     * ثانياً: إذا كان الحجز في حالة غير نشطة (`مكتمل` / `ملغى` / `غادر`) ولكن حقل `actualCheckout` فارغ في البيانات القديمة، فإنه يستخدم `now` بدلاً من `plannedCheckout`، مما يضاعف عدد الليالي لمئات الأيام! ونفس الخلل موجود في `GuestPaymentsDetailReportScreen._getActualDaysSpent` (`سطر 93-100`).

### 1.5 تجاهل قاعدة `14:01` وسقف الخصم في معاينة تعديل السعر وتقرير الإيرادات المفقودة
* **الموقع البرمجي:** `mobile/lib/services/booking_price_adjustment_service.dart:548-578` (`previewAdjustment`) و`726-740` (`generateLostRevenueReport`) (**ثغرة قائمة**)
* **تشخيص الخلل:**
  * تستخدم الدالتان الحساب التقويمي الخام:
    ```dart
    final totalNights = checkout.difference(checkin).inDays;
    ```
    وهذا الحساب يتجاهل كلياً `Time.nightsWithCutoff` وحد الساعة `14:00`:
    1. إذا دخل النزيل `2026-11-20 02:00` وغادر `2026-11-20 14:00`، فإن `checkout.difference(checkin).inDays` يُرجع `0` بينما الفعلي هو `1` ليلة!
    2. إذا غادر بعد `14:00` (مثلاً `15:30`)، ينقص الحساب ليلة كاملة عن `EnhancedBookingCalculationService`.
    3. في `previewAdjustment` (`سطر 556-567`)، لا يُطبق سقف الخصم `_maxNightDiscount(currentRoomRate)`، فقد يعرض للمستخدم في نافذة المعاينة إجمالياً صفرياً أو سالباً يختلف عما سيحفظه المحرك الفعلي.

### 1.6 تدمير هوية الليالي وتجاهل الخصومات في `RestoreFixService._rebuildBookingNights`
* **الموقع البرمجي:** `mobile/lib/services/restore_fix_service.dart:495-561` (**ثغرة قائمة**)
* **تشخيص الخلل:**
  * بينما تم تطوير `EnhancedBookingCalculationService._replaceBookingNights` (`enhanced_booking_calculation_service.dart:765-916`) ليحافظ على `id` و`localUuid` لصفوف `booking_nights` القائمة لكل `(bookingLocalId, hotelDayKey)` ويستخدم الحذف الناعم (Tombstone) لليالي الزائدة، فإن `RestoreFixService._rebuildBookingNights` لا يزال ينفذ:
    1. حذفاً فيزيائياً كاملاً: `await (db.delete(db.bookingNights)..where((n) => n.bookingLocalId.equals(booking.id))).go();`
    2. إعادة إدراج الليالي بـ `IdGen.uuid()` جديد تماماً (مما يكسر تتبع المزامنة مع Appwrite ويخلق نسخاً مكررة عند الرفع).
    3. إدراج كل ليلة بـ `adjustment: const Value(0)` و`finalRate: Value(roomPrice)` دون تمريرها عبر `EnhancedBookingCalculationService`، فتفقد صفوف `booking_nights` تفاصيل الخصومات وتعديلات الأسعار بعد تشغيل `RestoreFixService`!

---

## 2. تحليل مسارات مزامنة المدفوعات

تمر المدفوعات (`payments`) والكيانات المالية المرتبطة بها (`payment_voids`, `cash_transactions`, `bookings`) عبر خمسة مسارات متكاملة في `mobile/lib/`:

### 2.1 مسار الإنشاء والتعديل المحلي (`PaymentsRepository` → `PaymentsDao` → `OutboxDao`)
1. **الإدراج (`PaymentsRepository.create` - `payments_repository.dart:51-116`):**
   * يستخرج `bookingUuidCache` من `bookings.localUuid` إذا وُجد `bookingLocalId`.
   * يحسب `hotelDayKey` عبر `HotelTimeEngine.resolvePaymentHotelDayKey(paymentDateIso: paymentDate, explicitHotelDayKey: hotelDayKey)` لضمان تصنيف الدفعة في اليوم الفندقي الصحيح (`14:01 Asia/Aden`).
   * في `PaymentsDao.insertOne` (`payments_dao.dart:313-353`): يطبّع `localUuid` إلى الصيغة القياسية بالشرطات (`_canonicalPaymentUuid`)، ويختم `origin = 'local'`, ويدرج عملية `create` في `OutboxDao` عبر `_enqueueOutbox`.
2. **ثغرة `deviceId` عند الإنشاء المحلي قبل تسجيل الجهاز في Appwrite (`payments_dao.dart:327-329`):**
   * في الالتزام `9f4bdda`، تم استبدال `ensureDeviceIdForLocalWrite()` بـ:
     ```dart
     deviceId: originIsServer ? const Value.absent() : Value(AppwriteSyncManager.currentDeviceIdStatic ?? ''),
     ```
   * وفي `AppwriteSyncManager._loadSettings` (`appwrite_sync_manager.dart:460-471`)، يتم تعيين `updateStaticDeviceId(_currentDeviceId)` فقط من المفتاح `'appwrite_device_id'` (دون fallback إلى `_deviceLocalUuid`).
   * **الأثر:** إذا عمل التطبيق في وضع عدم الاتصال (Offline) منذ التثبيت الأول قبل أن ينجح `registerDevice` على Appwrite، فإن جميع المدفوعات المنشأة محلياً تُحفظ بـ `deviceId = ''` (نص فارغ)، مما يُضعف تتبع مصدر الدفعة وإشعارات التغيير عبر الأجهزة.

### 2.2 مسار الرفع إلى Appwrite (`_processPaymentEntry` & `PayloadMapper.paymentToRemote`)
1. **تحويل الحمولة (`PayloadMapper.paymentToRemote` - `payload_mapper.dart:208-235`):**
   * يطبّع كلاً من `localUuid` و`bookingUuidCache` إلى صيغة UUID القياسية ذات الشرطات (`36` حرفاً) عبر `_normalizeUuid`.
   * **عزل المعرفات المحلية:** يحذف عمداً `bookingLocalId` و`cashTransactionLocalId` من حمولة Appwrite لأنها أرقام `autoincrement` خاصة بالجهاز المرسل، ويحتفظ بـ `bookingUuidCache` كمرجع وحيد للحجز.
2. **القفل التفاؤلي وحل التعارضات (`_occCheckAndMerge` - `appwrite_sync_manager.dart:3718-3817`):**
   * يقرأ المستند من Appwrite باستخدام `paymentDocumentId = payload['localUuid']`.
   * إذا كانت `remoteVersion > localVersion`، يطبق قاعدة **Cloud Wins (§7.5)**: يرفض الدفع المحلي المتقادم، يسجل التعارض في `sync_conflicts`، ويعلّم عناصر `outbox` الخاصة بهذه الدفعة بحالة `superseded_by_cloud`.
3. **حماية الإلغاء المالي (`PaymentVoidService.voidPayment` - `payment_void_service.dart:28-236`):**
   * يرفض المبالغ الكسرية (`!_hasExactIntegerAmount`) لمنع فقدان الدقة عند تحويل `voidedAmount` إلى `int` في Appwrite.
   * ينفذ معاملة ذرية (Transaction) تُنشئ سجل `payment_voids` + سجل `audit_logs`، وتحدّث صف `payments` (`isVoided = true, isImmutable = true, version = version + 1`)، وتدفع كلاً من `payment_voids` و`payments` إلى `outbox`، ثم تستدعي `BookingDerivedFieldsService.refreshForBookingId`.

### 2.3 مسار السحب من Appwrite (`_buildPullTasks` → `_syncPayments` → `PaymentsAdapter`)
1. **ترتيب السحب (`_buildPullTasks` - `appwrite_sync_manager.dart:6766-6986`):**
   * تُسحب المجموعات بالترتيب: `rooms` ← `employees` ← `bookings` ← `cash_transactions` ← `expenses` ← `booking_nights` ← `booking_notes` ← `payments` ← `debts` ← ... ← `booking_price_adjustments` ← ... ← `payment_voids` ← `salary_carry_over_logs`.
2. **حارس حل مرجع الحجز (`PaymentsAdapter.resolveRefs` - `payments_adapter.dart:32-75`):**
   * يستدعي `resolver.resolveBooking(localId: localId, serverBookingId: serverBookingId, uuid: bookingUuid, fromRemote: true)`.
   * عندما يكون `fromRemote == true` (`Source.appwrite` أو `Source.drive`)، يرفض `IdResolver.resolveBooking` (`id_resolver.dart:118-174`) استخدام `localId` كـ fallback، ويبحث حصرياً عبر `bookingUuid` (بصيغتيه مع الشرطات وبدونها) ثم `serverBookingId`.
   * إذا كانت الدفعة تحمل أي إشارة لحجز (`hasBookingReference`) وفشل إيجاد الحجز محلياً (`resolvedId == null`)، يُرجع `shouldSkip = true`.
3. **طابور الروابط المعلقة الدائم (`_pendingLinks.recordUnresolved` - `appwrite_sync_manager.dart:2989-3008`):**
   * عند `refs.shouldSkip == true`، لا يتم إدراج الدفعة بـ `bookingLocalId = null` (لكي لا تتحول إلى إيراد عام غير منسوب لنزيل)، ولا يتم رمي استثناء يجمّد مؤشر مجموعة `payments`، بل يُحفظ الـ JSON الكامل للدفعة في جدول `pending_links` بانتظار وصول الحجز الأب.
4. **حارس عدم القابلية للتغيير المالي (`appwrite_sync_manager.dart:3013-3043`):**
   * يمنع إعادة إحياء دفعة محذوفة ناعماً محلياً (`existingPayment.deletedAt != null && remoteDeletedAt == null`).
   * إذا كانت النسخة المحلية أحدث أو مساوية (`existingPayment.lastModified >= incomingLastModified`)، يتم تخطي النسخة البعيدة.

### 2.4 الثغرات الحرجة المكتشفة في مسارات مزامنة المدفوعات

| # | الثغرة المكتشفة في مسار المزامنة | الموقع البرمجي الدقيق | الأثر المالي والتشغيلي |
|---|---|---|---|
| **S1** | **عدم تحديث الكاش المالي للحجز بعد سحب المدفوعات (`_syncPayments`)** | `appwrite_sync_manager.dart:3045-3120` | عند سحب دفعة جديدة من جهاز الاستقبال (أ) إلى جهاز الإدارة (ب)، تُدرج الدفعة في جدول `payments`، لكن لا يتم استدعاء `_bookingsRepository.derivedFields.refreshForBookingId`! النتيجة: تبقى حقول `totalPaidCached` و`remainingBalanceCached` و`isFullyPaid` في جدول `bookings` قديمة على الجهاز (ب)، فتظهر شاشات القوائم والتقارير السريعة رصيداً خاطئاً للنزيل! |
| **S2** | **انفصال `_syncPaymentVoids` عن جدول `payments` وعن كاش الحجز** | `appwrite_sync_manager.dart:10742-10797` | عند سحب سجل إلغاء دفعة (`payment_voids`)، يقوم `_syncPaymentVoids` بإدراج السجل في جدول `payment_voids` فقط دون تعليم الدفعة الأصلية في جدول `payments` بـ `isVoided = true, isImmutable = true` ودون تحديث `BookingDerivedFieldsService`! إذا فُقد تحديث `payments` أو تم تخطيه بسبب شرط `existingPayment.lastModified >= incomingLastModified`، تظل الدفعة الملغاة محتسبة كدفعة نشطة في رصيد النزيل وصندوق الفندق! |
| **S3** | **التدمير المزدوج للدفعات اليتيمة في `_performPostSyncIntegrityCheck`** | `appwrite_sync_manager.dart:11119-11225` | في فحص ما بعد المزامنة (`pullAllDataWithDisabledFK`)، عند رصد انتهاك مفتاح أجنبي لصف في `payments`: **(1)** السطر `11122` ينفذ `UPDATE payments SET booking_local_id = NULL, booking_uuid_cache = NULL` فيمسح `booking_uuid_cache`! **(2)** السطر `11180` في الحلقة التالية يضع `deletedAt = nowEpoch` (حذف ناعم للدفعة)! **(3)** السطر `11209` يبحث عن الدفعات اليتيمة بشرط `WHERE p.booking_local_id IS NOT NULL AND b.id IS NULL AND p.deleted_at IS NULL` فلا يجد شيئاً لأن الحلقة الأولى صفّرت `booking_local_id` و`booking_uuid_cache` والحلقة الثانية حذفت الصف ناعماً! |
| **S4** | **قصور شرط استدعاء `_relinkOrphanedPayments`** | `appwrite_sync_manager.dart:11209-11224` | استعلام الفحص `orphanPayments` يشترط `WHERE p.booking_local_id IS NOT NULL AND b.id IS NULL`، وبالتالي إذا كانت هناك دفعات في الجدول بـ `booking_local_id IS NULL` ولكن `booking_uuid_cache IS NOT NULL`، فإن `orphanPayCount` يساوي `0` ولا يتم استدعاء `_relinkOrphanedPayments()` إطلاقاً رغم أن الدالة نفسها مصممة لمعالجة `p.booking_local_id IS NULL`! |
| **S5** | **تأخر إعادة محاولة `pending_links` للدفعات** | `appwrite_sync_manager.dart:2128-2195` و`6827-6831` | دالة `_retryPendingFinancialLinks` (التي تعيد محاولة `payments` المعلقة في `pending_links`) تُستدعى فقط بعد سحب `employees` وبعد سحب `salary_carry_over_logs`، ولا تُستدعى بعد `_syncBookings`! إذا وصلت الدفعة في دورة سابقة ووصل الحجز في دورة لاحقة مع تعطيل مجموعة `salary_carry_over_logs` في `SyncPullScope`، تبقى الدفعة عالقة في `pending_links`. |
| **S6** | **سقوط حقول الإلغاء والربط في `PaymentsDao.importFromJson`** | `mobile/lib/services/daos/payments_dao.dart:495-549` | دالة `importFromJson` في `PaymentsDao` لا تقرأ `bookingUuidCache`, `hotelDayKey`, `isVoided`, `voidedAt`, `voidedBy`, `voidReason`, `isPendingBalance`, `isImmutable`. أي مسار استيراد يستدعي هذه الدالة سيُفقد الدفعات ارتباطها بـ UUID الحجز ويعيد إحياء الدفعات الملغاة والأرصدة المعلقة كدفعات نقدية فعلية! |

---

## 3. مخاطر اختلاف معرفات الحجز والدفعات

تنشأ مخاطر اختلاف المعرفات من ازدواجية نظام الهوية في التطبيق بين:
* **المعرف الرقمي المحلي (`id` / `bookingLocalId`):** رقم تسلسلي `INTEGER PRIMARY KEY AUTOINCREMENT` يولّده SQLite محلياً على كل جهاز بشكل مستقل.
* **المعرف العالمي (`localUuid` / `bookingUuidCache`):** سلسلة UUID نصية هي الهوية الوحيدة الثابتة عبر الأجهزة والسحابة (`Appwrite` و`Google Drive`).

### 3.1 السيناريوهات الثلاثة لانحراف الهوية (Identity Drift Scenarios)

#### السيناريو الأول: تصادم المفاتيح الرقمية بين جهازين (Cross-Device Numeric FK Collision)
* الجهاز (أ) ينشئ الحجز `UUID-1` فيأخذ `id = 10`، والدفعة `PAY-1` تأخذ `bookingLocalId = 10`.
* الجهاز (ب) كان قد أنشأ محلياً حجزاً آخر `UUID-2` أخذ `id = 10`، وعندما سحب الحجز `UUID-1` من السحابة أعطاه SQLite المحلي الرقم `id = 25`.
* **الخطر:** إذا تسرب `bookingLocalId = 10` من نسخة احتياطية أو مسار استيراد أو محول لا يطبق حارس `fromRemote: true`، فإن الدفعة `PAY-1` ستُربط على الجهاز (ب) بالحجز رقم `10` (`UUID-2`) الخاص بنزيل آخر تماماً، مما يسبب **اختلاساً/تداخلاً محاسبياً مزدوجاً** (نقص مدفوعات النزيل الأول، وزيادة وهمية لمدفوعات النزيل الثاني).

#### السيناريو الثاني: انفصام التمثيل النصي للـ UUID (Dashed 36-char vs Compact 32-char)
* بعض السجلات التاريخية والنسخ الاحتياطية ولّدت UUID بدون شرطات (`621b28eb87dd429b9f12fe19c18f17df` - `32` حرفاً)، بينما يقوم `BaseRepository._normalizeUuidFormat` و`PayloadMapper._normalizeUuid` بتحويلها إلى صيغة الشرطات القياسية (`621b28eb-87dd-429b-9f12-fe19c18f17df` - `36` حرفاً).
* **الخطر:** إذا تم تخزين `bookings.localUuid` بالشرطات بينما حملت دفعة مسحوبة أو مستعادة `bookingUuidCache` بدون شرطات (أو العكس)، فإن أي استعلام SQL يستخدم المساواة الحرفية `WHERE booking_uuid_cache = ?` بدلاً من فحص الصيغتين (`dashed` و`compact`) سيفشل في إيجاد الدفعة.

#### السيناريو الثالث: دفعات محمولة بالـ UUID فقط (`bookingLocalId == null && bookingUuidCache != null`)
* كما هو موثق في سجل الإنتاج (`payments_report_screen.dart:175`: *"نمط الإنتاج الموثق: 98/172 دفعة لحجز غرفة 203 تحمل `bookingUuidCache` فقط بلا `bookingLocalId`"*): عندما تفشل عملية الربط اللحظي بالـ `id` المحلي أثناء استعادة أو سحب قديم، تبقى الدفعة بـ `bookingLocalId = null` مع وجود `bookingUuidCache` صحيح.
* **الخطر:** أي خدمة أو شاشة تستعلم عن المدفوعات أو التعديلات أو الديون عبر `bookingLocalId` فقط ستتجاهل هذه السجلات كلياً!

### 3.2 جرد شامل للمواقع البرمجية المعرّضة لمخاطر اختلاف المعرفات في الكود الحالي

| المكون / الخدمة | الملف والسطر | حالة المطابقة حالياً | الخطر المحدد |
|---|---|---|---|
| `PaymentsDao.paymentsByBooking` & `watchTotalPaidForBooking` | `payments_dao.dart:279-297`, `558-609` | ✅ محصّن (`bookingLocalId` + `bookingUuidCache` بصيغتيه) | آمن؛ تم إصلاحه في `16ecc8d` و`de9f18a`. |
| `EnhancedBookingCalculationService.totalPaymentsForBooking` | `enhanced_booking_calculation_service.dart:611-647` | ✅ محصّن (`bookingLocalId` + `bookingUuidCache` بصيغتيه) | آمن. |
| **`PaymentsDao.list` & `PaymentsDao.watchList`** | `payments_dao.dart:200-275` | ❌ **غير محصّن** (`t.bookingLocalId.equals(bookingLocalId)` فقط) | أي شاشة تستدعي `paymentsRepo.list(bookingLocalId: id)` أو `watchList(bookingLocalId: id)` لن ترى الدفعات المربوطة عبر `bookingUuidCache` فقط! |
| **`PaymentsRepository.update`** | `payments_repository.dart:118-174` | ❌ **غير محصّن** (يحدّث `bookingLocalId` دون تحديث `bookingUuidCache`) | عند نقل دفعة أو ربطها بحجز جديد عبر `update()`، يظل `bookingUuidCache` قديماً أو فارغاً، وعند الرفع إلى Appwrite (الذي يحذف `bookingLocalId` ويعتمد `bookingUuidCache`) تعود الدفعة للحجز القديم على بقية الأجهزة! |
| **`GuestPaymentsDetailReportScreen._refreshData`** | `guest_payments_detail_report_screen.dart:216-223` | ❌ **غير محصّن** (`if (adj.bookingLocalId == null) continue;`) | تعديلات الأسعار المسحوبة التي تحمل `bookingLocalUuid` أو `bookingUuid` قبل تحديث `bookingLocalId` يتم إسقاطها كلياً من التقرير التفصيلي! |
| **`BookingPriceAdjustmentService` (3 دوال)** | `booking_price_adjustment_service.dart:460-476`, `676-690`, `702-710` | ❌ **غير محصّن** (`a.bookingLocalId.equals(bookingId)` فقط) | الدوال `transferAdjustmentsToRoom`, `getLongStayBookingsWithoutSurcharge`, `generateLostRevenueReport` لا تفحص `bookingLocalUuid`، خلافاً لدالة `getAdjustmentsForBooking` (`سطر 342`) التي تفحص الاثنين. |
| **`RestoreFixService._recalculateBookingFinancials`** | `restore_fix_service.dart:463-478` | ❌ **غير محصّن للديون** (`d.bookingLocalId.equals(booking.id)` فقط) | الديون (`debts`) التي تحمل `bookingUuidCache` بلا `bookingLocalId` لا يتم تحديثها أو تسويتها عند تشغيل الإصلاح التلقائي بعد الاستعادة. |
| **`FinancialLinkRelinkService.relinkAll`** | `financial_link_relink_service.dart:43-59` | ⚠️ **نطاق ناقص** (يربط الرواتب والمصروفات فقط) | يُشغَّل بعد الاستعادة الكاملة لإعادة ربط `UUID → local id`، لكنه يقتصر على جداول الموظفين والرواتب ولا يعيد ربط `payments`, `debts`, `booking_nights`, `booking_price_adjustments`, `booking_notes`! |

---

## 4. خطة إصلاح جذري مرتبة حسب الأولوية

تم ترتيب خطة الإصلاح الجذري وفق درجة الخطورة على السجل المالي وسلامة المزامنة من **`P0` (حرج وفوري)** إلى **`P3` (تحصين معماري)**:

### المرحلة الأولى (`P0` - حرجة وفورية): إيقاف الفقدان الصامت وتوحيد الحالة المالية بعد المزامنة

#### 1. `P0-1`: إصلاح التدمير المزدوج للدفعات اليتيمة في `_performPostSyncIntegrityCheck`
* **الملف:** `mobile/lib/services/appwrite_sync_manager.dart` (السطور `11119-11225`).
* **الإجراء الجذري:**
  1. **منع مسح `booking_uuid_cache` نهائياً:** في السطر `11122`، عند فك ارتباط `booking_local_id` الفاسد، يُعدَّل الاستعلام إلى:
     ```sql
     UPDATE payments SET booking_local_id = NULL WHERE rowid = ?
     ```
     مع الإبقاء على `booking_uuid_cache` سليماً لأن `booking_uuid_cache` هو الخيط الوحيد لإعادة ربط الدفعة بالحجز عند وصوله!
  2. **إلغاء الحذف الناعم التلقائي للدفعات والديون والليالي والتعديلات (`سطور 11157-11197`):** إزالة حلقة وضع `deletedAt = nowEpoch` على `payments`, `debts`, `booking_nights`, `booking_price_adjustments`. السجل المالي الذي لم يصل حجزه الأب بعد ليس سجلاً محذوفاً بل سجل ينتظر إعادة الربط (`Relink`).
  3. **تشغيل `_relinkOrphanedPayments()` و`_relinkOrphanedDebts()` دائماً دون شرط قاصر:** تعديل استعلام الفحص ليشمل `WHERE p.booking_uuid_cache IS NOT NULL AND p.booking_uuid_cache != '' AND p.deleted_at IS NULL AND (p.booking_local_id IS NULL OR b.id IS NULL)`.

#### 2. `P0-2`: ربط `_syncPayments` و`_syncPaymentVoids` بتحديث الكاش المالي للحجز (`BookingDerivedFieldsService`)
* **الملف:** `mobile/lib/services/appwrite_sync_manager.dart` (`_syncPayments` السطور `2954-3130`، و`_syncPaymentVoids` السطور `10742-10797`).
* **الإجراء الجذري:**
  1. في `_syncPayments`: جمع معرفات الحجوزات المتأثرة (`affectedBookingIds` عبر `refs.bookingLocalId` أو حل `bookingUuidCache`)، وبعد انتهاء الدفعة استدعاء:
     ```dart
     for (final bookingId in affectedBookingIds) {
       await _bookingsRepository.derivedFields.refreshForBookingId(
         bookingId,
         enqueueOutbox: false,
       );
     }
     ```
  2. في `_syncPaymentVoids`: عند تطبيق كل سجل `PaymentVoid`، البحث عن الدفعة الأصلية بواسطة `originalPaymentUuid` (بصيغتي الشرطات وبدونها) وتحديثها محلياً بـ `isVoided = true, isImmutable = true, voidedAt = voidedAtIso, voidedBy = voidedBy, voidReason = voidReason` إذا لم تكن معلّمة بعد، ثم استدعاء `refreshForBookingId` للحجز المرتبط (`bookingUuid`).
  3. في `_buildPullTasks` (`سطر 6828`): استدعاء `_retryPendingFinancialLinks()` مباشرة داخل `apply` الخاصة بمهمة `bookings` فور اكتمال `_syncBookings(docs)` حتى تُربط أي دفعات كانت معلقة في `pending_links` فور وصول حجزها.

#### 3. `P0-3`: استعادة ضمان `deviceId` للدفعات المنشأة دون اتصال (Offline)
* **الملف:** `mobile/lib/services/daos/payments_dao.dart` (`سطر 313-335`) و`mobile/lib/services/appwrite_sync_manager.dart` (`سطر 461-471`).
* **الإجراء الجذري:**
  * في `AppwriteSyncManager._loadSettings`: تعيين `updateStaticDeviceId(_currentDeviceId ?? _deviceLocalUuid)`، وإذا كان كلاهما فارغاً توليد `_deviceLocalUuid` وحفظه في `SharedPreferences` عند بدء التشغيل، بحيث لا تُكتب أي دفعة محلية بـ `deviceId = ''`.

---

### المرحلة الثانية (`P1` - أولوية عالية): إغلاق ثغرات حساب الليالي والتسعير المتبقية

#### 4. `P1-1`: تمرير `roomRate` الحقيقي وربط UUID التعديلات في `GuestPaymentsDetailReportScreen`
* **الملف:** `mobile/lib/screens/reports/guest_payments_detail_report_screen.dart` (`سطور 145-165` و`210-250`).
* **الإجراء الجذري:**
  1. جلب خريطة أسعار الغرف `Map<String, double> roomRatesByNumber` من جدول `rooms` في `_refreshData()`.
  2. تمرير `roomRate: roomRatesByNumber[b.roomNumber]` إلى `StayBalanceCalculator.calculate(b, roomRate: ..., priceAdjustments: filtered)` لمنع تفعيل حارس `skipDiscountBecauseDerived` بالخطأ ولضمان تطبيق التعديلات اليومية بدقة.
  3. تجميع `allAdjustments` باستخدام `adj.bookingLocalId` **أو** مطابقة `adj.bookingLocalUuid` / `adj.bookingUuid` مع `b.localUuid` (بصيغتي الشرطات وبدونها).

#### 5. `P1-2`: إصلاح حساب الليالي في `GuestPaymentCalculationService` لحجوزات المغادرة الفارغة والمستقبلية
* **الملف:** `mobile/lib/services/guest_payment_calculation_service.dart` (`سطور 80-95`).
* **الإجراء الجذري:**
  * استبدال `final effectiveEnd = actualCheckout ?? now;` بمنطق موحد يطابق `EnhancedBookingCalculationService._resolveStayEnd` و`BookingNightsDisplay.forList`:
    * إذا وُجد `actualCheckout` وكان `<= now` ← نستخدم `actualCheckout`.
    * إذا وُجد `actualCheckout` وكان `> now` (شذوذ مستقبلي) ← نقصّه إلى `now`.
    * إذا غاب `actualCheckout` وكان الحجز نشطاً (`StatusUtils.isActiveBooking(booking.status)`) ← نستخدم `now`.
    * إذا غاب `actualCheckout` وكان الحجز غير نشط ← نستخدم `plannedCheckout ?? checkin.add(const Duration(days: 1))`.

#### 6. `P1-3`: توحيد `BookingPriceAdjustmentService.previewAdjustment` و`generateLostRevenueReport` مع `Time.nightsWithCutoff`
* **الملف:** `mobile/lib/services/booking_price_adjustment_service.dart` (`سطور 548-578` و`726-740`).
* **الإجراء الجذري:**
  * استبدال `checkout.difference(checkin).inDays` بـ `Time.nightsWithCutoff(checkin, checkout: checkout)`.
  * تطبيق سقف الخصم الليلي `_maxNightDiscount(currentRoomRate)` في `previewAdjustment` لتتطابق أرقام المعاينة بنسبة `100%` مع الحساب الفعلي.

#### 7. `P1-4`: إيقاف الحذف الفيزيائي لـ `booking_nights` في `RestoreFixService._rebuildBookingNights`
* **الملف:** `mobile/lib/services/restore_fix_service.dart` (`سطور 495-561`).
* **الإجراء الجذري:**
  * استبدال منطق `DELETE` + `insert` اليدوي الساذج في `_rebuildBookingNights` باستدعاء `EnhancedBookingCalculationService(db).calculateForBooking(booking.id, forceRebuild: true)` (مع تمرير خيار عدم تلويث `outbox` أثناء الاستعادة)، مما يحافظ على `localUuid` لليالي القائمة ويحسب الخصومات وتعديلات الأسعار بدقة.

---

### المرحلة الثالثة (`P2` - أولوية متوسطة): توحيد عقود المعرفات (`UUID` + `Local ID`) في جميع الاستعلامات المتبقية

#### 8. `P2-1`: تحديث `bookingUuidCache` تلقائياً في `PaymentsRepository.update`
* **الملف:** `mobile/lib/services/repositories/payments_repository.dart` (`سطور 118-174`).
* **الإجراء الجذري:**
  * عند تمرير `bookingLocalId` إلى `PaymentsRepository.update`، جلب `booking.localUuid` من جدول `bookings` وتمريره كـ `bookingUuidCache: Value(booking.localUuid)` في `PaymentsCompanion`.

#### 9. `P2-2`: دعم `bookingUuidCache` في `PaymentsDao.list` و`PaymentsDao.watchList` وإصلاح `importFromJson`
* **الملف:** `mobile/lib/services/daos/payments_dao.dart` (`سطور 200-275` و`495-549`).
* **الإجراء الجذري:**
  1. في `list()` و`watchList()`: عند تمرير `bookingLocalId`، جلب `localUuid` للحجز واستخدام نفس شرط `(t.bookingLocalId.equals(bookingLocalId) | t.bookingUuidCache.isIn([dashed, compact]))` المعتمد في `paymentsByBooking`.
  2. في `importFromJson()`: تمرير السجل عبر `PaymentsAdapter.fromJson` أو إضافة قراءة كافة الحقول المفقودة (`bookingUuidCache`, `hotelDayKey`, `isVoided`, `voidedAt`, `voidedBy`, `voidReason`, `isPendingBalance`, `isImmutable`).

#### 10. `P2-3`: توسيع `FinancialLinkRelinkService.relinkAll` ليشمل جداول الحجوزات والمدفوعات
* **الملف:** `mobile/lib/services/sync_core/financial_link_relink_service.dart` (`سطور 43-59`).
* **الإجراء الجذري:**
  * إضافة دوال إعادة الربط بالـ UUID بعد الاستعادة لكل من:
    * `payments` (`booking_uuid_cache` → `booking_local_id`) عبر `PaymentsBookingLinkBackfillService`.
    * `debts` (`booking_uuid_cache` → `booking_local_id`).
    * `booking_nights` (`booking_uuid_cache` → `booking_local_id`).
    * `booking_price_adjustments` (`booking_local_uuid` / `booking_uuid` → `booking_local_id`).

---

### المرحلة الرابعة (`P3` - وقائية ومعمارية): حوكمة المخطط ومنع الانحدار

#### 11. `P3-1`: توحيد استعلامات `BookingPriceAdjustmentService` و`RestoreFixService` للديون
* **الملفات:** `booking_price_adjustment_service.dart:460-476, 676-710` و`restore_fix_service.dart:463-478`.
* **الإجراء الجذري:** استخدام مطابقة مزدوجة (`bookingLocalId OR bookingLocalUuid IN (dashed, compact)`) في كافة استعلامات التعديلات والديون.

---

## 5. اختبارات إلزامية قبل اعتماد الإصلاح

لا يجوز اعتماد أي إصلاح أو دمجه في الفرع الرئيسي (`main`) إلا بعد اجتياز حزمة الاختبارات الإلزامية التالية بنسبة نجاح `100%` عبر الأمر `flutter test`:

### 5.1 اختبارات خط الأساس الموجودة حالياً في المستودع (Regression Baseline)
يجب التأكد من استمرار نجاح كافة الاختبارات المضافة في الفرع الحالي:
1. `mobile/test/services/no_free_nights_test.dart`:
   * منع إنشاء تعديل خصم `>= roomRate`.
   * قصّ الخصم الليلي المركب عند `baseRate - 0.01` وتسجيل الليلة في `anomalyNights`.
   * عدم توقف `StayBalanceCalculator` بصمت عند مصادفة ليلة سعرها `<= 0` وإعلان `hasAnomaly`.
   * منع الاشتقاق المزدوج (`Double-Derivation`) عند غياب `roomRate`.
2. `mobile/test/services/stay_balance_hotel_day_extension_test.dart`:
   * محاذاة `autoCheckoutDate` و`coveredDates` مع بداية اليوم الفندقي (`14:01`) خاصةً لدخول الفجر (قبل `14:01`).
3. `mobile/test/services/actual_checkout_truncation_test.dart`:
   * قصّ `actualCheckout` المستقبلي الشاذ إلى `now`.
   * تطبيق الخصومات الليلية والإجمالية في مسار الاحتياط (`calculateActualStayCost`) والتمديد اليدوي (`calculateManualExtensionCharge`).
4. `mobile/test/services/booking_nights_identity_test.dart`:
   * ثبات `id` و`localUuid` لصفوف `booking_nights` عند إعادة الحساب (`_replaceBookingNights`) واستخدام الحذف الناعم لليالي الملغاة.
5. `mobile/test/services/hotel_day_sql_dart_parity_test.dart`:
   * تطابق فلتر اليوم الفندقي (`14:01 Asia/Aden`) بين كود Dart واستعلام SQL في `PaymentsDao` للتواريخ بصيغة `Z` وصيغة `+03:00` والتواريخ المحلية.
6. `mobile/test/services/payments_uuid_query_backfill_test.dart`:
   * احتساب الدفعات المربوطة بـ `bookingUuidCache` فقط (بالشرطات وبدونها) في `watchTotalPaidForBooking` و`paymentsByBooking` و`PaymentsBookingLinkBackfillService`.
7. `mobile/test/services/restore_fix_no_clamp_test.dart`:
   * الحفاظ على الرصيد الدائن السالب (`remainingBalance < 0`) للنزيل وعدم قصّه إلى `0`، وعدم تلويث `lastModified` أو `outbox` أثناء `RestoreFixService`.
8. `mobile/test/unit/remote_booking_ref_guard_test.dart` و`mobile/test/unit/payment_void_sync_test.dart` و`mobile/test/unit/file_management_merge_safety_test.dart`.

### 5.2 الاختبارات الإلزامية الجديدة الواجب إضافتها قبل الاعتماد

#### أ. اختبارات وحدة حساب الليالي والتقارير (`test/services/night_calculation_edge_cases_test.dart`)
1. **اختبار تمرير `roomRate` مع تعديلات جزئية في التقرير التفصيلي:**
   * حجز لمدة `3` ليالٍ بسعر غرفة `100`، مع تعديل خصم `20` يبدأ من الليلة الثانية فقط (`effectiveHotelDay = day2`).
   * **النتيجة الإلزامية:** الليلة الأولى = `100`، الثانية = `80`، الثالثة = `80`، إجمالي الاستهلاك = `260`، وعدم تفعيل `skipDiscountBecauseDerived` طالما تم تمرير `roomRate = 100`.
2. **اختبار عدم تراكم الليالي لحجز مكتمل/ملغى يفتقر إلى `actualCheckout` في `GuestPaymentCalculationService`:**
   * حجز تاريخ دخوله قبل `30` يوماً وتاريخ مغادرته المخطط قبل `28` يوماً وحالته `'مكتمل'` ولكن `actualCheckout == null`.
   * **النتيجة الإلزامية:** `actualNights == 2` وليس `30`!
3. **اختبار تطابق `previewAdjustment` مع `EnhancedBookingCalculationService` حول حد الساعة `14:01`:**
   * دخول `2026-11-20 02:00` وخروج `2026-11-20 14:00` (ليلة واحدة)، ودخول `2026-11-20 15:00` وخروج `2026-11-21 15:00` (ليلتان).
   * **النتيجة الإلزامية:** تطابق `totalNights` و`newTotalCost` في `previewAdjustment` مع `calculateNightlyBreakdown`.

#### ب. اختبارات تكامل مزامنة المدفوعات وإلغائها (`test/services/payment_sync_integrity_test.dart`)
1. **اختبار تحديث كاش الحجز تلقائياً بعد `_syncPayments`:**
   * حجز محلي `B1` (`totalDueCached = 300, totalPaidCached = 0, remainingBalanceCached = 300`).
   * سحب وثيقة دفعة من Appwrite بمبلغ `200` تحمل `bookingUuidCache = B1.localUuid` وبلا `bookingLocalId`.
   * **النتيجة الإلزامية:** بعد انتهاء `_syncPayments` مباشرةً، يصبح `B1.totalPaidCached == 200` و`B1.remainingBalanceCached == 100` و`payment.bookingLocalId == B1.id`.
2. **اختبار وصول الدفعة قبل الحجز ثم وصول الحجز (`PendingLinks` → `Bookings Pull`):**
   * سحب دفعة `P1` لحجز `UUID-X` غير موجود محلياً ← تُحفظ في `pending_links` ولا تُدرج في `payments` كدفعة عامة.
   * سحب الحجز `UUID-X` في مهمة `_syncBookings` ← يتم تشغيل `_retryPendingFinancialLinks` تلقائياً، فتُدرج `P1` في `payments` مربوطةً بـ `UUID-X` وتُعلَّم في `pending_links` كـ `resolvedAt != null` ويتحدث `totalPaidCached` للحجز.
3. **اختبار التئام `_syncPaymentVoids` مع جدول `payments`:**
   * وجود دفعة محلية `P1` بمبلغ `150` وحجز `B1` (`totalPaidCached = 150`).
   * سحب مستند `payment_voids` يشير إلى `originalPaymentUuid = P1.localUuid`.
   * **النتيجة الإلزامية:** يصبح `P1.isVoided == true` و`P1.isImmutable == true`، وينخفض `B1.totalPaidCached` إلى `0` ويرتفع `B1.remainingBalanceCached` إلى `150`.
4. **اختبار عدم مسح `booking_uuid_cache` أو حذف الدفعة ناعماً في `_performPostSyncIntegrityCheck`:**
   * إدراج دفعة تشير إلى `booking_local_id = 999` (غير موجود) مع `booking_uuid_cache = 'valid-booking-uuid'`.
   * تشغيل `performPostSyncIntegrityCheckForTesting()`.
   * **النتيجة الإلزامية:** `payment.deletedAt == null` و`payment.bookingUuidCache == 'valid-booking-uuid'`، وعند توفر الحجز صاحب `'valid-booking-uuid'` يتم ربط `payment.bookingLocalId` به بنجاح.

---

## 6. طريقة مصالحة بيانات النزيل دون إفساد سجله المالي

لإجراء مصالحة شاملة (Data Reconciliation) لبيانات النزلاء على الأجهزة التي تأثرت بأخطاء حساب الليالي السابقة أو باختلاف معرفات الحجوزات والمدفوعات، يجب تطبيق **بروتوكول المصالحة المالية غير المدمّر (Non-Destructive Financial Reconciliation Protocol)** التالي:

### 6.1 القواعد الذهبية السبع لحماية السجل المالي أثناء المصالحة
1. **حظر الحذف الفيزيائي أو الناعم التلقائي للقيود المالية:** لا يجوز لأي أداة إصلاح أو مصالحة تنفيذ `DELETE` أو تعيين `deletedAt` على صفوف `payments` أو `payment_voids` أو `debts` أو `cash_transactions`.
2. **صون الرصيد الدائن السالب للنزيل (`remainingBalance < 0`):** إذا دفع النزيل مقدماً مبلغاً أكبر من المستحق أو خُفّض سعر إقامته بعد السداد، فإن `remainingBalance = totalDue - totalPaid` يكون سالباً (رصيد دائن للنزيل). يُحظر قصّه بـ `clamp(0, totalDue)`، ويُحظر توليد دفعة عكسية تلقائية؛ التسوية النقدية تتم فقط بقرار محاسبي صريح وموثق في `audit_logs`.
3. **حظر تلويث `lastModified` أو طابور `outbox` أثناء إعادة الحساب المحلي:** عمليات إعادة بناء الكاش (`totalDueCached`, `totalPaidCached`, `remainingBalanceCached`) وإعادة الربط المحلي (`booking_local_id`) يجب أن تُنفذ بـ `enqueueOutbox: false` ودون رفع `lastModified`، حتى لا تُغرق السحابة بآلاف التحديثات الوهمية أو تتغلب بالخطأ على تعديل حقيقي أحدث في جهاز آخر (LWW / OCC).
4. **ثبات هوية الليالي (`booking_nights.localUuid`):** عند إعادة بناء جدول الليالي لحجز ما، يُحظر مسح الجدول وإعادة إنشائه بـ UUIDs جديدة؛ يجب التحديث في المكان (`In-Place Update`) بمفتاح `(bookingLocalId, hotelDayKey)` مع الاحتفاظ بـ `id` و`localUuid` الأصليين.
5. **احترام تجميد الإقامات المكتملة (`isFrozenCompletedStay`):** الحجوزات التي غادر نزلاؤها فعلياً (`actualCheckout != null`) ولديها سجل ليالٍ مكتمل في `booking_nights` لا يُعاد تسعير لياليها التاريخية بتغيرات أسعار الغرف اللاحقة، بل يُعاد فقط جمع `finalRate` لليالي المخزنة ومطابقته مع إجمالي المدفوعات الفعلي.
6. **توحيد صيغة UUID قبل أي مطابقة:** كل مقارنات الهوية بين الجداول يجب أن تطابق الصيغة القياسية بالشرطات (`36` حرفاً) والصيغة المضغوطة بلا شرطات (`32` حرفاً) مع `LOWER(TRIM(...))`.
7. **التوثيق الإلزامي للفروقات في سجل التدقيق (`audit_logs`):** أي تغيير في `totalDueCached` أو `totalPaidCached` أو `remainingBalanceCached` يتجاوز `0.01` أثناء المصالحة يجب أن يُسجَّل في تقرير مصالحة محلي يوضح (`القيمة قبل`، `القيمة بعد`، `سبب الفرق`).

---

### 6.2 الخوارزمية التنفيذية للمصالحة (6 مراحل متسلسلة)

تُنفَّذ المصالحة لكل حجز (أو على مستوى قاعدة البيانات بالكامل) داخل معاملة محلية محمية بالتسلسل التالي:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ المرحلة 1: أخذ لقطة تدقيق قبلية (Pre-Reconciliation Snapshot)            │
│ حفظ (id, localUuid, totalDueCached, totalPaidCached, remainingBalance)   │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ المرحلة 2: توحيد وتعبئة أختام UUID للأبناء (UUID Backfill)               │
│ تعبئة booking_uuid_cache / booking_local_uuid المفقودة من bookings.uuid │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ المرحلة 3: إعادة ربط المفاتيح المحلية بالـ UUID (Identity Relink)        │
│ تصحيح booking_local_id في payments, debts, nights, adjustments, notes    │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ المرحلة 4: مطابقة إلغاءات الدفع وتصحيح اليوم الفندقي (Voids & DayKey)    │
│ مزامنة payment_voids مع payments.isVoided وإصلاح hotelDayKey (14:01)     │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ المرحلة 5: إعادة حساب الليالي والمستحقات والمدفوعات (In-Place Recalc)    │
│ تحديث booking_nights (بثبات localUuid) وحساب totalDue و totalPaid الفعلي │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ المرحلة 6: إصدار كشف التسوية وعزل الحالات الشاذة للمراجعة البشرية        │
│ تصنيف: (متطابق / رصيد دائن للنزيل / شذوذ سعر صفري / دفعات غير منسوبة)    │
└──────────────────────────────────────────────────────────────────────────┘
```

#### تفاصيل التنفيذ التقني لكل مرحلة:

##### المرحلة 1: أخذ لقطة تدقيق قبلية (Pre-Reconciliation Snapshot)
* قبل لمس أي صف، تُقرأ القيم الحالية لكل حجز (`expectedNights`, `calculatedNights`, `totalNightsCached`, `totalDueCached`, `totalPaidCached`, `remainingBalanceCached`) وتُحفظ في الذاكرة لمقارنتها بعد انتهاء المصالحة.

##### المرحلة 2: تعبئة أختام `bookingUuidCache` المفقودة (Child UUID Backfill)
* تشغيل `BookingChildUuidBackfillService.run(db)` (`mobile/lib/services/booking_child_uuid_backfill_service.dart`) لملء `booking_uuid_cache` على `booking_nights` و`payments` و`debts` و`booking_notes` التي تملك `booking_local_id` صحيحاً محلياً ولكن ينقصها ختم الـ UUID.

##### المرحلة 3: إعادة ربط المفاتيح الرقمية المحلية من مصدر الحقيقة `UUID` (Deterministic Identity Relink)
* تنفيذ تحديث SQL ذري يعيد توجيه `booking_local_id` في جميع الجداول التابعة (`payments`, `debts`, `booking_nights`, `booking_price_adjustments`, `booking_notes`) ليطابق `bookings.id` المحلي المقابل لـ `bookings.local_uuid` (بصيغتي الشرطات وبدونها):
  ```sql
  -- 1. إصلاح ارتباط المدفوعات بالحجز الصحيح عبر UUID (حتى لو كان booking_local_id NULL أو يشير لحجز خاطئ)
  UPDATE payments
  SET booking_local_id = (
    SELECT b.id FROM bookings b
    WHERE REPLACE(LOWER(TRIM(b.local_uuid)), '-', '') =
          REPLACE(LOWER(TRIM(payments.booking_uuid_cache)), '-', '')
    LIMIT 1
  )
  WHERE booking_uuid_cache IS NOT NULL
    AND TRIM(booking_uuid_cache) != ''
    AND EXISTS (
      SELECT 1 FROM bookings b
      WHERE REPLACE(LOWER(TRIM(b.local_uuid)), '-', '') =
            REPLACE(LOWER(TRIM(payments.booking_uuid_cache)), '-', '')
    )
    AND (
      booking_local_id IS NULL
      OR booking_local_id != (
        SELECT b.id FROM bookings b
        WHERE REPLACE(LOWER(TRIM(b.local_uuid)), '-', '') =
              REPLACE(LOWER(TRIM(payments.booking_uuid_cache)), '-', '')
        LIMIT 1
      )
    );
  ```
* يُطبَّق نفس الاستعلام تماماً على `debts` (عبر `booking_uuid_cache`)، و`booking_nights` (عبر `booking_uuid_cache`)، و`booking_price_adjustments` (عبر `COALESCE(booking_local_uuid, booking_uuid)`).

##### المرحلة 4: مطابقة إلغاءات الدفع (`payment_voids`) وتصحيح مفاتيح اليوم الفندقي (`hotelDayKey`)
1. **تطبيق سجلات `payment_voids` على جدول `payments`:**
   ```sql
   UPDATE payments
   SET is_voided = 1,
       is_immutable = 1
   WHERE is_voided = 0
     AND EXISTS (
       SELECT 1 FROM payment_voids pv
       WHERE pv.deleted_at IS NULL
         AND REPLACE(LOWER(TRIM(pv.original_payment_uuid)), '-', '') =
             REPLACE(LOWER(TRIM(payments.local_uuid)), '-', '')
     );
   ```
2. **تصحيح `hotelDayKey` على المدفوعات والحجوزات:** تشغيل `HotelDayKeyFixService(db).runFixIfNeeded()` بعد تهيئة `HotelTimezone.ensureInitialized()` لضمان احتساب جميع الفواصل الزمنية وفق `14:01 Asia/Aden`.

##### المرحلة 5: إعادة حساب الليالي والأرصدة دون المساس بـ `lastModified` أو `outbox`
* لكل حجز غير محذوف (`deletedAt == null`):
  1. إذا كان الحجز **إقامة مكتملة مجمدة** (`BookingDerivedFieldsService.isFrozenCompletedStay(booking) == true` ولديه صفوف `booking_nights` غير محذوفة):
     * لا يُعاد تسعير الليالي من جدول الغرف؛ يُحسب `totalDue` من مجموع `booking_nights` القائمة (`finalRate > 0 ? finalRate : nightlyRate`).
  2. إذا كان الحجز **نشطاً أو غير مكتمل الليالي**:
     * يُستدعى `EnhancedBookingCalculationService(db).calculateForBooking(booking.id, forceRebuild: true)` الذي يحسب الليالي وفق `Time.nightsWithCutoff`، ويطبق `booking.discount` و`booking_price_adjustments` مع احترام قاعدة «لا ليالٍ مجانية» (`>= 0.01`)، ويحدّث `booking_nights` في مكانها (`_replaceBookingNights`) محتفظاً بـ `localUuid` لكل ليلة.
  3. يُحسب `totalPaid` من جدول `payments` عبر `totalPaymentsForBooking(booking)` (الذي يجمع فقط الدفعات التي تحقق `deletedAt == null && !isVoided && !isPendingBalance` والمطابقة لـ `booking.id` أو `booking.localUuid` بصيغتيه).
  4. يُحسب الرصيد المتبقي الموقّع (Signed Balance):
     ```dart
     final remainingBalance = totalDue - totalPaid; // ⚠️ بدون clamp(0, totalDue)
     final isFullyPaid = remainingBalance <= 0.01 && totalDue > 0;
     ```
  5. تُكتب الحقول المشتقة (`calculatedNights`, `totalNightsCached`, `totalDueCached`, `totalPaidCached`, `remainingBalanceCached`, `isFullyPaid`, `hotelDayCheckin`, `hotelDayCheckout`) مباشرةً في جدول `bookings` **دون تغيير `lastModified` ودون إضافة عنصر في `outbox`**.

##### المرحلة 6: معالجة الفروقات وإصدار تقرير التسوية المحاسبي (Reconciliation Report)
بعد اكتمال المرحلة الخامسة، يُصنَّف كل حجز تغيرت أرقامه عن لقطة المرحلة الأولى إلى إحدى الفئات الأربع التالية ليراجعه المحاسب بأمان:
1. **حجوزات تم تصحيح ربط دفعاتها (Relinked Payments):** دفعات كانت مخفية بسبب `bookingLocalId = null` وعادت للظهور في حساب النزيل؛ يظهر للنزيل الآن إجمالي مدفوعاته الحقيقي دون الحاجة لإدخال دفعة مكررة.
2. **حجوزات ذات رصيد دائن للنزيل (`remainingBalanceCached < 0`):** تظهر بوضوح في واجهة الدفع (`BookingPaymentScreen`) باللون البرتقالي تحت عنوان **«للنزيل رصيد دائن»** مع تنبيه **«لا تُنشئ دفعة عكسية تلقائياً؛ راجع التسوية المالية»**، بحيث يقرر المحاسب إما ترحيل الرصيد لتمديد إقامة النزيل أو رد الفائض نقداً بسند صرف موثق.
3. **حجوزات بها شذوذ تسعير صفري (`anomalyNights.isNotEmpty`):** حجوزات كانت تحتوي على خصم يساوي أو يتجاوز سعر الغرفة؛ تم رفع سعر الليلة فيها تلقائياً إلى `0.01` مع إظهار شارة التحذير في بطاقة ملخص الدفع لمراجعة تعديل السعر من شاشة تعديل النزيل (`GuestEditScreen`).
4. **دفعات استثنائية غير منسوبة (`Unattributed Payments`):** دفعات تحمل `bookingUuidCache` لحجز لم يصل بعد من جهاز آخر (موجودة في `pending_links`)؛ تُعرض في قسم الاستثناءات في `PaymentsReportScreen` (`_unattributedCount` / `_unattributedTotal`) ولا تُحذف ولا تُدمج قسراً في حجز عشوائي حتى يصل حجزها الأب عبر المزامنة.
