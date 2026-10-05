# Android/Kotlin: salary integrity review and repair

Date: 2026-10-06 (Asia/Aden). Target selected by the user: the current Android/Kotlin application and Worker, NOT the historical Flutter/Appwrite branch. The session stays on `arena/01a0ffdb-marina-hotel-wit-app`.

## Implemented in this pass

### R17: stop destructive direct D1 uploads

`CloudflareD1BackupService.uploadData` now fails before credentials, SQL generation or HTTP requests. The old `INSERT OR REPLACE` data-upload implementation was removed rather than merely hiding its button. The UI disables the action and directs users to Worker sync. Connection probing now uses read-only requests and `SELECT 1`; it no longer INSERTs into a supposed missing table or creates/drops a probe table. DML/DDL permission flags are not claimed available.

Read-only D1 diagnostics still use the user's previously configured credentials. This change does not claim that the entire credential-storage system has been migrated or audited, and does not disable normal Worker outbox upload or local snapshot export.

### R11: safe restore admission and checkpoints

- JSON restore shares the existing process sync mutex, so it cannot overlap a push/pull. Restore stays caller-owned: cancellation still rolls back Room rather than continuing after the caller exits.
- Under the Room transaction, reject restore while local primary-undelivered outbox entries, pending parent-link payloads or quarantined records exist. These are retained for review, NOT automatically deleted.
- Before the first destructive table change, synchronously commit the preference reset: cursor and last-success time zero, replay pending, full-sync/normalization completion false, automatic cloud sync disabled.
- Preferences and SQLite cannot share a transaction. If the subsequent import fails or rolls back, the conservative reset remains; this can cause a replay after explicit re-enablement, never a checkpoint beyond restored data.
- Clear database `sync_state` / unused `sync_remote_meta` in the import transaction and do not import another device's sync state from backup.
- Preserve login, device identity, server epoch and evidence/outbox. The UI reports that automatic synchronization remains disabled pending review. Explicit manual sync is still an intentional user action; this is not a new global maintenance lock on all local edits.
- Raw SQLite replacement remains disabled. The existing post-restore repair service remains a separate operation; no claim is made that import + all subsequent derived-data repairs form one transaction.

### R15: missing employee UUID indexes

Room schema **73 → 74** adds non-unique indexes on `salary_withdrawals.employee_uuid`, `salary_cycles.employee_uuid`, and `salary_payments.employee_uuid`. The entities declare the same indexes, so both fresh installations and upgrades receive them. Migration only creates indexes; no financial backfill, deletion, merge or field rewrite. Existing employee name/status and carry-over/cycle-reference indexes remain.

New migration tests use Room's real schema validation and `EXPLAIN QUERY PLAN`, covering fresh creation and 73→74 while retaining amounts/outbox. Existing 70/71/72 upgrade tests now reach schema 74.

## Mapping the historical findings to this checkout

| Findings | Current Android evidence / disposition |
|---|---|
| R1 | No equivalent Appwrite post-sync salary DELETE routine. Pull failures are stored in `sync_quarantine`; unresolved parents have durable `pending_sync_links`. No new orphan deletion was introduced. |
| R2 / R8a | `SyncIngestorRegistry` resolves UUID first, never falls back from a supplied unresolved UUID, and does not treat incoming numeric employee IDs as local IDs. Existing persisted local links are handled separately. |
| R3 / R12 / R13 | Salary expense mirrors already use `expense_uuid` plus employee ownership checks. `saveFromExpense` updates employee UUID; repeated equal-value same-day events remain independent. The Flutter amount/day/marker matcher is not this implementation. |
| R4 | `ExpensesRepositoryImpl` already encloses expense, mirror and outbox in one Room transaction. Existing rollback and repeated-edit tests cover this. |
| R5 | Failed/quarantined application blocks the saved cursor; deferred links survive separately. This differs from the historical skip-and-advance engine. |
| R6 | Existing orphan salary retry policy and primary-undelivered outbox tracking retain failed work. Flutter's cited `return true` handler is absent. |
| R7 | Kotlin registry includes all six named entities and fails unknown entities rather than counting an ignored switch branch as applied. A wholesale Flutter registry import is not needed. |
| R8b | `EmployeeExpenseTypes` and repository salary-type filters already include `سلفة`. |
| R9 | Flutter bulk mappers are absent. Kotlin entities/outbox carry the stable UUID fields; prior UUID/carry-over tests remain. No production historical backfill performed. |
| R10 | Current JSON restore uses raw column maps and retains provided primary IDs; it is not the cited Google Drive re-numbering path. Uncertain historical relationships are not automatically guessed. |
| R11 | Fixed above for actual Kotlin cursor storage (preferences), not the absent Flutter raw checkpoint store. |
| R14 | Full elimination of `serverId` is **not done**. A unique D1 server-ID shadow is still accepted only for UUID-absent legacy parents. Removing it requires a separately validated historical-data migration; never substitute a raw local-ID fallback. |
| R15 | Fixed above, with additive Room 74 migration. |
| R16 | **Follow-up implemented; Android verification pending:** stable `expense_kind` now spans Room 75, writers, outbox, pull, JSON restore and Worker migration 0015. Description edits preserve the kind. Ambiguous historical rows retain previous arithmetic and are flagged, not guessed. See [contract and rollout](expense-kind-contract.md). No production migration/deployment was executed. |
| R17 | Dangerous direct D1 writer disabled; read-only diagnostics retained. |
| R18 | Current JSON backup import copies available database columns, unlike the lossy Flutter DAO mapper. Kotlin Expense entity/domain mapping already carries employee UUID and auto-generated flag. Full heterogeneous legacy-import validation is not newly established by this pass. |

This is not approval of all historical migration/backfill plans, not a claim that every report item is fixed, and not a claim of full end-to-end financial convergence. The R16 implementation has a separate verification/rollout record; historical ambiguity is not automatically repaired. Full retirement of legacy server-ID resolution remains follow-up work. No Appwrite snapshot/backfill, new `hotel_sync` deployment, Google Drive engine migration, or financial-view rewrite was run.

## Tests

- Worker full local workerd/D1 suite: **214 passed / 20 files**, 86.67s; TypeScript production/test typecheck passed. No Worker source changed in this pass.
- Added five Android restore/direct-upload regressions and two index/migration regressions; retained cancellation/rollback, UUID, quarantine, independent same-day event and outbox tests.
- Android unit tests **passed** in run [37378526466](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/runs/37378526466), job `111994036676`, on final code `8a19cbb`. This includes all seven new regressions and the existing Room cancellation/rollback/UUID/financial cases. APK building was still in progress at verification time.
- Run `37377855214` initially found a malformed-backup regression (`sync_state: "bad"` was ignored). Fixed by validating all recognized fields before restoring, even metadata intentionally not imported. The final run above passed without skipping or weakening that test. Run `37377536800` was superseded/cancelled, not a pass.
- No production D1 changes or deployment. No new physical-device or 1 GB RAM validation; existing JSON full-memory limitations remain.
