# 📊 جداول وحقول المزامنة مع Appwrite Cloud

> **آخر تحديث:** 2026-06-14  
> **المصدر:** الكود الفعلي (local_db.dart + adapters + appwrite_sync_manager)  
> **عدد الجداول:** 21 جدولاً (19 SQLite + devices + app_settings)  
> **آلية المزامنة:** ثنائية الاتجاه (Push → Cloud / Pull ← Cloud)

---

## 🔷 1. rooms

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `roomNumber` | `roomNumber` | string | UNIQUE |
| `type` | `type` | string | |
| `price` | `price` | double | |
| `status` | `status` | string | |
| `imageUrl` | `imageUrl` | string | nullable |
| `cleaningStatus` | `cleaningStatus` | string | default: `'clean'` |
| `lastCleanedHotelDay` | `lastCleanedHotelDay` | string | nullable |
| `lastOccupiedHotelDay` | `lastOccupiedHotelDay` | string | nullable |
| `requiresMaintenance` | `requiresMaintenance` | boolean | default: `false` |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

**ملاحظة:** `_roomToRemote` في sync manager يضيف `roomType`, `basePrice`, `floor`, `bedsCount` لتوافق schema Appwrite.

---

## 🔷 2. bookings

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `serverBookingId` | `serverBookingId` | integer | nullable |
| `roomNumber` | `roomNumber` | string | FK → rooms.roomNumber |
| `guestName` | `guestName` | string | |
| `guestPhone` | `guestPhone` | string | |
| `guestIdType` | `guestIdType` | string | default: `'بطاقة شخصية'` |
| `guestIdNumber` | `guestIdNumber` | string | default: `''` |
| `guestIdIssueDate` | `guestIdIssueDate` | string | nullable |
| `guestIdIssuePlace` | `guestIdIssuePlace` | string | nullable |
| `guestNationality` | `guestNationality` | string | |
| `guestEmail` | `guestEmail` | string | nullable |
| `guestAddress` | `guestAddress` | string | nullable |
| `checkinDate` | `checkinDate` | string | |
| `checkoutDate` | `checkoutDate` | string | nullable |
| `actualCheckout` | `actualCheckout` | string | nullable |
| `status` | `status` | string | |
| `notes` | `notes` | string | nullable |
| `discount` | `discount` | double | default: `0` |
| `discountType` | `discountType` | string | default: `'per_night'` |
| `discountStartDate` | `discountStartDate` | string | nullable |
| `expectedNights` | `expectedNights` | integer | default: `1` |
| `calculatedNights` | `calculatedNights` | integer | default: `1` |
| `totalNightsCached` | `totalNightsCached` | integer | default: `0` |
| `stayDurationIso` | `stayDurationIso` | string | nullable |
| `lastNightEpoch` | `lastNightEpoch` | integer | nullable |
| `isOverdue` | `isOverdue` | boolean | default: `false` |
| `needsCheckoutReview` | `needsCheckoutReview` | boolean | default: `false` |
| `totalDueCached` | `totalDueCached` | double | default: `0.0` |
| `totalPaidCached` | `totalPaidCached` | double | default: `0.0` |
| `remainingBalanceCached` | `remainingBalanceCached` | double | default: `0.0` |
| `isFullyPaid` | `isFullyPaid` | boolean | default: `false` |
| `hotelDayCheckin` | `hotelDayCheckin` | string | nullable |
| `hotelDayCheckout` | `hotelDayCheckout` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 3. payments

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `serverPaymentId` | `serverPaymentId` | integer | nullable |
| `bookingLocalId` | `bookingLocalId` | integer | nullable — يُحل عبر bookingUuidCache |
| `serverBookingId` | `serverBookingId` | integer | nullable |
| `roomNumber` | `roomNumber` | string | nullable |
| `amount` | `amount` | double | |
| `paymentDate` | `paymentDate` | string | |
| `notes` | `notes` | string | nullable |
| `paymentMethod` | `paymentMethod` | string | |
| `revenueType` | `revenueType` | string | |
| `cashTransactionLocalId` | `cashTransactionLocalId` | integer | nullable |
| `cashTransactionServerId` | `cashTransactionServerId` | integer | nullable |
| `referenceNumber` | `referenceNumber` | string | nullable |
| `hotelDayKey` | `hotelDayKey` | string | nullable |
| `isPendingBalance` | `isPendingBalance` | boolean | default: `false` |
| `linkedDebtUuid` | `linkedDebtUuid` | string | nullable |
| `bookingUuidCache` | `bookingUuidCache` | string | nullable |
| `discountAmount` | `discountAmount` | double | nullable |
| `discountStartDate` | `discountStartDate` | string | nullable |
| `isVoided` | `isVoided` | boolean | default: `false` |
| `voidedAt` | `voidedAt` | integer | nullable |
| `voidedBy` | `voidedBy` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 4. expenses

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `expenseType` | `expenseType` | string | |
| `relatedId` | `relatedId` | integer | nullable |
| `description` | `description` | string | |
| `amount` | `amount` | double | |
| `date` | `date` | string | |
| `cashTransactionId` | `cashTransactionId` | integer | nullable |
| `hotelDayKey` | `hotelDayKey` | string | nullable |
| `categoryUuid` | `categoryUuid` | string | nullable |
| `cashFlowUuid` | `cashFlowUuid` | string | nullable |
| `isAutoGenerated` | `isAutoGenerated` | boolean | default: `false` |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 5. employees

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `name` | `name` | string | |
| `basicSalary` | `basicSalary` | double | |
| `position` | `position` | string | default: `'موظف'` |
| `phone` | `phone` | string | default: `''` |
| `hireDate` | `hireDate` | string | default: `''` |
| `status` | `status` | string | |
| `terminationDate` | `terminationDate` | string | nullable |
| `terminationReason` | `terminationReason` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 6. debts

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `bookingLocalId` | `bookingLocalId` | integer | nullable — يُحل عبر bookingUuidCache |
| `guestName` | `guestName` | string | |
| `checkinDate` | `checkinDate` | string | |
| `checkoutDate` | `checkoutDate` | string | |
| `dateRecorded` | `dateRecorded` | string | default: `''` |
| `debtReason` | `debtReason` | string | default: `''` |
| `totalAmount` | `totalAmount` | double | + يُرسل كـ `amount` أيضاً لـ Appwrite |
| `paidAmount` | `paidAmount` | double | |
| `remainingAmount` | `remainingAmount` | **integer** ⚠️ | `model.remainingAmount.round()` |
| `paymentDate` | `paymentDate` | string | |
| `isSettled` | `isSettled` | integer | 0/1 |
| `pledge` | `pledge` | string | nullable |
| `pledgeType` | `pledgeType` | string | nullable |
| `note` | `note` | string | nullable |
| `debtUuid` | `debtUuid` | string | nullable |
| `hotelDayOpened` | `hotelDayOpened` | string | nullable |
| `hotelDayClosed` | `hotelDayClosed` | string | nullable |
| `isFromAutoFix` | `isFromAutoFix` | boolean | default: `false` |
| `settlementConfirmed` | `settlementConfirmed` | boolean | default: `false` |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

