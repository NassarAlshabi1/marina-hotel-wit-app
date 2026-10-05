# Flutter salary integrity hardening

Date: 2026-10-06 (Asia/Aden). Target: the Flutter application in `mobile/`.

## Implemented

- **R17 — direct D1 writes disabled:** `CloudflareD1Service.uploadData` now fails
  before reading rows, generating SQL, or making HTTP requests. D1 probing uses
  `SELECT 1` only and no longer claims DML/DDL permission. Normal Worker/outbox
  synchronization and the safe `CloudflareD1PushMirror` path remain available.
- **R11 — guarded JSON restore:** restore and Cloudflare push/pull share one
  process lock. Restore is rejected while local primary-undelivered outbox work,
  pending parent links, or quarantined pull records exist. Before destructive
  table changes it resets the pull checkpoint/full-sync state and disables
  automatic cloud synchronization. It clears database sync metadata while
  retaining local outbox and audit evidence. Recognized backup tables are
  validated even when they are intentionally not imported. Raw live SQLite
  replacement is disabled; JSON is now the default restorable backup format.
- **R15 — salary UUID indexes:** local schema 68 → 69 adds indexes for
  `employee_uuid` on `salary_withdrawals`, `salary_cycles`, and
  `salary_payments`, both for fresh databases and upgrades. The migration is
  additive and does not rewrite financial data.

The existing Flutter hardening for the other historical findings remains in
place: remote numeric IDs are not treated as local employee IDs, unresolved
pull relationships are deferred/quarantined, salary expense classification
includes advances, and salary/outbox records are retained rather than silently
ignored.

## Verification added

- Direct D1 upload fails before row reads or network activity.
- D1 diagnostics issue read-only SQL only.
- Raw SQLite restore is rejected.
- Fresh-schema index presence and `EXPLAIN QUERY PLAN` coverage for all three
  salary employee UUID lookups.

No production D1 mutation, Appwrite migration, or deployment is performed by
this change.
