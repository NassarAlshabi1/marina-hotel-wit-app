package com.marina.marina.data.sync

/**
 * ✅ (2026-10-06) أسماء الحقول بين السلك (Cloudflare D1 / Flutter Drift) والحقل
 * المحلي في أندرويد — **مصدر حقيقة واحد في الاتجاهين**.
 *
 * سبب وجود هذا الملف (عطل مُثبت بالقياس لا اجتهاد): مقارنة آلية بين أعمدة
 * `worker/schema.sql` وأعمدة كيانات Room الـ24 أظهرت **14 عموداً خادمياً بلا
 * عمود محلي**؛ بعضها اختلاف تسمية فقط، والخادم يتبع مخطط Flutter (Drift)
 * الحرفي:
 *
 * | الكيان | السلك (وFlutter) | أندرويد المحلي |
 * | --- | --- | --- |
 * | `inventory_items` | `quantity` | `current_quantity` |
 * | `inventory_transactions` | `movement_type` | `transaction_type` |
 * | `blacklist` | `guest_name` / `guest_id_number` / `guest_phone` / `is_active` | `name` / `national_id` / `phone` / `active` |
 *
 * الأثر قبل الإصلاح:
 *  • **السحب**: القيم تُهمل صامتة (الكمية تُخزَّن 0، النوع يفقد قيمته)، وكان
 *    غياب `transaction_type` (عمود NOT NULL بلا مقابل خادمي) يُفشل تطبيق الصف
 *    فيتجمّد مؤشر الدلتا كلها — أي «الدلتا لا تسحب جدولاً ولا حقلاً».
 *  • **الرفع**: الخادم يفلتر الأعمدة غير المعروفة، فـ`current_quantity`
 *    و`transaction_type` تُسقَط صامتة ويبقى العمود الخادمي على صفر/فراغ.
 *
 * لذلك الاتجاهان هنا معاً: [localAliases] عند الاستيعاب، و[toWire] عند
 * بناء حمولة الـoutbox.
 */
object SyncWireFields {

    /** حقل السلك → الحقل المحلي (اتجاه السحب/الاستيعاب). */
    val localAliases: Map<String, Map<String, String>> = mapOf(
        "inventory_items" to mapOf("quantity" to "current_quantity"),
        "inventory_transactions" to mapOf(
            "movement_type" to "transaction_type",
            // لا عمود `transaction_time` على السلك إطلاقاً (`worker/schema.sql`
            // وFlutter Drift: الترتيب بـ`created_at`)، فالصف المسحوب كانت
            // تُكتب فيه 0 وتفقد ترتيبها الزمني في الشاشات — يُغذّى من
            // `created_at` عند غيابه فقط.
            "created_at" to "transaction_time"
        ),
        "blacklist" to mapOf(
            "guest_name" to "name",
            "guest_id_number" to "national_id",
            "guest_phone" to "phone",
            "is_active" to "active"
        )
    )

    /** حقول تُقابل Boolean محلياً: تُقبل 0/1 أو "true"/"false" أو Boolean. */
    val booleanTargets: Set<String> = setOf("blacklist.active")

    /**
     * ✅ (2026-10-06) افتراضيات الحقول **غير القابلة للـnull** حين يغيب العمود
     * عن الصفّ الواصل أو يصل `null` — نظير `?? fallback` في محوّلات Dart
     * (`inventory_adapter.dart`: `unit: ... ?? 'قطعة'`، `employees_adapter`:
     * `position: ... ?? 'موظف'`، `booking_notes_adapter`: `isActive: ... ?? 1`).
     *
     * العطل الذي أُغلق بهذا: Gson يترك حقل Kotlin غير القابل للـnull بقيمة
     * `null` (لا يستدعي القيمة الافتراضية المُعلنة في المُنشئ)، وRoom يرفض
     * الإدراج لقيد NOT NULL ⇒ الصف **يُعزل كاملاً** ولو كان كل ما فيه سليماً
     * سوى عمود واحد غاب. القياس: `inventory_items` بلا `unit` يفشل،
     * `blacklist` بلا `reported_by` يفشل، `salary_withdrawals` بلا
     * `withdrawal_type` يفشل — أي «لا تُسحب الجداول ولا الحقول» بحرفها.
     *
     * الفرق عن Dart: القيم مأخوذة من مخطط D1 (`worker/schema.sql`) ومحوّلات
     * Dart، وليست قيم مُنشئ Room (مثال: `employees.position` افتراضيه في
     * Kotlin `"-employed"` بينما Dart والدليل الخادمي `"موظف"` — فالمأخوذ
     * هو الأخير).
     *
     * ملاحظة: `version`/`origin` وبقية حقول [BaseSyncEntity] يعالجها
     * `applyBaseDefaults` في المستوعب، فلا تُكرَّر هنا.
     */
    val entityDefaults: Map<String, Map<String, Any>> = mapOf(
        // قيم مُثبتة حرفياً من محوّلات Dart (fallback:) — لا اجتهاد:
        "inventory_items" to mapOf("unit" to "قطعة", "is_active" to true),
        "employees" to mapOf("position" to "موظف", "phone" to "", "hire_date" to "", "status" to ""),
        "rooms" to mapOf("cleaning_status" to "clean", "status" to ""),
        "bookings" to mapOf(
            "guest_id_type" to "بطاقة شخصية", "discount_type" to "per_night", "status" to "",
            "expected_nights" to 1, "calculated_nights" to 1
        ),
        "guest_infos" to mapOf("id_type" to "بطاقة شخصية"),
        "salary_cycles" to mapOf("status" to "draft"),
        "salary_withdrawals" to mapOf("withdrawal_type" to "سحب راتب", "employee_name" to ""),
        "booking_notes" to mapOf("is_active" to 1),
        "booking_price_adjustments" to mapOf("is_active" to true),
        "price_adjustments" to mapOf("adjustment_mode" to "per_night"),
        // نظير `movementType: ... ?? 'adjustment'` في `inventory_adapter.dart`
        // (الفرع المرجعي). يُملأ المفتاحان معاً: مفتاح السلك `movement_type`
        // (كما في Dart) ومفتاحه المحلي `transaction_type` — لأن
        // `applyLocalAliases` ينسخ من السلك إلى المحلي **فقط إن وُجد** مفتاح
        // السلك، فغيابه الكامل يترك العمود المحلي NOT NULL بلا قيمة.
        "inventory_transactions" to mapOf(
            "movement_type" to "adjustment", "transaction_type" to "adjustment"
        ),
        "shift_notes" to mapOf("priority" to "medium", "shift_type" to "all", "created_by" to "user", "is_read" to 0),
        // كيانات بلا محوّل Dart (تُسحب عندنا فقط) — القيمة من مُنشئ Room
        // نفسه (وهي القيمة التي تحملها قاعدة Flutter محلياً في جدولها):
        "blacklist" to mapOf("reported_by" to "police", "active" to true),
        "devices" to mapOf("status" to "active", "is_active" to true),
        "app_users" to mapOf("active" to true)
    )

