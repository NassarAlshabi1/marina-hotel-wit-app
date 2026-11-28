# جداول وحقول المحوّلات (Sync Adapters) وجدول Outbox

**المصدر:** `lib/services/local_db.dart` (تعريفات جداول Drift) + `lib/services/local_db.g.dart` (أسماء الأعمدة المولَّدة فعلياً في قاعدة SQLite) + `lib/services/adapters/adapter_registry.dart` (ربط كل محوّل (Adapter) بجدوله).
**الفرع:** `refactor/performance-fixes-v2`

## كيف تُقرأ هذه الوثيقة

- كل محوّل في `lib/services/adapters/*_adapter.dart` يُطابق جدول Drift واحداً، ومسجَّل في `AdapterRegistry`.
- كل جداول المحوّلات (باستثناء `Outbox` نفسه) تستخدم **mixin `SyncFields`** الذي يضيف 17 عموداً مشتركاً لدعم المزامنة (مذكورة في §1 مرة واحدة فقط، ولا تتكرر تحت كل جدول).
- الأعمدة أدناه هي **الأعمدة الخاصة بكل جدول فقط** (إضافة إلى أعمدة §1 المشتركة لكل الجداول عدا Outbox).
- اسم العمود الفعلي داخل SQLite مأخوذ من `local_db.g.dart` (قد يختلف عن camelCase في Dart، مثل `employeeID` ← `employee_i_d`).

---

## 1. الحقول المشتركة لكل جداول المحوّلات (`SyncFields` mixin)

تضاف هذه الأعمدة تلقائياً لكل الجداول العشرين التالية (غير Outbox):

| # | العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | الوصف |
|---|---|---|---|---|---|
| 1 | `local_uuid` | `localUuid` | TEXT | **UNIQUE، NOT NULL** | الهوية الثابتة للسجل عبر كل الأجهزة — مفتاح المزامنة الأساسي |
| 2 | `server_id` | `serverId` | INTEGER | NULLABLE | معرّف السجل على الخادم (Appwrite) |
| 3 | `created_at` | `createdAt` | INTEGER | NOT NULL | طابع زمني الإنشاء (epoch ms) |
| 4 | `updated_at` | `updatedAt` | INTEGER | NOT NULL | طابع زمني آخر تعديل |
| 5 | `deleted_at` | `deletedAt` | INTEGER | NULLABLE | طابع زمني الحذف الناعم (soft delete) |
| 6 | `last_modified` | `lastModified` | INTEGER | NOT NULL | آخر تعديل — يُستخدم لحسم تعارضات Last-Write-Wins |
| 7 | `created_at_iso` | `createdAtIso` | TEXT | NULLABLE | الإنشاء بصيغة ISO-8601 |
| 8 | `updated_at_iso` | `updatedAtIso` | TEXT | NULLABLE | التعديل بصيغة ISO-8601 |
| 9 | `deleted_at_iso` | `deletedAtIso` | TEXT | NULLABLE | الحذف بصيغة ISO-8601 |
| 10 | `created_at_epoch` | `createdAtEpoch` | INTEGER | DEFAULT `0` | الإنشاء بالثواني |
| 11 | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER | DEFAULT `0` | آخر تعديل بالثواني |
| 12 | `version` | `version` | INTEGER | DEFAULT `1` | رقم إصدار السجل |
| 13 | `origin` | `origin` | TEXT | DEFAULT `'local'` | مصدر السجل (`local` / بعيد) |
| 14 | `vector_clock` | `vectorClock` | TEXT | DEFAULT `'{}'` | ساعة فيكتور (JSON) لحسم التعارضات بين الأجهزة |
| 15 | `device_id` | `deviceId` | TEXT | DEFAULT `''` | الجهاز الذي أنشأ/عدّل السجل |
| 16 | `sync_timestamp` | `syncTimestamp` | INTEGER | DEFAULT `0` | طابع زمني آخر مزامنة للسجل |
| 17 | `idempotency_key` | `idempotencyKey` | TEXT | NULLABLE | مفتاح منع تكرار العمليات عبر الأجهزة |

---

## 2. جداول المحوّلات (Adapters) — الأعمدة الخاصة بكل جدول

### 2.1 `rooms` — `RoomsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `room_number` | `roomNumber` | TEXT | **UNIQUE، NOT NULL** | رقم الغرفة |
| `type` | `type` | TEXT | NOT NULL | نوع الغرفة |
| `price` | `price` | REAL | NOT NULL | السعر |
| `status` | `status` | TEXT | NOT NULL | الحالة (شاغرة/مشغولة...) |
| `image_url` | `imageUrl` | TEXT | NULLABLE | رابط صورة الغرفة |
| `cleaning_status` | `cleaningStatus` | TEXT | DEFAULT `'clean'` | حالة التنظيف |
| `last_cleaned_hotel_day` | `lastCleanedHotelDay` | TEXT | NULLABLE | يوم آخر تنظيف |
| `last_occupied_hotel_day` | `lastOccupiedHotelDay` | TEXT | NULLABLE | يوم آخر إشغال |
| `requires_maintenance` | `requiresMaintenance` | BOOLEAN | DEFAULT `false` | تحتاج صيانة |

