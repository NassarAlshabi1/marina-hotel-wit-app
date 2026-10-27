#!/usr/bin/env node

/**
 * سكربت: نسخ سحبيات الراتب من جدول المصروفات إلى جدول salary_withdrawals
 * - يبحث عن المصروفات من نوع سحب/خصم راتب في Appwrite Cloud
 * - ينسخها إلى جدول salary_withdrawals مع منع التكرار (4 طبقات تحقق)
 * - لا يحذف شيء من المصروفات الأصلية (نسخ فقط)
 *
 * طبقات منع التكرار:
 *   1. localUuid — قوي: إذا كانت السحبية مرتبطة بنفس localUuid للمصروف
 *   2. reason = "exp_{id}" — قوي: إذا كانت السحبية مربوطة بنفس المصروف عبر reason
 *   3. موظف + تاريخ + مبلغ — متوسط: تطابق البيانات الأساسية
 *   4. بدون موظف — سلامة: تجاهل المصروفات غير المربوطة بموظف
 *
 * الاستخدام:
 *   node copy_salary_expenses_to_withdrawals.js
 *   node copy_salary_expenses_to_withdrawals.js --dry-run
 */

const { Client, Databases, Query, ID } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

const SALARY_EXPENSE_TYPES = ['سحب راتب', 'خصم راتب', 'سحب من الراتب', 'خصم من الراتب'];

const dryRun = process.argv.includes('--dry-run');

