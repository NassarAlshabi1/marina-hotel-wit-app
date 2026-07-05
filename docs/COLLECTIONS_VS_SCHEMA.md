# 📊 مقارنة شاملة: كل المجموعات مقابل مخطط Appwrite Cloud مع أنواع الحقول

**التاريخ:** 2026-07-05  
**الفرع:** `refactor/clean-v2`  

---

## 🗺️ فهرس المجموعات

| # | المجموعة | `collectionSchema` | `_backupFetchers` | الحالة |
|---|----------|-------------------|-------------------|--------|
| 1 | `rooms` | ✅ | ✅ | ✅ |
| 2 | `bookings` | ✅ | ✅ | ✅ |
| 3 | `payments` | ✅ | ✅ | ✅ |
| 4 | `expenses` | ✅ | ✅ | ✅ |
| 5 | `debts` | ✅ | ✅ | ⚠️ |
| 6 | `employees` | ✅ | ✅ | ⚠️ |
| 7 | `booking_notes` | ✅ | ✅ | ✅ |
| 8 | `booking_nights` | ✅ | ✅ | ✅ |
| 9 | `cash_transactions` | ✅ | ✅ | ⚠️ |
| 10 | `booking_price_adjustments` | ✅ | ✅ | ⚠️ |
| 11 | `audit_logs` | ✅ | ✅ | ⚠️ |
| 12 | `payment_voids` | ✅ | ✅ | ✅ |
| 13 | `guest_infos` | ✅ | ✅ | ✅ |
| 14 | `price_adjustments` | ✅ | ✅ | ✅ |
| 15 | `salary_cycles` | ✅ | ✅ | ✅ |
| 16 | `salary_payments` | ✅ | ✅ | ✅ |
| 17 | `salary_withdrawals` | ✅ | ✅ | ✅ |
| 18 | `salary_carry_over_logs` | ✅ | ✅ | ✅ |
| 19 | `shift_notes` | ✅ | ✅ | ✅ |
| 20 | `app_settings` | ❌ (VFP only) | ✅ | 🔴 |
| 21 | `blacklist` | ❌ (VFP only) | ⚠️ | 🟡 |
| 22 | `sync_logs` | ❌ (VFP only) | ❌ | ℹ️ |
| 23 | `sync_state` | ❌ (VFP only) | ❌ | ℹ️ |
| 24 | `app_users` | ❌ (VFP only) | ❌ | ℹ️ |
| 25 | `devices` | ❌ (VFP only) | ❌ | ℹ️ |

---

## 1. `rooms` ✅

| الحقل | النوع في السحابة | في `_roomToMap` | مطابق؟ |
|-------|-----------------|-----------------|--------|
| `localUuid` | `string` | ✅ `r.localUuid` | ✅ |
| `roomNumber` | `string` | ✅ `r.roomNumber` | ✅ |
| `type` | `string` | ✅ `r.type` | ✅ |
| `price` | `double` | ✅ `r.price` | ✅ |
| `status` | `string` | ✅ `r.status` | ✅ |
| `imageUrl` | `string` | ✅ `r.imageUrl` | ✅ |
| `cleaningStatus` | `string` | ✅ `r.cleaningStatus` | ✅ |
| `lastCleanedHotelDay` | `string` | ✅ `r.lastCleanedHotelDay` | ✅ |
| `lastOccupiedHotelDay` | `string` | ✅ `r.lastOccupiedHotelDay` | ✅ |
| `requiresMaintenance` | `boolean` | ✅ `r.requiresMaintenance` | ✅ |
| `serverId` | `integer` | ✅ `r.serverId` | ✅ |
| `createdAt` | `integer` | ✅ `r.createdAt` | ✅ |
| `updatedAt` | `integer` | ✅ `r.updatedAt` | ✅ |
| `deletedAt` | `integer` | ✅ `r.deletedAt` | ✅ |
| `lastModified` | `integer` | ✅ `r.lastModified` | ✅ |
| `createdAtIso` | `string` | ✅ `r.createdAtIso` | ✅ |
| `updatedAtIso` | `string` | ✅ `r.updatedAtIso` | ✅ |
| `deletedAtIso` | `string` | ✅ `r.deletedAtIso` | ✅ |
| `createdAtEpoch` | `integer` | ✅ `r.createdAtEpoch` | ✅ |
| `lastModifiedEpoch` | `integer` | ✅ `r.lastModifiedEpoch` | ✅ |
| `syncTimestamp` | `integer` | يضاف تلقائياً | ✅ |
| `deviceId` | `string` | ✅ `r.deviceId` | ✅ |
| `version` | `integer` | ✅ `r.version` | ✅ |
| `origin` | `string` | ✅ `r.origin` | ✅ |
| `vectorClock` | `string` | ✅ `r.vectorClock` | ✅ |
| `sync_origin` | `string` | يضاف تلقائياً | ✅ |
| `idempotencyKey` | `string` | يضاف تلقائياً | ✅ |

