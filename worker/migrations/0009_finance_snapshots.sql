-- ═══════════════════════════════════════════════════════════════
--  0009 — finance_snapshots: اعتماد نسخة أسبوعية من نموذج التدفقات
--
--  خطوات التحديث الأسبوعي (§8): عند اعتماد نسخة النموذج يُحفظ توقع
--  الـ13 أسبوعاً كاملاً (forecast_json) مع ملخصه الرقمي، ثم تُقارن
--  الأسابيع المنتهية فعلياً بحركات D1 الحية عبر /api/finance/variance
--  بإنذارات 5% (أخضر) / 10% (أصفر) / >10% (أحمر).
--
--  النسخ للقراءة فقط (append-only): لا UPDATE ولا DELETE من API —
--  سجل الحوكمة يبقى سليماً؛ الحجم نمو أسبوعي واحد (~10KB) ضئيل.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS finance_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL DEFAULT '',
  scenario_key TEXT NOT NULL DEFAULT 'base',
  scenario_json TEXT NOT NULL DEFAULT '{}',
  model_start TEXT NOT NULL,
  model_end TEXT NOT NULL,
  opening_balance REAL NOT NULL DEFAULT 0,
  total_inflow REAL NOT NULL DEFAULT 0,
  total_outflow REAL NOT NULL DEFAULT 0,
  financing_need REAL NOT NULL DEFAULT 0,
  weeks_below_threshold INTEGER NOT NULL DEFAULT 0,
  forecast_json TEXT NOT NULL,
  approved_by TEXT NOT NULL DEFAULT '',
  approved_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_finance_snapshots_approved
  ON finance_snapshots(approved_at DESC);
CREATE INDEX IF NOT EXISTS idx_finance_snapshots_scenario
  ON finance_snapshots(scenario_key, approved_at DESC);
