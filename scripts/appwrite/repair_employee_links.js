#!/usr/bin/env node
/**
 * إصلاح روابط الموظفين في Appwrite Cloud.
 *
 * الوضع الافتراضي dry-run. لا تستخدم --apply إلا بعد مراجعة التقرير.
 * الربط المسموح فقط:
 *   employeeUuid موجود وصحيح -> سليم
 *   employeeUuid مفقود + employeeId/relatedId يطابق serverId لموظف واحد -> إصلاح
 * الحالات الصفرية أو المتعددة -> تُسجل للمراجعة ولا تُعدل.
 */
const { Client, Databases, Query } = require('node-appwrite');

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = process.env.APPWRITE_PROJECT_ID || '690ff0da0025518570c1';
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || 'hotel_db';
const API_KEY = process.env.APPWRITE_API_KEY;
const APPLY = process.argv.includes('--apply');
const PAGE_SIZE = 100;

if (!API_KEY) {
  console.error('APPWRITE_API_KEY is required');
  process.exit(2);
}

const db = new Databases(new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY));

const value = (doc, ...keys) => keys.map(k => doc[k]).find(v => v !== null && v !== undefined && v !== '' && v !== 'null');
const asInt = v => {
  const n = Number.parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) ? n : null;
};
const employeeUuid = doc => value(doc, 'employeeUuid', 'employeeLocalUuid', 'employee_uuid', 'employee_local_uuid');

async function listAll(collectionId) {
  const out = [];
  let cursor;
  do {
    const queries = [Query.limit(PAGE_SIZE)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const page = await db.listDocuments(DATABASE_ID, collectionId, queries);
    out.push(...page.documents);
    cursor = page.documents.length === PAGE_SIZE ? page.documents[page.documents.length - 1].$id : undefined;
  } while (cursor);
  return out;
}

async function ensureAttribute(collectionId, key) {
  const collection = await db.getCollection(DATABASE_ID, collectionId);
  if (collection.attributes.some(a => a.key === key)) return false;
  await db.createStringAttribute(DATABASE_ID, collectionId, key, 36, false);
  return true;
}

async function waitForAttributes(collectionId, keys) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const collection = await db.getCollection(DATABASE_ID, collectionId);
    const ready = keys.every(key => {
      const attr = collection.attributes.find(a => a.key === key);
      return attr && attr.status === 'available';
    });
    if (ready) return;
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
  throw new Error(`Timed out waiting for attributes in ${collectionId}`);
}

async function main() {
  console.log(`Appwrite employee-link repair: ${APPLY ? 'APPLY' : 'DRY-RUN'}`);
  if (APPLY) {
    let createdAny = false;
    for (const key of ['employeeUuid', 'employeeLocalUuid']) {
      try {
        const created = await ensureAttribute('salary_cycles', key);
        createdAny = createdAny || created;
        if (created) console.log(`created attribute salary_cycles.${key}; wait for Appwrite status=available`);
      } catch (e) {
        console.error(`attribute salary_cycles.${key}: ${e.message}`);
        process.exit(1);
      }
    }
    if (createdAny) await waitForAttributes('salary_cycles', ['employeeUuid', 'employeeLocalUuid']);
  }
  const employees = await listAll('employees');
  const byServerId = new Map();
  const employeeByUuid = new Map();
  for (const e of employees) {
    const uuid = value(e, 'localUuid') || e.$id;
    employeeByUuid.set(uuid, e);
    const sid = asInt(value(e, 'serverId'));
    if (sid === null) continue;
    if (!byServerId.has(sid)) byServerId.set(sid, []);
    byServerId.get(sid).push(e);
  }
  console.log(`employees=${employees.length}`);

  const targets = [
    { collection: 'expenses', idKeys: ['relatedId', 'related_id'] },
    { collection: 'salary_withdrawals', idKeys: ['employeeId', 'employee_id'] },
    { collection: 'salary_cycles', idKeys: ['employeeId', 'employee_id'] },
  ];
  const summary = { clean: 0, fixed: 0, manual: 0, missingEmployee: 0, failed: 0 };

  for (const target of targets) {
    const docs = await listAll(target.collection);
    let clean = 0, fixed = 0, manual = 0, missingEmployee = 0;
    for (const doc of docs) {
      const existing = employeeUuid(doc);
      if (existing && employeeByUuid.has(existing)) { clean++; continue; }
      const id = asInt(value(doc, ...target.idKeys));
      const candidates = id === null ? [] : (byServerId.get(id) || []);
      if (candidates.length !== 1) {
        if (candidates.length === 0) missingEmployee++; else manual++;
        continue;
      }
      const uuid = value(candidates[0], 'localUuid') || candidates[0].$id;
      if (APPLY) {
        try {
          await db.updateDocument(DATABASE_ID, target.collection, doc.$id, {
            employeeUuid: uuid,
            employeeLocalUuid: uuid,
          });
        } catch (e) {
          summary.failed++;
          console.error(`  FAILED ${target.collection}/${doc.$id}: ${e.message}`);
          continue;
        }
      }
      fixed++;
      console.log(`  ${APPLY ? 'FIXED' : 'WOULD FIX'} ${target.collection}/${doc.$id} -> ${uuid}`);
    }
    Object.assign(summary, {
      clean: summary.clean + clean,
      fixed: summary.fixed + fixed,
      manual: summary.manual + manual,
      missingEmployee: summary.missingEmployee + missingEmployee,
    });
    console.log(`${target.collection}: clean=${clean} fixable=${fixed} ambiguous=${manual} noEmployee=${missingEmployee}`);
  }

  if (!APPLY) {
    console.log('No cloud data changed. Use --apply only after reviewing the report.');
  }
  console.log(JSON.stringify(summary, null, 2));
  process.exitCode = summary.failed ? 1 : 0;
}

main().catch(e => { console.error(`Fatal: ${e.message}`); process.exit(1); });