### 2.2 `bookings` — `BookingsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `server_booking_id` | `serverBookingId` | INTEGER | NULLABLE | |
| `room_number` | `roomNumber` | TEXT | NOT NULL | **FK** → `rooms.room_number` |
| `guest_name` | `guestName` | TEXT | NOT NULL | |
| `guest_phone` | `guestPhone` | TEXT | NOT NULL | |
| `guest_id_type` | `guestIdType` | TEXT | DEFAULT `'بطاقة شخصية'` | |
| `guest_id_number` | `guestIdNumber` | TEXT | DEFAULT `''` | |
| `guest_id_issue_date` | `guestIdIssueDate` | TEXT | NULLABLE | |
| `guest_id_issue_place` | `guestIdIssuePlace` | TEXT | NULLABLE | |
| `guest_nationality` | `guestNationality` | TEXT | NOT NULL | |
| `guest_email` | `guestEmail` | TEXT | NULLABLE | |
| `guest_address` | `guestAddress` | TEXT | NULLABLE | |
| `checkin_date` | `checkinDate` | TEXT | NOT NULL | |
| `checkout_date` | `checkoutDate` | TEXT | NULLABLE | |
| `actual_checkout` | `actualCheckout` | TEXT | NULLABLE | |
| `status` | `status` | TEXT | NOT NULL | |
| `notes` | `notes` | TEXT | NULLABLE | |
| `discount` | `discount` | REAL | DEFAULT `0` | |
| `discount_type` | `discountType` | TEXT | DEFAULT `'per_night'` | |
| `discount_start_date` | `discountStartDate` | TEXT | NULLABLE | |
| `expected_nights` | `expectedNights` | INTEGER | DEFAULT `1` | |
| `calculated_nights` | `calculatedNights` | INTEGER | DEFAULT `1` | |
| `total_nights_cached` | `totalNightsCached` | INTEGER | DEFAULT `0` | |
| `stay_duration_iso` | `stayDurationIso` | TEXT | NULLABLE | |
| `last_night_epoch` | `lastNightEpoch` | INTEGER | NULLABLE | |
| `is_overdue` | `isOverdue` | BOOLEAN | DEFAULT `false` | |
| `needs_checkout_review` | `needsCheckoutReview` | BOOLEAN | DEFAULT `false` | |
| `total_due_cached` | `totalDueCached` | REAL | DEFAULT `0.0` | |
| `total_paid_cached` | `totalPaidCached` | REAL | DEFAULT `0.0` | |
| `remaining_balance_cached` | `remainingBalanceCached` | REAL | DEFAULT `0.0` | |
| `is_fully_paid` | `isFullyPaid` | BOOLEAN | DEFAULT `false` | |
| `hotel_day_checkin` | `hotelDayCheckin` | TEXT | NULLABLE | |
| `hotel_day_checkout` | `hotelDayCheckout` | TEXT | NULLABLE | |
| `financial_frozen_at` | `financialFrozenAt` | INTEGER | NULLABLE | |
| `financial_hash` | `financialHash` | TEXT | NULLABLE | |

### 2.3 `booking_notes` — `BookingNotesAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `booking_id` | `bookingId` | INTEGER | NOT NULL | **FK** → `bookings.id` |
| `note_text` | `noteText` | TEXT | NOT NULL | |
| `alert_type` | `alertType` | TEXT | NOT NULL | |
| `alert_until` | `alertUntil` | TEXT | NULLABLE | |
| `is_active` | `isActive` | INTEGER | DEFAULT `1` | (0/1 — مرشّح ليصبح BOOLEAN) |

### 2.4 `employees` — `EmployeesAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `name` | `name` | TEXT | NOT NULL | |
| `basic_salary` | `basicSalary` | REAL | NOT NULL | |
| `position` | `position` | TEXT | DEFAULT `'موظف'` | |
| `phone` | `phone` | TEXT | DEFAULT `''` | |
| `hire_date` | `hireDate` | TEXT | DEFAULT `''` | |
| `status` | `status` | TEXT | NOT NULL | |
| `termination_date` | `terminationDate` | TEXT | NULLABLE | |
| `termination_reason` | `terminationReason` | TEXT | NULLABLE | |
| `employee_i_d` | `employeeID` | TEXT | NULLABLE | الرقم الوظيفي/الهوية الإدارية — الاسم الفعلي في SQLite مختلف عن Dart بسبب الأحرف الكبيرة المتتالية `ID` |

