package com.marina.marina.data.sync

/** Pure decision for comparing a pull response's server data generation. */
data class SyncEpochDecision(
    /** Non-null when a valid server epoch should replace the stored value. */
    val epochToPersist: String?,
    /** True when this page was built from a stale, non-zero cursor. */
    val restartFromZero: Boolean
)

/**
 * Mirrors the Cloudflare reference client contract:
 * - old Workers without an epoch remain compatible;
 * - the first observed epoch is adopted without an expensive re-pull;
 * - a changed epoch on a non-zero cursor invalidates that page/checkpoint;
 * - a changed epoch on a request already starting at zero is adopted in place.
 */
object SyncEpochPolicy {
    fun evaluate(
        storedEpoch: String?,
        responseEpoch: String?,
        pageBuiltFromZero: Boolean
    ): SyncEpochDecision {
        val serverEpoch = responseEpoch?.trim()?.takeIf { it.isNotEmpty() }
            ?: return SyncEpochDecision(epochToPersist = null, restartFromZero = false)
        val currentEpoch = storedEpoch?.trim()?.takeIf { it.isNotEmpty() }

        if (currentEpoch == serverEpoch) {
            return SyncEpochDecision(epochToPersist = null, restartFromZero = false)
        }

        val requiresRestart = currentEpoch != null && !pageBuiltFromZero
        return SyncEpochDecision(
            epochToPersist = serverEpoch,
            restartFromZero = requiresRestart
        )
    }
}
