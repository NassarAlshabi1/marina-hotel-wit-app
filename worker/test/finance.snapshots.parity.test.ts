// ═══════════════════════════════════════════════════════════════
//  finance.snapshots.parity.test.ts — قفل تكافؤ جداول الحوكمة الموحَّدة
//
//  الالتزام 4df4118 (دمج PR #619) أضاف إلى D1:
//    • 0008: فهرس TTL على idempotency_log(processed_at) لتنظيف cron.
//    • 0009: جدول finance_snapshots (سجل حوكمة append-only) + فهرسين.
//  وكان التحقق منهما **يدوياً فقط** (نصّ رسالة الالتزام: «SQLite schema
//  validation» بلا اختبار). هذا الملف يقفل العقد آلياً في مجموعة vitest،
//  ومقابله على أندرويد في `FinancialMigrationTest.migrate76To77…`.
//
//  ملاحظة مقصودة (فرق موثَّق): D1 ينشئ فهرسي الحوكمة بـ`approved_at DESC`،
//  بينما Room ينشئهما ASC لأن `@Index` لا يقبل ترتيباً. الفرق بلا أثر وظيفي
//  (SQLite يمسح الفهرس في الاتجاهين بالكفاءة نفسها تقريباً) — والاختباران
//  يسجّلان الاتجاهين صراحةً بدل ادّعاء تطابق حرفي غير قائم.
// ═══════════════════════════════════════════════════════════════

