# Cloudflare Sync Architecture — Professional Audit

**Date**: 2026-09-07
**Scope**: Mobile ↔ Cloudflare D1 sync (post-Appwrite migration)
**Files Audited**: 15+ core files across mobile/lib/services, mobile/lib/providers, mobile/lib/widgets, worker/src

---

## 1. System Overview

The Marina Hotel app is an offline-first Flutter application with a Cloudflare Worker API backend. After migrating from Appwrite sync, the Cloudflare sync path is now the primary (and intended only) sync mechanism.

### Active Sync Stack

```
TRIGGER LAYER
  Manual Button (UI tap)  →  CloudflareSyncManager.sync()
  Auto Timer (15 min)     →  CloudflareSyncManager.sync()
  Realtime WS (SyncLockDO) →  CloudflareRealtimeSync → sync()

CloudflareSyncManager.sync(push=true, pull=true)
  [Mutex: _syncInProgress]  [Kill switch: DualRun]
  [Local enable: appwrite_sync_enabled]
  ├── PUSH: _pushOutbox()
  │   └── Drift Outbox → POST /api/sync/push {operations: [...]}
  └── PULL: _pullChanges()
      └── GET /api/sync/pull?cursor=X&limit=200&exclude_device=Y
          └── _applyChange() → SmartConflictResolver → Local Drift DB
```

### Server Side (Worker)

```
POST /api/sync/push
  → validatePushOperation (schema + type check)
  → checkIdempotency (deduplicate via idempotencyKey)
  → createRecord / updateRecord / deleteRecord
      → allocateUpdatedAt() (monotonic sync_clock)
      → Vector clock merge
      → PRAGMA column whitelist (SQL injection defense)
  → saveIdempotency
  → broadcast to SyncLockDO (WebSocket hub)
  → Return per-operation results

GET /api/sync/pull
  → For each of 23 entity tables:
      SELECT * FROM table WHERE updated_at > cursor
      [AND device_id != exclude_device]  ← echo filter
      ORDER BY updated_at ASC LIMIT (limit+1)
  → Global sort by updated_at + local_uuid
  → Paginate to limit
  → Return {changes, cursor, has_more, errors[]}
```

---

## 2. Sync Contracts

### Push Contract (Mobile → Cloudflare)

```
POST {workerUrl}/api/sync/push
Authorization: Bearer {jwt}
Content-Type: application/json

{
  "operations": [
    {
      "idempotencyKey": "uuid-v4",
      "entity": "rooms",
      "operation": "create|update|delete",
      "data": { /* snake_case fields matching D1 columns */ },
      "vectorClock": "{\"device-id\": 5}",
      "updatedAt": 1694083200,
      "deviceId": "device-uuid"
    }
  ]
}
```

**Response**:
```json
{
  "results": [
    {
      "idempotencyKey": "...",
      "success": true,
      "entity": "rooms",
      "entityId": "local-uuid",
      "skipped": false
    }
  ],
  "summary": { "total": 25, "success": 25, "failed": 0, "skipped": 0 },
  "server_time": 1694083200
}
```

### Pull Contract (Cloudflare → Mobile)

```
GET {workerUrl}/api/sync/pull?cursor=1694000000&limit=200&exclude_device=dev-uuid
Authorization: Bearer {jwt}
```

**Response**:
```json
{
  "changes": [
    {
      "_entity": "rooms",
      "local_uuid": "uuid-1",
      "room_number": "101",
      "price": 100,
      "updated_at": 1694083201,
      "device_id": "other-device",
      "vector_clock": "{\"other-device\": 3}"
    }
  ],
  "cursor": "1694083201",
  "has_more": true,
  "errors": [],
  "server_time": 1694083201
}
```

### 23 Synced Entities

rooms, bookings, payments, expenses, employees, debts, booking_notes, booking_nights, booking_price_adjustments, guest_infos, shift_notes, cash_transactions, salary_cycles, salary_payments, salary_withdrawals, salary_carry_over_logs, price_adjustments, audit_logs, payment_voids, inventory_items, inventory_transactions, app_users, devices, blacklist

---

## 3. Critical Issues Found

### Issue 1: SmartSyncManager Still Wired into Button Path

**File**: `mobile/lib/widgets/enhanced_sync_button.dart:99-117`

