package com.marina.marina.domain.util

/** Arabic fuzzy name matching, ported from lib/services/repositories/blacklist_repository.dart. */
object ArabicNameMatcher {

    fun normalize(input: String): String {
        var s = input.trim()
        s = s.replace(Regex("[\u0617-\u061A\u064B-\u0652\u0670\u0653-\u065F\u06D6-\u06ED]"), "")
        s = s.replace("\u0640", "")
        s = s.replace(Regex("[إأٱآ]"), "ا")
        s = s.replace("ؤ", "و").replace("ئ", "ي").replace("ى", "ي")
        s = s.replace(Regex("[^\u0621-\u064A0-9 ]+"), " ")
        return s.replace(Regex(" +"), " ").trim().lowercase()
    }

    fun tokens(name: String): List<String> =
        normalize(name).split(Regex("\\s+")).filter { it.isNotEmpty() }

    /** True when the first three name tokens are identical (Flutter `_tripleMatch`). */
    fun tripleMatch(a: String, b: String): Boolean {
        val ta = tokens(a)
        val tb = tokens(b)
        if (ta.size < 3 || tb.size < 3) return false
        return ta[0] == tb[0] && ta[1] == tb[1] && ta[2] == tb[2]
    }
}
