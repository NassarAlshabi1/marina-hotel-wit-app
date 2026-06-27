# ⚡ مرجع سريع - Marina Hotel Mobile

> **للوصول السريع عند الحاجة — التفاصيل في `PROJECT_MEMORY.md`**

---

## 🔑 معلومات الاتصال

```
Endpoint:    https://fra.cloud.appwrite.io/v1
Project ID:  690ff0da0025518570c1
Database ID: hotel_db
Branch:      marina
Flutter:     3.35.7
Dart:        3.9.2
```

---

## 📁 الملفات الحرجة

| الملف | الوظيفة |
|------|--------|
| `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` ← مصدر الحقيقة للحقول |
| `lib/services/appwrite_sync_manager.dart` | مدير المزامنة الرئيسي |
| `lib/services/appwrite_service.dart` | عميل Appwrite + Failover |
| `lib/services/daos/outbox_dao.dart` | إدارة outbox (dual-delivery) |
| `lib/services/local_db.dart` | تعريف قاعدة البيانات (schema v44) |
| `lib/services/secondary_sync_manager.dart` | مدير المزامنة الثانوية |
| `lib/services/appwrite_health_checker.dart` | فحص صحة الوجهتين |

---

## 🚦 قواعد سريعة

### ✅ افعَل
- أضف كل حقل على Cloud إلى `validFieldsPerCollection`
- استخدم `version` و `vectorClock` (وليس sync_version/sync_vector_clock)
- استخدم `markDeliveredToPrimary/Secondary` (وليس removeById)
- اجعل `flutter analyze` نظيفاً دائماً
- وثّق الحقول في `*_SYNC_REPORT.md`

### ❌ لا تفعل
- لا تحذف سجلات outbox مباشرة بعد Secondary فقط
- لا ترسل حقول غير موجودة على Cloud
- لا تستخدم `sync_version` أو `sync_vector_clock`
- لا تخلط بين `note` (ملاحظة المستخدم) و `reason` (سبب السحب)
- لا تستخدم `== true` للقيم null bool — استخدم `?? false`

---

## 🔄 تدفّق المزامنة السريع

```
تغيير محلي → outbox.merge()
         → _pushAllEntities()
         → takeBatch(delivered_to_primary = 0)
         → _xxxToRemote() + sanitizePayload()
         → filterPayloadForCollection(validFieldsPerCollection)
         → appwriteService.upsertXxx()
         → markDeliveredToPrimary()
         → إذا Secondary مُفعّل: SecondarySyncManager.sync()
         → markDeliveredToSecondary()
         → إذا كلاهما true: 🗑️ حذف تلقائي
```

---

## ☁️ Failover السريع

```
Primary معطّل + Secondary مُفعّل (Pull) → قراءة من Secondary تلقائياً
الكتابة دائماً عبر outbox (لا Failover للكتابة)
```

---

## 📊 عدد الحقول لكل مجموعة

| المجموعة | الحقول | التقرير |
|---------|--------|---------|
| rooms | 28 | ROOMS_SYNC_REPORT.md |
| bookings | 39 | BOOKINGS_SYNC_REPORT.md |
| payments | 38 | PAYMENTS_SYNC_REPORT.md |
| expenses | 28 | EXPENSES_SYNC_REPORT.md |
| debts | 43 | DEBTS_SYNC_REPORT.md |
| salary_withdrawals | 33 | SALARY_WITHDRAWALS_SYNC_REPORT.md |
| salary_payments | 30 | SALARY_PAYMENTS_SYNC_REPORT.md |
| cash_transactions | 31 | CASH_TRANSACTIONS_SYNC_REPORT.md |
| shift_notes | 34 | SHIFT_NOTES_SYNC_REPORT.md |
| booking_notes | 24 | BOOKING_NOTES_SYNC_REPORT.md |
| booking_price_adjustments | 32 | BOOKING_PRICE_ADJUSTMENTS_SYNC_REPORT.md |
| payment_voids | 40+ | PAYMENT_VOIDS_SYNC_REPORT.md |
| guest_infos | 27 | GUEST_INFOS_SYNC_REPORT.md |
| app_settings | 50+ | APP_SETTINGS_SYNC_REPORT.md |

---

## 🛠️ أوامر مفيدة

```bash
# تشغيل flutter analyze
flutter analyze

# تشغيل build_runner (بعد تعديل local_db.dart)
dart run build_runner build --delete-conflicting-outputs

# دفع التغييرات
git add -A && git commit -m "..." && git push origin marina

# مراقبة GitHub Actions
curl -s -H "Authorization: token ghp_..." \
  "https://api.github.com/repos/NassarAlshabi1/marina-hotel-wit-app/actions/runs?branch=marina&per_page=5"
```

---

## 🎯 آخر التزامات مهمة

- `91a3c219` — إزالة نهائية لـ sync_version/sync_vector_clock + cash_transactions/shift_notes/salary_payments
- `41541f38` — إزالة sync_version/sync_vector_clock + booking_notes/rooms/payment_voids
- `fe253fb7` — إضافة حقول debts و expenses
- `91a3c219` — آخر حالة مستقرة

---

**آخر تحديث:** 2026-06-27