The enhanced sync button calls `SmartSyncManager.forceSyncNow()` BEFORE `CloudflareSyncManager.sync()`. SmartSyncManager is Google Drive-focused — it has its own timers, conflict resolution (`ConflictResolution` enum), and data-usage tracking. If Google Drive sync is enabled, this causes dual-path operations that waste bandwidth and can create conflicting change streams.

**Impact**: Silent dual sync, potential data divergence between Cloudflare D1 and Google Drive backup.

**Fix**: Remove `smartSyncManager.forceSyncNow()` from the button trigger, or gate it behind a Google-Drive-only flag.

### Issue 2: Triple Orchestration Layers

Three separate orchestration systems exist:

| Layer | File | Lines | Function |
|-------|------|-------|----------|
| `CentralSyncCoordinator` | central_sync_coordinator.dart | 156 | Debounce 3s + cooldown 10s |
| `UnifiedSyncOrchestrator` | unified_sync_orchestrator.dart | 650 | Multi-backend coordination |
| `SyncOrchestrator` | sync_orchestrator.dart | 624 | Task queue + circuit breakers |

`CentralSyncCoordinator` wraps `UnifiedSyncOrchestrator` which wraps `CloudflareSyncManager`. Each layer adds its own debouncing/cooldown logic, creating:
- Up to 13+ seconds of aggregate delay before a manual sync executes
- Non-deterministic behavior when multiple triggers fire simultaneously
- Confusion about which orchestrator "owns" sync state

`SyncOrchestrator` (624 lines) is initialized in main.dart but never actually triggers CloudflareSyncManager — it has its own task queue that is separate.

**Fix**: Consolidate to a single orchestrator. `CloudflareSyncManager` already has re-entrancy protection (`_syncInProgress`). The additional orchestration layers are redundant.

### Issue 3: Duplicate Sync Triggers on App Resume

**File**: `mobile/lib/main.dart:831, 1009`

Two independent sync triggers fire on every app resume:
1. `_syncOnResume()` → `CloudflareSyncManager.sync(pull: false)` — push only
2. `UnifiedSyncOrchestrator.onAppForeground()` → full push+pull

The `_syncInProgress` mutex prevents concurrent execution, but:
- The first to acquire the lock wins; the second silently returns "Sync already in progress"
- Push-only from trigger #1 can complete before trigger #2 starts, but if trigger #2 wins first, trigger #1's push is wasted
- Comment in code (line 817) acknowledges this pattern but depends on timing

**Fix**: Remove one of the two resume triggers. Keep only `UnifiedSyncOrchestrator.onAppForeground()` (full push+pull).

### Issue 4: DeltaSyncService Is Orphaned from Cloudflare Path

**File**: `mobile/lib/services/delta_sync_service.dart` (857 lines)

DeltaSyncService computes outbound deltas using a hash-based mirror table (`sync_mirror`) in an isolate. However, `CloudflareSyncManager._pushOutbox()` reads directly from the **outbox table**, not from DeltaSyncService.

DeltaSyncService is only consumed by:
- `sync_service.dart` — legacy PHP REST API sync (likely dead code)
- `google_drive_delta_sync.dart` — Google Drive sync

**Impact**: 857 lines of compute-heavy code (isolate-based SHA1 hashing) are unused in the Cloudflare path.

### Issue 5: Dead Stubs from Appwrite Migration

**File**: `mobile/lib/services/cloudflare_sync_manager.dart`

| Method | Returns | Used By |
|--------|---------|---------|
| `pushAllLocalDataToAppwrite()` | `{errors: 0}` | Google Drive backup service |
| `pullAllDataWithDisabledFK()` | `sync()` | Settings screen |
| `pushAllEntities()` | `void` | Dead code |
| `getRegisteredDevices()` | Empty list | Settings screen |
| `pushLocalChanges()` | Calls sync() | CentralSyncCoordinator |
| `pushAllLocalData()` | Calls sync() | Backup provider |

These stubs return success (0 errors) even though they don't actually push data. Callers may think data was backed up when it wasn't.

### Issue 6: UnifiedSyncOrchestrator Creates Second Manager Reference

**File**: `mobile/lib/services/unified_sync_orchestrator.dart:465-474`