### 2.5 `expenses` — `ExpensesAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `expense_type` | `expenseType` | TEXT | NOT NULL | |
| `related_id` | `relatedId` | INTEGER | NULLABLE | |
| `description` | `description` | TEXT | NOT NULL | |
| `amount` | `amount` | REAL | NOT NULL | |
| `date` | `date` | TEXT | NOT NULL | |
| `cash_transaction_id` | `cashTransactionId` | INTEGER | NULLABLE | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NULLABLE | |
| `category_uuid` | `categoryUuid` | TEXT | NULLABLE | |
| `cash_flow_uuid` | `cashFlowUuid` | TEXT | NULLABLE | |
| `is_auto_generated` | `isAutoGenerated` | BOOLEAN | DEFAULT `false` | |
| `employee_uuid` | `employeeUuid` | TEXT | NULLABLE | رابط مرآة للموظف عبر الأجهزة |
| `withdrawal_uuid` | `withdrawalUuid` | TEXT | NULLABLE | رابط مرآة لسحبة الراتب المقابلة |

### 2.6 `cash_transactions` — `CashTransactionsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `register_id` | `registerId` | INTEGER | NULLABLE | |
| `transaction_type` | `transactionType` | TEXT | NOT NULL | |
| `amount` | `amount` | REAL | NOT NULL | |
| `reference_type` | `referenceType` | TEXT | NULLABLE | |
| `reference_id` | `referenceId` | INTEGER | NULLABLE | |
| `description` | `description` | TEXT | NULLABLE | |
| `transaction_time` | `transactionTime` | TEXT | NOT NULL | |
| `created_by` | `createdBy` | INTEGER | NULLABLE | |

### 2.7 `payments` — `PaymentsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `server_payment_id` | `serverPaymentId` | INTEGER | NULLABLE | |
| `booking_local_id` | `bookingLocalId` | INTEGER | NULLABLE | **FK** → `bookings.id` |
| `server_booking_id` | `serverBookingId` | INTEGER | NULLABLE | |
| `room_number` | `roomNumber` | TEXT | NULLABLE | |
| `amount` | `amount` | REAL | NOT NULL | |
| `payment_date` | `paymentDate` | TEXT | NOT NULL | |
| `notes` | `notes` | TEXT | NULLABLE | |
| `payment_method` | `paymentMethod` | TEXT | NOT NULL | |
| `revenue_type` | `revenueType` | TEXT | NOT NULL | |
| `cash_transaction_local_id` | `cashTransactionLocalId` | INTEGER | NULLABLE | **FK** → `cash_transactions.id` |
| `cash_transaction_server_id` | `cashTransactionServerId` | INTEGER | NULLABLE | |
| `reference_number` | `referenceNumber` | TEXT | NULLABLE | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NULLABLE | |
| `is_pending_balance` | `isPendingBalance` | BOOLEAN | DEFAULT `false` | |
| `linked_debt_uuid` | `linkedDebtUuid` | TEXT | NULLABLE | |
| `booking_uuid_cache` | `bookingUuidCache` | TEXT | NULLABLE | |
| `discount_amount` | `discountAmount` | REAL | NULLABLE | |
| `discount_start_date` | `discountStartDate` | TEXT | NULLABLE | |
| `is_voided` | `isVoided` | BOOLEAN | DEFAULT `false` | |
| `voided_at` | `voidedAt` | INTEGER | NULLABLE | |
| `voided_by` | `voidedBy` | TEXT | NULLABLE | |
| `void_reason` | `voidReason` | TEXT | NULLABLE | |
| `is_immutable` | `isImmutable` | BOOLEAN | DEFAULT `false` | |
| `received_by_user_id` | `receivedByUserId` | INTEGER | NULLABLE | |
| `received_by_name` | `receivedByName` | TEXT | NULLABLE | |
| `received_session_uuid` | `receivedSessionUuid` | TEXT | NULLABLE | |
| `received_by_cloud_id` | `receivedByCloudId` | TEXT | NULLABLE | معرّف مستخدم Appwrite الثابت |
| `deleted_by_device` | `deletedByDevice` | TEXT | NULLABLE | |
| `deleted_by_name` | `deletedByName` | TEXT | NULLABLE | |

