# 📊 مقارنة شاملة: كل المجموعات مقابل مخطط Appwrite Cloud

**التاريخ:** 2026-07-05  
**الفرع:** `refactor/clean-v2`  
**الملفات المرجعية:**
- `appwrite_sync_utils.dart` — `validFieldsPerCollection` + `collectionSchema`
- `secondary_appwrite_service.dart` — `_backupFetchers` + `_*ToMap`
- `appwrite_config.dart` — `_entityToCollection`
- `local_db.dart` — جداول Drift

---

## 🗺️ نظرة عامة — كل المجموعات

| # | المجموعة | `validFieldsPerCollection` | `collectionSchema` | `_backupFetchers` | `_entityToCollection` | الحالة |
|---|----------|---------------------------|-------------------|-------------------|----------------------|--------|
| 1 | `rooms` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 2 | `bookings` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 3 | `payments` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 4 | `expenses` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 5 | `debts` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 6 | `employees` | ✅ | ✅ | ✅ | ✅ | ⚠️ حقل EmployeeID |
| 7 | `booking_notes` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 8 | `booking_nights` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 9 | `cash_transactions` | ✅ | ✅ | ✅ | ✅ | ⚠️ حقول مفقودة |
| 10 | `booking_price_adjustments` | ✅ | ✅ | ✅ | ✅ | ⚠️ appliedAt |
| 11 | `audit_logs` | ✅ | ✅ | ✅ | ✅ | ⚠️ action/operationType |
| 12 | `payment_voids` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 13 | `guest_infos` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 14 | `price_adjustments` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 15 | `salary_cycles` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 16 | `salary_payments` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 17 | `salary_withdrawals` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 18 | `salary_carry_over_logs` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 19 | `shift_notes` | ✅ | ✅ | ✅ | ✅ | ✅ كامل |
| 20 | `app_settings` | ✅ | ❌ | ✅ | ✅ | 🔴 CRITICAL |
| 21 | `blacklist` | ✅ | ❌ | ⚠️ workaround | ✅ | 🟡 متوسط |
| 22 | `sync_logs` | ✅ | ❌ | ❌ | ❌ | ℹ️ للقراءة فقط |
| 23 | `sync_state` | ✅ | ❌ | ❌ | ❌ | ℹ️ للقراءة فقط |
| 24 | `app_users` | ✅ | ❌ | ❌ | ❌ | ℹ️ غير مستخدم |
| 25 | `devices` | ✅ | ❌ | ❌ | ❌ | ℹ️ غير مستخدم |

---

## 🔍 تفصيل كل مجموعة

### 1. `rooms` ✅ — كامل
**الحقول في `_*ToMap` (22):** `localUuid`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch`, `version`, `origin`, `vectorClock`, `deviceId`, `roomNumber`, `type`, `price`, `status`, `imageUrl`, `cleaningStatus`, `lastCleanedHotelDay`, `lastOccupiedHotelDay`, `requiresMaintenance`

**الحقول في `collectionSchema` (27):** `localUuid`, `roomNumber`, `type`, `price`, `status`, `imageUrl`, `cleaningStatus`, `lastCleanedHotelDay`, `lastOccupiedHotelDay`, `requiresMaintenance`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch`, `syncTimestamp`, `deviceId`, `version`, `origin`, `vectorClock`, `sync_origin`, `idempotencyKey`

**الملاحظات:** ✅ `idempotencyKey`, `syncTimestamp`, `sync_origin` تُضاف تلقائياً في `uploadFullBackup` عبر `enhancedData`.

---

