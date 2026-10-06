package com.marina.marina.data.remote.realtime

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * طابور أحداث السحب في Realtime — نقل حرفي لعقد Flutter
 * (`cloudflare_realtime_sync.dart`، قسم «طابور أحداث السحب»):
 *
 *  • **debounce 500ms**: أحداث متتالية تُدمج في حدث واحد.
 *  • **cooldown 15s** بين دورات السحب الفعلية (حماية من عاصفة أحداث
 *    من كاتب ساخن على جهاز آخر).
 *  • **حارس in-flight + متابعة trailing**: لا سحوبات متزامنة إطلاقاً؛
 *    حدث يصل أثناء سحب جارٍ يُسجَّل ويُنفَّذ بعده مباشرة (أو بعد انتهاء
 *    التهدئة) بدل الضياع.
 *  • **فشل السحب لا يهضم الحدث**: يُعاد الجدولة بعد التهدئة (نفس
 *    `_pullQueued = true` عند `ok == false`).
 *
 * الوقت والتنفيذ محقونان للاختبار (scope + now + execute) — لا شبكة هنا.
 */
internal class RealtimePullScheduler(
    private val scope: CoroutineScope,
    private val now: () -> Long,
    private val execute: suspend () -> Boolean,
    private val debounceMs: Long = REALTIME_DEBOUNCE_MS,
    private val cooldownMs: Long = REALTIME_PULL_COOLDOWN_MS
) {
    private var debounceJob: Job? = null
    private var trailingJob: Job? = null
    private var inFlight = false
    private var queued = false
    private var lastFireAt: Long? = null

    /** حدث تغيير بعيد — يجدول سحباً بعد نافذة الدمج. */
    fun onRemoteChange() {
        debounceJob?.cancel()
        debounceJob = scope.launch {
            delay(debounceMs)
            fire()
        }
    }

    /** إلغاء كل ما هو مجدول (stop/intentional) — لا يمس سحباً جارياً. */
    fun cancelPending() {
        debounceJob?.cancel()
        debounceJob = null
        trailingJob?.cancel()
        trailingJob = null
        queued = false
    }

    internal fun cooldownRemainingMs(): Long {
        val last = lastFireAt ?: return 0L
        val elapsed = now() - last
        if (elapsed < 0) return 0L
        return if (elapsed >= cooldownMs) 0L else cooldownMs - elapsed
    }

    private fun scheduleTrailing(afterMs: Long) {
        trailingJob?.cancel()
        trailingJob = scope.launch {
            delay(afterMs)
            fireTrailing()
        }
    }

    private suspend fun fire() {
        if (inFlight) {
            queued = true
            return
        }
        val remaining = cooldownRemainingMs()
        if (remaining > 0) {
            queued = true
            scheduleTrailing(remaining)
            return
        }
        executePull()
    }

    private suspend fun fireTrailing() {
        if (inFlight || !queued) return
        val remaining = cooldownRemainingMs()
        if (remaining > 0) {
            scheduleTrailing(remaining)
            return
        }
        executePull()
    }

    private suspend fun executePull() {
        inFlight = true
        queued = false
        lastFireAt = now()
        val succeeded = try {
            execute()
        } catch (cancelled: CancellationException) {
            inFlight = false
            throw cancelled
        } catch (_: Exception) {
            false
        } finally {
            inFlight = false
        }
        // فشل/تخطي السحب لا يهضم الحدث — متابعة بعد التهدئة.
        if (!succeeded) queued = true
        if (queued) {
            val remaining = cooldownRemainingMs()
            if (remaining > 0) scheduleTrailing(remaining) else executePull()
        }
    }
}