### 2.8 `debts` — `DebtsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `booking_local_id` | `bookingLocalId` | INTEGER | NULLABLE | **FK** → `bookings.id` |
| `guest_name` | `guestName` | TEXT | NOT NULL | |
| `checkin_date` | `checkinDate` | TEXT | NOT NULL | |
| `checkout_date` | `checkoutDate` | TEXT | NOT NULL | |
| `date_recorded` | `dateRecorded` | TEXT | DEFAULT `''` | |
| `debt_reason` | `debtReason` | TEXT | DEFAULT `''` | |
| `total_amount` | `totalAmount` | REAL | NOT NULL | |
| `paid_amount` | `paidAmount` | REAL | NOT NULL | |
| `remaining_amount` | `remainingAmount` | REAL | NOT NULL | |
| `payment_date` | `paymentDate` | TEXT | NOT NULL | |
| `is_settled` | `isSettled` | INTEGER | DEFAULT `0` | |
| `pledge` | `pledge` | TEXT | NULLABLE | |
| `pledge_type` | `pledgeType` | TEXT | NULLABLE | |
| `note` | `note` | TEXT | NULLABLE | |
| `debt_uuid` | `debtUuid` | TEXT | NULLABLE | |
| `hotel_day_opened` | `hotelDayOpened` | TEXT | NULLABLE | |
| `hotel_day_closed` | `hotelDayClosed` | TEXT | NULLABLE | |
| `is_from_auto_fix` | `isFromAutoFix` | BOOLEAN | DEFAULT `false` | |
| `settlement_confirmed` | `settlementConfirmed` | BOOLEAN | DEFAULT `false` | |
| `guest_phone` | `guestPhone` | TEXT | NULLABLE | |
| `description` | `description` | TEXT | NULLABLE | |
| `status` | `status` | TEXT | NULLABLE | |
| `due_date` | `dueDate` | TEXT | NULLABLE | |
| `booking_uuid_cache` | `bookingUuidCache` | TEXT | NULLABLE | |
| `debtor_name` | `debtorName` | TEXT | NULLABLE | |
| `amount` | `amount` | REAL | NULLABLE | |
| `date` | `date` | TEXT | NULLABLE | |

### 2.9 `shift_notes` — `ShiftNotesAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `title` | `title` | TEXT | NOT NULL | |
| `content` | `content` | TEXT | NOT NULL | |
| `priority` | `priority` | TEXT | DEFAULT `'medium'` | high/medium/low |
| `shift_type` | `shiftType` | TEXT | DEFAULT `'all'` | morning/evening/night/all |
| `is_read` | `isRead` | INTEGER | DEFAULT `0` | 0=غير مقروء، 1=مقروء |
| `expires_at` | `expiresAt` | TEXT | NULLABLE | |
| `created_by` | `createdBy` | TEXT | DEFAULT `'user'` | |

### 2.10 `booking_nights` — `NightsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `booking_local_id` | `bookingLocalId` | INTEGER | NOT NULL | **FK** → `bookings.id` |
| `hotel_day_key` | `hotelDayKey` | TEXT | NOT NULL | مع `booking_local_id`: **UNIQUE مركّب** |
| `night_start` | `nightStart` | TEXT | NOT NULL | |
| `night_end` | `nightEnd` | TEXT | NOT NULL | |
| `nightly_rate` | `nightlyRate` | REAL | DEFAULT `0.0` | |
| `sequence` | `sequence` | INTEGER | DEFAULT `0` | |
| `is_processed_by_auto_fix` | `isProcessedByAutoFix` | BOOLEAN | DEFAULT `false` | |
| `base_rate` | `baseRate` | REAL | DEFAULT `0.0` | |
| `adjustment` | `adjustment` | REAL | DEFAULT `0.0` | |
| `final_rate` | `finalRate` | REAL | DEFAULT `0.0` | |
| `applied_adjustment_uuid` | `appliedAdjustmentUuid` | TEXT | NULLABLE | |
| `applied_adjustments_json` | `appliedAdjustmentsJson` | TEXT | NULLABLE | |
| `booking_uuid_cache` | `bookingUuidCache` | TEXT | NULLABLE | |
| `server_booking_id` | `serverBookingId` | INTEGER | NULLABLE | |

### 2.11 `price_adjustments` — `PriceAdjustmentsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `target_type` | `targetType` | TEXT | NOT NULL | |
| `target_uuid` | `targetUuid` | TEXT | NOT NULL | |
| `adjustment_type` | `adjustmentType` | TEXT | NOT NULL | |
| `previous_value` | `previousValue` | REAL | NOT NULL | |
| `new_value` | `newValue` | REAL | NOT NULL | |
| `reason` | `reason` | TEXT | NULLABLE | |
| `effective_date` | `effectiveDate` | TEXT | NOT NULL | |
| `applied_by` | `appliedBy` | TEXT | NOT NULL | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NULLABLE | |
| `adjustment_mode` | `adjustmentMode` | TEXT | DEFAULT `'per_night'` | |
| `booking_uuid` | `bookingUuid` | TEXT | NULLABLE | |
| `applied_at` | `appliedAt` | INTEGER | NULLABLE | |
| `is_reversed` | `isReversed` | BOOLEAN | DEFAULT `false` | |
| `reversed_at` | `reversedAt` | TEXT | NULLABLE | |
| `reversed_by` | `reversedBy` | TEXT | NULLABLE | |

