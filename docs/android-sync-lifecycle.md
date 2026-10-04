# Android sync lifetime

Accepted `SyncManager` operations (`syncNow`, `pullOnly`, `pushOnly`, `fullPull`)
run on a singleton process-owned IO scope, not the calling screen or ViewModel.
Cancelling a screen's await does not cancel its accepted operation. A mutex
rejects overlapping requests; it does not queue duplicate full replays. Completion
and unexpected failures clear the shared busy state and release admission.

Settings manual connection/outbox preflight also has process ownership, with UI
callbacks on Main. A recreated settings screen observes repository busy state
and disables manual actions while sync is running. Push-only/pull-only semantics,
financial calculations, outbox processing, and replay cursor rules are unchanged.

## Boundaries

This is **not** persistent WorkManager scheduling or a foreground service. Screen
navigation cannot cancel accepted work, but background execution remains subject
to Android scheduling, process freezing/termination, connectivity and power
restrictions. Force-stop and process death are not covered. Existing saved cursor,
full-replay marker and outbox recovery remain the recovery mechanisms; they do not
guarantee immediate restart. In particular, a 1 GiB device can still kill the app.
A cycle can end at the existing replay page budget; the UI preserves the manager's
continuation message rather than claiming that every remote page was downloaded.

## Regression coverage

`SyncOperationRunnerTest` covers caller cancellation, atomic busy rejection,
recovery after failure, cancelled admission, owner cancellation before execution,
admission callback failure, and settings preflight lifetime.
`SyncIngestorRegistryTest.acceptedPullFinishesAfterScreenCancellationWithoutAllowingOverlap`
uses the real manager and preferences with a blocked fake HTTP response to verify
that a cancelled screen leaves the pull alive, push/full-pull cannot overlap it,
and its cursor is saved on completion. No production network/data is used.
