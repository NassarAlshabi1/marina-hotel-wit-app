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

## CI evidence (2026-10-04, application source `90ae94c`)

- Release workflow [37225884889](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/runs/37225884889):
  `testDebugUnitTest` passed (including the seven runner cases and manager regression).
  Signed APK build was still running when this note was written; no APK success is claimed here.
- Quality/emulator workflow [37225884933](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/runs/37225884933):
  emulator job passed; quality job failed with 1,424 Detekt findings and 36 Lint
  warnings. Detekt is two findings above the earlier baseline (the manager function
  count and the runner's cleanup catch). No rules were suppressed. The full workflow
  is **not green**. Emulator smoke coverage is not a real navigation/background E2E test.
- Test artifacts could not be downloaded in this sandbox (artifact host EOF);
  the successful test step is confirmed via the GitHub jobs API, not locally opened XML.

## Foreground execution follow-up

The original process-only boundary above describes `90ae94c`, not the new
implementation. Accepted operations now hold a reference-counted `dataSync`
foreground service, with an Arabic ongoing notification and a return-to-app
PendingIntent. Settings acquires protection synchronously at the manual action,
including preflight; nested manager work keeps its own lease. Completion/failure
releases the lease, and the last lease stops the service. Navigation and Home do
not release it. `stopWithTask=false`; this is not an immortal service or a boot job.

Android background-start rejection is surfaced rather than silently running
without protection. Android 15's data-sync time-limit callback cancels owned work
and stops the service promptly. The service is non-sticky: stale intents cannot
replay a finished full pull or push. Notification permission denial does not grant
any bypass of Android policy; Android may show the foreground task in its task
manager rather than the notification drawer.

Force-stop, network failures, OS/vendor termination, and the platform's foreground
service time budget still cannot be overridden. There is no new durable WorkManager
retry; cursor/outbox recovery is unchanged. The existing 100-page cycle budget also
remains; this change protects the lifetime of a cycle, not an unbounded all-page loop.

Added foreground lease, rejected start, system timeout/retry, reference-counting,
and real-service notification tests. Their CI result must be checked separately
from the older successful process-only tests above.