    /**
     * يملأ الحقول التي غاب مفتاحها **أو وصلت `null`** بافتراضياتها المحلية
     * (نظير `?? default` في Dart: القيمة الغائبة والقيمة `null` سيان، أما
     * الفراغ المعلن `""` فقيمة صريحة لا تُستبدل).
     *
     * **الحد المقصود**: لا يُلفَّق صفر مكان قيمة مالية («٠ ريال» ليست معلومة
     * صحيحة). القيم المالية/العددية غير المُدرَجة أعلاه تبقى على سلوكها:
     * الصف يُعزل بحمولته — وهذا صار آمناً لأن المؤشر يتقدّم (لا تجميد)، ويُعاد
     * حلّه من الحمولة إن وصلت قيمة صحيحة لاحقاً.
     */
    fun applyWireDefaults(entity: String, mapped: MutableMap<String, Any>) {
        val defaults = entityDefaults[entity] ?: return
        for ((key, value) in defaults) {
            if (mapped[key] == null) mapped[key] = value
        }
    }

    /**
     * الحقل المحلي → أسماء السلك التي يجب أن تحمل القيمة نفسها عند الرفع.
     * (لا تُحذف الأسماء المحلية من الحمولة: الخادم يفلتر غير المعروف،
     * وإبقاؤها يجعل الصف مقروءاً في سجلات التشخيص.)
     */
    val wireMirrors: Map<String, Map<String, String>> = mapOf(
        "inventory_items" to mapOf("current_quantity" to "quantity"),
        "inventory_transactions" to mapOf("transaction_type" to "movement_type"),
        "blacklist" to mapOf("active" to "is_active")
    )

    private fun booleanify(value: Any?): Any? = when (value) {
        is Boolean -> value
        is Number -> value.toLong() != 0L
        is String -> value == "1" || value.equals("true", ignoreCase = true)
        else -> value
    }

    /**
     * ينقل القيم الخادمية إلى أسمائها المحلية **فقط** إذا كان المحلي غائباً
     * أو فارغاً (لا نطمس قيمة محلية أدق). الأسماء الخادمية تبقى في الخريطة:
     * Gson يتجاهل غير المعروف، ويستفيد منها منطق حلّ المراجع لاحقاً.
     */
    fun applyLocalAliases(entity: String, mapped: MutableMap<String, Any>) {
        val aliases = localAliases[entity] ?: return
        for ((wire, local) in aliases) {
            val incoming = mapped[wire] ?: continue
            val current = mapped[local]
            val currentIsBlank = current == null || (current as? String)?.isBlank() == true
            if (!currentIsBlank) continue
            mapped[local] =
                if ("$entity.$local" in booleanTargets) booleanify(incoming) ?: incoming else incoming
        }
    }

    /**
     * حمولة الرفع بأسماء السلك: تُضاف الأسماء الخادمية المرادفة بجانب المحلية
     * كي لا يفلترها الخادم كأعمدة غير معروفة. حمولة null/غير الرقمية تُترك كما
     * هي (لا يُكتب صفر مكان قيمة غائبة).
     */
    fun toWire(entity: String, payload: Map<String, Any>): Map<String, Any> {
        val mirrors = wireMirrors[entity] ?: return payload
        var out: MutableMap<String, Any>? = null
        for ((local, wire) in mirrors) {
            val value = payload[local] ?: continue
            if (out == null) out = payload.toMutableMap()
            out[wire] = value
        }
        return out ?: payload
    }
}
