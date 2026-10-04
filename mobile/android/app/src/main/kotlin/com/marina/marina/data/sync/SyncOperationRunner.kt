package com.marina.marina.data.sync

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CancellationException
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
    private val requestDispatcher: CoroutineDispatcher,
    private val acquireForeground: () -> AutoCloseable = { AutoCloseable {} }
) {
    @Inject constructor(foreground: SyncForegroundLifetime) : this(
        CoroutineScope(SupervisorJob() + Dispatchers.IO),
        Dispatchers.Main.immediate,
        foreground::acquire
    )

    private val mutex = Mutex()
    private val systemStopGeneration = AtomicLong()
    private val activeJobs = ConcurrentHashMap.newKeySet<Job>()

    fun cancelForSystemStop() {
        systemStopGeneration.incrementAndGet()
        activeJobs.forEach { it.cancel(CancellationException("Android stopped the sync foreground service")) }
    }

    private fun <T : Job> track(job: T): T {
        activeJobs.add(job)
        job.invokeOnCompletion { activeJobs.remove(job) }
        return job
    }

    /** Settings preflight and UI-state callbacks also survive their originating ViewModel. */
    fun launch(
        onStartFailure: (Exception) -> Unit = {},
        block: suspend CoroutineScope.() -> Unit
    ): Job {
        val generation = systemStopGeneration.get()
        // Acquire synchronously from the button callback, before the user can press Home.
        val lease = try {
            acquireForeground()
        } catch (error: Exception) {
            onStartFailure(error)
            return Job().apply { complete() }
        }
        val job = try {
            track(scope.launch(requestDispatcher, start = CoroutineStart.LAZY) {
                ensureGeneration(generation)
                block()
            })
        } catch (error: Throwable) {
            lease.close()
            throw error
        }
        job.invokeOnCompletion { cause ->
            lease.close()
            if (cause != null) scope.launch(requestDispatcher) {
                onStartFailure(IllegalStateException("Foreground sync stopped", cause))
            }
        }
        job.start()
        return job
    }

    private fun ensureGeneration(generation: Long) {
        if (systemStopGeneration.get() != generation) {
            throw CancellationException("Foreground service stopped during admission")
        }
    }

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
        val generation = systemStopGeneration.get()
        var lease: AutoCloseable? = null
        val task = try {
            onAccepted()
            lease = acquireForeground()
            track(scope.async(start = CoroutineStart.LAZY) {
                ensureGeneration(generation)
                operation()
            })
        } catch (error: Throwable) {
            try {
                onFinished(error)
            } finally {
                try {
                    lease?.close()
                } finally {
                    mutex.unlock(owner)
                }
            }
            throw error
        }
        task.invokeOnCompletion { cause ->
            try {
                onFinished(cause)
            } finally {
                try {
                    lease?.close()
                } finally {
                    mutex.unlock(owner)
                }
            }
        }
        task.start()
        return task.await()
    }
}
