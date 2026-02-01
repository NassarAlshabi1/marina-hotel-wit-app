# تقرير مطابقة قاعدة البيانات
# Database Schema Verification Report

## نظرة عامة | Overview

تم فحص ومقارنة الجداول والحقول بين:
- قاعدة البيانات المحلية (SQLite/Drift)
- Appwrite Collections
- Google Drive Backup Format

---

## الجداول القابلة للمزامنة | Synchronizable Tables

| # | الجدول | Local DB | Appwrite | Google Drive | Adapter |
|---|--------|----------|----------|--------------|---------|
| 1 | rooms | ✅ | ✅ | ✅ | ✅ |
| 2 | bookings | ✅ | ✅ | ✅ | ✅ |
| 3 | booking_notes | ✅ | ✅ | ✅ | ✅ |
| 4 | booking_nights | ✅ | ✅ | ✅ | ✅ |
| 5 | employees | ✅ | ✅ | ✅ | ✅ |
| 6 | expenses | ✅ | ✅ | ✅ | ✅ |
| 7 | cash_transactions | ✅ | ✅ | ✅ | ✅ |
| 8 | payments | ✅ | ✅ | ✅ | ✅ |
| 9 | debts | ✅ | ✅ | ✅ | ✅ |
| 10 | shift_notes | ✅ | ✅ | ✅ | ✅ |
| 11 | hotel_day_ledger | ✅ | ✅ | ✅ | ⚠️ |
| 12 | salary_cycles | ✅ | ✅ | ✅ | ✅ |
| 13 | salary_payments | ✅ | ✅ | ✅ | ✅ |

---

## حقول المزامنة المشتركة | Common Sync Fields (SyncFields Mixin)

| الحقل | النوع | Local DB | Appwrite | Google Drive |
|-------|------|----------|----------|--------------|
| localUuid | TEXT | ✅ | ✅ | ✅ |
| serverId | INT? | ✅ | ✅ | ✅ |
| createdAt | INT | ✅ | ✅ | ✅ |
| updatedAt | INT | ✅ | ✅ | ✅ |
| deletedAt | INT? | ✅ | ✅ | ✅ |
| lastModified | INT | ✅ | ✅ | ✅ |
| createdAtIso | TEXT? | ✅ | ✅ | ✅ |
| updatedAtIso | TEXT? | ✅ | ✅ | ✅ |
| deletedAtIso | TEXT? | ✅ | ✅ | ✅ |
| createdAtEpoch | INT | ✅ | ✅ | ✅ |
| lastModifiedEpoch | INT | ✅ | ✅ | ✅ |
| version | INT | ✅ | ✅ | ✅ |
| origin | TEXT | ✅ | ✅ | ✅ |
| vectorClock | TEXT | ✅ | ✅ | ✅ |

---

## تفاصيل كل جدول | Table Field Details

### 1. ROOMS (الغرف)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | Auto-increment locally |
| roomNumber | TEXT | ✅ | ✅ | ✅ | Unique |
| type | TEXT | ✅ | ✅ | ✅ | |
| price | REAL | ✅ | ✅ | ✅ | |
| status | TEXT | ✅ | ✅ | ✅ | |
| imageUrl | TEXT? | ✅ | ✅ | ✅ | |
| cleaningStatus | TEXT | ✅ | ✅ | ✅ | default: 'clean' |
| lastCleanedHotelDay | TEXT? | ✅ | ✅ | ✅ | |
| lastOccupiedHotelDay | TEXT? | ✅ | ✅ | ✅ | |
| requiresMaintenance | BOOL | ✅ | ✅ | ✅ | default: false |

