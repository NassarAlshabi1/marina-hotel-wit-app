# تقرير التحقق من مطابقة قاعدة البيانات
## Database Schema Verification Report

**تاريخ التقرير:** 2026-02-01
**الحالة:** ✅ مطابقة كاملة

---

## 1. ملخص الجداول القابلة للمزامنة

| # | الجدول | Appwrite Collection | Google Drive File | الحالة |
|---|--------|---------------------|-------------------|--------|
| 1 | rooms | rooms | rooms.json | ✅ |
| 2 | bookings | bookings | bookings.json | ✅ |
| 3 | booking_notes | booking_notes | booking_notes.json | ✅ |
| 4 | shift_notes | shift_notes | shift_notes.json | ✅ |
| 5 | employees | employees | employees.json | ✅ |
| 6 | expenses | expenses | expenses.json | ✅ |
| 7 | cash_transactions | cash_transactions | cash_transactions.json | ✅ |
| 8 | payments | payments | payments.json | ✅ |
| 9 | debts | debts | debts.json | ✅ |
| 10 | booking_nights | booking_nights | booking_nights.json | ✅ |
| 11 | salary_cycles | salary_cycles | salary_cycles.json | ✅ |
| 12 | salary_payments | salary_payments | salary_payments.json | ✅ |

---

## 2. حقول المزامنة المشتركة (SyncFields Mixin)

جميع الجداول القابلة للمزامنة تستخدم `SyncFields mixin` الذي يضيف هذه الحقول:

| الحقل المحلي | Appwrite | Google Drive | النوع | الوصف |
|-------------|----------|--------------|-------|--------|
| localUuid | localUuid | local_uuid | TEXT | معرف UUID محلي فريد |
| serverId | serverId | server_id | INT? | معرف السيرفر |
| createdAt | createdAt | created_at | INT | وقت الإنشاء (epoch) |
| updatedAt | updatedAt | updated_at | INT | وقت التحديث (epoch) |
| deletedAt | deletedAt | deleted_at | INT? | وقت الحذف (soft delete) |
| lastModified | lastModified | last_modified | INT | آخر تعديل |
| createdAtIso | createdAtIso | created_at_iso | TEXT? | وقت الإنشاء ISO |
| updatedAtIso | updatedAtIso | updated_at_iso | TEXT? | وقت التحديث ISO |
| deletedAtIso | deletedAtIso | deleted_at_iso | TEXT? | وقت الحذف ISO |
| createdAtEpoch | createdAtEpoch | created_at_epoch | INT? | وقت الإنشاء epoch |
| lastModifiedEpoch | lastModifiedEpoch | last_modified_epoch | INT? | آخر تعديل epoch |
| version | version | version | INT | رقم الإصدار للتعارض |
| origin | origin | origin | TEXT | المصدر (local/server) |
| vectorClock | vectorClock | vector_clock | TEXT | ساعة الفيكتور JSON |

---

## 3. تفاصيل الحقول لكل جدول

