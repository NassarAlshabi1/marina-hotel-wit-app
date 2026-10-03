-- 0013: explicit source identity. No guessing/backfill of legacy exp_N values.
ALTER TABLE salary_withdrawals ADD COLUMN expense_uuid TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_salary_withdrawals_active_expense
  ON salary_withdrawals(expense_uuid) WHERE deleted_at IS NULL AND expense_uuid IS NOT NULL;
