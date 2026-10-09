# 📇 دليل تحسين الفهارس في Appwrite Cloud

> **التاريخ:** 4 فبراير 2026  
> **المشروع:** Marina Hotel  
> **Database:** hotel_db

---

## 🎯 الهدف

تحسين أداء قاعدة البيانات عن طريق:
- إزالة الفهارس غير الضرورية (Over-Indexing)
- الإبقاء على الفهارس المستخدمة فعلياً فقط
- تقليل كلفة الكتابة (insert/update)

---

## 📊 النتائج

| المقياس | قبل | بعد | التحسين |
|---------|-----|-----|---------|
| إجمالي الفهارس | 58 | 39 | -33% |
| Business Tables | ~45 | 30 | -33% |
| Small Tables | ~10 | 6 | -40% |
| System Tables | ~13 | 3 | -77% |

---

## 📋 التوزيع النهائي

### Business Tables (3-5 فهارس)

| الجدول | الفهارس | الحالة |
|--------|---------|--------|
| rooms | 5 | ✅ |
| bookings | 5 | ✅ |
| payments | 5 | ✅ |
| expenses | 4 | ✅ |
| employees | 4 | ✅ |
| debts | 4 | ✅ |
| cash_transactions | 3 | ✅ |

### Small Tables (1 فهرس)

| الجدول | الفهارس | الحالة |
|--------|---------|--------|
| booking_notes | 1 | ✅ |
| booking_nights | 1 | ✅ |
| salary_cycles | 1 | ✅ |
| salary_payments | 1 | ✅ |
| shift_notes | 1 | ✅ |
| hotel_day_ledger | 1 | ✅ |

### System/Runtime Tables (1-2 فهرس)

| الجدول | الفهارس | الحالة |
|--------|---------|--------|
| devices | 1 | ✅ |
| sync_logs | 2 | ✅ |

---

## ✅ الفهارس الموصى بها (لكل Collection أساسي)

| الفهرس | النوع | السبب |
|--------|-------|-------|
| `localUuid` | Unique | Identity - المعرف الفريد |
| `lastModifiedEpoch` | Key | Delta Sync - المزامنة التفاضلية |
| `deletedAt` | Key | Soft Delete - الحذف الناعم |
| (اختياري) فهرس UI واحد | Key | Query فعلي من الواجهة |

---

## ❌ فهارس لا تحتاجها (تجنّبها)

| الفهرس | السبب |
|--------|-------|
| `serverId` | لا يُستخدم في queries |
| `createdAt` | نادراً ما يُفلتر عليه |
| `updatedAtIso` | مكرر مع lastModifiedEpoch |
| `vectorClock` | للمقارنة فقط، لا للفلترة |
| `localUuid + lastModifiedEpoch` (composite) | غير ضروري إذا كان كل منهما موجود |

---

## 🔧 القاعدة الذهبية

> **أضف فهرس فقط إذا كان هناك Query فعلي يستخدمه**

❌ ليس لأنه "موجود في SQLite"  
❌ ليس لأننا "قد نحتاجه لاحقاً"  
✅ فقط إذا كان هناك استعلام حقيقي

---

## 📈 فوائد التحسين

1. **كتابة أسرع** - كل insert/update يحدّث فهارس أقل
2. **استهلاك أقل للموارد** - مساحة تخزين أقل
3. **صيانة أسهل** - فهارس واضحة ومفهومة
4. **كلفة أقل** - في Appwrite Cloud

---

## 🔍 كيفية التحقق

```bash
# تشغيل سكربت التحقق
APPWRITE_API_KEY="your-key" node verify_collections.js
```

---

## 📝 ملاحظات

- **devices**: جدول runtime، لا يحتاج فهارس كثيرة
- **sync_logs**: append-only، فهرس timestamp كافٍ
- **Small tables**: تُستخدم عبر العلاقات، localUuid كافٍ

---

## 🏁 الخلاصة

| الفئة | الحد الأقصى المقترح |
|-------|---------------------|
| Business Collections | 4-5 فهارس |
| Small/Lookup Tables | 1-2 فهرس |
| System/Runtime Tables | 1-2 فهرس |

**Appwrite يحب القِلّة المدروسة، لا الكثرة.**
