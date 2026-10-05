# Cloudflare Delta sync audit — 2026-10-05

## Repair update (same date)

The findings below are the **pre-fix audit history**, not the current test verdict.
The authorized repair is implemented in source, not deployed to production:

- Business row, final `updated_at`, clock advancement, and response readback now
  share one D1 atomic batch. Applies to create/update/delete/device writes.
- Poison repair allocates and publishes in the same transaction and checks the
  poison predicate at write time, preserving concurrent legitimate edits.
- Each pull establishes a fixed clock ceiling before reading entity pages.
  Later commits remain above that ceiling and are delivered on a later request.
  Indexed sane-MAX probes include legacy timestamps when establishing the ceiling;
  this adds per-table index queries, not a full payload scan or client RAM load.
- Confirmed AI expense inserts also use transaction-scoped clock allocation;
  independent same-day events and whole-range transaction semantics are retained.
- Worker accepts both `1` and `true` for the two full-replay flags.
- `repair_pending` acknowledges a repair-only page. Android retries at the same
  cursor at most three times, still rejects unacknowledged stalls, and never
  treats exhausted repair/page budgets as a successful stalled cycle.
- Normalization is recorded complete only with explicit `complete=true` and
  `remaining=0`; failed table scans cannot claim completion.
- Dashboard remains `pullDeltaChanges → pullOnly`, using the saved server cursor;
  no automatic full pull, hour-gating of manual actions, or checkpoint reset added.

Verification: Worker typecheck passed; **208 tests / 19 files passed** (65.68s).
The 10 audit regression cases include both original interleavings, delayed update
and delete, rollback, Boolean flags, repair acknowledgement, failed normalization
and AI writes. Six new Android integration cases cover repair bounds and
normalization acknowledgements; Android CI verification is recorded separately
when available. The existing Dashboard saved-cursor regression remains in place.

Deployment: ship Worker and Android together (Worker first). No schema migration
is added. Existing schema prerequisites including `sync_write_times` remain.
No deployment, remote D1 write, historical full replay or epoch reset was run.
These fixes prevent the reproduced future misses; they do not automatically
recover changes skipped before deployment. Coordinate any historical replay
separately, after backing up and resolving pending local uploads.

The guarantee covers participating Worker write paths. Direct SQL imports,
restores or external D1 edits must honor clock publication / epoch-reset rules;
no application protocol can order arbitrary external backdated SQL writes.
Worst-case legacy equal-timestamp pages remain a soft batch limit; no new
1 GB RAM performance claim is made.

## Original pre-fix verdict

The ordinary path uses a persisted server cursor, not the app-open time, and contains useful replay/error safeguards. It is **not yet demonstrated lossless under concurrent writes**. Two distinct, reproducible cursor-loss interleavings exist. No production code, production D1 data, deployment, migration, financial calculations or Android scheduling was changed in this audit.

## Evidence

Local workerd / D1 emulation, with production remote bindings disabled:

- Existing suite before new audit tests: **198 passed / 18 files**.
- `npm run typecheck`: passed, including the new audit tests.
- Full suite after adding `worker/test/sync.delta.audit.test.ts`: **198 passed, 4 failed / 202 tests**, 19 files, 64.69 seconds.
- These four tests assert the required correct behavior and intentionally remain red pending repair. They are not skipped or marked expected failures. Consequently the current full suite is **not green**.
- Commands: `cd worker && npm run typecheck`; `npm test -- --reporter=dot`.
- Session logs: `/home/user/cloudflare-delta-audit-tests.log`, `/home/user/cloudflare-delta-audit-regressions.log`, `/home/user/cloudflare-delta-audit-full.log`.

These results are not evidence that production has already lost a particular record. They reproduce legal concurrent interleavings against the actual local SQL implementation. No device or 1 GB RAM performance test was performed here.

## Confirmed high-priority failures

### 1. Timestamp allocation and record commit are separate operations