---

## 2. `bookings` ✅

| الحقل | النوع | في `_bookingToMap` | مطابق؟ |
|-------|-------|-------------------|--------|
| `localUuid` | `string` | ✅ `b.localUuid` | ✅ |
| `serverBookingId` | `integer` | ✅ `b.serverBookingId` | ✅ |
| `roomNumber` | `string` | ✅ `b.roomNumber` | ✅ |
| `guestName` | `string` | ✅ `b.guestName` | ✅ |
| `guestPhone` | `string` | ✅ `b.guestPhone` | ✅ |
| `guestIdType` | `string` | ✅ `b.guestIdType` | ✅ |
| `guestIdNumber` | `string` | ✅ `b.guestIdNumber` | ✅ |
| `guestIdIssueDate` | `string` | ✅ `b.guestIdIssueDate` | ✅ |
| `guestIdIssuePlace` | `string` | ✅ `b.guestIdIssuePlace` | ✅ |
| `guestNationality` | `string` | ✅ `b.guestNationality` | ✅ |
| `guestEmail` | `string` | ✅ `b.guestEmail` | ✅ |
| `guestAddress` | `string` | ✅ `b.guestAddress` | ✅ |
| `checkinDate` | `string` | ✅ `b.checkinDate` | ✅ |
| `checkoutDate` | `string` | ✅ `b.checkoutDate` | ✅ |
| `actualCheckout` | `string` | ✅ `b.actualCheckout` | ✅ |
| `status` | `string` | ✅ `b.status` | ✅ |
| `notes` | `string` | ✅ `b.notes` | ✅ |
| `expectedNights` | `integer` | ✅ `b.expectedNights` | ✅ |
| `calculatedNights` | `integer` | ✅ `b.calculatedNights` | ✅ |
| `totalNightsCached` | `integer` | ✅ `b.totalNightsCached` | ✅ |
| `stayDurationIso` | `string` | ✅ `b.stayDurationIso` | ✅ |
| `lastNightEpoch` | `integer` | ✅ `b.lastNightEpoch` | ✅ |
| `isOverdue` | `boolean` | ✅ `b.isOverdue` | ✅ |
| `needsCheckoutReview` | `boolean` | ✅ `b.needsCheckoutReview` | ✅ |
| `totalDueCached` | `double` | ✅ `b.totalDueCached` | ✅ |
| `totalPaidCached` | `double` | ✅ `b.totalPaidCached` | ✅ |
| `remainingBalanceCached` | `double` | ✅ `b.remainingBalanceCached` | ✅ |
| `isFullyPaid` | `boolean` | ✅ `b.isFullyPaid` | ✅ |
| `discount` | `double` | ✅ `b.discount` | ✅ |
| `discountType` | `string` | ✅ `b.discountType` | ✅ |
| `discountStartDate` | `string` | ✅ `b.discountStartDate` | ✅ |
| `hotelDayCheckin` | `string` | ✅ `b.hotelDayCheckin` | ✅ |
| `hotelDayCheckout` | `string` | ✅ `b.hotelDayCheckout` | ✅ |
| `financialFrozenAt` | `integer` | ❌ غير موجود محلياً | ℹ️ |
| `financialHash` | `string` | ❌ غير موجود محلياً | ℹ️ |
| حقول SyncFields (8) | متنوعة | ✅ من الـ mixin | ✅ |

---

## 3. `payments` ✅

