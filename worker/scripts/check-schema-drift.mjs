#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════
//  check-schema-drift.mjs — حارس تطابق «التثبيت الجديد» مع «الترقية»
//
//  المشكلة التي يمنعها: ملف `schema.sql` هو ما ينفّذه `npm run db:init`
//  على قاعدة جديدة، وملفات `migrations/*.sql` هي ما ينفّذه من لديه قاعدة
//  قائمة. عندما تُضاف migration ولا تُنسخ في `schema.sql` (أو العكس) ينتج
//  اسكيمان مختلفان لنفس التطبيق: قاعدة جديدة بلا فهرس/عمود، أو ترقية
//  تُعيد إنشاء عمود موجود فتفشل.
//
//  الحالة الحقيقية التي كشفها هذا الحارس (2026-11-23):
//    migrations/0006 أنشأ idx_salary_withdrawals_employee_uuid ولم يكن
//    موجوداً في schema.sql → كل تثبيت جديد يبحث بحثاً كاملاً في
//    salary_withdrawals عند الفلترة بـ employee_uuid.
//
//  التشغيل: npm run check:schema   (يفشل بـ exit 1 عند أي انحراف)
// ════════════════════════════════════════════════════════════════════

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const schema = readFileSync(join(root, 'schema.sql'), 'utf8');

/** جداول CREATE TABLE في ملف SQL: اسم → أعمدة. */
function tablesOf(sql) {
  const out = new Map();
  const re = /CREATE TABLE\s+(?:IF NOT EXISTS\s+)?["`]?(\w+)["`]?\s*\(([\s\S]*?)\n\);/gi;
  let m;
  while ((m = re.exec(sql)) !== null) {
    const name = m[1];
    const cols = [];
    for (const rawLine of m[2].split('\n')) {
      const line = rawLine.trim().replace(/,$/, '');
      if (!line || line.startsWith('--')) continue;
      if (/^(PRIMARY|FOREIGN|UNIQUE|CHECK|CONSTRAINT)\b/i.test(line)) continue;
      const col = /^["`]?(\w+)["`]?\s+[A-Za-z]/.exec(line);
      if (col) cols.push(col[1]);
    }
    out.set(name, cols);
  }
  return out;
}

function indexesOf(sql) {
  const out = new Set();
  const re = /CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF NOT EXISTS\s+)?["`]?(\w+)["`]?/gi;
  let m;
  while ((m = re.exec(sql)) !== null) out.add(m[1]);
  return out;
}

const schemaTables = tablesOf(schema);
const schemaIndexes = indexesOf(schema);

const migrationsDir = join(root, 'migrations');
const migrationFiles = readdirSync(migrationsDir)
  .filter((f) => f.endsWith('.sql'))
  .sort();

const problems = [];

// جداول مؤقتة تُبنى ثم تُحذف/تُعاد تسميتها داخل الهجرة نفسها (إعادة بناء)
const transient = new Set();
for (const file of migrationFiles) {
  const sql = readFileSync(join(migrationsDir, file), 'utf8');
  for (const m of sql.matchAll(/DROP TABLE\s+(?:IF EXISTS\s+)?["`]?(\w+)["`]?/gi)) {
    transient.add(m[1]);
  }
  for (const m of sql.matchAll(/ALTER TABLE\s+["`]?(\w+)["`]?\s+RENAME/gi)) {
    transient.add(m[1]);
  }
}

for (const file of migrationFiles) {
  const sql = readFileSync(join(migrationsDir, file), 'utf8');
  const where = `migrations/${file}`;

  for (const m of sql.matchAll(/ALTER TABLE\s+["`]?(\w+)["`]?\s+ADD COLUMN\s+(?:IF NOT EXISTS\s+)?["`]?(\w+)["`]?/gi)) {
    const [, table, column] = m;
    if (!schemaTables.has(table)) {
      problems.push(`${where}: ALTER على جدول غير موجود في schema.sql (${table})`);
      continue;
    }
    if (!schemaTables.get(table).includes(column)) {
      problems.push(`${where}: العمود ${table}.${column} غير موجود في schema.sql (تثبيت جديد يفتقده)`);
    }
  }

  for (const m of sql.matchAll(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF NOT EXISTS\s+)?["`]?(\w+)["`]?/gi)) {
    const index = m[1];
    if (!schemaIndexes.has(index)) {
      problems.push(`${where}: الفهرس ${index} غير موجود في schema.sql (تثبيت جديد يفتقده)`);
    }
  }

  for (const m of sql.matchAll(/CREATE TABLE\s+(?:IF NOT EXISTS\s+)?["`]?(\w+)["`]?/gi)) {
    const table = m[1];
    if (transient.has(table)) continue;
    if (!schemaTables.has(table)) {
      problems.push(`${where}: الجدول ${table} غير موجود في schema.sql`);
    }
  }
}

if (problems.length > 0) {
  console.error('✗ انحراف بين schema.sql والهجرات:\n');
  for (const p of problems) console.error(`  • ${p}`);
  console.error(
    `\nالإصلاح: انسخ التغيير في schema.sql أيضاً (أو أضف هجرة مضادة) ثم أعد التشغيل.`
  );
  process.exit(1);
}

console.log(
  `✓ لا انحراف: ${migrationFiles.length} هجرة، ${schemaTables.size} جدول، ` +
    `${schemaIndexes.size} فهرس — كل ما تضيفه الهجرات موجود في schema.sql.`
);
