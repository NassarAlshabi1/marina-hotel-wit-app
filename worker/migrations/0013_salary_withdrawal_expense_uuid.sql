-- 0013_salary_withdrawal_expense_uuid.sql
-- Parity unification: ports branch3's 0013 unique-index rule to branch2.
-- IMPORTANT: branch2's existing migration 0011_portable_financial_relationships.sql
-- already creates `salary_withdrawals.expense_uuid` (it is part of the
-- unified 4-UUID bridge). Therefore this migration creates ONLY the
-- unique partial index — re-adding the column would fail with
-- `duplicate column name` on a fresh install.
-- Branch3's worker originally added both the column AND the index in 0013
-- because B3's 0011 only added cycle_uuid + carry_over_logs.employee_uuid.
-- The unified migration set canonicalises on the B2 split (column in 0011,
-- index in 0013) so the two branches converge on the same final shape.
CREATE UNIQUE INDEX IF NOT EXISTS idx_salary_withdrawals_active_expense
  ON salary_withdrawals(expense_uuid) WHERE deleted_at IS NULL AND expense_uuid IS NOT NULL;