`_ensureAppwriteManager()` creates a new `AppwriteSyncManager` (aliased to `CloudflareSyncManager`). While `CloudflareSyncManager` is a singleton, the double `initialize()` call (once from providers, once from orchestrator) can cause race conditions if the first JWT login is still in progress.

### Issue 7: Confusing Naming Creates Maintenance Risk

The `typedef AppwriteSyncManager = CloudflareSyncManager` means:
- `appwrite_providers.dart` exports `appwriteSyncManagerProvider` which is actually CloudflareSyncManager
- `appwrite_sync_enabled` preference controls Cloudflare sync
- 20+ files import `appwrite_sync_manager.dart` thinking they're using Appwrite

New developers will assume Appwrite is still active. This is a maintenance hazard.

---

## 4. Conflict Resolution Analysis

### Vector Clock Protocol

Both client and server maintain vector clocks per record:
- **Client**: Drift `vector_clock` column (JSON: `{deviceId: counter}`)
- **Server**: D1 `vector_clock` column (same format)

**Comparison logic** (`SmartConflictResolver`):
- `localVc == remoteVc` → equal (no conflict)
- `localVc > remoteVc` → local newer → skip remote
- `localVc < remoteVc` → remote newer → apply remote
- `localVc ∥ remoteVc` → concurrent → SmartConflictResolver field-level merge

**LWW fallback**: When vector clocks are absent or empty, `updated_at` timestamps decide (Last Writer Wins). On tie, `version` counter breaks it.

### Pull-Side Conflict Resolution (`_applyChange`)

```
1. If remote record has deleted_at → apply tombstone ALWAYS (P0-E)
   (tombstone is final even if local is newer)
2. If local updatedAt > remote updatedAt → skip (local is newer)
3. If vector clocks are concurrent → SmartConflictResolver merge
   → Write merged result to local DB
   → Enqueue to outbox for re-upload to server
4. Otherwise → apply remote (sequential update)
```

### Pull-Side Checkpoint Safety (P0-C)

The pull cursor is only advanced on **full success** — if any record fails to apply, the cursor stays at its initial position, and the next pull re-fetches the same page. This prevents data loss from partial failures.

---

## 5. Realtime Sync Analysis

### Architecture

```
Server Push → SyncLockDO.broadcast() → WebSocket → CloudflareRealtimeSync
                                                        ↓
                                                    echo filter (skip own device)
                                                        ↓
                                                    debounce 500ms
                                                        ↓
                                                    cooldown 15s
                                                        ↓
                                                    _executePull()
                                                        ↓
                                                    CloudflareSyncManager.sync()
```

### Strengths
- Echo filter prevents self-triggered pull loops
- Debounce + cooldown prevents flooding (max ~4 pulls/min)
- In-flight guard + trailing queue ensure no concurrent pulls
- Recovery pull after disconnect catches missed changes
- Exponential backoff (1s → 60s, max 6 attempts) for reconnection

### Weaknesses
- WebSocket broadcasts to ALL connected sessions including the sender — echo filter adds latency
- If cooldown blocks a pull and no further events arrive, the trailing timer fires one final pull — but if that fails, the event is lost
- No acknowledgment protocol: client doesn't confirm receipt of change events

---

## 6. Data Integrity Analysis

### Outbox Pattern (Write-Ahead Log)

```
Local DB write → outbox_dao.enqueue() → processing_status: 'pending'
    ↓
pushOutbox() → takeBatch(pending/failed) → POST /api/sync/push
    ↓
On success → processing_status: 'processing' → delete entry
On failure → processing_status: 'failed' (retryable)
On crash → reclaimForPush() at init: stuck 'processing' → 'pending'
```

### Strengths
- Crash recovery: stuck processing entries reclaimed on app restart
- Idempotency: `idempotencyKey` prevents duplicate server writes
- Ordering: `clientTs` ordering ensures causal consistency within a device

### Integrity Risks

1. **No transaction wrapping for outbox + local DB**: A local DB write + outbox enqueue is not atomic. If the app crashes between the two, the change exists locally but won't be pushed until the next manual sync.

2. **`INSERT OR IGNORE` for new records**: If two devices create a record with the same `local_uuid`, the second INSERT is silently ignored. This is by design (local_uuid is device-specific), but a UUID collision = silent data loss.