### 2.12 `booking_price_adjustments` — `BookingPriceAdjustmentsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `booking_local_uuid` | `bookingLocalUuid` | TEXT | NOT NULL | **FK** → `bookings.local_uuid` |
| `booking_local_id` | `bookingLocalId` | INTEGER | NULLABLE | **FK** → `bookings.id` |
| `room_number` | `roomNumber` | TEXT | NULLABLE | طول 1–20 |
| `amount` | `amount` | REAL | DEFAULT `0.0` | |
| `effective_hotel_day` | `effectiveHotelDay` | TEXT | NOT NULL | |
| `end_hotel_day` | `endHotelDay` | TEXT | NULLABLE | |
| `is_active` | `isActive` | BOOLEAN | DEFAULT `true` | |
| `reason` | `reason` | TEXT | NULLABLE | |
| `applied_by` | `appliedBy` | TEXT | NULLABLE | |
| `cancelled_at` | `cancelledAt` | TEXT | NULLABLE | |
| `cancelled_by` | `cancelledBy` | TEXT | NULLABLE | |
| `booking_uuid` | `bookingUuid` | TEXT | NULLABLE | |
| `adjustment_type` | `adjustmentType` | INTEGER | NULLABLE | |
| `adjustment_mode` | `adjustmentMode` | TEXT | NULLABLE | |
| `applied_at` | `appliedAt` | INTEGER | NULLABLE | |

### 2.13 `audit_logs` — `AuditLogsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `operation_type` | `operationType` | TEXT | NOT NULL | |
| `entity_type` | `entityType` | TEXT | NOT NULL | |
| `entity_uuid` | `entityUuid` | TEXT | NOT NULL | |
| `entity_id` | `entityId` | INTEGER | NULLABLE | |
| `previous_state` | `previousState` | TEXT | NULLABLE | |
| `new_state` | `newState` | TEXT | NULLABLE | |
| `changed_fields` | `changedFields` | TEXT | NULLABLE | |
| `performed_by` | `performedBy` | TEXT | NOT NULL | |
| `ip_address` | `ipAddress` | TEXT | NULLABLE | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NOT NULL | |
| `timestamp` | `timestamp` | INTEGER | NOT NULL | |
| `timestamp_iso` | `timestampIso` | TEXT | NOT NULL | |
| `is_financial` | `isFinancial` | BOOLEAN | DEFAULT `false` | |
| `amount_impact` | `amountImpact` | INTEGER | NULLABLE | |

### 2.14 `payment_voids` — `PaymentVoidsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `original_payment_uuid` | `originalPaymentUuid` | TEXT | **UNIQUE، NOT NULL** | |
| `original_payment_id` | `originalPaymentId` | INTEGER | NOT NULL | |
| `booking_uuid` | `bookingUuid` | TEXT | NOT NULL | |
| `voided_amount` | `voidedAmount` | INTEGER | NOT NULL | |
| `void_reason` | `voidReason` | TEXT | NOT NULL | |
| `voided_by` | `voidedBy` | TEXT | NOT NULL | |
| `voided_at` | `voidedAt` | INTEGER | NOT NULL | |
| `voided_at_iso` | `voidedAtIso` | TEXT | NOT NULL | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NOT NULL | |
| `reversal_payment_uuid` | `reversalPaymentUuid` | TEXT | NULLABLE | |
| `approved_by` | `approvedBy` | TEXT | NULLABLE | |
| `note` | `note` | TEXT | NULLABLE | |
| `original_amount` | `originalAmount` | REAL | NULLABLE | |
| `payment_uuid` | `paymentUuid` | TEXT | NULLABLE | |

### 2.15 `guest_infos` — `GuestInfosAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `room_number` | `roomNumber` | TEXT | NOT NULL | |
| `guest_name` | `guestName` | TEXT | NOT NULL | |
| `nationality` | `nationality` | TEXT | NOT NULL | |
| `id_number` | `idNumber` | TEXT | NOT NULL | |
| `id_type` | `idType` | TEXT | DEFAULT `'بطاقة شخصية'` | |
| `issue_date` | `issueDate` | TEXT | NULLABLE | |
| `issue_place` | `issuePlace` | TEXT | NULLABLE | |
| `governorate` | `governorate` | TEXT | NULLABLE | |
| `notes` | `notes` | TEXT | NULLABLE | |
| `entry_date` | `entryDate` | TEXT | NULLABLE | |
| `guest_phone` | `guestPhone` | TEXT | NULLABLE | |

