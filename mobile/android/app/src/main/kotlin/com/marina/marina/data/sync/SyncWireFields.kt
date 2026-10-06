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
