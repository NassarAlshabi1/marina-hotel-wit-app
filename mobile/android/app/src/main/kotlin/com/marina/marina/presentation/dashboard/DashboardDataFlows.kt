package com.marina.marina.presentation.dashboard

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.shareIn

/**
 * Share one database subscription, preserving failures for each consumer's catch.
 * Consumers' stateIn already provides the 5s lifecycle grace period; don't add
 * another delay here. Clear replay when idle so a fresh subscription reloads DB.
 */
internal fun <T> Flow<T>.shareDashboardSource(
    scope: CoroutineScope,
    dispatcher: CoroutineDispatcher = Dispatchers.Default
): Flow<T> {
    val snapshots = map { Result.success(it) }
        .catch { emit(Result.failure(it)) }
        .flowOn(dispatcher)
        .shareIn(scope, SharingStarted.WhileSubscribed(replayExpirationMillis = 0), replay = 1)
    return snapshots.map { it.getOrThrow() }
}
