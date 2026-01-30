-- إضافة جدول سجل صحة قاعدة البيانات
CREATE TABLE IF NOT EXISTS database_health_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scanned_at INTEGER NOT NULL,
  health_score REAL NOT NULL,
  invalid_server_ids INTEGER DEFAULT 0,
  orphan_payments INTEGER DEFAULT 0,
  orphan_expenses INTEGER DEFAULT 0,
  total_issues INTEGER DEFAULT 0,
  status TEXT NOT NULL,
  scan_duration_ms INTEGER,
  scan_type TEXT DEFAULT 'quick',
  fixes_applied INTEGER DEFAULT 0,
  notes TEXT,
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- فهرس للبحث السريع
CREATE INDEX IF NOT EXISTS idx_health_log_scanned_at 
ON database_health_log(scanned_at DESC);

-- فهرس للحالة
CREATE INDEX IF NOT EXISTS idx_health_log_status 
ON database_health_log(status);

-- حذف السجلات القديمة (أكثر من 90 يوم)
DELETE FROM database_health_log 
WHERE scanned_at < strftime('%s', 'now', '-90 days');
