-- 0011: stable UUID links for salary payments and carry-over logs.
-- Add nullable bridge columns only; legacy rows are intentionally left NULL
-- until a trustworthy source-of-truth can be used for any historical backfill.
ALTER TABLE salary_payments ADD COLUMN cycle_uuid TEXT;
ALTER TABLE salary_carry_over_logs ADD COLUMN employee_uuid TEXT;

CREATE INDEX IF NOT EXISTS idx_salary_payments_cycle_uuid
  ON salary_payments(cycle_uuid);
CREATE INDEX IF NOT EXISTS idx_salary_carryover_employee_uuid
  ON salary_carry_over_logs(employee_uuid);
