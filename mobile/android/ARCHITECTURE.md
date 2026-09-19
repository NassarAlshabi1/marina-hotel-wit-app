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