**ملاحظة:** يرسل `_debtToRemote` كلاً من `totalAmount` و `amount` للتوافق مع Appwrite Cloud.

---

## 🔷 7. booking_notes

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `bookingId` | `bookingId` | integer | FK → bookings.id |
| `noteText` | `noteText` | string | |
| `alertType` | `alertType` | string | |
| `alertUntil` | `alertUntil` | string | nullable |
| `isActive` | `isActive` | integer | default: `1` |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 8. booking_nights

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `bookingLocalId` | `bookingLocalId` | integer | nullable — يُحل عبر bookingUuidCache |
| `hotelDayKey` | `hotelDayKey` | string | |
| `nightStart` | `nightStart` | string | |
| `nightEnd` | `nightEnd` | string | |
| `nightlyRate` | `nightlyRate` | double | default: `0` |
| `sequence` | `sequence` | integer | default: `0` |
| `isProcessedByAutoFix` | `isProcessedByAutoFix` | boolean | default: `false` |
| `baseRate` | `baseRate` | double | default: `0` |
| `adjustment` | `adjustment` | double | default: `0` |
| `finalRate` | `finalRate` | double | default: `0` |
| `appliedAdjustmentUuid` | `appliedAdjustmentUuid` | string | nullable |
| `appliedAdjustmentsJson` | `appliedAdjustmentsJson` | string | nullable (⚠️ ليس في SQLite — يُرسل فقط) |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