| الحقل | النوع | في `_paymentToMap` | مطابق؟ |
|-------|-------|-------------------|--------|
| `localUuid` | `string` | ✅ | ✅ |
| `serverPaymentId` | `integer` | ✅ | ✅ |
| `bookingLocalId` | `integer` | ✅ | ✅ |
| `serverBookingId` | `integer` | ✅ | ✅ |
| `roomNumber` | `string` | ✅ | ✅ |
| `amount` | `double` | ✅ | ✅ |
| `paymentDate` | `string` | ✅ | ✅ |
| `notes` | `string` | ✅ | ✅ |
| `paymentMethod` | `string` | ✅ | ✅ |
| `revenueType` | `string` | ✅ | ✅ |
| `cashTransactionLocalId` | `integer` | ✅ | ✅ |
| `cashTransactionServerId` | `integer` | ✅ | ✅ |
| `referenceNumber` | `string` | ✅ | ✅ |
| `hotelDayKey` | `string` | ✅ | ✅ |
| `isPendingBalance` | `boolean` | ✅ | ✅ |
| `linkedDebtUuid` | `string` | ✅ | ✅ |
| `bookingUuidCache` | `string` | ✅ | ✅ |
| `isVoided` | `boolean` | ✅ | ✅ |
| `voidedAt` | `integer` | ✅ | ✅ |
| `voidedBy` | `string` | ✅ | ✅ |
| `voidReason` | `string` | ❌ غير موجود محلياً | ℹ️ |
| `isImmutable` | `boolean` | ❌ غير موجود محلياً | ℹ️ |
| `discountAmount` | `double` | ✅ | ✅ |
| `discountStartDate` | `string` | ✅ | ✅ |

---

## 4. `expenses` ✅ — تطابق تام

| الحقل | النوع | في `_expenseToMap` |
|-------|-------|-------------------|
| `localUuid` | `string` | ✅ |
| `serverId` | `integer` | ✅ |
| `createdAt` | `integer` | ✅ |
| `updatedAt` | `integer` | ✅ |
| `deletedAt` | `integer` | ✅ |
| `lastModified` | `integer` | ✅ |
| `createdAtIso` | `string` | ✅ |
| `updatedAtIso` | `string` | ✅ |
| `deletedAtIso` | `string` | ✅ |
| `createdAtEpoch` | `integer` | ✅ |
| `lastModifiedEpoch` | `integer` | ✅ |
| `version` | `integer` | ✅ |
| `origin` | `string` | ✅ |
| `vectorClock` | `string` | ✅ |
| `deviceId` | `string` | ✅ |
| `idempotencyKey` | `string` | ✅ |
| `syncTimestamp` | `integer` | ✅ (يضاف تلقائياً) |
| `sync_origin` | `string` | ✅ (يضاف تلقائياً) |
| `expenseType` | `string` | ✅ |
| `relatedId` | `integer` | ✅ |
| `description` | `string` | ✅ |
| `amount` | `double` | ✅ |
| `date` | `string` | ✅ |
| `cashTransactionId` | `integer` | ✅ |
| `hotelDayKey` | `string` | ✅ |
| `categoryUuid` | `string` | ✅ |
| `cashFlowUuid` | `string` | ✅ |
| `isAutoGenerated` | `boolean` | ✅ |
| `employeeUuid` | `string` | ✅ |

---

## 5. `debts` ⚠️ — حقل مكرر

| الحقل | النوع | في `_debtToMap` | ملاحظة |
|-------|-------|-----------------|---------|
| `localUuid` | `string` | ✅ | |
| `bookingLocalId` | `integer` | ✅ | |
| `guestName` | `string` | ✅ | |
| `checkinDate` | `string` | ✅ | |
| `checkoutDate` | `string` | ✅ | |
| `dateRecorded` | `string` | ✅ | |
| `debtReason` | `string` | ✅ | |
| `totalAmount` | `double` | ✅ `d.totalAmount` | |
| `paidAmount` | `double` | ✅ | |
| `remainingAmount` | `double` | ✅ | |
| `paymentDate` | `string` | ✅ | |
| `isSettled` | `boolean` | ✅ `d.isSettled` | ⚠️ Drift: IntColumn |
| `pledge` | `string` | ✅ | |
| `pledgeType` | `string` | ✅ | |
| `amount` | `double` | ✅ **`d.totalAmount`** | 🔴 **مكرر مع totalAmount** |
| `note` | `string` | ✅ | |
| `debtUuid` | `string` | ✅ | |
| `hotelDayOpened` | `string` | ✅ | |
| `hotelDayClosed` | `string` | ✅ | |
| `isFromAutoFix` | `boolean` | ✅ | |
| `settlementConfirmed` | `boolean` | ✅ | |
| `date` | `string` | ❌ | غير موجود محلياً |
| `debtorName` | `string` | ❌ | غير موجود محلياً |
| `description` | `string` | ❌ | غير موجود محلياً |
| `dueDate` | `string` | ❌ | غير موجود محلياً |
| `guestPhone` | `string` | ❌ | غير موجود محلياً |
| `status` | `string` | ❌ | غير موجود محلياً |
| `bookingUuidCache` | `string` | ❌ | غير موجود محلياً |

