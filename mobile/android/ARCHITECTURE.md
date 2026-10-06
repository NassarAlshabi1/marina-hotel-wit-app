# Marina Hotel — Android Clean Architecture

## Layers (dependency rule: inward only)

```
presentation  ->  domain  <-  data
     \                          /
      -------- di (Hilt) --------
```

- `domain/model` — pure data classes (`Booking`, `SyncUiState`, ...). No Android/data imports.
- `domain/repository` — interfaces only (`RoomsRepository`, `SyncRepository`,
  `AuthRepository`, `AiAssistantRepository`, ...).
- `domain/usecase` — one-shot business operations (`LoginUseCase`,
  `RequestSyncUseCase`, `ChatWithAssistantUseCase`, ...). Thin, injectable,
  `operator fun invoke`.
- `domain/session`, `domain/util` — session holder + pure business rules
  (`HotelTimeEngine`, `StatusUtils`, ...).
- `data/local|remote|mapper|repository|auth|ai` — Room, Retrofit, mappers,
  repository implementations. Implements `domain/repository` interfaces.
- `presentation/*` — Compose screens + `ViewModel`s. May depend **only** on
  `domain` (repositories, use cases, session, util). Never on `data.*`.
- `di` — Hilt modules (composition root). The **only** layer allowed to
  reference both `data` and `domain` for bindings.

## Rules

1. No `import com.marina.marina.data` inside `presentation/` or `domain/`.
   Check: `rg "import com.marina.marina.data" presentation/ domain/` must be empty
   (outside `di/`).
2. `ViewModel`s receive domain interfaces/use-cases via `@Inject` constructor.
3. New sync/auth/AI capabilities go through `domain/repository` interfaces +
   `domain/usecase` wrappers, with implementations in `data/`.
4. `SyncUiState` lives in `domain/model` (single source of truth).

## Cloudflare sync execution contract

- Wire DTOs in `data/remote/CloudflareWorkerApi.kt` mirror Worker JSON;
  boundary normalization stays in `PushWireContract` (including legacy aliases
  and millisecond-to-second conversion).
- `SyncManager` applies each page through `SyncIngestorRegistry`, validates
  monotonic cursors, and commits the checkpoint only after a clean pull.
  D1 `epoch` changes invalidate stale pages and restart once from cursor zero;
  Workers deployed before migration 0010 remain compatible.
- The Worker is authoritative for deletes. A `deleted` push disposition clears
  the losing local outbox edit and tombstones the row; pulled tombstones win
  over local edits without replacing the row's newer business fields.
- Realtime is an **event, not data**: `CloudflareRealtimeClient` subscribes to
  `/api/realtime?deviceId=..&entity=*`, ignores its own echo, debounces 500 ms
  with a 15 s cooldown, and triggers `SyncManager.pullOnRealtimeEvent()` — a
  delta-only, push-free pull that skips while another sync runs. FCM data
  messages (`type=marina_sync`) feed the same signal. Both live in the
  foreground only; background signals are consumed on resume.
- One-time historical tombstone sweep (`tombstones_only=1`) uses its own
  resumable cursor and never advances the delta cursor. Cursor poisoning guards
  (2e9 fixed bound, `server_time` + one year) reject millisecond/sentinel
  checkpoints at startup, mid-cycle, and install time.
- Contract logic has JVM tests under `app/src/test`; Worker protocol tests live
  in `worker/test`. Run `./gradlew :app:testDebugUnitTest` and `npm test` from
  their respective project directories when JDK/Node dependencies are present.
  See `docs/android-pull-parity-flutter.md` for the pull-path parity contract.

## Financial integrity / Room 72

- Expense mutations own the transaction: expense + UUID-linked withdrawal +
  all Outbox rows commit or roll back together. ViewModels do not write mirrors.
- Each Outbox mutation gets a distinct persisted idempotency key; retries reuse it.
- `pending_sync_links` is a local-only durable inbox, written in the page
  transaction before the cursor may advance. Replay occurs after every pull,
  including empty deltas. A new epoch discards the old generation's inbox and
  replays from zero without echo filtering, even across page limits/restarts.
- Legacy financial links are not inferred from device-local IDs. Unverified
  legacy mirror edits/deletes fail closed for manual review. Reports keep
  unresolved rows visible with a warning rather than deduplicating by amount/day.
- Supported database upgrades are 70→71→72 and 71→72. Unknown versions fail
  closed; there is no destructive fallback. See `docs/financial-integrity-fixes.md`.
