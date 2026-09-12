/**
 * backfill_salary_withdrawals_employee_uuid.js
 *
 * ✅ شفاء البيانات القديمة (Legacy Self-Healing) على السحابة:
 *
 * المشكلة:
 *   سجلات salary_withdrawals / salary_cycles القديمة رُفعت إلى Appwrite
 *   قبل أن يُضف حقل employeeUuid إلى جانب الرفع، فحملت employeeId رقمي
 *   (id محلي بجهاز المصدر) فقط. عند سحبها على أجهزة أخرى تفشل طرق الحل
 *   الثلاث (UUID → id → serverId) وتُتخطى كـ «سجلات يتيمة» في كل دورة
 *   مزامنة — بيانات مالية (سحبات رواتب) لا تظهر على بقية الأجهزة.
 *
 * الحل:
 *   لكل سجل على السحابة employeeUuid فارغ:
 *     1. البحث في مجموعة employees عن موظف serverId == employeeId
 *        (serverId على السحابة = id الموظف المحلي بجهاز المصدر).
 *     2. إن وُجد مرشح واحد فقط → كتابة employeeUuid = الموظف.localUuid.
 *     3. إن تعددت المرشحات (خطر ربط خاطئ ببيانات مالية) → تجاهل + إدراج
 *        في قائمة "يدوي" دون تحديث.
 *     4. إن لم يوجد أي موظف → إدراج في قائمة "موظف محذوف فعلاً".
 *
 * الاستخدام:
 *   node backfill_salary_withdrawals_employee_uuid.js            # dry-run (افتراضي)
 *   node backfill_salary_withdrawals_employee_uuid.js --apply    # تطبيق فعلي
 *
 * لا يُعدّل lastModified/version — employeeUuid فقط — حتى لا يُخلّ بحل
 * التعارضات (السجلات اليتيمة ليست محلية على أي جهاز، فستُسحب فوراً بعد الشفاء).
 */

const { Client, Databases, Query } = require("node-appwrite");

const endpoint =
  process.env.APPWRITE_ENDPOINT || "https://fra.cloud.appwrite.io/v1";
const projectId = process.env.APPWRITE_PROJECT_ID || "6a2b01d0000752ce97e7";
const apiKey =
  process.env.APPWRITE_API_KEY ||
  "standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d";
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";

const APPLY = process.argv.includes("--apply");
const PAGE_SIZE = 100;

const TARGET_COLLECTIONS = [
  { name: "salary_withdrawals", idField: "employeeId" },
  { name: "salary_cycles", idField: "employeeId" },
];

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const db = new Databases(client);

function extractEmployeeId(data, field) {
  const raw = data[field] ?? data[`_${field}`];
  if (raw === null || raw === undefined) return null;
  const n = typeof raw === "number" ? raw : parseInt(String(raw), 10);
  return Number.isFinite(n) ? n : null;
}

function extractEmployeeUuid(data) {
  for (const k of ["employeeUuid", "employee_uuid", "employeeLocalUuid", "employee_local_uuid"]) {
    const v = data[k];
    if (typeof v === "string" && v.trim().length > 0) return v.trim();
  }
  return null;
}

async function listAllDocs(collectionId) {
  const all = [];
  let cursor = undefined;
  let total = 0;
  do {
    const queries = [Query.limit(PAGE_SIZE)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const res = await db.listDocuments(databaseId, collectionId, queries);
    all.push(...res.documents);
    total = res.total;
    cursor = res.documents.length > 0 ? res.documents[res.documents.length - 1].$id : undefined;
    process.stdout.write(`\r  📥 ${collectionId}: ${all.length}/${total}`);
  } while (cursor && all.length < total);
  process.stdout.write("\n");
  return all;
}

async function listAllEmployees() {
  return listAllDocs("employees");
}

(async () => {
  console.log("════════════════════════════════════════════");
  console.log(`🛠  Backfill employeeUuid  |  mode: ${APPLY ? "APPLY ⚡" : "DRY-RUN (استخدم --apply للتطبيق)"}`);
  console.log("════════════════════════════════════════════");

  // 1) تحميل الموظفين وبناء فهرس: serverId → [localUuid,...]
  console.log("📥 تحميل الموظفين من السحابة...");
  const employees = await listAllEmployees();
  const byServerId = new Map();
  for (const e of employees) {
    const sid = e.serverId ?? e.server_id ?? null;
    const n = typeof sid === "number" ? sid : parseInt(String(sid ?? ""), 10);
    if (!Number.isFinite(n)) continue;
    if (!byServerId.has(n)) byServerId.set(n, []);
    byServerId.get(n).push({ localUuid: e.localUuid ?? e.$id, name: e.name, $id: e.$id });
  }
  console.log(`👥 الموظفون: ${employees.length} | مفهرس بـ serverId: ${byServerId.size}\n`);

  let grandFixed = 0;
  let grandManual = 0;
  let grandDeleted = 0;
  let grandClean = 0;

  for (const target of TARGET_COLLECTIONS) {
    console.log(`\n🔎 ${target.name}`);
    const docs = await listAllDocs(target.name);

    let fixed = 0;
    let clean = 0;
    const manual = [];
    const deleted = [];

    for (const doc of docs) {
      const uuid = extractEmployeeUuid(doc);
      if (uuid) {
        clean++;
        continue;
      }
      const empId = extractEmployeeId(doc, target.idField);
      if (empId === null) {
        manual.push({ $id: doc.$id, reason: "بدون employeeId رقمي" });
        continue;
      }
      const candidates = byServerId.get(empId) || [];
      if (candidates.length === 1) {
        const emp = candidates[0];
        if (APPLY) {
          try {
            await db.updateDocument(databaseId, target.name, doc.$id, {
              employeeUuid: emp.localUuid,
            });
            fixed++;
          } catch (err) {
            manual.push({ $id: doc.$id, reason: `فشل التحديث: ${err.message}` });
          }
        } else {
          fixed++;
        }
        console.log(
          `  ✅ ${doc.$id} → employeeId=${empId} → موظف "${emp.name}" (${emp.localUuid})`,
        );
      } else if (candidates.length > 1) {
        manual.push({ $id: doc.$id, reason: `تعدد مرشحين (${candidates.length}) لـ serverId=${empId}` });
      } else {
        deleted.push({ $id: doc.$id, empId });
      }
    }

    console.log(
      `\n  📊 ${target.name}: سليم=${clean} | شُفي=${fixed}${APPLY ? "" : " (dry-run)"} | يحتاج مراجعة يدوية=${manual.length} | موظف محذوف فعلاً=${deleted.length}`,
    );
    for (const m of manual) console.log(`     ⚠️  يدوي: ${m.$id} — ${m.reason}`);
    for (const d of deleted) console.log(`     🗑  يتيم نهائي: ${d.$id} (employeeId=${d.empId})`);

    grandFixed += fixed;
    grandManual += manual.length;
    grandDeleted += deleted.length;
    grandClean += clean;
  }

  console.log("\n════════════════════════════════════════════");
  console.log(`🏁 الإجمالي: سليم=${grandClean} | شُفي=${grandFixed}${APPLY ? "" : " (dry-run)"}`);
  console.log(`   مراجعة يدوية=${grandManual} | يتيم نهائي (موظف محذوف)=${grandDeleted}`);
  if (!APPLY && grandFixed > 0) {
    console.log("\n💡 هذه محاكاة فقط. للتطبيق الفعلي شغّل:  node backfill_salary_withdrawals_employee_uuid.js --apply");
  }
  console.log("════════════════════════════════════════════");
})().catch((e) => {
  console.error("Fatal:", e?.message || e);
  process.exit(1);
});