---

## 6. `employees` ⚠️ — EmployeeID

| الحقل | النوع | في `_employeeToMap` | ملاحظة |
|-------|-------|-------------------|---------|
| `name` | `string` | ✅ | |
| `basicSalary` | `double` | ✅ | |
| `position` | `string` | ✅ | |
| `phone` | `string` | ✅ | |
| `hireDate` | `string` | ✅ | |
| `status` | `string` | ✅ | |
| `terminationDate` | `string` | ✅ | |
| `terminationReason` | `string` | ✅ | |
| `EmployeeID` | `string` | ✅ `e.employeeID` | ✅ تم الإصلاح |
| حقول SyncFields | متنوعة | ✅ من الـ mixin | ✅ |

---

## 7. `booking_notes` ✅ — تطابق تام

| الحقل | النوع | في `_bookingNoteToMap` |
|-------|-------|----------------------|
| `bookingId` | `integer` | ✅ |
| `noteText` | `string` | ✅ |
| `alertType` | `string` | ✅ |
| `alertUntil` | `string` | ✅ |
| `isActive` | `boolean` | ✅ |
| `bookingUuidCache` | `string` | ❌ غير موجود محلياً |
| حقول SyncFields | متنوعة | ✅ |

---

## 8. `booking_nights` ✅ — كامل

| الحقل | النوع | في `_nightToMap` | ملاحظة |
|-------|-------|-----------------|---------|
| `bookingLocalId` | `integer` | ✅ | |
| `hotelDayKey` | `string` | ✅ | |
| `nightStart` | `string` | ✅ | |
| `nightEnd` | `string` | ✅ | |
| `nightlyRate` | `double` | ✅ | |
| `sequence` | `integer` | ✅ | |
| `isProcessedByAutoFix` | `boolean` | ✅ | |
| `baseRate` | `double` | ✅ | |
| `adjustment` | `double` | ✅ | |
| `finalRate` | `double` | ✅ | |
| `appliedAdjustmentUuid` | `string` | ✅ | ✅ تم الإصلاح |
| `appliedAdjustmentsJson` | `string` | ✅ | ✅ تم الإصلاح |
| `bookingUuidCache` | `string` | ❌ | غير موجود محلياً |
| `serverBookingId` | `integer` | ❌ | غير موجود محلياً |

---

## 9. `cash_transactions` ⚠️ — حقول مفقودة

| الحقل | النوع | في `_cashTransactionToMap` | ملاحظة |
|-------|-------|--------------------------|---------|
| `registerId` | `integer` | ❌ | موجود محلياً لكن ليس في ToMap |
| `referenceType` | `string` | ❌ | موجود محلياً لكن ليس في ToMap |
| `referenceId` | `integer` | ❌ | موجود محلياً لكن ليس في ToMap |

---

## 10. `booking_price_adjustments` ⚠️ — `appliedAt`

| الحقل | النوع | في `_bookingPriceAdjustmentToMap` | ملاحظة |
|-------|-------|----------------------------------|---------|
| `bookingLocalUuid` | `string` | ✅ | |
| `bookingUuid` | `string` | ✅ **= b.bookingLocalUuid** | 🔴 نفس القيمة |
| `bookingLocalId` | `integer` | ✅ | |
| `roomNumber` | `string` | ✅ | |
| `adjustmentType` | `integer` | ✅ | |
| `adjustmentMode` | `string` | ✅ | |
| `amount` | `double` | ✅ | |
| `effectiveHotelDay` | `string` | ✅ | |
| `endHotelDay` | `string` | ✅ | |
| `isActive` | `boolean` | ✅ | |
| `reason` | `string` | ✅ | |
| `appliedBy` | `string` | ✅ | |
| `appliedAt` | `integer` | ✅ **= b.createdAt** | 🟡 دلالياً غير دقيق |
| `cancelledAt` | `string` | ✅ | |
| `cancelledBy` | `string` | ✅ | |