### 2. BOOKINGS (الحجوزات)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | Auto-increment |
| serverBookingId | INT? | ✅ | ✅ | ✅ | |
| roomNumber | TEXT | ✅ | ✅ | ✅ | FK→rooms |
| guestName | TEXT | ✅ | ✅ | ✅ | |
| guestPhone | TEXT | ✅ | ✅ | ✅ | |
| guestIdType | TEXT | ✅ | ✅ | ✅ | |
| guestIdNumber | TEXT | ✅ | ✅ | ✅ | |
| guestIdIssueDate | TEXT? | ✅ | ✅ | ✅ | |
| guestIdIssuePlace | TEXT? | ✅ | ✅ | ✅ | |
| guestNationality | TEXT | ✅ | ✅ | ✅ | |
| guestEmail | TEXT? | ✅ | ✅ | ✅ | |
| guestAddress | TEXT? | ✅ | ✅ | ✅ | |
| checkinDate | TEXT | ✅ | ✅ | ✅ | |
| checkoutDate | TEXT? | ✅ | ✅ | ✅ | |
| actualCheckout | TEXT? | ✅ | ✅ | ✅ | |
| status | TEXT | ✅ | ✅ | ✅ | |
| notes | TEXT? | ✅ | ✅ | ✅ | |
| expectedNights | INT | ✅ | ✅ | ✅ | |
| calculatedNights | INT | ✅ | ✅ | ✅ | |
| totalNightsCached | INT | ✅ | ✅ | ✅ | |
| stayDurationIso | TEXT? | ✅ | ✅ | ✅ | |
| lastNightEpoch | INT? | ✅ | ✅ | ✅ | |
| isOverdue | BOOL | ✅ | ✅ | ✅ | |
| needsCheckoutReview | BOOL | ✅ | ✅ | ✅ | |
| totalDueCached | REAL | ✅ | ✅ | ✅ | |
| totalPaidCached | REAL | ✅ | ✅ | ✅ | |
| remainingBalanceCached | REAL | ✅ | ✅ | ✅ | |
| isFullyPaid | BOOL | ✅ | ✅ | ✅ | |
| hotelDayCheckin | TEXT? | ✅ | ✅ | ✅ | |
| hotelDayCheckout | TEXT? | ✅ | ✅ | ✅ | |

### 3. EMPLOYEES (الموظفين)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| name | TEXT | ✅ | ✅ | ✅ | |
| basicSalary | REAL | ✅ | ✅ | ✅ | |
| position | TEXT | ✅ | ✅ | ✅ | |
| phone | TEXT | ✅ | ✅ | ✅ | |
| hireDate | TEXT | ✅ | ✅ | ✅ | |
| status | TEXT | ✅ | ✅ | ✅ | |

### 4. PAYMENTS (المدفوعات)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| serverPaymentId | INT? | ✅ | ✅ | ✅ | |
| bookingLocalId | INT? | ✅ | ✅ | ✅ | FK→bookings |
| serverBookingId | INT? | ✅ | ✅ | ✅ | |
| roomNumber | TEXT? | ✅ | ✅ | ✅ | |
| amount | REAL | ✅ | ✅ | ✅ | |
| paymentDate | TEXT | ✅ | ✅ | ✅ | |
| notes | TEXT? | ✅ | ✅ | ✅ | |
| paymentMethod | TEXT | ✅ | ✅ | ✅ | |
| revenueType | TEXT | ✅ | ✅ | ✅ | |
| cashTransactionLocalId | INT? | ✅ | ✅ | ✅ | FK→cash_transactions |
| cashTransactionServerId | INT? | ✅ | ✅ | ✅ | |
| referenceNumber | TEXT? | ✅ | ✅ | ✅ | |
| hotelDayKey | TEXT? | ✅ | ✅ | ✅ | |
| isPendingBalance | BOOL | ✅ | ✅ | ✅ | |
| linkedDebtUuid | TEXT? | ✅ | ✅ | ✅ | |
| bookingUuidCache | TEXT? | ✅ | ✅ | ✅ | |

### 5. EXPENSES (المصروفات)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| expenseType | TEXT | ✅ | ✅ | ✅ | |
| relatedId | INT? | ✅ | ✅ | ✅ | |
| description | TEXT | ✅ | ✅ | ✅ | |
| amount | REAL | ✅ | ✅ | ✅ | |
| date | TEXT | ✅ | ✅ | ✅ | |
| cashTransactionId | INT? | ✅ | ✅ | ✅ | |
| hotelDayKey | TEXT? | ✅ | ✅ | ✅ | |
| categoryUuid | TEXT? | ✅ | ✅ | ✅ | |
| cashFlowUuid | TEXT? | ✅ | ✅ | ✅ | |
| isAutoGenerated | BOOL | ✅ | ✅ | ✅ | |