### 2.16 `salary_cycles` — `SalaryCyclesAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `employee_id` | `employeeId` | INTEGER | NOT NULL | **FK** → `employees.id` |
| `employee_uuid` | `employeeUuid` | TEXT | NULLABLE | |
| `cycle_key` | `cycleKey` | TEXT | NOT NULL | مع `employee_id`: **UNIQUE مركّب** |
| `hotel_day_start` | `hotelDayStart` | TEXT | NULLABLE | |
| `hotel_day_end` | `hotelDayEnd` | TEXT | NULLABLE | |
| `expected_amount` | `expectedAmount` | INTEGER | DEFAULT `0` | |
| `actual_paid` | `actualPaid` | INTEGER | DEFAULT `0` | |
| `remaining_amount` | `remainingAmount` | INTEGER | DEFAULT `0` | |
| `status` | `status` | TEXT | DEFAULT `'draft'` | |

### 2.17 `salary_payments` — `SalaryPaymentsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `cycle_id` | `cycleId` | INTEGER | NOT NULL | **FK** → `salary_cycles.id` |
| `employee_uuid` | `employeeUuid` | TEXT | NULLABLE | |
| `cycle_uuid` | `cycleUuid` | TEXT | NULLABLE | |
| `amount` | `amount` | INTEGER | DEFAULT `0` | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NULLABLE | |
| `payment_date_iso` | `paymentDateIso` | TEXT | NOT NULL | |
| `method` | `method` | TEXT | NULLABLE | |
| `is_auto_generated` | `isAutoGenerated` | BOOLEAN | DEFAULT `false` | |

### 2.18 `salary_withdrawals` — `SalaryWithdrawalsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `employee_id` | `employeeId` | INTEGER | NOT NULL | **FK** → `employees.id` |
| `employee_uuid` | `employeeUuid` | TEXT | NULLABLE | |
| `amount` | `amount` | REAL | NOT NULL | |
| `withdraw_date` | `withdrawDate` | TEXT | NOT NULL | |
| `reason` | `reason` | TEXT | NULLABLE | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NULLABLE | |
| `withdrawal_type` | `withdrawalType` | TEXT | NULLABLE | |
| `description` | `description` | TEXT | NULLABLE | |
| `expense_id` | `expenseId` | INTEGER | NULLABLE | |
| `expense_uuid` | `expenseUuid` | TEXT | NULLABLE | **UNIQUE جزئي** (نشطة فقط، غير محذوفة) |
| `recorder_name` | `recorderName` | TEXT | NULLABLE | |

### 2.19 `salary_carry_over_logs` — `SalaryCarryOverLogsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `employee_id` | `employeeId` | INTEGER | NOT NULL | **FK** → `employees.id` |
| `employee_uuid` | `employeeUuid` | TEXT | NULLABLE | |
| `amount` | `amount` | REAL | NOT NULL | |
| `previous_cycle_start` | `previousCycleStart` | TEXT | NOT NULL | |
| `previous_cycle_end` | `previousCycleEnd` | TEXT | NOT NULL | |
| `new_cycle_start` | `newCycleStart` | TEXT | NOT NULL | |
| `new_cycle_end` | `newCycleEnd` | TEXT | NOT NULL | |
| `reason` | `reason` | TEXT | NOT NULL | |
| `carried_at` | `carriedAt` | INTEGER | NOT NULL | |
| `from_cycle_id` | `fromCycleId` | TEXT | NULLABLE | |
| `to_cycle_id` | `toCycleId` | TEXT | NULLABLE | |
| `carry_date` | `carryDate` | TEXT | NULLABLE | |
| `performed_by` | `performedBy` | TEXT | NULLABLE | |
| `hotel_day_key` | `hotelDayKey` | TEXT | NULLABLE | |

### 2.20 `inventory_items` — `InventoryItemsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `name` | `name` | TEXT | **UNIQUE، NOT NULL** | |
| `unit` | `unit` | TEXT | DEFAULT `'قطعة'` | |
| `category` | `category` | TEXT | NULLABLE | |
| `quantity` | `quantity` | INTEGER | DEFAULT `0` | |
| `minimum_quantity` | `minimumQuantity` | INTEGER | DEFAULT `0` | |
| `is_active` | `isActive` | BOOLEAN | DEFAULT `true` | |

