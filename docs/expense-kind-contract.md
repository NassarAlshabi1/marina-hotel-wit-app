# Stable expense classification (R16)

Date: 2026-10-06, Asia/Aden. Scope: current Android/Kotlin + Worker; no Flutter import.

## Contract

`expenses.expense_kind` is the authoritative classification when present. The nullable field is an explicit compatibility boundary for old rows/payloads, not an implicit `normal` default that could erase a financial type.

| Value | Meaning |
|---|---|
| `normal` | Ordinary non-salary expense |
| `salary_advance` | Advance paid to the employee |
| `salary_installment` | Repayment installment of an advance, not a second manual deduction |
| `salary_withdrawal` | Salary withdrawal |
| `salary_deduction` | Manual/other actual salary deduction |
| `unclassified` | Historical automated deduction whose current description cannot prove its original category |

The extra deduction value is essential: the four initially proposed values cannot faithfully represent the existing manual-deduction arithmetic. `unclassified` prevents guessing that an automated deduction with an edited description is an installment.

## Android implementation

- Room schema **74 → 75**, additive nullable `expense_kind TEXT`.
- A one-time migration assigns categories according to the previous exact type rules. An automated `خصم من الراتب` with the existing `قسط سلفة` marker becomes an installment; without that evidence it becomes `unclassified`, not a guessed installment. Amounts, UUIDs, timestamps, identities, outbox and versions are not rewritten.
- The classifier exists in `ExpenseKind`; domain/entity mappers retain the field. Repository writes validate supplied values and fill the kind on new records.
- A description-only edit preserves the stored kind, including records first received from another device. An explicit change of the expense **type** in the existing editor is treated as a classification action; text edits alone are not.
- The current repository editor does not expose an arbitrary kind-edit control. Resolving historical unclassified records requires reviewed evidence, not another guessed background repair.
- Pull validates supplied kinds and quarantines invalid values. Missing/null kind from a legacy response cannot erase an existing stored kind; on a first legacy import it uses the conservative compatibility classifier.
- Salary entitlement arithmetic switches on the kind, not the description. The nullable fallback is limited to legacy/untyped inputs. For unclassified historical auto-deductions, the old deduction arithmetic is retained and the UI explicitly shows a review warning. This does not claim to correct amounts that were already misclassified before this release.
- Salary expense filtering / advance exclusion and local mirror ownership use the kind where present, with legacy compatibility for NULL rows. Independent same-day equal-amount expenses remain independent.
- JSON backup/restore retains kinds and the other source columns. Legacy backups without kind are classified once on import; invalid kinds abort/roll back import.

## Worker implementation

- Fresh schema has the nullable field plus a CHECK constraint on the closed values.
- Migration **0015_expense_kind.sql** only adds that column/constraint. It performs no production backfill and no unsequenced UPDATE of financial rows.
- Create validates or derives a legacy kind. Updates from old clients preserve the existing classification; explicit valid kinds from upgraded clients are accepted. CAS retry continues to evaluate the original payload against fresh state.
- Missing schema causes typed expense writes to fail rather than silently filtering out the column.
- The next accepted write materializes a NULL legacy kind inside the existing atomic business-row/clock/edit-time transaction. A legacy pull exposes the conservative inferred kind without mutating the database.
- Confirmed AI expense writes also supply a kind in their existing atomic write batch.
- Push validation rejects unknown values as `validation_error`, rather than acknowledging a discarded field.

## Safe rollout and compatibility

An old Worker filters columns it does not know. Merely shipping a new Android field would therefore be unsafe. The authenticated `/api/health/d1` now advertises `expense_kind: true` only when this Worker implementation can see the migrated D1 column.

Android probes this capability before a batch containing a non-delete typed expense. The probe has an eight-second cancellable limit. Old/missing/false capability or a failed probe prevents the push call; the existing outbox failure path retains the pending edits. This adds one small capability request per affected batch. Untyped legacy operations, non-expense operations and deletes retain their previous path.

Deployment order, after backup and target verification:

1. Apply additive D1 migration 0015 once using the existing migration discipline.
2. Deploy the updated Worker and verify authenticated D1 health reports `expense_kind: true`.
3. Install Android with Room 75 and verify two-device edits.

No production D1 migration, Worker deployment, epoch rotation, UUID backfill or financial-data repair was executed in this task. Do not run `schema.sql` as a production reset. Do not downgrade an upgraded local database by destructive fallback.

Older apps still use their old description-based readers; their report behavior cannot be corrected by a server change alone. Upgrade all reporting devices before treating classification as converged. No new `server_seq`, `sync_changes`, second UUID or deletion Boolean was introduced; cursor ordering, Vector Clock/CAS, tombstones and financial equations remain.

## Verification

- Worker: TypeScript production/test checks passed; **227 tests / 21 files passed**, 81.06s (`/home/user/expense-kind-worker-final.log`). Thirteen added cases cover legacy mappings, explicit/manual types, description edits, pull propagation, invalid kinds, additive migration, missing migration and health capability.
- Android: ten added tests cover calculation stability and independent events, Room 74→75, repository/outbox, different numeric employee IDs on pull, old/invalid payloads, backup/legacy restore and capability admission. CI run `37382042171` compiled production and test sources, then found one new test asserting the raw UUID instead of the existing `uuid:` quarantine key. The assertion is corrected to the actual entity/key contract; a fresh full run is required before claiming Android success.
- Existing migration chains now target Room 75, retaining money/outbox validation. No new device, production or 1 GB RAM benchmark was performed.