---

## 11. `audit_logs` ⚠️ — `action` / `operationType`

| الحقل | النوع | في `_auditLogToMap` | ملاحظة |
|-------|-------|--------------------|---------|
| `operationType` | `string` | ✅ `a.operationType` | |
| `action` | `string` | ✅ **= a.operationType** | 🟡 بديل توافقي |
| باقي الحقول (27) | متنوعة | ✅ |  |

---

## 12-19. الجداول المتبقية ✅

جميعها متطابقة:
- `payment_voids` ✅ — مع `voidedAmount: integer` (يُحوّل تلقائياً)
- `guest_infos` ✅
- `price_adjustments` ✅
- `salary_cycles` ✅
- `salary_payments` ✅
- `salary_withdrawals` ✅
- `salary_carry_over_logs` ✅
- `shift_notes` ✅

---

## 20. `app_settings` 🔴 — **حرجة (تم الإصلاح)**

**لا يوجد `collectionSchema`** — فقط `validFieldsPerCollection` بـ snake_case.

### المشكلة الأصلية:
`sanitizePayload()` يحوّل `hotel_name` → `hotelName` (camelCase) لكن `validFieldsPerCollection` ينتظر `hotel_name` (snake_case) → الحقل يُحذف.

### الحقول المعرّضة (قبل الإصلاح):

| الحقل | النوع (مفترض) | الحالة بعد الإصلاح |
|-------|--------------|-------------------|
| `localUuid` | `string` | ✅ |
| `key` | `string` | ✅ |
| `value` | `string` | ✅ |
| `hotel_name` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `hotel_cutoff_hour` | `integer` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `dark_mode` | `boolean` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `wa_api_type` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `wa_api_base_url` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `wa_api_instance_id` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `wa_custom_url_template` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `wa_sendzen_api_key` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `wa_sendzen_from_number` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `telegram_enabled` | `boolean` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `telegram_chat_id` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `telegram_notifications_enabled` | `boolean` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `telegram_daily_report_enabled` | `boolean` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `telegram_daily_report_time` | `string` | ✅ أُضيف إلى `_preserveSnakeCase` |
| `appwrite_sync_interval` | `integer` | ✅ أُضيف إلى `_preserveSnakeCase` |

---

## 21. `blacklist` 🟡 — Wilma Workaround

لا يوجد `collectionSchema`. الحقول في `validFieldsPerCollection`:
`active`, `name`, `nationalId`, `nationality`, `notes`, `phone`, `reason`, `reportedBy`  
➕ حقول SyncFields.

**المشكلة:** `_backupFetchers` يستخدم `shiftNotes` بدلاً من جدول `blacklist` حقيقي.

---

## 📋 أنواع الحقول في Appwrite Cloud

| النوع | المعنى | الأمثلة |
|-------|--------|---------|
| `string` | نص | `guestName`, `hotelDayKey` |
| `integer` | عدد صحيح | `createdAt`, `version` |
| `double` | عدد عشري | `amount`, `price`, `basicSalary` |
| `boolean` | منطقي | `isActive`, `isVoided`, `requiresMaintenance` |

---

## ⚠️ تحذيرات تحويل الأنواع

```dart
// payment_voids.voidedAmount: integer (يُحوّل double → int)
static const Map<String, Set<String>> _intAmountFields = {
    'payment_voids': {'voidedAmount'},
};
```

- `isSettled` في `debts`: السحابة `boolean`، المحلي `IntColumn` (0/1) — يتم التحويل تلقائياً
- `isRead` في `shift_notes`: السحابة `boolean`، المحلي `IntColumn` (0/1) — يتم التحويل تلقائياً
- `isActive` في `booking_notes`: السحابة `boolean`، المحلي `IntColumn` (0/1) — يتم التحويل تلقائياً

---

*تم إعداد التقرير بواسطة Codex — 2026-07-05*
