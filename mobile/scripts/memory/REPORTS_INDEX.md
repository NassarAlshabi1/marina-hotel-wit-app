# 📚 فهرس تقارير المزامنة - Marina Hotel Mobile

> **جميع تقارير المزامنة في مكان واحد**

**تاريخ التحديث:** 2026-06-27  
**المسار:** `mobile/scripts/`

---

## 📋 التقارير المتوفرة

| # | التقرير | المجموعة | الحقول | السجلات على Cloud | الحالة |
|---|---------|---------|--------|------------------|--------|
| 1 | [ROOMS_SYNC_REPORT.md](../ROOMS_SYNC_REPORT.md) | `rooms` | 28 | 20 | ✅ مكتمل |
| 2 | [BOOKINGS_SYNC_REPORT.md](../BOOKINGS_SYNC_REPORT.md) | `bookings` | 39 | 215 | ✅ مكتمل |
| 3 | [PAYMENTS_SYNC_REPORT.md](../PAYMENTS_SYNC_REPORT.md) | `payments` | 38 | 689 | ✅ مكتمل |
| 4 | [EXPENSES_SYNC_REPORT.md](../EXPENSES_SYNC_REPORT.md) | `expenses` | 28 | 1199 | ✅ مكتمل |
| 5 | [DEBTS_SYNC_REPORT.md](../DEBTS_SYNC_REPORT.md) | `debts` | 43 | 4 | ✅ مكتمل |
| 6 | [BOOKING_NOTES_SYNC_REPORT.md](../BOOKING_NOTES_SYNC_REPORT.md) | `booking_notes` | 24 | 0 | ✅ مكتمل |
| 7 | [CASH_TRANSACTIONS_SYNC_REPORT.md](../CASH_TRANSACTIONS_SYNC_REPORT.md) | `cash_transactions` | 31 | 0 | ✅ مكتمل |
| 8 | [SHIFT_NOTES_SYNC_REPORT.md](../SHIFT_NOTES_SYNC_REPORT.md) | `shift_notes` | 34 | 1 | ✅ مكتمل |
| 9 | [SALARY_WITHDRAWALS_SYNC_REPORT.md](../SALARY_WITHDRAWALS_SYNC_REPORT.md) | `salary_withdrawals` | 33 | 371 | ✅ مكتمل |
| 10 | [SALARY_PAYMENTS_SYNC_REPORT.md](../SALARY_PAYMENTS_SYNC_REPORT.md) | `salary_payments` | 30 | 0 | ✅ مكتمل |
| 11 | [BOOKING_PRICE_ADJUSTMENTS_SYNC_REPORT.md](../BOOKING_PRICE_ADJUSTMENTS_SYNC_REPORT.md) | `booking_price_adjustments` | 32 | 56 | ✅ مكتمل |
| 12 | [PAYMENT_VOIDS_SYNC_REPORT.md](../PAYMENT_VOIDS_SYNC_REPORT.md) | `payment_voids` | 40+ | 4 | ✅ مكتمل |
| 13 | [GUEST_INFOS_SYNC_REPORT.md](../GUEST_INFOS_SYNC_REPORT.md) | `guest_infos` | 27 | 75 | ✅ مكتمل |
| 14 | [APP_SETTINGS_SYNC_REPORT.md](../APP_SETTINGS_SYNC_REPORT.md) | `app_settings` | 50+ | 1 | ✅ مكتمل |

---

## 📊 الإحصائيات الإجمالية

| البند | القيمة |
|-------|-------|
| **عدد المجموعات الموثّقة** | 14 مجموعة |
| **إجمالي الحقول الموثّقة** | 450+ حقل |
| **إجمالي السجلات على Cloud** | 2600+ سجل |
| **آخر تحديث شامل** | 2026-06-27 |

---

## 🧠 المراجع

| المرجع | المسار | الوصف |
|--------|--------|------|
| **المرجع الشامل** | [memory/PROJECT_MEMORY.md](PROJECT_MEMORY.md) | مرجع كامل لكل القرارات المعمارية |
| **المرجع السريع** | [memory/QUICK_REFERENCE.md](QUICK_REFERENCE.md) | وصول سريع للمعلومات الحرجة |
| **الفهرس** | [memory/REPORTS_INDEX.md](REPORTS_INDEX.md) | هذا الملف — فهرس كل التقارير |

---

## 📝 كيفية استخدام التقارير

### عند إضافة حقل جديد إلى Cloud
1. افحص Appwrite Cloud للتأكد من وجود الحقل
2. أضفه إلى `validFieldsPerCollection[collectionId]` في `appwrite_sync_utils.dart`
3. حدّث التقرير المناسب في `*_SYNC_REPORT.md`
4. أضف سجل تغييرات في التقرير
5. شغّل `flutter analyze` للتأكد من النظافة

### عند إنشاء تقرير جديد
1. استخدم نفس بنية التقارير الموجودة
2. أضف قسم "الحقول المطلوبة (REQUIRED)"
3. أضف قسم "الحقول الاختيارية (OPTIONAL)"
4. أضف قسم "ملاحظات مهمة"
5. أضف قسم "سجل التغييرات"
6. أضف التقرير إلى هذا الفهرس

---

## 🔄 ترتيب التحديث (الأحدث أولاً)

| التاريخ | المجموعة | التحديث |
|---------|---------|---------|
| 2026-06-27 | cash_transactions, shift_notes, salary_payments | إزالة sync_version/sync_vector_clock + إضافة حقول |
| 2026-06-27 | booking_notes, rooms, payment_voids | إزالة sync_version/sync_vector_clock + إضافة حقول |
| 2026-06-27 | debts, expenses | إضافة حقول مفقودة |
| 2026-06-27 | guest_infos, booking_price_adjustments | إضافة حقول مفقودة |
| 2026-06-27 | payments | إنشاء validFieldsPerCollection كاملة |
| 2026-06-27 | app_settings | إضافة 30+ حقل مفقود |
| 2026-06-27 | bookings | إضافة financialFrozenAt, financialHash, sync_origin, syncTimestamp, idempotencyKey, id |
| 2026-06-27 | salary_withdrawals | إضافة withdrawDate, withdrawalType, description, hotelDayKey, reason |

---

**آخر تحديث:** 2026-06-27  
**المُنسق:** Marina Hotel Agent
