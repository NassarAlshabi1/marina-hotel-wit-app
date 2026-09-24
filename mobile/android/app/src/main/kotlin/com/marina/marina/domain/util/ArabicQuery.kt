package com.marina.marina.domain.util

/**
 * أدوات البحث العربي — port 1:1 من `mobile/lib/utils/arabic_query.dart`
 * (فرع feat/cloudflare-sync-execution).
 *
 * مشكلة SQLite LIKE: مطابقة بايتية لا تعرف التطبيع — «احمد» لا تجد
 * «أحمد». الحل هنا توسيع نمط البحث إلى متغيرات الحروف المتغيرة
 * (عائلة الألف، الياء/الألف المقصورة، الواو/الهمزة) دون أي تغيير
 * في مخطط قاعدة البيانات.
 */
object ArabicQuery {

    /** عائلات الحروف المتغيرة — نفس عقد Dart `_variantFamilies`. */
    private val variantFamilies: Map<Char, List<Char>> = mapOf(
        'ا' to listOf('ا', 'أ', 'إ', 'آ', 'ٱ', 'ى'),
        'ي' to listOf('ي', 'ى', 'ئ'),
        'و' to listOf('و', 'ؤ'),
        'ه' to listOf('ه', 'ة')
    )

    /** التشكيل وعلامات القرآن + التطويل — تُحذف في التطبيع. */
    private val diacriticsRegex = Regex("[\u0617-\u061A\u064B-\u0652\u0670\u0653-\u065F\u06D6-\u06ED]")
    private val tatweel = '\u0640'
    private val alefFamilyRegex = Regex("[إأٱآ]")
    private val whitespaceRegex = Regex("\\s+")

    /**
     * إزالة التشكيل والتطويل وتوحيد الحروف المتغيرة — للمقارنات.
     * ة→ه (تغاير إملائي شائع في الأسماء) — عقد بحث لا عقد مطابقة.
     */
    fun normalizeArabicForSearch(input: String): String {
        var s = input.trim()
        s = diacriticsRegex.replace(s, "")
        s = s.replace(tatweel.toString(), "")
        s = alefFamilyRegex.replace(s, "ا")
        s = s.replace('ؤ', 'و')
        s = s.replace('ئ', 'ي')
        s = s.replace('ى', 'ي')
        s = s.replace('ة', 'ه')
        s = whitespaceRegex.replace(s, " ").trim()
        return s.lowercase()
    }

    /**
     * توليد متغيرات كلمة واحدة لتغطية فروق التهجئة.
     *
     * الخوارزمية: الكلمة المطبَّعة أساساً + كل استبدال أحادي الموضع
     * (كل موضع حرف متغيّر يُستبدل بكل أفراد عائلته) — بحد أقصى
     * [maxVariants] بلا انفجار توافقي.
     */
    fun expandArabicVariants(token: String, maxVariants: Int = 16): Set<String> {
        val normalized = normalizeArabicForSearch(token)
        if (normalized.isEmpty()) return emptySet()
        val variants = LinkedHashSet<String>()
        variants.add(normalized)
        for (i in normalized.indices) {
            val family = variantFamilies[normalized[i]] ?: continue
            for (replacement in family) {
                if (replacement == normalized[i]) continue
                variants.add(normalized.replaceRange(i, i + 1, replacement.toString()))
                if (variants.size >= maxVariants) return variants
            }
        }
        return variants
    }

    /** تقسيم استعلام متعدد الكلمات إلى كلمات مطبَّعة (بحد أقصى [maxWords]). */
    fun tokenizeQuery(input: String, maxWords: Int = 3): List<String> =
        normalizeArabicForSearch(input)
            .split(' ')
            .filter { it.isNotEmpty() }
            .take(maxWords)

    /** تهريب محارف LIKE الخاصة داخل نمط (بعقد ESCAPE '\'). */
    fun escapeLike(raw: String): String {
        val sb = StringBuilder()
        for (ch in raw) {
            if (ch == '\\' || ch == '%' || ch == '_') sb.append('\\')
            sb.append(ch)
        }
        return sb.toString()
    }

    /** أنماط LIKE الجاهزة لكلمة واحدة: %متغير% لكل متغير همزي — مرتبة. */
    fun likePatternsForWord(token: String, maxVariants: Int = 12): List<String> =
        expandArabicVariants(token, maxVariants)
            .map { "%${escapeLike(it)}%" }
            .sorted()

    /**
     * محاولة قراءة المدخل كرقم مبلغ — يدعم الأرقام العربية والفواصل.
     * «40,000» و«٤٠٠٠٠» تُقرأ رقمياً؛ «أحمد» و«123abc» تُرجعان null.
     */
    fun tryParseAmount(input: String): Double? {
        var s = input.trim()
        val arabicDigits = "٠١٢٣٤٥٦٧٨٩"
        val sb = StringBuilder()
        for (ch in s) {
            val idx = arabicDigits.indexOf(ch)
            sb.append(if (idx >= 0) ('0' + idx) else ch)
        }
        s = sb.toString().replace(",", "").replace("،", "").replace(" ", "")
        if (s.isEmpty()) return null
        return s.toDoubleOrNull()
    }
}