import { beforeEach, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import migrationSql0008 from '../migrations/0008_idempotency_log_cleanup.sql?raw';
import migrationSql0009 from '../migrations/0009_finance_snapshots.sql?raw';
import { resetDb, schemaStatements } from './helpers';

interface ColumnInfo {
  name: string;
  type: string;
  notnull: number;
  dflt_value: string | null;
}

/** العقد الكامل لجدول finance_snapshots (من 0009 / schema.sql). */
const EXPECTED_COLUMNS: ReadonlyArray<[string, string, number, string | null]> = [
  // `id INTEGER PRIMARY KEY AUTOINCREMENT` بلا NOT NULL صريح: SQLite يبلّغ
  // notnull=0 للـPK الصحيح (والمعنى واحد: لا NULL فيه، والإدراج بلا قيمة
  // يُولّد تلقائياً). Room ينشئ نفس العمود بـ`NOT NULL` صريح فيبلّغ 1 — فرق
  // تصريحي بلا أثر (انظر FinancialMigrationTest المقابل في أندرويد).
  ['id', 'INTEGER', 0, null],
  ['label', 'TEXT', 1, "''"],
  ['scenario_key', 'TEXT', 1, "'base'"],
  ['scenario_json', 'TEXT', 1, "'{}'"],
  ['model_start', 'TEXT', 1, null],
  ['model_end', 'TEXT', 1, null],
  ['opening_balance', 'REAL', 1, '0'],
  ['total_inflow', 'REAL', 1, '0'],
  ['total_outflow', 'REAL', 1, '0'],
  ['financing_need', 'REAL', 1, '0'],
  ['weeks_below_threshold', 'INTEGER', 1, '0'],
  ['forecast_json', 'TEXT', 1, null],
  ['approved_by', 'TEXT', 1, "''"],
  ['approved_at', 'INTEGER', 1, null],
];

async function columnsOf(table: string): Promise<Map<string, ColumnInfo>> {
  const res = await env.DB.prepare(`PRAGMA table_info(${table})`).all<ColumnInfo>();
  return new Map(res.results.map((c) => [c.name, c]));
}

async function indexNamesOf(table: string): Promise<string[]> {
  const res = await env.DB.prepare(`PRAGMA index_list(${table})`).all<{ name: string }>();
  return res.results.map((r) => r.name).sort();
}

async function indexColumnsOf(indexName: string): Promise<string[]> {
  const res = await env.DB.prepare(`PRAGMA index_info(${indexName})`).all<{ name: string }>();
  return res.results.map((r) => r.name);
}

async function indexSqlOf(indexName: string): Promise<string> {
  const row = await env.DB.prepare(
    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
  )
    .bind(indexName)
    .first<{ sql: string | null }>();
  return row?.sql ?? '';
}

async function applyRaw(sqlText: string): Promise<void> {
  for (const stmt of schemaStatements(sqlText)) {
    await env.DB.prepare(stmt).run();
  }
}

describe('finance_snapshots — عقد المخطط على D1', () => {
  beforeEach(async () => {
    await resetDb();
  });

  it('الجدول موجود بأعمدته الأربعة عشر وأنواعها وقيد NOT NULL وافتراضياتها', async () => {
    const columns = await columnsOf('finance_snapshots');
    expect(columns.size).toBe(EXPECTED_COLUMNS.length);
    for (const [name, type, notnull, dflt] of EXPECTED_COLUMNS) {
      const info = columns.get(name);
      expect(info, `عمود مفقود: ${name}`).toBeDefined();
      expect(info!.type, `نوع مختلف: ${name}`).toBe(type);
      expect(info!.notnull, `يجب NOT NULL: ${name}`).toBe(notnull);
      expect(info!.dflt_value, `افتراضي مختلف: ${name}`).toBe(dflt);
    }
  });

  it('فهرسا الحوكمة موجودان بأعمدتهما وبترتيب DESC المقصود على D1', async () => {
    expect(await indexNamesOf('finance_snapshots')).toEqual([
      'idx_finance_snapshots_approved',
      'idx_finance_snapshots_scenario',
    ]);
    expect(await indexColumnsOf('idx_finance_snapshots_approved')).toEqual(['approved_at']);
    expect(await indexColumnsOf('idx_finance_snapshots_scenario')).toEqual([
      'scenario_key',
      'approved_at',
    ]);
    // الاتجاه DESC هنا مقصود ومختلف عن Room (ASC) — انظر ترويسة الملف.
    expect(await indexSqlOf('idx_finance_snapshots_approved')).toContain('DESC');
    expect(await indexSqlOf('idx_finance_snapshots_scenario')).toContain('DESC');
  });

  it('الإدراج بأعمدة الحوكمة الإلزامية فقط يُكمله الافتراضيون (append-only عملي)', async () => {
    await env.DB.prepare(
      `INSERT INTO finance_snapshots (model_start, model_end, forecast_json, approved_at)
       VALUES ('2026-W40', '2027-W01', '[]', 1760000000)`,
    ).run();
    const row = await env.DB.prepare('SELECT * FROM finance_snapshots LIMIT 1').first<
      Record<string, unknown>
    >();
    expect(row).not.toBeNull();
    expect(row!.scenario_key).toBe('base');
    expect(row!.scenario_json).toBe('{}');
    expect(row!.label).toBe('');
    expect(row!.approved_by).toBe('');
    expect(row!.opening_balance).toBe(0);
    expect(row!.weeks_below_threshold).toBe(0);

    // عمود إلزامي غائب (model_start) ⇒ رفض صريح لا صف ناقص.
    await expect(
      env.DB.prepare(
        `INSERT INTO finance_snapshots (model_end, forecast_json, approved_at)
         VALUES ('2027-W01', '[]', 1760000000)`,
      ).run(),
    ).rejects.toThrow();
  });

  it('فهرس TTL على idempotency_log(processed_at) موجود — عقد تنظيف cron اليومي', async () => {
    expect(await indexNamesOf('idempotency_log')).toContain('idx_idempotency_processed_at');
    expect(await indexColumnsOf('idx_idempotency_processed_at')).toEqual(['processed_at']);
  });
});

describe('migration 0009 — آمنة على نشر قديم (legacy) وعلى إعادة التشغيل', () => {
  beforeEach(async () => {
    await resetDb();
  });

  it('تُنشئ الجدول لو غاب، وتُعيد التشغيل بلا أثر (idempotent) مع بقاء البيانات', async () => {
    // محاكاة نشر قديم: الجدول غائب تماماً.
    await env.DB.prepare('DROP TABLE IF EXISTS finance_snapshots').run();
    await applyRaw(migrationSql0009);

    const columns = await columnsOf('finance_snapshots');
    expect(columns.size).toBe(EXPECTED_COLUMNS.length);
    expect(await indexNamesOf('finance_snapshots')).toEqual([
      'idx_finance_snapshots_approved',
      'idx_finance_snapshots_scenario',
    ]);

    // إعادة التطبيق (سلوك `db:migrate:finance` عند إطلاقه مرتين) لا تمحو صفاً.
    await env.DB.prepare(
      `INSERT INTO finance_snapshots (model_start, model_end, forecast_json, approved_at)
       VALUES ('2026-W40', '2027-W01', '[]', 1760000000)`,
    ).run();
    await applyRaw(migrationSql0009);
    const count = await env.DB.prepare(
      'SELECT COUNT(*) AS c FROM finance_snapshots',
    ).first<{ c: number }>();
    expect(Number(count?.c ?? 0)).toBe(1);
  });

  it('0008 قابلة لإعادة التشغيل بلا خطأ وتحافظ على نفس الفهرس', async () => {
    await applyRaw(migrationSql0008);
    await applyRaw(migrationSql0008);
    expect(await indexColumnsOf('idx_idempotency_processed_at')).toEqual(['processed_at']);
  });
});