**ملاحظة:** `bookingUuidCache` و `serverBookingId` ليسا أعمدة في SQLite لكن يتم إرسالهما عبر ربط `id_resolver` عند الرفع — يُحلّان في `resolveRefs` عند السحب.

---

## 🔷 9. cash_transactions

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `registerId` | `registerId` | integer | nullable |
| `transactionType` | `transactionType` | string | default: `'expense'` |
| `amount` | `amount` | **integer** ⚠️ | `model.amount.round()` |
| `referenceType` | `referenceType` | string | nullable |
| `referenceId` | `referenceId` | integer | nullable |
| `description` | `description` | string | nullable |
| `transactionTime` | `transactionTime` | string | ISO datetime |
| `createdBy` | `createdBy` | integer | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 10. shift_notes

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `title` | `title` | string | |
| `content` | `content` | string | + يُنسخ إلى `note` |
| `priority` | `priority` | string | default: `'medium'` |
| `shiftType` | `shiftType` | string | default: `'all'` |
| `isRead` | `isRead` | **boolean** ⚠️ | `model.isRead == 1` |
| `createdBy` | `createdBy` | string | default: `'user'` |
| `expiresAt` | `expiresAt` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |
| — | `shiftDate` | string | ✅ مشتق من `createdAt` — يُضاف في adapter |
| — | `note` | string | ✅ يوازي `content` — يُضاف في adapter |

---

## 🔷 11. salary_cycles

> **⚠️ تصحيح:** الحقول الفعلية تختلف عن النسخة السابقة من هذا المستند.

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `employeeId` | `employeeId` | integer | FK → employees.id |
| `cycleKey` | `cycleKey` | string | معرف الدورة (مثال: `'2026-05'`) |
| `hotelDayStart` | `hotelDayStart` | string | nullable |
| `hotelDayEnd` | `hotelDayEnd` | string | nullable |
| `expectedAmount` | `expectedAmount` | integer | default: `0` |
| `actualPaid` | `actualPaid` | integer | default: `0` |
| `remainingAmount` | `remainingAmount` | integer | default: `0` |
| `status` | `status` | string | default: `'draft'` |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 12. salary_payments

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `cycleId` | `cycleId` | integer | FK → salary_cycles.id |
| `amount` | `amount` | integer | default: `0` |
| `hotelDayKey` | `hotelDayKey` | string | nullable |
| `paymentDateIso` | `paymentDateIso` | string | |
| `method` | `method` | string | nullable |
| `isAutoGenerated` | `isAutoGenerated` | boolean | default: `false` |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

**ملاحظة:** `employeeId`, `paymentDate`, `notes` — غير موجودة في SQLite! السحب من Appwrite يحل `employeeId` عبر `id_resolver`.

---

## 🔷 13. price_adjustments

> **⚠️ تصحيح جذري:** هذا الجدول مختلف تماماً عن `booking_price_adjustments`.  
> يستخدم نظام تعديل أسعار عام (targetType/targetUuid) بدلاً من room-specific.

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `targetType` | `targetType` | string | نوع الهدف (room, booking, ...) |
| `targetUuid` | `targetUuid` | string | UUID الهدف |
| `adjustmentType` | `adjustmentType` | **string** | نوع التعديل (نص، ليس integer!) |
| `previousValue` | `previousValue` | integer | القيمة القديمة |
| `newValue` | `newValue` | integer | القيمة الجديدة |
| `reason` | `reason` | string | nullable |
| `effectiveDate` | `effectiveDate` | string | |
| `appliedBy` | `appliedBy` | string | |
| `hotelDayKey` | `hotelDayKey` | string | |
| `isReversed` | `isReversed` | boolean | default: `false` |
| `reversedAt` | `reversedAt` | string | nullable |
| `reversedBy` | `reversedBy` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

**ملاحظة:** الـ adapter لا يرسل `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch` رغم وجودها في SQLite (SyncFields).