### 2. `bookings` ✅ — كامل
**الحقول في `_bookingToMap` (42):** `localUuid`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch`, `version`, `origin`, `vectorClock`, `deviceId`, `serverBookingId`, `roomNumber`, `guestName`, `guestPhone`, `guestIdType`, `guestIdNumber`, `guestIdIssueDate`, `guestIdIssuePlace`, `guestNationality`, `guestEmail`, `guestAddress`, `checkinDate`, `checkoutDate`, `actualCheckout`, `status`, `notes`, `discount`, `discountType`, `discountStartDate`, `expectedNights`, `calculatedNights`, `totalNightsCached`, `stayDurationIso`, `lastNightEpoch`, `isOverdue`, `needsCheckoutReview`, `totalDueCached`, `totalPaidCached`, `remainingBalanceCached`, `isFullyPaid`, `hotelDayCheckin`, `hotelDayCheckout`

**الحقول الإضافية في `collectionSchema` (45):** `financialFrozenAt`, `financialHash` — غير موجودة في النموذج المحلي (Drift).

**الملاحظات:** ✅ حقول `financialFrozenAt` و `financialHash` موجودة في السحابة فقط (تستخدم لأغراض التدقيق المالي). لا حاجة لإضافتها محلياً.

---

### 3. `payments` ✅ — كامل
**الحقول في `_paymentToMap` (34):** `localUuid`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch`, `version`, `origin`, `vectorClock`, `deviceId`, `serverPaymentId`, `bookingLocalId`, `serverBookingId`, `roomNumber`, `amount`, `paymentDate`, `notes`, `paymentMethod`, `revenueType`, `cashTransactionLocalId`, `cashTransactionServerId`, `referenceNumber`, `hotelDayKey`, `isPendingBalance`, `linkedDebtUuid`, `bookingUuidCache`, `discountAmount`, `discountStartDate`, `isVoided`, `voidedAt`, `voidedBy`

**الحقول الإضافية في `collectionSchema` (38):** `isImmutable`, `voidReason` — موجودة في السحابة ولكن ليست في النموذج المحلي.

**الملاحظات:** ✅ كامل للتطبيق العملي. حقل `discountAmount` متوفر.

---

### 4. `expenses` ✅ — كامل
**الحقول في `_expenseToMap` (27):** `localUuid`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch`, `version`, `origin`, `vectorClock`, `deviceId`, `expenseType`, `relatedId`, `description`, `amount`, `date`, `cashTransactionId`, `hotelDayKey`, `categoryUuid`, `cashFlowUuid`, `isAutoGenerated`, `employeeUuid`

**الحقول في `collectionSchema` (27):** 🔄 نفس الحقول — ✅ **تطابق تام**

---

### 5. `debts` ⚠️ — حقل مكرر
**الحقول في `_debtToMap` (29):** `localUuid`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch`, `version`, `origin`, `vectorClock`, `deviceId`, `bookingLocalId`, `guestName`, `checkinDate`, `checkoutDate`, `dateRecorded`, `debtReason`, `totalAmount`, `paidAmount`, `remainingAmount`, `paymentDate`, `isSettled`, `pledge`, `pledgeType`, `amount` ← مكرر `totalAmount`, `note`, `debtUuid`, `hotelDayOpened`, `hotelDayClosed`, `isFromAutoFix`, `settlementConfirmed`

**الملاحظات:** ⚠️ `amount` و `totalAmount` يحملان نفس القيمة (`d.totalAmount`). كلاهما موجود في `collectionSchema` لكنهما مكرران. يُفضل إزالة `amount` أو جعله حقيقياً.

---

### 6. `employees` ⚠️ — EmployeeID
**الحقول في `_employeeToMap` (22):** `localUuid`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `createdAtIso`, `updatedAtIso`, `deletedAtIso`, `createdAtEpoch`, `lastModifiedEpoch`, `version`, `origin`, `vectorClock`, `deviceId`, `name`, `basicSalary`, `position`, `phone`, `hireDate`, `status`, `terminationDate`, `terminationReason`, `EmployeeID`

**الملاحظات:** ✅ `EmployeeID` موجود الآن (تمت إضافته في الإصلاح السابق).

---

### 7. `booking_notes` ✅ — كامل
تطابق تام بين `_bookingNoteToMap` و `collectionSchema`.

---

### 8. `booking_nights` ✅ — كامل
**الملاحظات:** `appliedAdjustmentUuid` و `appliedAdjustmentsJson` موجودان الآن. `bookingUuidCache` و `serverBookingId` غير موجودين في النموذج المحلي لكنهما موجودان في السحابة.

---

### 9. `cash_transactions` ⚠️ — حقول مفقودة
**الحقول في `_cashTransactionToMap` (19):** الحقول الأساسية فقط.
**الحقول المفقودة من `collectionSchema` (22):** `registerId`, `referenceType`, `referenceId`