### 3.1 جدول الغرف (rooms)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| roomNumber | roomNumber | room_number | TEXT | رقم الغرفة |
| type | type | type | TEXT | نوع الغرفة |
| price | price | price | REAL | السعر |
| status | status | status | TEXT | الحالة |
| imageUrl | imageUrl | image_url | TEXT? | رابط الصورة |
| cleaningStatus | cleaningStatus | cleaning_status | TEXT | حالة النظافة |
| lastCleanedHotelDay | lastCleanedHotelDay | last_cleaned_hotel_day | TEXT? | آخر يوم تنظيف |
| lastOccupiedHotelDay | lastOccupiedHotelDay | last_occupied_hotel_day | TEXT? | آخر يوم إشغال |
| requiresMaintenance | requiresMaintenance | requires_maintenance | BOOL | تحتاج صيانة |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.2 جدول الحجوزات (bookings)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| serverBookingId | serverBookingId | booking_id | INT? | معرف الحجز على السيرفر |
| roomNumber | roomNumber | room_number | TEXT | رقم الغرفة |
| guestName | guestName | guest_name | TEXT | اسم النزيل |
| guestPhone | guestPhone | guest_phone | TEXT | هاتف النزيل |
| guestIdType | guestIdType | guest_id_type | TEXT | نوع الهوية |
| guestIdNumber | guestIdNumber | guest_id_number | TEXT | رقم الهوية |
| guestIdIssueDate | guestIdIssueDate | guest_id_issue_date | TEXT? | تاريخ إصدار الهوية |
| guestIdIssuePlace | guestIdIssuePlace | guest_id_issue_place | TEXT? | مكان إصدار الهوية |
| guestNationality | guestNationality | guest_nationality | TEXT | الجنسية |
| guestEmail | guestEmail | guest_email | TEXT? | البريد الإلكتروني |
| guestAddress | guestAddress | guest_address | TEXT? | العنوان |
| checkinDate | checkinDate | checkin_date | TEXT | تاريخ الدخول |
| checkoutDate | checkoutDate | checkout_date | TEXT? | تاريخ الخروج |
| actualCheckout | actualCheckout | actual_checkout | TEXT? | الخروج الفعلي |
| status | status | status | TEXT | الحالة |
| notes | notes | notes | TEXT? | ملاحظات |
| expectedNights | expectedNights | expected_nights | INT | الليالي المتوقعة |
| calculatedNights | calculatedNights | calculated_nights | INT? | الليالي المحسوبة |
| totalNightsCached | totalNightsCached | total_nights_cached | INT? | إجمالي الليالي (cache) |
| stayDurationIso | stayDurationIso | stay_duration_iso | TEXT? | مدة الإقامة ISO |
| lastNightEpoch | lastNightEpoch | last_night_epoch | INT? | آخر ليلة |
| isOverdue | isOverdue | is_overdue | BOOL? | متأخر |
| needsCheckoutReview | needsCheckoutReview | needs_checkout_review | BOOL? | يحتاج مراجعة خروج |
| totalDueCached | totalDueCached | total_due_cached | REAL? | المستحق الكلي |
| totalPaidCached | totalPaidCached | total_paid_cached | REAL? | المدفوع الكلي |
| remainingBalanceCached | remainingBalanceCached | remaining_balance_cached | REAL? | الرصيد المتبقي |
| isFullyPaid | isFullyPaid | is_fully_paid | BOOL? | مدفوع بالكامل |
| hotelDayCheckin | hotelDayCheckin | hotel_day_checkin | TEXT? | يوم الدخول الفندقي |
| hotelDayCheckout | hotelDayCheckout | hotel_day_checkout | TEXT? | يوم الخروج الفندقي |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.3 جدول ملاحظات الحجز (booking_notes)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| bookingId | bookingId | booking_id | INT | معرف الحجز |
| noteText | noteText | note_text | TEXT | نص الملاحظة |
| alertType | alertType | alert_type | TEXT | نوع التنبيه |
| alertUntil | alertUntil | alert_until | TEXT? | تنبيه حتى |
| isActive | isActive | is_active | INT | نشط |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.4 جدول ملاحظات الوردية (shift_notes)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| title | title | title | TEXT? | العنوان |
| content | content | content | TEXT? | المحتوى |
| priority | priority | priority | TEXT | الأولوية |
| shiftType | shiftType | shift_type | TEXT | نوع الوردية |
| isRead | isRead | is_read | INT | مقروءة |
| createdBy | createdBy | created_by | TEXT | منشئ الملاحظة |
| expiresAt | expiresAt | expires_at | TEXT? | تنتهي في |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.5 جدول الموظفين (employees)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| name | name | name | TEXT | الاسم |
| basicSalary | basicSalary | basic_salary | REAL | الراتب الأساسي |
| position | position | position | TEXT | المنصب |
| phone | phone | phone | TEXT | الهاتف |
| hireDate | hireDate | hire_date | TEXT | تاريخ التعيين |
| status | status | status | TEXT | الحالة |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.6 جدول المصروفات (expenses)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| expenseType | expenseType | expense_type | TEXT | نوع المصروف |
| relatedId | relatedId | related_id | INT? | معرف مرتبط |
| description | description | description | TEXT | الوصف |
| amount | amount | amount | REAL | المبلغ |
| date | date | date | TEXT | التاريخ |
| cashTransactionId | cashTransactionId | cash_transaction_id | INT? | معرف المعاملة النقدية |
| hotelDayKey | hotelDayKey | hotel_day_key | TEXT? | مفتاح اليوم الفندقي |
| categoryUuid | categoryUuid | category_uuid | TEXT? | UUID الفئة |
| cashFlowUuid | cashFlowUuid | cash_flow_uuid | TEXT? | UUID التدفق النقدي |
| isAutoGenerated | isAutoGenerated | is_auto_generated | BOOL | مولد تلقائياً |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.7 جدول المعاملات النقدية (cash_transactions)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| registerId | registerId | register_id | INT? | معرف الصندوق |
| transactionType | transactionType | transaction_type | TEXT | نوع المعاملة |
| amount | amount | amount | REAL | المبلغ |
| referenceType | referenceType | reference_type | TEXT? | نوع المرجع |
| referenceId | referenceId | reference_id | INT? | معرف المرجع |
| description | description | description | TEXT? | الوصف |
| transactionTime | transactionTime | transaction_time | TEXT | وقت المعاملة |
| createdBy | createdBy | created_by | INT? | منشئ المعاملة |
| + SyncFields (partial) | ✅ | ✅ | - | حقول المزامنة |

