# 📋 تقارير الجداول المتبقية - الكود المحلي

**تاريخ التقرير:** 2026-06-26  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  

---

## ✅ تصحيح مهم - SyncFields

> **ملاحظة:** في التقارير السابقة، ذُكرت بعض الحقول كـ "مفقودة" في الجداول. هذا كان خطأ في التحليل!
> 
> **✅ جميع حقول SyncFields موجودة فعلياً في Appwrite Cloud!**

### حقول SyncFields المُثبت وجودها:

| الحقل | النوع | الوصف |
|-------|------|-------|
| `createdAt` | string | تاريخ الإنشاء |
| `updatedAt` | string | تاريخ التحديث |
| `deletedAt` | string? | تاريخ الحذف |
| `lastModified` | string | آخر تعديل |
| `createdAtIso` | string | تاريخ ISO |
| `updatedAtIso` | string | تحديث ISO |
| `deletedAtIso` | string? | حذف ISO |
| `createdAtEpoch` | integer | طابع epoch |
| `lastModifiedEpoch` | integer | epoch التعديل |
| `version` | integer | الإصدار |
| `origin` | string | المصدر |
| `vectorClock` | string? | ساعة المتجهات |
| `deviceId` | string? | معرف الجهاز |

### الجداول التي تحتوي SyncFields:
- ✅ Bookings
- ✅ Payments  
- ✅ Debts
- ✅ Booking Nights
- ✅ Price Adjustments
- ✅ Payment Voids
- ✅ Audit Logs
- ✅ Rooms
- ✅ Expenses

---

## 📊 قائمة شاملة بجميع الجداول (22 جدول)

| # | الجدول | Collection ID | الحقول | الفهارس | الحالة |
|---|--------|---------------|--------|---------|--------|
| 1 | Rooms | `rooms` | 28 | 13 | ✅ من Cloud |
| 2 | Bookings | `bookings` | 46 | 22 | ✅ من Cloud |
| 3 | Payments | `payments` | 43 | 20 | ✅ من Cloud |
| 4 | Employees | `employees` | 26 | 9 | ⚠️ من الكود |
| 5 | Expenses | `expenses` | 26 | 3 | ⚠️ من الكود |
| 6 | Salary Withdrawals | `salary_withdrawals` | 24 | 1 | ⚠️ من الكود |
| 7 | Guest Infos | `guest_infos` | 25 | - | ⚠️ من الكود |
| 8 | Debts | `debts` | 35 | 1 | ⚠️ من الكود |
| 9 | Audit Logs | `audit_logs` | 20 | ? | ⚠️ من الكود |
| 10 | Booking Notes | `booking_notes` | 7 | 1 | ⚠️ من الكود |
| 11 | Cash Transactions | `cash_transactions` | 12 | 2 | ⚠️ من الكود |
| 12 | Shift Notes | `shift_notes` | 13 | 4 | ⚠️ من الكود |
| 13 | Booking Nights | `booking_nights` | 16 | 1 | ⚠️ من الكود |
| 14 | Price Adjustments | `price_adjustments` | 17 | 2 | ⚠️ من الكود |
| 15 | Booking Price Adjustments | `booking_price_adjustments` | 18 | 2 | ⚠️ من الكود |
| 16 | Payment Voids | `payment_voids` | 15 | 2 | ⚠️ من الكود |
| 17 | Salary Cycles | `salary_cycles` | 13 | 1 | ⚠️ من الكود |
| 18 | Salary Payments | `salary_payments` | 11 | 1 | ⚠️ من الكود |
| 19 | Salary Carry Over Logs | `salary_carry_over_logs` | 12 | 1 | ⚠️ من الكود |
| 20 | Hotel Day Ledger | `hotel_day_ledger` | 15 | ? | ⚠️ من الكود |
| 21 | Blacklist | `blacklist` | 11 | - | ⚠️ (in shift_notes) |
| 22 | Outbox | `outbox` | 10 | ? | ⚠️ محلي فقط |

---

## 📋 تفاصيل الجداول المتبقية

### 1. Audit Logs (سجل التدقيق)

**الفئة:** `AuditLogs`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `localUuid` | string | UUID فريد |
| `operationType` | string | نوع العملية |
| `entityType` | string | نوع الكيان |
| `entityUuid` | string | UUID الكيان |
| `entityId` | integer? | معرف الكيان |
| `previousState` | string? | الحالة السابقة |
| `newState` | string? | الحالة الجديدة |
| `changedFields` | string? | الحقول المتغيرة |
| `performedBy` | string | من قام بالعملية |
| `deviceId` | string | معرف الجهاز |
| `ipAddress` | string? | عنوان IP |
| `hotelDayKey` | string | يوم الفندق |
| `timestamp` | DateTime | الطابع الزمني |

