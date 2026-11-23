#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════
//  check-wire-contract.mjs — حارس «Snake case + هوية موحّدة»
//
//  المشكلة التي يمنعها (تقرير 2026-11-23):
//    عميل Flutter يبني حمولات camelCase من الـ adapter، ثم يطبّعها
//    `PayloadNormalizer` عند الدفع. لكن أي مفتاح لا يتحوّل إلى اسم عمود
//    حقيقي على D1 يُسقَط صمتاً في `prepareInsertRow` (فلترة الأعمدة).
//    أمثلة وقعت فعلاً: `booking_id` بدل `server_booking_id`، و`payment_id`
//    بدل `server_payment_id`، و`EmployeeID`، وغياب `booking_uuid_cache`
//    من ليالي الحجز. النتيجة: هوية ناقصة → ربط خاطئ → ليالٍ/مدفوعات
//    تتضارب بين الأجهزة.
//
//  ما يفعله هذا السكربت:
//    1. يقرأ أعمدة كل جدول من `worker/schema.sql` (+ ALTER TABLE في
//       الهجرات).
//    2. يقرأ من كل `mobile/lib/services/adapters/*_adapter.dart` أسماء
//       الأعمدة التي يُرسلها `toJson` بعد تحويل camelCase → snake_case
//       (نفس قاعدة `PayloadNormalizer.toSnakeCase`).
//    3. يفشل (exit 1) إذا أرسل الـ adapter مفتاحاً ليس عموداً، أو أهمل
//       عمود هوية إلزامياً للكيانات في النطاق الصارم.
//
//  التشغيل:  node scripts/check-wire-contract.mjs
//        أو:  npm run check:wire
// ═══════════════════════════════════════════════════════════════════

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKER_DIR = resolve(HERE, '..');
const REPO_DIR = resolve(WORKER_DIR, '..');
const ADAPTER_DIR = join(REPO_DIR, 'mobile', 'lib', 'services', 'adapters');

/** الكيانات في النطاق الصارم (توجيه المستخدم 2026-11-23). */
const STRICT_ENTITIES = [
  'bookings',
  'booking_nights',
  'payments',
  'debts',
  'employees',
  'expenses',
];

/** أعمدة هوية يجب أن تُرسل دائماً لكل كيان (عالمية، لا رقمية جهازية). */
const REQUIRED_IDENTITY = {
  bookings: ['local_uuid'],
  booking_nights: ['local_uuid', 'booking_uuid_cache', 'hotel_day_key'],
  payments: ['local_uuid', 'booking_uuid_cache'],
  debts: ['local_uuid', 'booking_uuid_cache'],
  employees: ['local_uuid', 'employee_id'],
  expenses: ['local_uuid', 'employee_uuid', 'withdrawal_uuid'],
};

/** نفس قاعدة `PayloadNormalizer.toSnakeCase`: حدّ بين صغير/رقم وكبير. */
function toSnakeCase(key) {
  if (!/[A-Z]/.test(key)) return key;
  return key.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
}

function splitStatements(sqlText) {
  return sqlText
    .split('\n')
    .filter((line) => !line.trimStart().startsWith('--'))
    .join('\n')
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean);
}

/** أعمدة كل جدول من schema.sql + الهجرات (ALTER TABLE ... ADD COLUMN). */
function loadColumns() {
  const columns = new Map();
  const schema = readFileSync(join(WORKER_DIR, 'schema.sql'), 'utf8');

  const tableRe = /CREATE TABLE IF NOT EXISTS\s+(\w+)\s*\(([\s\S]*?)\n\);/g;
  for (const match of schema.matchAll(tableRe)) {
    const [, table, body] = match;
    const cols = new Set();
    for (const rawLine of body.split('\n')) {
      const line = rawLine.trim();
      if (!line || line.startsWith('--') || line.startsWith('UNIQUE') || line.startsWith('FOREIGN')) {
        continue;
      }
      const m = line.match(/^([A-Za-z_0-9]+)\s+(TEXT|INTEGER|REAL|NUMERIC|BLOB)/);
      if (m) cols.add(m[1]);
    }
    columns.set(table, cols);
  }

  const migrationDir = join(WORKER_DIR, 'migrations');
  for (const file of readdirSync(migrationDir)) {
    if (!file.endsWith('.sql')) continue;
    const sql = readFileSync(join(migrationDir, file), 'utf8');
    for (const m of sql.matchAll(/ALTER TABLE\s+(\w+)\s+ADD COLUMN\s+(\w+)/g)) {
      const [, table, column] = m;
      if (!columns.has(table)) columns.set(table, new Set());
      columns.get(table).add(column);
    }
  }
  return columns;
}