async function main() {
  const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

  const db = new Databases(client);

  console.log('='.repeat(70));
  console.log('نسخ سحبيات الراتب من المصروفات إلى salary_withdrawals');
  console.log('='.repeat(70));
  console.log(`Endpoint: ${ENDPOINT}`);
  console.log(`Database: ${DATABASE_ID}`);
  console.log(`Dry Run: ${dryRun ? 'نعم (لن يتم إدخال بيانات)' : 'لا (سيتم الإدخال فعلياً)'}`);
  console.log('');

  // ─── 1. جلب جميع المصروفات من أنواع سحب/خصم الراتب ───
  console.log('📡 جلب المصروفات من Appwrite...');
  let allExpenses = [];
  let offset = 0;
  const limit = 100;

  for (const type of SALARY_EXPENSE_TYPES) {
    try {
      let fetched = 0;
      do {
        const queries = [
          Query.equal('expenseType', type),
          Query.limit(limit),
          Query.offset(offset),
        ];
        const result = await db.listDocuments(DATABASE_ID, 'expenses', queries);
        allExpenses.push(...result.documents);
        fetched = result.documents.length;
        offset += limit;
      } while (fetched === limit);
      offset = 0;
    } catch (e) {
      console.log(`  ⚠️ خطأ في جلب النوع "${type}": ${e.message}`);
    }
  }

  // تصفية المصروفات المحذوفة (deletedAt != null)
  allExpenses = allExpenses.filter(exp => !exp.deletedAt || exp.deletedAt === 'null');

  console.log(`  ✅ إجمالي المصروفات العائدة للراتب (غير محذوفة): ${allExpenses.length}`);

  if (allExpenses.length === 0) {
    console.log('\nلم يتم العثور على مصروفات سحب/خصم راتب.');
    return;
  }

  // ─── 2. جلب جميع السحبيات الموجودة مسبقاً لمنع التكرار ───
  console.log('\n📡 جلب السحبيات الموجودة مسبقاً...');
  let existingWithdrawals = [];
  offset = 0;
  let lastFetched = 0;
  do {
    const queries = [Query.limit(limit), Query.offset(offset)];
    const result = await db.listDocuments(DATABASE_ID, 'salary_withdrawals', queries);
    existingWithdrawals.push(...result.documents);
    lastFetched = result.documents.length;
    offset += limit;
  } while (lastFetched === limit);

  console.log(`  ✅ عدد السحبيات الموجودة مسبقاً: ${existingWithdrawals.length}`);

  // ─── 3. بناء فهارس منع التكرار (4 طبقات) ───

  // الطبقة 1: existingByLocalUuid — أقوى طبقة
  // localUuid للسحبية قد يكون نفس localUuid المصروف أو يحتوي عليه
  const existingByLocalUuid = new Set();
  for (const w of existingWithdrawals) {
    const uuid = w.localUuid || w.local_uuid || '';
    if (uuid) existingByLocalUuid.add(uuid);
  }

  // الطبقة 2: existingExpenseRefs — الربط عبر reason = "exp_{id}" أو expenseId
  const existingExpenseRefs = new Set();
  for (const w of existingWithdrawals) {
    // reason = "exp_{localId}" أو "exp_{serverId}"
    if (w.reason && w.reason.startsWith('exp_')) {
      existingExpenseRefs.add(w.reason); // يحفظ كاملاً "exp_123"
    }
    if (w.expenseId != null) {
      existingExpenseRefs.add(`exp_${w.expenseId}`);
    }
  }

  // الطبقة 3: existingByDataKey — موظف + تاريخ + مبلغ
  const existingByDataKey = new Set();
  for (const w of existingWithdrawals) {
    const empId = String(w.employeeId || w.employee_id || '');
    const date = w.withdrawDate || w.withdraw_date || w.date || '';
    const amt = Math.round(parseFloat(w.amount || 0));
    existingByDataKey.add(`${empId}|${date}|${amt}`);
  }

  // ─── 4. تحديد المصروفات التي تحتاج نسخ ───
  const toInsert = [];
  const skipped = [];

  for (const exp of allExpenses) {
    const expLocalUuid = exp.localUuid || exp.local_uuid || '';
    const expId = String(exp.id || '');
    const empId = exp.relatedId || exp.related_id || '';
    const date = exp.date || '';
    const amt = Math.round(parseFloat(exp.amount || 0));

    // الطبقة 1: التحقق عبر localUuid
    // السحبية المنسوخة سابقاً يكون localUuid = "sw_copy_{expenseLocalUuid}"
    if (expLocalUuid) {
      const swUuid = `sw_copy_${expLocalUuid}`;
      if (existingByLocalUuid.has(swUuid)) {
        skipped.push({ exp, reason: `[طبقة 1] localUuid مطابق: ${swUuid}` });
        continue;
      }
      // أيضاً قد تكون السحبية لها نفس localUuid المصروف مباشرة
      if (existingByLocalUuid.has(expLocalUuid)) {
        skipped.push({ exp, reason: `[طبقة 1] localUuid موجود: ${expLocalUuid}` });
        continue;
      }
    }

    // الطبقة 2: التحقق عبر reason = "exp_{id}" أو expenseId
    const refKey1 = `exp_${expId}`;
    const refKey2 = `exp_${expLocalUuid}`;
    if (existingExpenseRefs.has(refKey1)) {
      skipped.push({ exp, reason: `[طبقة 2] reason مرتبط: ${refKey1}` });
      continue;
    }
    if (expLocalUuid && existingExpenseRefs.has(refKey2)) {
      skipped.push({ exp, reason: `[طبقة 2] reason مرتبط: ${refKey2}` });
      continue;
    }

    // الطبقة 3: التحقق عبر موظف + تاريخ + مبلغ
    if (empId) {
      const dataKey = `${empId}|${date}|${amt}`;
      if (existingByDataKey.has(dataKey)) {
        skipped.push({ exp, reason: `[طبقة 3] بيانات مطابقة: موظف=${empId}، تاريخ=${date}، مبلغ=${amt}` });
        continue;
      }
    }

    // الطبقة 4: بدون موظف = لا يمكن نسخها
    if (!empId) {
      skipped.push({ exp, reason: `[طبقة 4] غير مربوطة بموظف (بدون relatedId)` });
      continue;
    }

    toInsert.push(exp);
  }

  console.log(`\n📊 النتائج:`);
  console.log(`  - مصروفات الراتب: ${allExpenses.length}`);
  console.log(`  - تحتاج نسخ: ${toInsert.length}`);
  console.log(`  - تم تخطيها (موجودة مسبقاً): ${skipped.length}`);

  if (skipped.length > 0) {
    console.log('\n  التفاصيل (تم التخطي):');
    for (const s of skipped) {
      const empId = s.exp.relatedId || s.exp.related_id || '?';
      const desc = s.exp.description || '';
      const amt = s.exp.amount || 0;
      const date = s.exp.date || '?';
      console.log(`    ❌ موظف=${empId} | مبلغ=${amt} | تاريخ=${date} | ${s.reason}`);
      if (desc) console.log(`       الوصف: ${desc}`);
    }
  }

  if (toInsert.length === 0) {
    console.log('\n✅ جميع سحبيات الراتب موجودة مسبقاً. لا حاجة للنسخ.');
    return;
  }

  // ─── 5. عرض المصروفات التي سيتم نسخها ───
  console.log('\n📋 المصروفات التي سيتم نسخها:');
  for (const exp of toInsert) {
    const empId = exp.relatedId || exp.related_id || '?';
    const desc = exp.description || '';
    const amt = exp.amount || 0;
    const date = exp.date || '?';
    const type = exp.expenseType || '';
    const uuid = exp.localUuid || exp.local_uuid || '';
    console.log(`    ✅ موظف=${empId} | مبلغ=${amt} | تاريخ=${date} | نوع=${type}`);
    if (desc) console.log(`       الوصف: ${desc}`);
    if (uuid) console.log(`       localUuid: ${uuid}`);
  }

  if (dryRun) {
    console.log('\n🔄 Dry Run — لن يتم إدخال أي بيانات.');
    console.log(`   قم بتشغيل بدون --dry-run لتنفيذ النسخ الفعلي.`);
    return;
  }

  // ─── 6. إدخال البيانات في salary_withdrawals ───
  console.log('\n⏳ جاري النسخ إلى salary_withdrawals...');
  let inserted = 0;
  let failed = 0;

  for (const exp of toInsert) {
    try {
      const now = Math.floor(Date.now() / 1000);
      const nowIso = new Date().toISOString();

      let withdrawalType = 'سحب';
      if (exp.expenseType.includes('خصم')) {
        withdrawalType = 'خصم';
      }

      const expenseLocalUuid = exp.localUuid || exp.local_uuid || '';
      const documentId = ID.unique();

      // localUuid السحبية = "sw_copy_" + localUuid المصروف لسهولة التتبع
      const swLocalUuid = expenseLocalUuid ? `sw_copy_${expenseLocalUuid}` : documentId;

      // reason يربط بالمصروف الأصلي
      const reasonVal = exp.id ? `exp_${exp.id}` : '';

      const docData = {
        localUuid: swLocalUuid,
        employeeId: exp.relatedId || exp.related_id,
        amount: Math.round(parseFloat(exp.amount || 0)),
        withdrawDate: exp.date || '',
        reason: reasonVal,
        hotelDayKey: exp.hotelDayKey || exp.hotel_day_key || '',
        withdrawalType: withdrawalType,
        description: exp.description || '',
        createdAt: exp.createdAt || exp.created_at || now,
        updatedAt: exp.updatedAt || exp.updated_at || now,
        deletedAt: null,
        lastModified: exp.lastModified || exp.last_modified || now,
        createdAtIso: exp.createdAtIso || exp.created_at_iso || nowIso,
        updatedAtIso: exp.updatedAtIso || exp.updated_at_iso || nowIso,
        deletedAtIso: null,
        version: 1,
        origin: 'server',
        vectorClock: '{}',
        // حقول توافقية إضافية (للاتساق مع SalaryWithdrawalsAdapter)
        date: exp.date || '',
        action: withdrawalType,
        note: exp.description || '',
        expenseId: exp.id ? parseInt(exp.id) : null,
      };

      await db.createDocument(DATABASE_ID, 'salary_withdrawals', documentId, docData);
      inserted++;
      console.log(`  ✅ تم نسخ: موظف=${docData.employeeId} | مبلغ=${docData.amount} | تاريخ=${docData.withdrawDate}`);
      console.log(`     localUuid: ${swLocalUuid} ← مصروف: ${expenseLocalUuid || exp.id}`);
    } catch (e) {
      failed++;
      console.log(`  ❌ فشل نسخ: ${e.message}`);
    }
  }

  console.log('\n' + '='.repeat(70));
  console.log('📄 ملخص النتائج:');
  console.log(`  ✅ تم نسخ: ${inserted}`);
  console.log(`  ❌ فشل: ${failed}`);
  console.log(`  ⏭️  تم التخطي (موجودة مسبقاً): ${skipped.length}`);
  console.log(`  📊 إجمالي المصروفات المعالجة: ${allExpenses.length}`);
  console.log('='.repeat(70));
}

main().catch(err => {
  console.error('\n❌ خطأ عام:', err.message);
  process.exit(1);
});