### 2.21 `inventory_transactions` — `InventoryTransactionsAdapter`
| العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | ملاحظات |
|---|---|---|---|---|
| `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| `item_local_uuid` | `itemLocalUuid` | TEXT | NULLABLE | |
| `item_id` | `itemId` | INTEGER | NOT NULL | **FK** → `inventory_items.id` |
| `movement_type` | `movementType` | TEXT | NOT NULL | |
| `quantity` | `quantity` | INTEGER | NOT NULL | |
| `balance_after` | `balanceAfter` | INTEGER | NOT NULL | |
| `note` | `note` | TEXT | NULLABLE | |
| `user_id` | `userId` | INTEGER | NULLABLE | |
| `user_name` | `userName` | TEXT | NULLABLE | |

---

## 3. جدول `outbox` (لا يستخدم `SyncFields` — حقوله كلها خاصة به)

**الغرض:** صفّ التغييرات المحلية المعلّقة قبل رفعها إلى Appwrite (Primary) و/أو وجهة ثانوية (Secondary)، مع تتبّع محاولات إعادة الإرسال وحالتها لكل وجهة بشكل مستقل.

| # | العمود (DB) | الحقل (Dart) | النوع | Nullable / Default | الوصف |
|---|---|---|---|---|---|
| 1 | `id` | `id` | INTEGER | PK, AUTOINCREMENT | |
| 2 | `entity` | `entity` | TEXT | NOT NULL | اسم الكيان/الجدول المصدر (مثل `rooms`, `bookings`) |
| 3 | `op` | `op` | TEXT | NOT NULL | نوع العملية: `create` / `update` / `delete` |
| 4 | `local_uuid` | `localUuid` | TEXT | NOT NULL | هوية السجل المصدر |
| 5 | `server_id` | `serverId` | INTEGER | NULLABLE | |
| 6 | `payload` | `payload` | TEXT | NOT NULL | محتوى التغيير بصيغة JSON |
| 7 | `client_ts` | `clientTs` | INTEGER | NOT NULL | طابع زمني العميل عند إنشاء العنصر |
| 8 | `attempts` | `attempts` | INTEGER | DEFAULT `0` | عدد محاولات الإرسال (عام، قديم) |
| 9 | `last_error` | `lastError` | TEXT | NULLABLE | آخر رسالة خطأ (عام، قديم) |
| 10 | `idempotency_key` | `idempotencyKey` | TEXT | NULLABLE | **UNIQUE جزئي** — يمنع تكرار نفس العملية عند إعادة المحاولة بعد timeout |
| 11 | `processing_status` | `processingStatus` | TEXT | DEFAULT `'pending'` | الحالة العامة: `pending` / `failed` / `dead` (عام، قديم) |
| 12 | `processing_started_at` | `processingStartedAt` | INTEGER | NULLABLE | وقت بدء المعالجة الحالية |
| 13 | `processing_worker` | `processingWorker` | TEXT | NULLABLE | معرّف العامل (worker) الذي التقط السجل |
| 14 | `source` | `source` | TEXT | DEFAULT `'local'` | `local` = تغيير مستخدم محلي، `restore` = ناتج عن استعادة نسخة احتياطية |
| 15 | `delivered_to_primary` | `deliveredToPrimary` | BOOLEAN | DEFAULT `false` | تم التسليم للوجهة الرئيسية؟ |
| 16 | `delivered_to_secondary` | `deliveredToSecondary` | BOOLEAN | DEFAULT `true` | تم التسليم للوجهة الثانوية؟ (افتراضياً `true` لتفادي حجب السجلات عند تعطيل Secondary) |
| 17 | `primary_processing_status` | `primaryProcessingStatus` | TEXT | DEFAULT `'pending'` | حالة المعالجة الخاصة بالوجهة الرئيسية |
| 18 | `primary_attempts` | `primaryAttempts` | INTEGER | DEFAULT `0` | عدد محاولات الوجهة الرئيسية |
| 19 | `primary_last_error` | `primaryLastError` | TEXT | NULLABLE | آخر خطأ للوجهة الرئيسية |
| 20 | `secondary_processing_status` | `secondaryProcessingStatus` | TEXT | DEFAULT `'pending'` | حالة المعالجة الخاصة بالوجهة الثانوية |
| 21 | `secondary_attempts` | `secondaryAttempts` | INTEGER | DEFAULT `0` | عدد محاولات الوجهة الثانوية |
| 22 | `secondary_last_error` | `secondaryLastError` | TEXT | NULLABLE | آخر خطأ للوجهة الثانوية |
| 23 | `payload_version` | `payloadVersion` | INTEGER | DEFAULT `1` | يزداد عند كل تحديث لـ `payload`/`op`/`client_ts` عبر `merge()` — يمنع تأكيدات فائتة (stale ack) |
| 24 | `processing_payload_version` | `processingPayloadVersion` | INTEGER | NULLABLE | قيمة `payload_version` عند الالتقاط (claim) — تُقارَن عند التأكيد لرفض التأكيدات القديمة |

### فهارس `outbox` (`lib/services/local_db.dart`)

| اسم الفهرس | الأعمدة | الغرض |
|---|---|---|
| `idx_outbox_status` | `processing_status` | تسريع جلب السجلات حسب الحالة العامة |
| `idx_outbox_entity_status` | `entity, op, processing_status` | تسريع البحث حسب الكيان والعملية |
| `idx_outbox_uuid_pending` | `entity, local_uuid, processing_status` | إيجاد السجلات المعلّقة لكيان محدد بسرعة |
| `idx_outbox_client_ts` | `client_ts` | الترتيب الزمني |
| `idx_outbox_processing_started` | `processing_status, processing_started_at` | اكتشاف السجلات العالقة (stuck) في المعالجة |
| `idx_outbox_source_status` | `source, processing_status` | التمييز بين تغييرات `local` و `restore` |
| `idx_outbox_delivery_primary` | `delivered_to_primary, processing_status` | ما لم يُسلَّم بعد للوجهة الرئيسية |
| `idx_outbox_delivery_secondary` | `delivered_to_secondary, processing_status` | ما لم يُسلَّم بعد للوجهة الثانوية |
| `idx_outbox_pending_primary_source_ts` | `source, client_ts` (شرطي: `pending` و `delivered_to_primary = 0`) | استعلام سريع لقائمة الإرسال المعلّقة للرئيسي |

---

## 4. جدول مرجعي سريع — ربط المحوّل بجدوله واسم الـ Repository

| المحوّل (Adapter) | ملف المصدر | جدول Drift | اسم الجدول في SQLite |
|---|---|---|---|
| `RoomsAdapter` | `rooms_adapter.dart` | `Rooms` | `rooms` |
| `BookingsAdapter` | `bookings_adapter.dart` | `Bookings` | `bookings` |
| `BookingNotesAdapter` | `booking_notes_adapter.dart` | `BookingNotes` | `booking_notes` |
| `EmployeesAdapter` | `employees_adapter.dart` | `Employees` | `employees` |
| `ExpensesAdapter` | `expenses_adapter.dart` | `Expenses` | `expenses` |
| `CashTransactionsAdapter` | `cash_transactions_adapter.dart` | `CashTransactions` | `cash_transactions` |
| `PaymentsAdapter` | `payments_adapter.dart` | `Payments` | `payments` |
| `DebtsAdapter` | `debts_adapter.dart` | `Debts` | `debts` |
| `ShiftNotesAdapter` | `shift_notes_adapter.dart` | `ShiftNotes` | `shift_notes` |
| `NightsAdapter` | `nights_adapter.dart` | `BookingNights` | `booking_nights` |
| `PriceAdjustmentsAdapter` | `price_adjustments_adapter.dart` | `PriceAdjustments` | `price_adjustments` |
| `BookingPriceAdjustmentsAdapter` | `booking_price_adjustments_adapter.dart` | `BookingPriceAdjustments` | `booking_price_adjustments` |
| `AuditLogsAdapter` | `audit_logs_adapter.dart` | `AuditLogs` | `audit_logs` |
| `PaymentVoidsAdapter` | `payment_voids_adapter.dart` | `PaymentVoids` | `payment_voids` |
| `GuestInfosAdapter` | `guest_infos_adapter.dart` | `GuestInfos` | `guest_infos` |
| `SalaryCyclesAdapter` | `salary_cycles_adapter.dart` | `SalaryCycles` | `salary_cycles` |
| `SalaryPaymentsAdapter` | `salary_payments_adapter.dart` | `SalaryPayments` | `salary_payments` |
| `SalaryWithdrawalsAdapter` | `salary_withdrawals_adapter.dart` | `SalaryWithdrawals` | `salary_withdrawals` |
| `SalaryCarryOverLogsAdapter` | `salary_carry_over_logs_adapter.dart` | `SalaryCarryOverLogs` | `salary_carry_over_logs` |
| `InventoryItemsAdapter` | `inventory_adapter.dart` | `InventoryItems` | `inventory_items` |
| `InventoryTransactionsAdapter` | `inventory_adapter.dart` | `InventoryTransactions` | `inventory_transactions` |
| *(لا محوّل مخصّص — Outbox يُدار عبر `OutboxDao`)* | `lib/services/daos/outbox_dao.dart` | `Outbox` | `outbox` |

---

*تم استخراج هذه الوثيقة مباشرة من تعريفات Drift الفعلية (`local_db.dart` + `local_db.g.dart`) وسجل المحوّلات (`adapter_registry.dart`) بتاريخ 2026-11-28، لضمان مطابقتها لمخطط قاعدة البيانات الحالي حرفياً.*
