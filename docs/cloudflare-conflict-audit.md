# Conflict resolution and remote metadata audit — 2026-10-05

## Authorized repair and verification

Implemented after the audit, on the same date:

- Read the business row and `sync_write_times.edited_at` in one SQL snapshot.
- Conditional UPDATE checks the observed `updated_at`, version, vector clock,
  edit metadata and a live (`deleted_at IS NULL`) row at commit time.
- The row's final cursor and edit metadata are published in the same atomic D1
  batch. `changes()` immediately after the conditional UPDATE gates the metadata
  upsert. A rejected CAS leaves the winning row and its edit metadata untouched;
  unused logical-clock gaps are permitted and cannot skip records.
- Retry the complete conflict decision using fresh state and the original
  payload/edit timestamp, at most five attempts. Persistent contention is a
  transient error, not success, allowing the existing outbox retry path to work.
- A delete committed after the initial read is recognized on retry and returns
  the existing `status=deleted` contract; a live-row snapshot cannot resurrect it.
- Deletion increments the current stored version in the write transaction and
  records the deleting `device_id`. This prevents a stale version increment and
  ensures the original author receives another device's tombstone through the
  existing echo filter.

Validation: `npm run typecheck` passed. The full local workerd/D1 suite passed
**214/214 tests in 20 files**, 69.97s. Output:
`/home/user/conflict-fix-full.log`. Six concurrency-audit cases now cover the
sequential control, older edit losing, newer edit winning after retry, delete
winning, bounded repeated contention, metadata preservation, and delayed delete
version/echo delivery (some cases check several invariants).

No schema migration, financial calculation change, production D1 mutation or
Worker deployment was performed. The existing delta boundary/publication fixes
are retained. These are local Worker tests, not a new Android/device validation.

`computeChangedIds` / `sync_remote_meta` caching was **not added**: it is a
separate fetch optimization, not the repair for the demonstrated conflict races.
The Android reconciliation follow-up noted below remains outside these tested
server-concurrency fixes; no claim is made that every end-to-end conflict case
has now been proven.

## Original audit: scope and verdict

Verification only: no production implementation, deployment, remote D1 data or financial calculation was changed. Added `worker/test/conflict.concurrent.audit.test.ts` to reproduce two concurrency failures. These tests deliberately assert the desired invariants and are not skipped or marked expected failures.

The current implementation handles the covered sequential conflicts, but cannot yet be described as safe for concurrent updates/deletes of the same record. Atomic publication of the delta cursor (the preceding fix) does not make the earlier conflict decision atomic.

## computeChangedIds / sync_remote_meta

- No `computeChangedIds` implementation was found in the current checkout.
- Android has `SyncRemoteMetaEntity` and `SyncRemoteMetaDao`, keyed by `(collection, doc_id)` with `remote_updated_at_sec`.
- Main Kotlin references are schema/DAO/DI and backup handling; the active sync repository/ingestor does not read or update this metadata map.
- `CloudflareWorkerApi.pull` requests `/api/sync/pull` with a saved global cursor. Worker selects `updated_at > cursor` under the fixed upper boundary and returns full changed records, not a metadata-only manifest followed by document fetches.
- Local ingest uses `last_modified` comparison (incoming wins ties) and unconditional application of server tombstones. This is distinct from the server's vector clock, edit time and version policy.

Thus the proposed stamp-map comparison is not the active Cloudflare mechanism in this checkout. It is a fetch optimization, not a substitute for resolving competing edits. Adding it would require an explicit metadata/record-fetch contract to reduce network payload; checking the map only after full rows arrive does not save their download. Metadata must be updated only with successful local application, not failed/quarantined/deferred records, and invalidated or rebuilt on epoch changes/restores. Pending local edits must remain protected independently.

## Confirmed failures

### Competing update can overwrite the newer winning edit

`worker/src/database.ts`, `updateRecord()`:

1. A reads version 1 and evaluates its edit as acceptable.
2. The test pauses A immediately before the real D1 write batch.
3. B commits a newer edit (`price=999`, edit time now+20).
4. A resumes its older edit (`price=111`, edit time now+10).
5. Its UPDATE has only `WHERE local_uuid = ?`, not a guard against the changed row revision. Stored price becomes **111**, contrary to the sequential resolution policy.

A sequential control test with identical competing edits keeps **999**. This distinguishes a race from a disagreement over the conflict policy. Both requests use valid vector clocks and version 2; no malformed input or remote database is involved.

### Delayed edit can resurrect a deleted row

The same delayed edit contains `deleted_at: null`, as a normal live-row snapshot can. B deletes the row after A's initial deletion check. A's eventual unguarded UPDATE clears the tombstone, so the row is live again. The assertion requiring a retained tombstone fails.

The `existing.deleted_at` check before conflict evaluation is correct for already-deleted rows, but cannot protect a deletion committed after that check.

## Verification

Local workerd/D1 emulation only:

- `npm ci --no-audit --no-fund`: succeeded.
- `npm run typecheck`: passed.
- `npm test -- --reporter=dot`: **209 passed, 2 failed / 211 tests**, 20 files, 74.96s.
- All 208 previous tests still passed; the new sequential control passed; both new concurrent invariants failed.
- Session output: `/home/user/conflict-audit-tests.log`.

No new Android integration tests or physical-device tests were executed for this audit. There is no evidence here that a particular production record has suffered either race.

## Original repair recommendation

Evaluate conflicts against a coherent record/edit-time revision, condition the mutation on that revision still being current, and retry resolution against fresh state if another writer won first. Guard both business-row mutation and its associated edit-time metadata in the atomic batch; otherwise a rejected/no-op write could still corrupt conflict metadata. A process-local mutex is not enough across Worker isolates. Delete-wins must remain protected at commit time, not just at the initial read.

Also validate end-to-end reconciliation of server-rejected edits on Android: push success currently marks the outbox item delivered, while only `status=deleted` gets special local reconciliation. Other losing edits rely on later pull and local last_modified rules. This is a source-level follow-up concern, not an additional reproduced failure in this audit.

Preserve the earlier cursor-publication/read-boundary fix and existing UUID/event identity rules. Do not implement timestamp-map caching as a workaround for these server races.
