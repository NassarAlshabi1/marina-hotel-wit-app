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
- Contract logic has JVM tests under `app/src/test`; Worker protocol tests live
  in `worker/test`. Run `./gradlew :app:testDebugUnitTest` and `npm test` from
  their respective project directories when JDK/Node dependencies are present.