**الملاحظات:** ℹ️ هذه الحقول غير موجودة في نموذج Drift المحلي. قد تكون قد أُضيفت إلى السحابة لاستخدامات مستقبلية.

---

### 10. `booking_price_adjustments` ⚠️ — `appliedAt`
**الملاحظات:** `appliedAt: b.createdAt` — هذا تجميع دلالي غير دقيق. `appliedAt` يجب أن يكون وقت تطبيق التعديل الفعلي وليس وقت إنشاء السجل.

---

### 11. `audit_logs` ⚠️ — `action` / `operationType`
**الملاحظات:** `action` و `operationType` يحملان نفس القيمة. `action` هو حقل توافقي (backward compatibility) مع إصدارات سابقة من المخطط.

---

### 12. `payment_voids` ✅ — كامل
تطابق تام بين `_paymentVoidToMap` و `collectionSchema`.

---

### 13. `guest_infos` ✅ — كامل
تطابق تام بين `_guestInfoToMap` و `collectionSchema`.

---

### 14. `price_adjustments` ✅ — كامل
تطابق تام بين `_priceAdjustmentToMap` و `collectionSchema`.

---

### 15-18. جداول الرواتب ✅ — كاملة
`salary_cycles`, `salary_payments`, `salary_withdrawals`, `salary_carry_over_logs` كلها متطابقة.

---

### 19. `shift_notes` ✅ — كامل
تطابق تام بين `_shiftNoteToMap` و `collectionSchema`.

---

### 20. `app_settings` 🔴 — حرجة
**المشكلة:** لا يحتوي على `collectionSchema`، فقط `validFieldsPerCollection` الذي يستخدم snake_case.  
**الإصلاح:** أُضيفت جميع الحقول snake_case إلى `_preserveSnakeCase` لمنع تحويلها إلى camelCase.

**الحقول المتوقعة من `_appSettingsToMap`:** `localUuid`, `key`, `value`, `hotel_name`, `hotel_cutoff_hour`, `dark_mode`, `wa_api_type`, `wa_api_base_url`, `wa_api_instance_id`, `wa_custom_url_template`, `wa_sendzen_api_key`, `wa_sendzen_from_number`, `telegram_enabled`, `telegram_chat_id`, `telegram_notifications_enabled`, `telegram_daily_report_enabled`, `telegram_daily_report_time`, `appwrite_sync_interval`, `deviceId`, `serverId`, `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `syncTimestamp`, `idempotencyKey`, `sync_origin`

**الحقول الإضافية في `validFieldsPerCollection` (غير مرسلة):** `api_key`, `database_id`, `endpoint`, `enabled`, `project_id`, `pull_enabled`, `push_enabled`, `secondary_appwrite_config`, `sync_performance_profile`, `telegram_bot_token`, `wa_api_token`, `wifi_only_sync`

---

### 21. `blacklist` 🟡 — Workaround
**لا يحتوي على `collectionSchema`.**  
**المشكلة:** `_backupFetchers` يستخدم `shiftNotes` كـ workaround لأن جدول `blacklist` غير موجود في Drift.

---

### 22-25. جداول غير مستخدمة
- `sync_logs` — للقراءة فقط، لا يتم رفعها
- `sync_state` — للقراءة فقط، لا يتم رفعها
- `app_users` — غير مستخدم في هذا التطبيق
- `devices` — غير مستخدم في هذا التطبيق

---

## 📋 ملخص الفجوات

| المستوى | العدد | التفاصيل |
|---------|-------|---------|
| 🔴 حرج | 1 | `app_settings` — تم الإصلاح ✅ |
| 🟡 متوسط | 3 | `employees` (EmployeeID)، `booking_price_adjustments` (appliedAt)، `blacklist` (workaround) |
| 🟢 خفيف | 2 | `debts` (amount مكرر)، `audit_logs` (action/operationType) |
| ℹ️ معلوماتي | 3 | `cash_transactions` (3 حقول مفقودة)، `booking_nights` (2 حقول مفقودة) |

---

*تم إعداد التقرير بواسطة Codex — 2026-07-05*
