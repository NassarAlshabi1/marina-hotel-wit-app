package com.marina.marina.data.sync

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex

/** Owns accepted sync operations for the process, never for a screen's lifetime. */
@Singleton
class SyncOperationRunner internal constructor(
    private val scope: CoroutineScope,
    private val requestDispatcher: CoroutineDispatcher
) {
    @Inject constructor() : this(
        CoroutineScope(SupervisorJob() + Dispatchers.IO),
        Dispatchers.Main.immediate
    )

    private val mutex = Mutex()

    /** Settings preflight and UI-state callbacks also survive their originating ViewModel. */
    fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(requestDispatcher, block = block)

    /**
     * Admission is atomic. Reject overlapping operations rather than queuing duplicate
     * full pulls or silently replacing a push with a pull. Cancelling await does not
     * cancel the application-owned Deferred. Completion releases admission even when
     * the owner scope is cancelled before the operation's body starts.
     */
    suspend fun <T> runIfIdle(
        onBusy: () -> T,
        onAccepted: () -> Unit = {},
        onFinished: (Throwable?) -> Unit = {},
        operation: suspend () -> T
    ): T {
        currentCoroutineContext().ensureActive()
        scope.coroutineContext.ensureActive()
        val owner = Any()
        if (!mutex.tryLock(owner)) return onBusy()
        val task = try {
            onAccepted()
            scope.async { operation() }
        } catch (error: Throwable) {
            try {
                onFinished(error)
            } finally {
                mutex.unlock(owner)
            }
            throw error
        }
        task.invokeOnCompletion { cause ->
            try {
                onFinished(cause)
            } finally {
                mutex.unlock(owner)
            }
        }
        return task.await()
    }
}
