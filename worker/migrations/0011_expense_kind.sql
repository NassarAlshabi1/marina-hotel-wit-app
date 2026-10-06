-- 0011 — nullable, contract-checked expense classification.
-- Additive only: legacy rows remain NULL and are classified on read/materialize-on-write.
ALTER TABLE expenses ADD COLUMN expense_kind TEXT
CHECK (expense_kind IS NULL OR expense_kind IN (
  'normal',
  'salary_advance',
  'salary_installment',
  'salary_withdrawal',
  'salary_deduction',
  'unclassified'
));

CREATE INDEX IF NOT EXISTS idx_expenses_kind ON expenses(expense_kind);
