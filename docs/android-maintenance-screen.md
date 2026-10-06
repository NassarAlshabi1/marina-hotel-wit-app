# Settings → Maintenance

**Current mode:** diagnostics plus explicit, confirmed UUID-cache repairs, as
specified in the maintenance-center section below. The original read-only release
is retained here as historical context.

## Original read-only release

Entry: **الإعدادات → الصيانة → صيانة البيانات** (`maintenance` route).
The route checks the current user's existing `isAdmin` policy before composing the
screen/creating its ViewModel. Non-admin users see a denial and a Back action.

The screen is local and read-only:

- actual Room database version and snapshot timestamp;
- quarantine and pending-parent counts;
- missing/blank `salary_carry_over_logs.employee_uuid` and
  `salary_payments.cycle_uuid` counts for non-deleted rows;
- saved `salary_cycles.expected_amount`, `actual_paid`, `remaining_amount` totals
  for all non-deleted cycles (not a date-range report or recomputed balance);
- quarantine entity/key/reason pages of 50 records. The SELECT omits payload and
  bounds reason text to 500 characters; no full quarantine table is loaded;
- links to sync health, sync error history, and backup/restore.

Manual refresh and page navigation read a consistent local transaction off Main.
A shrinking list clamps to the last existing page. Loading/errors/empty state are
explicit; stale results are labelled on refresh failure. The screen does not run
SQL entered by a user, repair links, delete evidence, upload data, or start sync.
Opening a linked tool does not automatically execute that tool's actions.

No entity/schema migration or financial algorithm changes. New Room repository
regressions cover empty data, correct salary columns, deleted-row exclusions,
UUID gaps, read-only behavior, bounded quarantine projection and page clamping.
The complete unit-test step passed for application source `ddd0d0e` in
[run 37239788276](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/runs/37239788276),
including the three new repository regression cases. This also compiled the new
Compose route/screen and Hilt wiring. Signed release APK build was still running
at this update; UI navigation/rendering and role gating still require device
verification. No all-green CI or actual-1-GiB device result is claimed.

## Maintenance center — diagnostics and confirmed local repairs

The initial read-only screen above is superseded by four tabs: overview,
searchable/filterable quarantine, safe repair preview, and paginated repair history.

- Added missing-parent, conflicting-cache and canonical duplicate-parent UUID
  counters. `PRAGMA quick_check(1)` is an explicit read-only structural check, not
  a financial audit. Repairs also require a successful quick check.
- Quarantine search uses bound literal substring matching; reasons and metadata
  remain bounded. Details show reason/key/payload character count and guidance,
  never raw payload. Report export uses Android's document picker and contains only
  snapshot counts/integrity/salary totals, not guests, UUIDs, search text or payloads.
- Repair is intentionally limited to filling EMPTY `employee_uuid` in salary
  carry-over logs and EMPTY `cycle_uuid` in salary payments from the stored LOCAL
  parent ID. No retargeting, deletion, merge, quarantine replay, financial
  recalculation, outbox mutation, version or timestamp changes occur.
- Existing/deleted/missing/ambiguous parents, duplicate child UUIDs, conflicting
  payment employee UUIDs, quarantine/pending-inbox children and undelivered outbox
  children are excluded. Unresolved cases remain for manual investigation.
- Preview is capped at 100 patches; confirmations are service-issued, single-use,
  bound to the current admin session, expire after five minutes, and are revalidated
  inside the same SQLite write transaction that performs the repair. Concurrent
  sync/repair is rejected by the existing operation runner gate. Navigation does
  not cancel admitted work; Android/process/force-stop limitations remain.
- BEFORE cache writes, an app-private AtomicFile preimage is written, fsynced,
  read back and hashed. This is a **backup of affected UUID fields only**, not a
  full database backup. The UI explicitly distinguishes it and links to full backup.
  It is capped at 512 KiB and does not load whole tables or whole payloads.
- Patch details and completed run status commit atomically with cache updates.
  Errors roll back patches. Failure status is recorded afterwards where storage
  allows; a crash can leave `pending`/unknown, never a fabricated success. A late
  cancellation must not overwrite an already-committed success audit.
- Existing local `auto_fix_runs` / `restore_fix_log` tables are reused, isolated by
  source `maintenance_uuid_cache`; no schema migration or canceled period-lock /
  reversal feature is introduced. History uses 20 rows per page. Completed backups
  can be exported explicitly through the document picker after SHA-256 validation.
  No automatic undo/restore of these preimages is implemented.

Added service tests for confirmation/field isolation/audit/backup, backup failure,
stale preview, ambiguity, unsupported rows, authorization/session change, sync
exclusion, transactional rollback and bounded/expired preview; repository tests
cover literal search, bounded details, quick check and history paging.

### Verification for the maintenance center

The full `testDebugUnitTest` step passed for source `89fd4be` in
[run 37248379722](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/runs/37248379722),
including 10 repair-service tests and 2 additional repository cases. Compilation
of the new Compose UI, Hilt graph, and Room queries passed in that step. Source
identity/cache lengths are bounded in SQL before materializing backup entries.

At this update the signed APK build and emulator smoke were still running; the
quality job in [37248379740](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/runs/37248379740)
was failed. No all-green CI, device UI/SAF navigation, crash-injection proof,
production data mutation, or actual-1-GiB performance claim is made.
