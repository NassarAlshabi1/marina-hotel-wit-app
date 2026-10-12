-- 0012_expense_employee_link_clear_flag.sql
-- Parity unification: ports branch3's 0012 migration to branch2.
-- Persists explicit employee-link removal so pull clients can distinguish
-- it from a legacy/null snapshot that must not erase a valid local
-- relationship. The flag is INTEGER NOT NULL DEFAULT 0 to mirror branch3's
-- worker schema.sql and the Android Room entity (ExpenseEntity.kt).
ALTER TABLE expenses
  ADD COLUMN employee_link_cleared INTEGER NOT NULL DEFAULT 0;