### 6. DEBTS (الديون)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| bookingLocalId | INT? | ✅ | ✅ | ✅ | FK→bookings |
| guestName | TEXT | ✅ | ✅ (debtorName) | ✅ | |
| checkinDate | TEXT | ✅ | ✅ | ✅ | |
| checkoutDate | TEXT | ✅ | ✅ | ✅ | |
| dateRecorded | TEXT | ✅ | ✅ | ✅ | |
| debtReason | TEXT | ✅ | ✅ | ✅ | |
| totalAmount | REAL | ✅ | ✅ (amount) | ✅ | |
| paidAmount | REAL | ✅ | ✅ | ✅ | |
| remainingAmount | REAL | ✅ | ✅ | ✅ | |
| paymentDate | TEXT | ✅ | ✅ (dueDate) | ✅ | |
| isSettled | INT | ✅ | ✅ (status) | ✅ | 0/1 → pending/settled |
| pledge | TEXT? | ✅ | ✅ | ✅ | |
| pledgeType | TEXT? | ✅ | ✅ | ✅ | |
| note | TEXT? | ✅ | ✅ | ✅ | |
| debtUuid | TEXT? | ✅ | ✅ | ✅ | |
| hotelDayOpened | TEXT? | ✅ | ✅ | ✅ | |
| hotelDayClosed | TEXT? | ✅ | ✅ | ✅ | |
| isFromAutoFix | BOOL | ✅ | ✅ | ✅ | |
| settlementConfirmed | BOOL | ✅ | ✅ | ✅ | |

### 7. CASH_TRANSACTIONS (المعاملات النقدية)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| registerId | INT? | ✅ | ✅ | ✅ | |
| transactionType | TEXT | ✅ | ✅ | ✅ | |
| amount | REAL | ✅ | ✅ | ✅ | |
| referenceType | TEXT? | ✅ | ✅ | ✅ | |
| referenceId | INT? | ✅ | ✅ | ✅ | |
| description | TEXT? | ✅ | ✅ | ✅ | |
| transactionTime | TEXT | ✅ | ✅ | ✅ | |
| createdBy | INT? | ✅ | ✅ | ✅ | |

### 8. BOOKING_NOTES (ملاحظات الحجز)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| bookingId | INT | ✅ | ✅ | ✅ | FK→bookings |
| noteText | TEXT | ✅ | ✅ | ✅ | |
| alertType | TEXT | ✅ | ✅ | ✅ | |
| alertUntil | TEXT? | ✅ | ✅ | ✅ | |
| isActive | INT | ✅ | ✅ | ✅ | |

### 9. BOOKING_NIGHTS (ليالي الحجز)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| bookingLocalId | INT | ✅ | ✅ | ✅ | FK→bookings |
| hotelDayKey | TEXT | ✅ | ✅ | ✅ | |
| nightStart | TEXT | ✅ | ✅ | ✅ | |
| nightEnd | TEXT | ✅ | ✅ | ✅ | |
| nightlyRate | REAL | ✅ | ✅ | ✅ | |
| sequence | INT | ✅ | ✅ | ✅ | |
| isProcessedByAutoFix | BOOL | ✅ | ✅ | ✅ | |

### 10. SHIFT_NOTES (ملاحظات الشيفت)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| title | TEXT | ✅ | ✅ | ✅ | |
| content | TEXT | ✅ | ✅ | ✅ | |
| priority | TEXT | ✅ | ✅ | ✅ | |
| shiftType | TEXT | ✅ | ✅ | ✅ | |
| isRead | INT | ✅ | ✅ | ✅ | |
| expiresAt | TEXT? | ✅ | ✅ | ✅ | |
| createdBy | TEXT | ✅ | ✅ | ✅ | |

### 11. HOTEL_DAY_LEDGER (دفتر اليوم الفندقي)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| hotelDayKey | TEXT | ✅ | ✅ | ✅ | Unique |
| totalIncome | REAL | ✅ | ✅ | ✅ | |
| totalExpenses | REAL | ✅ | ✅ | ✅ | |
| pendingBalances | REAL | ✅ | ✅ | ✅ | |
| occupancyRate | REAL | ✅ | ✅ | ✅ | |
| bookingsProcessed | INT | ✅ | ✅ | ✅ | |
| paymentsProcessed | INT | ✅ | ✅ | ✅ | |
| debtsProcessed | INT | ✅ | ✅ | ✅ | |
| expensesProcessed | INT | ✅ | ✅ | ✅ | |
| status | TEXT | ✅ | ✅ | ✅ | |