/** جدول D1 + مفاتيح toJson من ملف adapter. */
function loadAdapter(file, source) {
  const tableMatch = source.match(/String get tableName\s*=>\s*['"](\w+)['"]/);
  if (!tableMatch) return null;
  const table = tableMatch[1];

  const toJsonIndex = source.indexOf('Map<String, dynamic> toJson(');
  if (toJsonIndex < 0) return null;
  const body = source.slice(toJsonIndex);
  const end = body.indexOf('\n  }\n');
  const mapBody = end > 0 ? body.slice(0, end) : body;

  const keys = new Set();
  for (const m of mapBody.matchAll(/_k\(\s*src\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*\)/g)) {
    keys.add(m[2]);
  }
  for (const m of mapBody.matchAll(/^\s*'([A-Za-z_0-9]+)'\s*:/gm)) {
    keys.add(toSnakeCase(m[1]));
  }
  return { file, table, keys };
}

function main() {
  const columns = loadColumns();
  const files = readdirSync(ADAPTER_DIR).filter((f) => f.endsWith('_adapter.dart'));

  const errors = [];
  const warnings = [];
  const rows = [];

  for (const file of files) {
    const source = readFileSync(join(ADAPTER_DIR, file), 'utf8');
    const adapter = loadAdapter(file, source);
    if (!adapter) continue;
    const { table, keys } = adapter;
    const tableCols = columns.get(table);
    if (!tableCols) {
      warnings.push(`${file}: جدول غير معروف في schema.sql (${table}) — تُخطّي`);
      continue;
    }

    const unknown = [...keys].filter((k) => !tableCols.has(k)).sort();
    const strict = STRICT_ENTITIES.includes(table);
    const missingIdentity = strict
      ? (REQUIRED_IDENTITY[table] ?? []).filter((k) => !keys.has(k))
      : [];
    const missingColumns = strict
      ? [...tableCols].filter((c) => !keys.has(c) && c !== 'id').sort()
      : [];

    rows.push({
      table,
      file,
      sent: keys.size,
      columns: tableCols.size,
      unknown,
      missingIdentity,
      missingColumns,
    });

    if (unknown.length > 0) {
      const msg =
        `${table} (${file}): ${unknown.length} مفتاحاً ليس عموداً على D1 → ` +
        `يُسقَط صمتاً عند الرفع: ${unknown.join(', ')}`;
      if (strict) errors.push(msg);
      else warnings.push(msg);
    }
    if (missingIdentity.length > 0) {
      errors.push(
        `${table} (${file}): عمود هوية إلزامي لا يُرسل: ${missingIdentity.join(', ')}`
      );
    }
  }

  console.log('هوية الليلة/الحجز ولغة الأعمدة على السلك (snake_case):\n');
  for (const row of rows.sort((a, b) => a.table.localeCompare(b.table))) {
    const flag = STRICT_ENTITIES.includes(row.table) ? '★' : ' ';
    const gap = row.missingColumns.length
      ? ` | أعمدة لا تُرسل: ${row.missingColumns.length}`
      : '';
    console.log(
      `${flag} ${row.table.padEnd(24)} ${String(row.sent).padStart(3)}/${String(
        row.columns
      ).padStart(3)}${gap}`
    );
  }

  if (warnings.length > 0) {
    console.log(`\nتنبيهات (${warnings.length}) — خارج النطاق الصارم:`);
    for (const w of warnings) console.log('  • ' + w);
  }

  if (errors.length > 0) {
    console.error(`\n✖ فشل عقد السلك (${errors.length}):`);
    for (const e of errors) console.error('  • ' + e);
    process.exit(1);
  }

  console.log('\n✓ كل كيانات النطاق الصارم ترسل أعمدة D1 بأسمائها snake_case + هوية عالمية.');
}

main();
