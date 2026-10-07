package com.marina.marina.data.sync

/**
 * ✅ (2026-10-06) وحدة عقد الطوابع الزمنية على السلك — **ثوانٍ لا ميلي ثانية**.
 *
 * القياس الذي كشف العطل: المرجع الدارتي يختم حقول المزامنة بـ
 * `Time.nowEpoch()` = `millisecondsSinceEpoch ~/ 1000` (`mobile/lib/utils/time.dart:8`)،
 * وأعمدة D1 تُختم في الـ Worker بنفس الوحدة (`Math.floor(Date.now()/1000)`)،
 * بينما طبقة البيانات عندنا كانت تختم `last_modified` بـ
 * `System.currentTimeMillis()` (ميلي ثانية) في مواضع عدة.
 *
 * الأثر المقيس بقراءة الشيفرة (لا اجتهاد):
 *  • **رفض تحديثات الخادم**: قرار «آخر كتابة تفوز» في `SyncIngestorRegistry`
 *    يقارن `remote.last_modified` (ثوانٍ، ~1.76e9) بـ`existing.last_modified`
 *    المحلي (ميلي، ~1.77e12) ⇒ الخادم يخسر دائماً ⇒ ذلك الصف **لا يستقبل أي
 *    تحديث من السحابة بعد أول لمسة محلية** (والصف نفسه لا يعرف أنه قديم).
 *  • **تلويث D1**: الـ Worker ينسخ حمولة العميل حرفياً (`createRecord`:
 *    `if (!record.last_modified) … = now` — أي يترك ما أرسله العميل)، فطابعنا
 *    الميلي يُكتب في D1 ثم يُقارن على الأجهزة الأخرى (Flutter) بثوانيها
 *    فيفوز عليها دائماً بلا سبب حقيقي.
 *  • **عتبات الـ Worker**: `MS_TIMESTAMP_THRESHOLD = 1e11` و
 *    `FUTURE_TIMESTAMP_THRESHOLD = 2e9` (`worker/src/database.ts:603/614`) —
 *    أي أن كل قيمة ≥ 1e11 تُصنَّف «مسمومة» عنده، وإصلاحه الذاتي
 *    (`reStampPoisoned`) لا يعمل إلا إذا كان `updated_at` نفسه فوق العتبة،
 *    وحمولتنا كانت تُرسل `updated_at` بالسليمة (ثوانٍ) و`last_modified`
 *    بالميلي ⇒ **لا يُكتشف ولا يُصلَّح**.
 *
 * لذلك هذا الملف هو نقطة واحدة للعقد في الاتجاهين: [nowSeconds] للكتابة
 * المحلية، و[normalizeWireEpochFields] على الحدود (سحب/رفع).
 *
 * ⚠️ النطاق: أعمدة الطوابع الأربعة الأساسية + عمودَي `*_epoch` المساعدين.
 * أعمدة **الأعمال** (مثل `checkin_date`/`hotel_day_key`/`transaction_time`)
 * تبقى بوحدتها الحالية (ميلي ثانية) — لا تلمسها هذه الطبقة.
 */
object SyncEpochs {

    /**
     * عتبة تمييز الميلي ثانية — نفس قيمة الـ Worker
     * (`Database.MS_TIMESTAMP_THRESHOLD = 100_000_000_000`) ونفس
     * `PushWireContract.MILLIS_EPOCH_THRESHOLD`. أي ثوانٍ شرعية (حتى سنة 5138)
     * أقل منها، وأي ميلي ثانية (بعد 1973) أعلى منها.
     */
    const val MILLIS_THRESHOLD: Long = 100_000_000_000L

    /** سقف «مستقبلي» مطابق للـ Worker: فوقه الطابع مسموم لا مؤشّر. */
    const val FUTURE_THRESHOLD: Long = 2_000_000_000L

    /** الأعمدة التي تُطبَّع وحدتها على الحدّين (سحب/رفع). */
    val WIRE_EPOCH_FIELDS: Set<String> = setOf(
        "created_at",
        "updated_at",
        "deleted_at",
        "last_modified",
        "created_at_epoch",
        "last_modified_epoch"
    )

    /**
     * الوقت الحالي بالثواني — نظير `Time.nowEpoch()` في المرجع الدارتي.
     * تُستعمل في كل كتابة محلية لحقول المزامنة.
     */
    fun nowSeconds(): Long = System.currentTimeMillis() / 1_000L

    /** هل القيمة تُقرأ كميلي ثانية؟ (القيم الغائبة/الصفرية لا تُلمس). */
    fun isMillisLike(value: Long?): Boolean =
        value != null && value > MILLIS_THRESHOLD

    /**
     * يوحّد الطابع إلى ثوانٍ: الميلي يُقسَم على 1000، والثواني تبقى كما هي
     * (والقيم غير الصالحة/الصفرية تُعاد كما هي — لا نُخمّن مكان غياب معلومة).
     */
    fun toSeconds(value: Long?): Long? = when {
        value == null -> null
        value > MILLIS_THRESHOLD -> value / 1_000L
        else -> value
    }

    /**
     * يطبّع حقول الطوابع في سجل واصل من الشبكة **في مكانه** — يُنادى قبل
     * بناء الكيان (Gson) وقبل قرار LWW، فيصبح ما يُخزَّن محلياً بالثواني
     * أيضاً (صفوف D1 المسمومة تُشفي نفسها عند أول سحب).
     *
     * المقايضة المقصودة: يُقبل أي `Number` (Int/Long/Double) كما يرسله Gson.
     */
    fun normalizeWireEpochFields(mapped: MutableMap<String, Any>) {
        for (field in WIRE_EPOCH_FIELDS) {
            val raw = mapped[field]
            val asLong = when (raw) {
                is Number -> raw.toLong()
                is String -> raw.trim().toLongOrNull()
                else -> null
            } ?: continue
            if (!isMillisLike(asLong)) continue
            // يحافظ على نوع القيمة الأصلي قدر الإمكان (Gson يقرأ JSON number).
            mapped[field] = if (raw is Int || raw is Double) {
                (asLong / 1_000L).toDouble()
            } else {
                asLong / 1_000L
            }
        }
    }

    /**
     * يطبّع مفاتيح الطوابع في حمولة رفع (map اسمه snake_case أصلاً أو بعد
     * التحويل) — يمنع تلويث D1 لبقية الأجهزة. لا يعيد بناء الخريطة:
     * يُعدّل النسخة القابلة للتعديل.
     */
    fun normalizeOutgoingEpochFields(data: MutableMap<String, Any>) {
        for (field in WIRE_EPOCH_FIELDS) {
            val raw = data[field]
            val asLong = when (raw) {
                is Number -> raw.toLong()
                is String -> raw.trim().toLongOrNull()
                else -> null
            } ?: continue
            if (!isMillisLike(asLong)) continue
            data[field] = asLong / 1_000L
        }
    }
}