### 12. SALARY_CYCLES (دورات الرواتب)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| employeeId | INT | ✅ | ✅ | ✅ | FK→employees |
| cycleKey | TEXT | ✅ | ✅ | ✅ | |
| hotelDayStart | TEXT? | ✅ | ✅ | ✅ | |
| hotelDayEnd | TEXT? | ✅ | ✅ | ✅ | |
| expectedAmount | REAL | ✅ | ✅ | ✅ | |
| actualPaid | REAL | ✅ | ✅ | ✅ | |
| remainingAmount | REAL | ✅ | ✅ | ✅ | |
| status | TEXT | ✅ | ✅ | ✅ | |

### 13. SALARY_PAYMENTS (مدفوعات الرواتب)

| الحقل | النوع | Local | Appwrite | Drive | ملاحظات |
|-------|------|-------|----------|-------|---------|
| id | INT | ✅ | - | ✅ | |
| cycleId | INT | ✅ | ✅ | ✅ | FK→salary_cycles |
| amount | REAL | ✅ | ✅ | ✅ | |
| hotelDayKey | TEXT? | ✅ | ✅ | ✅ | |
| paymentDateIso | TEXT | ✅ | ✅ | ✅ | |
| method | TEXT? | ✅ | ✅ | ✅ | |
| isAutoGenerated | BOOL | ✅ | ✅ | ✅ | |

---

## الجداول المحلية فقط | Local-Only Tables

هذه الجداول لا تُزامَن مع Appwrite ولكنها تُنسَخ إلى Google Drive:

| # | الجدول | الغرض |
|---|--------|-------|
| 1 | outbox | طابور المزامنة المحلي |
| 2 | sync_state | حالة المزامنة الحالية |
| 3 | sync_queue | طابور العمليات |
| 4 | sync_log | سجل المزامنة |
| 5 | sync_conflicts | سجل التضاربات |
| 6 | auto_fix_runs | سجل الإصلاحات التلقائية |
| 7 | integrity_violations | انتهاكات سلامة البيانات |
| 8 | app_sessions | جلسات التطبيق |
| 9 | restore_fix_log | سجل الاستعادة والإصلاح |

---

## اختلافات تسمية الحقول | Field Naming Differences

### Appwrite vs Local (ملاحظة: تختلف بعض الأسماء)

| Local DB | Appwrite | ملاحظات |
|----------|----------|---------|
| guestName | debtorName | في جدول debts |
| totalAmount | amount | في جدول debts |
| paymentDate | dueDate | في جدول debts |
| isSettled (0/1) | status (pending/settled) | تحويل النوع |

---

## ترتيب المزامنة | Sync Order (Dependencies)

```
1. rooms (لا تبعيات)
2. employees (لا تبعيات)
3. bookings (يعتمد على rooms)
4. booking_notes (يعتمد على bookings)
5. booking_nights (يعتمد على bookings)
6. cash_transactions (لا تبعيات)
7. payments (يعتمد على bookings, cash_transactions)
8. expenses (يعتمد على cash_transactions)
9. debts (يعتمد على bookings)
10. shift_notes (لا تبعيات)
11. hotel_day_ledger (لا تبعيات)
12. salary_cycles (يعتمد على employees)
13. salary_payments (يعتمد على salary_cycles)
```

---

## نتيجة التحقق | Verification Result

✅ **جميع الجداول متطابقة** بين قاعدة البيانات المحلية و Appwrite و Google Drive

✅ **جميع الحقول المطلوبة موجودة** في كل الأنظمة الثلاثة

✅ **Adapters موجودة** لجميع الجداول القابلة للمزامنة

⚠️ **ملاحظة**: جدول `hotel_day_ledger` يحتاج إلى adapter مخصص (يستخدم حالياً التحويل العام)

---

## التوصيات | Recommendations

1. ✅ Schema متطابق - لا تغييرات مطلوبة
2. ⚠️ إضافة adapter مخصص لـ hotel_day_ledger للتأكد من المطابقة الدقيقة
3. ✅ ترتيب المزامنة صحيح ويراعي التبعيات

---

تاريخ التحقق: 2026-02-01
