-- 0015_expense_kind.sql
-- Parity unification: ports branch3's 0015 migration to branch2.
-- Additive. No guessing of UUIDs, no bulk financial rewrite or cursor bypass.
-- NULL is a pre-contract row: pull exposes a conservative legacy classification;
-- the next accepted edit materialises its kind atomically with updated_at.
ALTER TABLE expenses ADD COLUMN expense_kind TEXT
  CHECK (expense_kind IS NULL OR expense_kind IN (
    'normal','salary_advance','salary_installment','salary_withdrawal',
    'salary_deduction','unclassified'
  ));