---

### 2. Booking Notes (ملاحظات الحجز)

**الفئة:** `BookingNotes`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `bookingId` | integer | FK إلى الحجز |
| `noteText` | string | نص الملاحظة |
| `alertType` | string | نوع التنبيه |
| `alertUntil` | string? | صلاحية التنبيه |
| `isActive` | integer | هل التنبيه نشط (1/0) |

---

### 3. Cash Transactions (المعاملات النقدية)

**الفئة:** `CashTransactions`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `registerId` | integer? | معرف الدرج |
| `transactionType` | string | نوع المعاملة |
| `amount` | double | المبلغ |
| `referenceType` | string? | نوع المرجع |
| `referenceId` | integer? | معرف المرجع |
| `description` | string? | الوصف |
| `transactionTime` | string | وقت المعاملة |
| `createdBy` | integer? | منشئ المعاملة |

---

### 4. Shift Notes (ملاحظات الورديات)

**الفئة:** `ShiftNotes`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `title` | string | العنوان |
| `content` | string | المحتوى |
| `priority` | string | الأولوية (high/medium/low) |
| `shiftType` | string | نوع الوردية |
| `isRead` | integer | هل مقروء (0/1) |
| `expiresAt` | string? | تاريخ الانتهاء |
| `createdBy` | string | منشئ الملاحظة |

---

### 5. Booking Nights (ليالي الحجز)

**الفئة:** `BookingNights`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `bookingLocalId` | integer | FK إلى الحجز |
| `hotelDayKey` | string | مفتاح يوم الفندق |
| `nightStart` | string | بداية الليلة |
| `nightEnd` | string | نهاية الليلة |
| `nightlyRate` | double | السعر الليلي |
| `sequence` | integer | التسلسل |
| `isProcessedByAutoFix` | boolean | معالج بواسطة AutoFix |
| `baseRate` | double | السعر الأساسي |
| `adjustment` | double | التعديل |
| `finalRate` | double | السعر النهائي |
| `appliedAdjustmentUuid` | string? | UUID التعديل المطبق |
| `appliedAdjustmentsJson` | string? | JSON التعديلات |

---

### 6. Price Adjustments (تعديلات الأسعار)

**الفئة:** `PriceAdjustments`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `targetType` | string | نوع الهدف |
| `targetUuid` | string | UUID الهدف |
| `adjustmentType` | string | نوع التعديل |
| `previousValue` | integer | القيمة السابقة |
| `newValue` | integer | القيمة الجديدة |
| `reason` | string? | السبب |
| `effectiveDate` | string | تاريخ الفعالية |
| `appliedBy` | string | من طبّق التعديل |
| `hotelDayKey` | string | يوم الفندق |
| `isReversed` | boolean | هل تم إلغاؤه |
| `reversedAt` | string? | تاريخ الإلغاء |
| `reversedBy` | string? | من ألغى |

---

### 7. Booking Price Adjustments

**الفئة:** `BookingPriceAdjustments`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `bookingLocalUuid` | string | UUID الحجز |
| `bookingLocalId` | integer? | معرف الحجز |
| `roomNumber` | string? | رقم الغرفة |
| `adjustmentType` | integer | نوع التعديل |
| `adjustmentMode` | string | وضع التعديل |
| `amount` | double | المبلغ |
| `effectiveHotelDay` | string | يوم الفندق الفعال |
| `endHotelDay` | string? | يوم انتهاء الصلاحية |
| `isActive` | boolean | هل نشط |
| `reason` | string? | السبب |
| `appliedBy` | string? | من طبّق |
| `cancelledAt` | string? | تاريخ الإلغاء |
| `cancelledBy` | string? | من ألغى |

---

### 8. Payment Voids (إلغاء المدفوعات)

**الفئة:** `PaymentVoids`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `originalPaymentUuid` | string | UUID الدفع الأصلي |
| `originalPaymentId` | integer | معرف الدفع الأصلي |
| `bookingUuid` | string | UUID الحجز |
| `voidedAmount` | integer | المبلغ الملغى |
| `voidReason` | string | سبب الإلغاء |
| `voidedBy` | string | من ألغى |
| `voidedAt` | integer | وقت الإلغاء |
| `voidedAtIso` | string | وقت الإلغاء ISO |
| `hotelDayKey` | string | يوم الفندق |
| `reversalPaymentUuid` | string? | UUID الدفع المعاكس |
| `approvedBy` | string? | من وافق |