`worker/src/database.ts`: `allocateUpdatedAt()` and `createRecord()` (allocation near line 1014); other write methods also call the allocator separately.

Reproduction:

1. Writer A reserves timestamp A and pauses before its business row is inserted.
2. Writer B reserves a greater timestamp B and commits.
3. A pull returns B and advances its cursor to B.
4. Writer A commits its real row with timestamp A.
5. The next `updated_at > B` pull never returns A unless another operation subsequently changes its timestamp or the client replays from an older cursor.

The test subclasses Database only to delay the real allocator's return. It does not forge timestamps or SQL results; it verifies the late row exists in D1 before asserting that the subsequent pull must contain it. The assertion fails with an empty changes list.

Atomic allocation alone is insufficient: allocation and publication must preserve the ordering of committed changes. The optional sync-lock endpoint is not a compulsory guard around the push/pull routes.

### 2. Multi-table reads do not share a stable snapshot

`worker/src/database.ts`: `pullChanges()` entity loop and the shared global cursor.

Reproduction, even with sequential completed business writes:

1. Pull reads the rooms table.
2. A new room is committed.
3. A newer employee is committed.
4. The same pull reads employees and advances its global cursor to the employee timestamp.
5. Neither this page nor the next page contains the room.

The test wraps real D1 reads to inject real Database writes immediately after the rooms query completes; it does not replace query results. The observed combined pages contain only the employee, not the room.

**Fixing the allocator alone does not fix this second failure.** A repair needs both committed-write ordering and a safe shared read boundary/snapshot (or a correctly ordered change feed). A high-water mark captured at pull start is not sufficient by itself while writers can commit later below that mark. Do not substitute a small arbitrary lookback as proof of correctness.

## Confirmed wire-contract failures

`CloudflareWorkerApi.kt:157–158` declares nullable Boolean query parameters. Normal Retrofit conversion sends `true`/`false`, while `worker/src/sync.ts:220,226` accepts only the literal `1` for:

- `include_remaining`
- `normalize_timestamps`

Two authenticated HTTP tests requesting `true` receive HTTP-success payloads with the requested results still null. These affect full replay/progress/normalization, rather than ordinary delta requests with the flags false. Android additionally sets its normalization-done preference after a successful requested page without requiring an acknowledged normalization result (`SyncManager.kt`, near line 406).

Repair should explicitly align accepted wire values and require an appropriate normalization acknowledgement before recording completion.

## Additional source-level recovery mismatch

A page containing only poisoned timestamps can be successfully restamped by Worker and return no changes, the same cursor and `has_more=true`. Android's unchanged-cursor guard (`SyncManager.kt`, near line 393) treats this as stalled pagination and aborts the cycle. A subsequent cycle may recover the now-restamped rows; this finding is **not** equivalent to permanent cursor loss. It has not received a new end-to-end Android regression test in this audit. A bounded, explicit repair-progress/retry contract should distinguish this case from a genuinely stalled server.

## Existing safeguards observed

- Ordinary delta selects `updated_at > cursor`, including deletion markers, with optional device echo filtering.
- Rows are sorted and equal-timestamp boundary groups are retained to avoid cutting through a legacy tie group.
- The returned cursor is based on served valid rows, not server wall time or an unserved global maximum.
- Errors / truncation block unsafe checkpoint advancement.
- Android validates cursor progression, applies pages, resolves pending links and persists its checkpoint after a clean bounded pull cycle.
- Epoch changes trigger bounded replay; ordinary pulls do not reset the cursor.
- Hourly eligibility uses successful-pull wall time separately from the server's change-selection cursor.

Boundary-group extension makes the nominal 250-row Android batch a **soft** response limit. The existing per-table tie cap is 20,000. This audit does not establish suitability of worst-case response sizes on a 1 GB RAM device.

## Next step

Repair the two independent ordering/snapshot failures first, align the flag and recovery contracts, then require all audit tests and the existing suite to pass. Deployment and any recovery of potentially missed historical changes need separate validation; no production replay or mutation was attempted during verification.