---

## 🔷 14. booking_price_adjustments

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `bookingLocalUuid` | `bookingLocalUuid` | string | FK → bookings.localUuid |
| `bookingLocalId` | `bookingLocalId` | integer | nullable — يُحل عبر bookingLocalUuid |
| `roomNumber` | `roomNumber` | string | nullable |
| `adjustmentType` | `adjustmentType` | integer | default: `0` |
| `adjustmentMode` | `adjustmentMode` | string | default: `'per_night'` |
| `amount` | `amount` | **integer** ⚠️ | `model.amount.round()` ✅ في adapter |
| `effectiveHotelDay` | `effectiveHotelDay` | string | |
| `endHotelDay` | `endHotelDay` | string | nullable |
| `isActive` | `isActive` | boolean | default: `true` |
| `reason` | `reason` | string | nullable |
| `appliedBy` | `appliedBy` | string | nullable |
| `cancelledAt` | `cancelledAt` | string | nullable |
| `cancelledBy` | `cancelledBy` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 15. audit_logs

> لا يستخدم `SyncFields` mixin — حقول المزامنة محدودة.

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `operationType` | `operationType` | string | |
| `entityType` | `entityType` | string | |
| `entityUuid` | `entityUuid` | string | |
| `entityId` | `entityId` | integer | nullable |
| `previousState` | `previousState` | string | nullable (JSON) |
| `newState` | `newState` | string | nullable (JSON) |
| `changedFields` | `changedFields` | string | nullable (JSON) |
| `performedBy` | `performedBy` | string | |
| `deviceId` | `deviceId` | string | |
| `ipAddress` | `ipAddress` | string | nullable |
| `hotelDayKey` | `hotelDayKey` | string | |
| `timestamp` | `timestamp` | integer | |
| `timestampIso` | `timestampIso` | string | |
| `isFinancial` | `isFinancial` | boolean | default: `false` |
| `amountImpact` | `amountImpact` | integer | nullable |
| `createdAt` | `createdAt` | integer | |

---

## 🔷 16. payment_voids

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `originalPaymentUuid` | `originalPaymentUuid` | string | |
| `originalPaymentId` | `originalPaymentId` | integer | default: `0` |
| `bookingUuid` | `bookingUuid` | string | |
| `voidedAmount` | `voidedAmount` | integer | default: `0` |
| `voidReason` | `voidReason` | string | |
| `voidedBy` | `voidedBy` | string | |
| `voidedAt` | `voidedAt` | integer | |
| `voidedAtIso` | `voidedAtIso` | string | |
| `hotelDayKey` | `hotelDayKey` | string | |
| `reversalPaymentUuid` | `reversalPaymentUuid` | string | nullable |
| `approvedBy` | `approvedBy` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

**ملاحظة:** الـ adapter لا يرسل `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch` رغم وجودها في SQLite (SyncFields).

---

## 🔷 17. guest_infos

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `roomNumber` | `roomNumber` | string | |
| `guestName` | `guestName` | string | |
| `nationality` | `nationality` | string | |
| `idNumber` | `idNumber` | string | |
| `idType` | `idType` | string | default: `'بطاقة شخصية'` |
| `issueDate` | `issueDate` | string | nullable |
| `issuePlace` | `issuePlace` | string | nullable |
| `governorate` | `governorate` | string | nullable |
| `notes` | `notes` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

---

## 🔷 18. salary_withdrawals

> **⚠️ تصحيح:** الحقول الفعلية مختلفة عن النسخة السابقة.