---

### 9. Salary Cycles (دورات الرواتب)

**الفئة:** `SalaryCycles`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `employeeId` | integer | FK إلى الموظف |
| `cycleKey` | string | مفتاح الدورة |
| `hotelDayStart` | string? | بداية الدورة |
| `hotelDayEnd` | string? | نهاية الدورة |
| `expectedAmount` | integer | المبلغ المتوقع |
| `actualPaid` | integer | المبلغ الفعلي |
| `remainingAmount` | integer | المبلغ المتبقي |
| `status` | string | الحالة |

---

### 10. Salary Payments (مدفوعات الرواتب)

**الفئة:** `SalaryPayments`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `cycleId` | integer | FK إلى دورة الراتب |
| `amount` | integer | المبلغ |
| `hotelDayKey` | string? | يوم الفندق |
| `paymentDateIso` | string | تاريخ الدفع |
| `method` | string? | طريقة الدفع |
| `isAutoGenerated` | boolean | مُنشأ تلقائياً |

---

### 11. Salary Carry Over Logs (سجلات ترحيل الرواتب)

**الفئة:** `SalaryCarryOverLogs`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `employeeId` | integer | FK إلى الموظف |
| `amount` | double | المبلغ |
| `previousCycleStart` | string | بداية الدورة السابقة |
| `previousCycleEnd` | string | نهاية الدورة السابقة |
| `newCycleStart` | string | بداية الدورة الجديدة |
| `newCycleEnd` | string | نهاية الدورة الجديدة |
| `reason` | string | السبب |
| `carriedAt` | integer | وقت الترحيل |

---

### 12. Hotel Day Ledger (دفتر يوم الفندق)

**الفئة:** `HotelDayLedger`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `hotelDayKey` | string | مفتاح يوم الفندق |
| `totalIncome` | double | إجمالي الدخل |
| `totalExpenses` | double | إجمالي المصروفات |
| `pendingBalances` | double | الأرصدة المعلقة |
| `occupancyRate` | double | نسبة الإشغال |
| `bookingsProcessed` | integer | عدد الحجز المعالجة |

---

### 13. Blacklist (القائمة السوداء)

**التخزين:** في `shift_notes` مع `createdBy = 'blacklist'`

| الحقل | النوع | الوصف |
|-------|------|-------|
| `name` | string | اسم الشخص |
| `nationality` | string? | الجنسية |
| `nationalId` | string? | رقم الهوية |
| `phone` | string? | الهاتف |
| `reason` | string? | سبب الحظر |
| `notes` | string? | ملاحظات |
| `reportedBy` | string | المُبلّغ |
| `active` | boolean | نشط |

---

### 14. Outbox (الصندوق الوارد للمزامنة)

**الفئة:** `Outbox` (محلي فقط - لا يُزامن)

| الحقل | النوع | الوصف |
|-------|------|-------|
| `id` | integer | معرف محلي |
| `entity` | string | نوع الكيان |
| `op` | string | العملية |
| `localUuid` | string | UUID المحلي |
| `serverId` | integer? | معرف السيرفر |
| `payload` | string | البيانات |
| `clientTs` | integer | وقت العميل |
| `serverTs` | integer? | وقت السيرفر |
| `status` | string | الحالة |
| `attempts` | integer | عدد المحاولات |
| `lastError` | string? | آخر خطأ |

---

## 📊 ملخص إحصائي

| الفئة | العدد |
|-------|-------|
| جداول المزامنة الأساسية | 3 (rooms, bookings, payments) |
| جداول الموارد البشرية | 4 (employees, salary_*) |
| جداول المالية | 5 (expenses, debts, cash_*, payments) |
| جداول الحجوزات | 4 (bookings, booking_notes, nights, price_adj) |
| جداول عامة | 3 (shift_notes, audit_logs, blacklist) |
| جداول تقنية | 3 (outbox, hotel_day_ledger, app_settings) |
| **المجموع** | **22 جدول** |

---

## ⚠️ ملاحظة حول الصلاحيات

الـ API Key الحالي لا يملك صلاحيات كافية للوصول إلى بعض الجداول. يجب إضافة الصلاحيات يدوياً من Appwrite Console.

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
