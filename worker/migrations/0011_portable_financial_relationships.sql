-- Provider-independent financial relationships.
--
-- These columns are nullable by design. Existing D1 numeric references came
-- from device-local SQLite ids, so this migration MUST NOT infer UUID links
-- from matching employee, amount, date, description, or coincident numbers.
-- Historical nulls are surfaced for reconciliation; new clients send UUIDs.
ALTER TABLE expenses ADD COLUMN withdrawal_uuid TEXT;
ALTER TABLE salary_withdrawals ADD COLUMN expense_uuid TEXT;
ALTER TABLE salary_payments ADD COLUMN cycle_uuid TEXT;
ALTER TABLE salary_carry_over_logs ADD COLUMN employee_uuid TEXT;

CREATE INDEX IF NOT EXISTS idx_expenses_withdrawal_uuid
  ON expenses(withdrawal_uuid);
CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_expense_uuid
  ON salary_withdrawals(expense_uuid);
CREATE INDEX IF NOT EXISTS idx_salary_payments_cycle_uuid
  ON salary_payments(cycle_uuid);
CREATE INDEX IF NOT EXISTS idx_salary_carryover_employee_uuid
  ON salary_carry_over_logs(employee_uuid);
