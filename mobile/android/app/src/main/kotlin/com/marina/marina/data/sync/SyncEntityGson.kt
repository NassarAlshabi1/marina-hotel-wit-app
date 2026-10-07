package com.marina.marina.data.sync

import com.google.gson.ExclusionStrategy
import com.google.gson.FieldAttributes
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import java.util.concurrent.ConcurrentHashMap

/**
 * ✅ (2026-10-07) Gson واعٍ **بظلّ الحقول** في كيانات Room — نقطة واحدة
 * لكل التسلسل (الرفع والاستيعاب).
 *
 * العطل المقيس (كشفه الاختبار الجديد `RepositoryEpochParityTest` في CI): كل
 * كيان يرث [com.marina.marina.data.local.entity.BaseSyncEntity] **يعيد تعريف**
 * حقول الأساس (`id`, `local_uuid`, …) بـ`override val` مع `@SerializedName`،
 * فيوجد في الـJVM حقلان بالاسم نفسه (حقل الصنف وظلّه في الأساس). Gson يرفض
 * ذلك: `declares multiple JSON fields named 'id'` ⇒ أي محاولة لتسلسل كيان
 * خام كانت **ترمي استثناءً** — وموضعنا الوحيد الذي يمرّر كياناً خاماً هو
 * `inventory_transactions` في `InventoryRepositoryImpl` ⇒ حركات المخزون لم
 * تكن تُرفع إطلاقاً (الاستثناء يُلتقط كـ`Result.failure`، والحركة المحلية
 * تبقى فلا يظهر شيء للمستخدم).
 *
 * الحل: استراتيجية استبعاد تُسقط حقل الأساس المظلَّل **فقط** عند وجود حقل
 * بالاسم نفسه في الصنف نفسه، فيُسلسَل الحقل المُوسَم بالاسم السلكي مرة واحدة
 * (لا سقوط لقيمة من حمولة الرفع). هذه هي الاستراتيجية نفسها المستعملة في
 * `SyncIngestorRegistry.gsonFor` — نُقلت هنا لتُستعمل من مساري الرفع
 * والاستيعاب معاً (لا نسختان تفترقان).
 *
 * النتيجة مخزّنة لكل صنف (`ConcurrentHashMap`) — لا إعادة بناء عند كل صف.
 */
internal object SyncEntityGson {

    private val cache = ConcurrentHashMap<Class<*>, Gson>()

    fun forClass(clazz: Class<*>): Gson = cache.getOrPut(clazz) {
        val ownNames = clazz.declaredFields.map { it.name }.toSet()
        val strategy = object : ExclusionStrategy {
            override fun shouldSkipField(f: FieldAttributes): Boolean =
                f.declaringClass != clazz && f.name in ownNames

            override fun shouldSkipClass(clazz: Class<*>): Boolean = false
        }
        GsonBuilder()
            .addDeserializationExclusionStrategy(strategy)
            .addSerializationExclusionStrategy(strategy)
            .create()
    }

    /** تسلسل أي كائن (كيان أو نموذج) — يختار Gson الصنف الصحيح تلقائياً. */
    fun toJson(value: Any): String = forClass(value.javaClass).toJson(value)

    @Suppress("UNCHECKED_CAST")
    fun toMap(value: Any): Map<String, Any> =
        forClass(value.javaClass).fromJson(
            forClass(value.javaClass).toJson(value),
            Map::class.java
        ) as? Map<String, Any> ?: emptyMap()
}