| الحقل في SQLite | الحقل في Appwrite | النوع | ملاحظات |
|----------------|-------------------|-------|---------|
| `id` | `id` | integer | PK autoIncrement |
| `localUuid` | `localUuid` | string | ⭐ معرّف موحد |
| `serverId` | `serverId` | integer | nullable |
| `employeeId` | `employeeId` | integer | FK → employees.id |
| `amount` | `amount` | double | ✅ `round()` في adapter |
| `withdrawDate` | `withdrawDate` | string | تاريخ السحب |
| `reason` | `reason` | string | nullable |
| `hotelDayKey` | `hotelDayKey` | string | nullable |
| `withdrawalType` | `withdrawalType` | string | nullable |
| `description` | `description` | string | nullable |
| `createdAt` | `createdAt` | integer | |
| `updatedAt` | `updatedAt` | integer | |
| `deletedAt` | `deletedAt` | integer | nullable |
| `lastModified` | `lastModified` | integer | ⭐ حقل المزامنة |
| `createdAtIso` | `createdAtIso` | string | nullable |
| `updatedAtIso` | `updatedAtIso` | string | nullable |
| `deletedAtIso` | `deletedAtIso` | string | nullable |
| `createdAtEpoch` | `createdAtEpoch` | integer | default: `0` |
| `lastModifiedEpoch` | `lastModifiedEpoch` | integer | default: `0` |
| `version` | `version` | integer | default: `1` |
| `origin` | `origin` | string | |
| `vectorClock` | `vectorClock` | string | default: `'{}'` |
| `deviceId` | `deviceId` | string | nullable |

**ملاحظة:** عند الإرسال لـ Appwrite، يضيف الـ adapter حقولاً إضافية (`date`, `action`, `note`, `expenseId`) للتوافق مع schema Appwrite القديم.

---

## 🔷 19. devices

> جدول Appwrite فقط — لا يوجد له مقابل في SQLite المحلي.

| الحقل | النوع | ملاحظات |
|-------|-------|---------|
| `\$id` | string | PK تلقائي من Appwrite |
| `deviceName` | string | |
| `deviceModel` | string | |
| `osVersion` | string | |
| `deviceType` | string | |
| `status` | string | `'active'`, `'inactive'`, `'suspended'` |
| `localUuid` | string | |
| `deviceId` | string | |
| `isActive` | boolean | |
| `fcmToken` | string | nullable |
| `fcmTokenUpdatedAt` | integer | nullable |
| `lastSeen` | string | ISO datetime |
| `lastActive` | integer | |
| `createdAt` | integer | |
| `updatedAt` | integer | |
| `lastModified` | integer | |
| `version` | integer | default: `1` |
| `origin` | string | nullable |

---

## 📂 الملفات المسؤولة

| الملف | الوظيفة |
|-------|---------|
| `lib/services/adapters/*.dart` | تحويل البيانات بين SQLite و Appwrite (المصدر الرسمي للحقول) |
| `lib/services/appwrite_sync_manager.dart` | مدير المزامنة — push (`_*ToRemote`) + pull + outbox |
| `lib/services/appwrite_service.dart` | عمليات CRUD الأساسية مع Appwrite |
| `lib/services/appwrite_config.dart` | إعدادات الـ collections + database |
| `lib/services/appwrite_full_pull.dart` | السحب الكامل لكل جدول |
| `lib/services/appwrite_delta_sync.dart` | السحب المتزايد (delta sync) |
| `lib/services/local_db.dart` | تعريف جداول SQLite (Drift ORM) |

---

## ⚠️ تحويلات الأنواع (Type Mismatches) — مؤكدة

| الجدول | الحقل | في SQLite | في Appwrite | مكان التحويل | الحالة |
|--------|-------|-----------|-------------|-------------|--------|
| `cash_transactions` | `amount` | `double` | **integer** | `model.amount.round()` في adapter | ✅ |
| `debts` | `remainingAmount` | `double` | **integer** | `model.remainingAmount.round()` في adapter | ✅ |
| `booking_price_adjustments` | `amount` | `double` | **integer** | `model.amount.round()` في adapter | ✅ |
| `shift_notes` | `isRead` | `integer` (0/1) | **boolean** | `model.isRead == 1` في adapter | ✅ |
| `salary_withdrawals` | `amount` | `double` | **integer** | `model.amount.round()` في adapter | ✅ |

---

## 🔴 حقول SyncFields مفقودة من بعض الـ adapters (toJson)

| الـ adapter | الحقول المفقودة |
|-------------|-----------------|
| `price_adjustments_adapter` | `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch` |
| `payment_voids_adapter` | `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch` |
| `booking_nights_adapter` (NightsAdapter) | `bookingUuidCache`, `serverBookingId` (تُحل عبر id_resolver) |
