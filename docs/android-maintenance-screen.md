# Settings → Maintenance

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
UI navigation/rendering still requires device verification; CI tests/build pending.
