-- Saved expenses and salary withdrawals are posted, never drafts. No old rows are rewritten.
ALTER TABLE expenses ADD COLUMN reversal_of_uuid TEXT;
ALTER TABLE expenses ADD COLUMN reversal_reason TEXT;
ALTER TABLE expenses ADD COLUMN reversal_actor TEXT;
ALTER TABLE salary_withdrawals ADD COLUMN reversal_of_uuid TEXT;
ALTER TABLE salary_withdrawals ADD COLUMN reversal_reason TEXT;
ALTER TABLE salary_withdrawals ADD COLUMN reversal_actor TEXT;
CREATE TABLE IF NOT EXISTS financial_period_lock (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  closed_through TEXT NOT NULL DEFAULT ''
);
INSERT OR IGNORE INTO financial_period_lock(id, closed_through) VALUES (1, '');
CREATE TABLE IF NOT EXISTS financial_events (
  id TEXT PRIMARY KEY,
  entity TEXT NOT NULL,
  source_uuid TEXT NOT NULL,
  reversal_uuid TEXT,
  mirror_reversal_uuid TEXT,
  reason TEXT NOT NULL,
  actor TEXT NOT NULL,
  device_id TEXT NOT NULL,
  hotel_day_key TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE(entity, source_uuid)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_expenses_reversal ON expenses(reversal_of_uuid) WHERE reversal_of_uuid IS NOT NULL;
CREATE TRIGGER IF NOT EXISTS expenses_immutable BEFORE UPDATE ON expenses WHEN NEW.expense_type IS NOT OLD.expense_type OR NEW.related_id IS NOT OLD.related_id OR NEW.description IS NOT OLD.description OR NEW.amount IS NOT OLD.amount OR NEW.date IS NOT OLD.date OR NEW.hotel_day_key IS NOT OLD.hotel_day_key OR NEW.category_uuid IS NOT OLD.category_uuid OR NEW.employee_uuid IS NOT OLD.employee_uuid OR NEW.deleted_at IS NOT OLD.deleted_at OR NEW.cash_transaction_id IS NOT OLD.cash_transaction_id OR NEW.cash_flow_uuid IS NOT OLD.cash_flow_uuid OR NEW.local_uuid IS NOT OLD.local_uuid OR NEW.reversal_of_uuid IS NOT OLD.reversal_of_uuid OR NEW.reversal_reason IS NOT OLD.reversal_reason OR NEW.reversal_actor IS NOT OLD.reversal_actor BEGIN SELECT RAISE(ABORT, 'FINANCIAL_IMMUTABLE: use reversal'); END;
CREATE TRIGGER IF NOT EXISTS expenses_no_delete BEFORE DELETE ON expenses BEGIN SELECT RAISE(ABORT, 'FINANCIAL_IMMUTABLE: use reversal'); END;
CREATE TRIGGER IF NOT EXISTS expenses_open_period BEFORE INSERT ON expenses WHEN COALESCE(NULLIF(NEW.hotel_day_key, ''), substr(NEW.date, 1, 10)) <= (SELECT closed_through FROM financial_period_lock WHERE id = 1) BEGIN SELECT RAISE(ABORT, 'FINANCIAL_PERIOD_CLOSED'); END;
CREATE TRIGGER IF NOT EXISTS expenses_no_replace BEFORE INSERT ON expenses WHEN EXISTS(SELECT 1 FROM expenses WHERE local_uuid = NEW.local_uuid) BEGIN SELECT RAISE(ABORT, 'FINANCIAL_IMMUTABLE: duplicate UUID'); END;
CREATE UNIQUE INDEX IF NOT EXISTS idx_salary_withdrawals_reversal ON salary_withdrawals(reversal_of_uuid) WHERE reversal_of_uuid IS NOT NULL;
CREATE TRIGGER IF NOT EXISTS salary_withdrawals_immutable BEFORE UPDATE ON salary_withdrawals WHEN NEW.employee_id IS NOT OLD.employee_id OR NEW.employee_uuid IS NOT OLD.employee_uuid OR NEW.expense_uuid IS NOT OLD.expense_uuid OR NEW.amount IS NOT OLD.amount OR NEW.withdraw_date IS NOT OLD.withdraw_date OR NEW.hotel_day_key IS NOT OLD.hotel_day_key OR NEW.withdrawal_type IS NOT OLD.withdrawal_type OR NEW.reason IS NOT OLD.reason OR NEW.description IS NOT OLD.description OR NEW.deleted_at IS NOT OLD.deleted_at OR NEW.local_uuid IS NOT OLD.local_uuid OR NEW.reversal_of_uuid IS NOT OLD.reversal_of_uuid OR NEW.reversal_reason IS NOT OLD.reversal_reason OR NEW.reversal_actor IS NOT OLD.reversal_actor BEGIN SELECT RAISE(ABORT, 'FINANCIAL_IMMUTABLE: use reversal'); END;
CREATE TRIGGER IF NOT EXISTS salary_withdrawals_no_delete BEFORE DELETE ON salary_withdrawals BEGIN SELECT RAISE(ABORT, 'FINANCIAL_IMMUTABLE: use reversal'); END;
CREATE TRIGGER IF NOT EXISTS salary_withdrawals_open_period BEFORE INSERT ON salary_withdrawals WHEN COALESCE(NULLIF(NEW.hotel_day_key, ''), substr(NEW.withdraw_date, 1, 10)) <= (SELECT closed_through FROM financial_period_lock WHERE id = 1) BEGIN SELECT RAISE(ABORT, 'FINANCIAL_PERIOD_CLOSED'); END;
CREATE TRIGGER IF NOT EXISTS salary_withdrawals_no_replace BEFORE INSERT ON salary_withdrawals WHEN EXISTS(SELECT 1 FROM salary_withdrawals WHERE local_uuid = NEW.local_uuid) BEGIN SELECT RAISE(ABORT, 'FINANCIAL_IMMUTABLE: duplicate UUID'); END;
CREATE TRIGGER IF NOT EXISTS financial_events_no_update BEFORE UPDATE ON financial_events BEGIN SELECT RAISE(ABORT, 'FINANCIAL_AUDIT_IMMUTABLE'); END;
CREATE TRIGGER IF NOT EXISTS financial_events_no_delete BEFORE DELETE ON financial_events BEGIN SELECT RAISE(ABORT, 'FINANCIAL_AUDIT_IMMUTABLE'); END;
CREATE TRIGGER IF NOT EXISTS financial_close_requires_complete_mirrors BEFORE UPDATE ON financial_period_lock WHEN NEW.closed_through > OLD.closed_through AND EXISTS (SELECT 1 FROM expenses e WHERE e.deleted_at IS NULL AND COALESCE(NULLIF(e.hotel_day_key, ''), substr(e.date, 1, 10)) <= NEW.closed_through AND trim(e.expense_type) IN ('رواتب','سحب راتب','سحب من الراتب','سلفة','خصم راتب','خصم من الراتب','خصم','غياب','employee') AND (e.related_id IS NOT NULL OR NULLIF(e.employee_uuid, '') IS NOT NULL) AND NOT EXISTS (SELECT 1 FROM salary_withdrawals w WHERE w.expense_uuid = e.local_uuid AND w.deleted_at IS NULL AND w.amount = e.amount AND w.employee_uuid = e.employee_uuid AND COALESCE(NULLIF(w.hotel_day_key, ''), substr(w.withdraw_date, 1, 10)) = COALESCE(NULLIF(e.hotel_day_key, ''), substr(e.date, 1, 10)))) BEGIN SELECT RAISE(ABORT, 'FINANCIAL_UNRESOLVED_MIRRORS: reconcile before closing'); END;