3. **`_derivedRefreshAfterPull` skip behavior**: If two pulls happen rapidly (realtime + manual), the refresh mutex skips the second refresh — potentially leaving stale derived data (booking_nights, totals).

---

## 7. Security Analysis

### Authentication
- JWT HMAC-SHA256 with constant-time comparison
- PBKDF2-SHA256 (25k iterations) for password hashing
- Token expiry: 24h (configurable via `JWT_EXPIRY_HOURS`)

### SQL Injection Defense
- Server uses parameterized queries (D1 prepared statements)
- Column whitelist via `PRAGMA table_info` — unknown columns rejected
- Migration handler: INSERT-only whitelist with forbidden keyword scanning

### Rate Limiting
- D1-based (atomic UPSERT + RETURNING)
- 1000 req/min per client (configurable)
- Separate login bucket: 20/window

### Vulnerability: API Token Exposed in Conversation

The Cloudflare API token was provided in the conversation context. **This token should be revoked immediately** and a new one generated.

---

## 8. Recommendations

### Priority 1 (Immediate — Data Integrity)

1. **Remove SmartSyncManager from enhanced_sync_button**: It triggers Google Drive sync unnecessarily in the Cloudflare-only path.

2. **Remove duplicate resume sync trigger**: Keep only `UnifiedSyncOrchestrator.onAppForeground()` — delete the separate `_syncOnResume()` push-only call.

3. **Wrap outbox + local DB write in a transaction**: Prevent crash-gap between local write and outbox enqueue.

### Priority 2 (Short-term — Architecture Cleanup)

4. **Consolidate orchestration layers**: Remove `CentralSyncCoordinator` debounce (CloudflareSyncManager already has `_syncInProgress` mutex). Simplify `UnifiedSyncOrchestrator` to only coordinate Cloudflare + Google Drive without additional debounce.

5. **Remove or gate DeltaSyncService from Cloudflare path**: 857 lines of unused code. Either delete it or mark it clearly as Google Drive-only.

6. **Clean up Appwrite naming**: Rename typedef, preferences, and file references to reflect Cloudflare-only reality.

### Priority 3 (Medium-term — Reliability)

7. **Add retry logic to realtime pull failures**: Currently, a failed pull from a realtime event is only retried once via `_pullQueued`. Add exponential backoff retry.

8. **Add server-side acknowledgment for realtime events**: WebSocket client should confirm receipt so the server can retry broadcasting.

9. **Fix `_derivedRefreshRunning` skip behavior**: Use a "pending refresh" flag — if a refresh is in progress, mark that another is needed and run it after the current one completes.

### Priority 4 (Low — Technical Debt)

10. **Remove dead stubs**: `pushAllLocalDataToAppwrite()`, `pushAllEntities()`, `getRegisteredDevices()`.

11. **Reduce `SyncOrchestrator` (624 lines)**: It has its own task queue + circuit breakers but doesn't connect to CloudflareSyncManager. Either wire it up or remove it.

12. **Consolidate sync_providers.dart**: Currently just 3 lines (syncGateProvider + syncIsBusyProvider). Expand to own sync state or remove.

---

## 9. Architecture Health Score

| Dimension | Score | Notes |
|-----------|-------|-------|
| **Data Correctness** | 8/10 | LWW + VC solid; outbox crash recovery good; transaction gap is a risk |
| **Conflict Resolution** | 8/10 | Vector clocks + SmartConflictResolver field-level merge is sophisticated |
| **Realtime Latency** | 7/10 | Debounce/cooldown adds 500ms-15s delay; acceptable for hotel ops |
| **Code Maintainability** | 4/10 | Triple orchestration, Appwrite naming ghosts, 857-line orphan, dead stubs |
| **Error Recovery** | 7/10 | P0 checkpoints, crash reclaim, re-entrancy guards; missing realtime retry |
| **Security** | 7/10 | Good JWT/PBKDF2/rate-limiting; column whitelist defense; API token leaked |

**Overall**: The sync *logic* is solid — the contracts, conflict resolution, and data flow are well-designed. The *architecture* needs cleanup: removing legacy layers and Appwrite ghosts would improve maintainability significantly without changing runtime behavior.