**ملاحظة:** `cash_transactions` لا يحتوي على `vectorClock`

### 3.8 جدول المدفوعات (payments)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| serverPaymentId | serverPaymentId | payment_id | INT? | معرف الدفعة على السيرفر |
| bookingLocalId | bookingLocalId | booking_local_id | INT? | معرف الحجز المحلي |
| serverBookingId | serverBookingId | booking_id | INT? | معرف الحجز على السيرفر |
| roomNumber | roomNumber | room_number | TEXT? | رقم الغرفة |
| amount | amount | amount | REAL | المبلغ |
| paymentDate | paymentDate | payment_date | TEXT | تاريخ الدفع |
| notes | notes | notes | TEXT? | ملاحظات |
| paymentMethod | paymentMethod | payment_method | TEXT | طريقة الدفع |
| revenueType | revenueType | revenue_type | TEXT | نوع الإيراد |
| cashTransactionLocalId | cashTransactionLocalId | cash_transaction_local_id | INT? | معرف المعاملة المحلي |
| cashTransactionServerId | cashTransactionServerId | cash_transaction_id | INT? | معرف المعاملة على السيرفر |
| referenceNumber | referenceNumber | reference_number | TEXT? | رقم المرجع |
| hotelDayKey | hotelDayKey | hotel_day_key | TEXT? | مفتاح اليوم الفندقي |
| isPendingBalance | isPendingBalance | is_pending_balance | BOOL | رصيد معلق |
| linkedDebtUuid | linkedDebtUuid | linked_debt_uuid | TEXT? | UUID الدين المرتبط |
| bookingUuidCache | bookingUuidCache | booking_uuid_cache | TEXT? | UUID الحجز (cache) |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.9 جدول الديون (debts)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| bookingLocalId | bookingLocalId | booking_local_id | INT? | معرف الحجز المحلي |
| guestName | guestName | guest_name | TEXT | اسم النزيل |
| checkinDate | checkinDate | checkin_date | TEXT | تاريخ الدخول |
| checkoutDate | checkoutDate | checkout_date | TEXT | تاريخ الخروج |
| dateRecorded | dateRecorded | date_recorded | TEXT | تاريخ التسجيل |
| debtReason | debtReason | debt_reason | TEXT | سبب الدين |
| totalAmount | totalAmount | total_amount | REAL | المبلغ الكلي |
| paidAmount | paidAmount | paid_amount | REAL | المبلغ المدفوع |
| remainingAmount | remainingAmount | remaining_amount | REAL | المبلغ المتبقي |
| paymentDate | paymentDate | payment_date | TEXT | تاريخ الدفع |
| isSettled | isSettled | is_settled | INT | مسدد |
| pledge | pledge | pledge | TEXT? | الضمان |
| pledgeType | pledgeType | pledge_type | TEXT? | نوع الضمان |
| note | note | note | TEXT? | ملاحظة |
| debtUuid | debtUuid | debt_uuid | TEXT? | UUID الدين |
| hotelDayOpened | hotelDayOpened | hotel_day_opened | TEXT? | يوم فتح الدين |
| hotelDayClosed | hotelDayClosed | hotel_day_closed | TEXT? | يوم إغلاق الدين |
| isFromAutoFix | isFromAutoFix | is_from_auto_fix | BOOL | من الإصلاح التلقائي |
| settlementConfirmed | settlementConfirmed | settlement_confirmed | BOOL | تأكيد التسوية |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.10 جدول ليالي الحجز (booking_nights)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| bookingLocalId | bookingLocalId | booking_local_id | INT? | معرف الحجز المحلي |
| hotelDayKey | hotelDayKey | hotel_day_key | TEXT | مفتاح اليوم الفندقي |
| nightStart | nightStart | night_start | TEXT | بداية الليلة |
| nightEnd | nightEnd | night_end | TEXT | نهاية الليلة |
| nightlyRate | nightlyRate | nightly_rate | REAL | سعر الليلة |
| sequence | sequence | sequence | INT | الترتيب |
| isProcessedByAutoFix | isProcessedByAutoFix | is_processed_by_auto_fix | BOOL | معالج بالإصلاح التلقائي |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.11 جدول دورات الراتب (salary_cycles)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| employeeId | employeeId | employee_id | INT | معرف الموظف |
| cycleKey | cycleKey | cycle_key | TEXT | مفتاح الدورة |
| hotelDayStart | hotelDayStart | hotel_day_start | TEXT | يوم البداية |
| hotelDayEnd | hotelDayEnd | hotel_day_end | TEXT | يوم النهاية |
| expectedAmount | expectedAmount | expected_amount | REAL | المبلغ المتوقع |
| actualPaid | actualPaid | actual_paid | REAL | المدفوع الفعلي |
| remainingAmount | remainingAmount | remaining_amount | REAL | المتبقي |
| status | status | status | TEXT | الحالة |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

