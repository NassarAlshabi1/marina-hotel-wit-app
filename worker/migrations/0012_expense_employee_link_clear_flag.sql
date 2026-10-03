-- Persist explicit employee-link removal so pull clients can distinguish it
-- from a legacy/null snapshot that must not erase a valid local relationship.
ALTER TABLE expenses
  ADD COLUMN employee_link_cleared INTEGER NOT NULL DEFAULT 0;
