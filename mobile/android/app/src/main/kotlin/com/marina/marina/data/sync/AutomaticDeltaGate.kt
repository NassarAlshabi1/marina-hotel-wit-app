package com.marina.marina.data.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex

internal const val AUTOMATIC_PULL_INTERVAL_MS = 60L * 60 * 1000

/** Wall clock is only a scheduling hint. Never derive the server cursor from it. */
internal fun automaticPullDue(now: Long, lastSuccess: Long): Boolean =
    lastSuccess <= 0 || now < lastSuccess || now - lastSuccess >= AUTOMATIC_PULL_INTERVAL_MS

enum class AutomaticDeltaStatus(val message: String) {
    LOCAL("البيانات المحلية جاهزة"),
    DISABLED("السحب التلقائي غير مفعّل"),
    OFFLINE("وضع محلي — لا يوجد اتصال إنترنت متاح للمزامنة"),
    CHECKING("جارٍ فحص الاتصال بـ Cloudflare D1…"),
    UNREACHABLE("وضع محلي — تعذّر الاتصال بقاعدة Cloudflare D1؛ ستُعاد المحاولة"),
    CURRENT("الاتصال بقاعدة D1 متاح — لم تمضِ ساعة على آخر سحب ناجح"),
    PULLING("جارٍ سحب Delta من آخر مؤشر محفوظ…"),
    UPDATED("اكتمل فحص السحب التلقائي — البيانات المحلية متاحة"),
    RETRY("السحب مؤجل أو لم يكتمل بنجاح؛ البيانات المحلية متاحة")
}

/** One process-owned admission gate for app-open, network recovery and timer signals.
 * SyncManager alone owns/persists successful-pull timestamps and cursors.
 */
internal class AutomaticDeltaGate(
    private val enabled: () -> Boolean,
    private val networkAllowed: () -> Boolean,
    private val lastSuccess: () -> Long,
    private val now: () -> Long,
    private val monotonicNow: () -> Long,
    private val probe: suspend () -> Boolean,
    private val pullIfDue: suspend () -> Int,
    private val canStart: () -> Boolean = { true }
) {
    private val lock = Mutex()
    private val _status = MutableStateFlow(AutomaticDeltaStatus.LOCAL)
    val status = _status.asStateFlow()
    private var lastAttempt: Long? = null

    suspend fun check(probeWhenFresh: Boolean) {
        if (!lock.tryLock()) return
        try {
            if (!enabled()) { _status.value = AutomaticDeltaStatus.DISABLED; return }
            if (!networkAllowed()) { _status.value = AutomaticDeltaStatus.OFFLINE; return }
            if (!probeWhenFresh && !automaticPullDue(now(), lastSuccess())) return
            val tick = monotonicNow()
            // Prevent capability callback storms and rapid retries after auth/D1 failure.
            if (lastAttempt?.let { tick >= it && tick - it < 30_000L } == true) return
            lastAttempt = tick
            _status.value = AutomaticDeltaStatus.CHECKING
            if (!probe()) { _status.value = AutomaticDeltaStatus.UNREACHABLE; return }
            if (!enabled() || !networkAllowed()) {
                _status.value = if (enabled()) AutomaticDeltaStatus.OFFLINE else AutomaticDeltaStatus.DISABLED
                return
            }
            if (!automaticPullDue(now(), lastSuccess())) {
                _status.value = AutomaticDeltaStatus.CURRENT
                return
            }
            if (!canStart()) { _status.value = AutomaticDeltaStatus.RETRY; return }
            _status.value = AutomaticDeltaStatus.PULLING
            _status.value = if (pullIfDue() >= 0) AutomaticDeltaStatus.UPDATED else AutomaticDeltaStatus.RETRY
        } catch (cancelled: CancellationException) {
            _status.value = AutomaticDeltaStatus.RETRY
            throw cancelled
        } catch (_: Exception) {
            _status.value = AutomaticDeltaStatus.UNREACHABLE
        } finally {
            lock.unlock()
        }
    }
}