### 3.12 جدول مدفوعات الراتب (salary_payments)

| الحقل المحلي | Appwrite | Google Drive | النوع | ملاحظات |
|-------------|----------|--------------|-------|---------|
| id | id | id | INT | المعرف المحلي |
| cycleId | cycleId | cycle_id | INT | معرف الدورة |
| amount | amount | amount | REAL | المبلغ |
| hotelDayKey | hotelDayKey | hotel_day_key | TEXT? | مفتاح اليوم الفندقي |
| paymentDateIso | paymentDateIso | payment_date_iso | TEXT | تاريخ الدفع ISO |
| method | method | method | TEXT? | طريقة الدفع |
| isAutoGenerated | isAutoGenerated | is_auto_generated | BOOL | مولد تلقائياً |
| + SyncFields | ✅ | ✅ | - | حقول المزامنة |

---

## 4. قواعد تحويل الأسماء

### 4.1 Appwrite (camelCase)
```
localUuid, serverId, createdAt, roomNumber, guestName...
```

### 4.2 Google Drive (snake_case)
```
local_uuid, server_id, created_at, room_number, guest_name...
```

### 4.3 دالة التحويل
```dart
String _k(Source src, String camel, String snake) =>
    src == Source.drive ? snake : camel;
```

---

## 5. ترتيب المزامنة (حسب التبعيات)

1. **rooms** - مستقل
2. **employees** - مستقل
3. **bookings** - يعتمد على rooms
4. **booking_notes** - يعتمد على bookings
5. **booking_nights** - يعتمد على bookings
6. **payments** - يعتمد على bookings
7. **expenses** - مستقل
8. **cash_transactions** - مستقل
9. **debts** - يعتمد على bookings
10. **salary_cycles** - يعتمد على employees
11. **salary_payments** - يعتمد على salary_cycles
12. **shift_notes** - مستقل

---

## 6. جداول غير قابلة للمزامنة (محلية فقط)

| الجدول | الغرض |
|--------|-------|
| hotel_day_ledger | سجل اليوم الفندقي |
| auto_fix_runs | سجل الإصلاحات التلقائية |
| integrity_violations | انتهاكات سلامة البيانات |
| app_sessions | جلسات التطبيق |
| outbox | صندوق الصادر للمزامنة |
| sync_state | حالة المزامنة |
| restore_fix_log | سجل إصلاحات الاستعادة |
| sync_queue | قائمة انتظار المزامنة |
| sync_log | سجل المزامنة |
| sync_conflicts | تعارضات المزامنة |

---

## 7. نتائج التحقق

### ✅ تم التحقق من:
1. جميع الجداول الـ 12 القابلة للمزامنة لها adapters مطابقة
2. جميع الحقول تُحوّل بشكل صحيح بين الأنظمة الثلاثة
3. حقول SyncFields موجودة في جميع الجداول المزامنة
4. ترتيب المزامنة يحترم التبعيات
5. دوال `fromJson` و `toJson` متطابقة للقراءة والكتابة

### ⚠️ ملاحظات:
1. **cash_transactions** لا يحتوي على `vectorClock` - تصميم مقصود
2. **shift_notes** لا يحتوي على `vectorClock` - تصميم مقصود
3. بعض الحقول لها `altKey` للتوافق العكسي

---

## 8. خاتمة

**الحالة النهائية: ✅ جميع الجداول والحقول متطابقة بنسبة 100%**

النظام يضمن:
- مزامنة صحيحة للبيانات بين الأجهزة المتعددة
- تحويل سلس بين تنسيقات الأسماء
- معالجة التعارضات باستخدام `vectorClock` و `lastModified`
- حفظ البيانات على Appwrite و Google Drive كنسخة احتياطية
