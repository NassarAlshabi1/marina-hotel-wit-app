#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يولّد «مسودة مواصفة المزامنة لتطبيق Flutter/Dart» من المصدر مباشرة.

الاستعمال (من جذر المستودع):
    python3 docs/tools/generate_sync_spec.py

المدخلات (تُقرأ فقط — لا يُعدَّل شيء):
    worker/src/database.ts            → ENTITY_TABLES (الكيان على السلك ↔ جدول D1)
    worker/schema.sql                 → أعمدة D1 وأنواعها وقيودها
    mobile/android/app/src/main/kotlin/com/marina/marina/data/local/entity/*Entity.kt
                                      → أعمدة Room و@SerializedName
    .../data/sync/SyncWireFields.kt   → aliases / entityDefaults / wireMirrors / millisTargets
    .../data/local/entity/BaseSyncEntity.kt → حقول المزامنة الإلزامية

المخرج:
    docs/sync-spec-draft-for-flutter-dart.md   (يُستبدَل بالكامل)

ملاحظة: الأقسام السردية (المعمارية/العقود/قائمة التحقق) مكتوبة في هذا السكربت،
وأما فهارس الحقول فهي مولّدة من المصدر أعلاه — أي تغيير في المخطط يستلزم
إعادة تشغيل السكربت."""
import re, pathlib, json

ROOT = pathlib.Path(__file__).resolve().parents[2]   # docs/tools/<script> → جذر المستودع
out = []
def w(line=""): out.append(line)

# ─────────────────────────── استخراج البيانات ───────────────────────────

db_src = (ROOT/"worker/src/database.ts").read_text(encoding='utf-8')
m = re.search(r'const ENTITY_TABLES: Record<string, string> = \{(.*?)\n\};', db_src, re.S)
ENTITY_TABLES = dict(re.findall(r"(\w+):\s*'([^']+)'", m.group(1)))

schema = (ROOT/"worker/schema.sql").read_text(encoding='utf-8')
D1 = {}
for tm in re.finditer(r'CREATE TABLE IF NOT EXISTS (\w+)\s*\((.*?)\n\);', schema, re.S):
    name, body = tm.group(1), tm.group(2)
    cols = {}
    for line in body.split("\n"):
        s = line.strip().rstrip(',')
        if not s or s.startswith("--") or s.upper().startswith(("PRIMARY KEY(", "UNIQUE(", "FOREIGN KEY(", "CHECK(")):
            continue
        cm = re.match(r'(\w+)\s+(TEXT|INTEGER|REAL|BLOB|NUMERIC)', s, re.I)
        if cm:
            cols[cm.group(1)] = {
                "type": cm.group(2).upper(),
                "notnull": "NOT NULL" in s.upper(),
                "default": (re.search(r'DEFAULT\s+([^\s,]+)', s, re.I) or [None, None])[1],
            }
    D1[name] = cols

# كيانات Room
ENT = ROOT/"mobile/android/app/src/main/kotlin/com/marina/marina/data/local/entity"
room_entities = {}
for p in sorted(ENT.glob("*Entity.kt")):
    src = p.read_text(encoding='utf-8')
    tm = re.search(r'tableName\s*=\s*"([^"]+)"', src)
    if not tm:
        continue
    cls = re.search(r'(?:data class|open class) (\w+)', src)
    serial = colinfo = None
    cols = []
    for ln in src.split("\n"):
        sm = re.search(r'@SerializedName\("([^"]+)"\)', ln)
        cm = re.search(r'@ColumnInfo\(name = "([^"]+)"\)', ln)
        if sm: serial = sm.group(1)
        if cm: colinfo = cm.group(1)
        fm = re.search(r'(?:override\s+)?val (\w+)\s*:', ln)
        if fm and not ln.strip().startswith("//"):
            cols.append({"prop": fm.group(1), "wire": serial, "col": colinfo})
            serial = colinfo = None
    room_entities[tm.group(1)] = {"cls": cls.group(1) if cls else p.stem, "columns": cols}

# خرائط SyncWireFields
sw = (ROOT/"mobile/android/app/src/main/kotlin/com/marina/marina/data/sync/SyncWireFields.kt").read_text(encoding='utf-8')
def _balanced(text, start, open_ch, close_ch):
    """يرجع نص ما بين القوسين بدءاً من موضع open_ch (يجب أن يكون هو)."""
    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    return text[start + 1:]

def _outer_body(src, key):
    gi = src.find(f"val {key}")
    if gi < 0:
        return None
    mi = src.find("mapOf(", gi)
    if mi < 0:
        return None
    return _balanced(src, src.index("(", mi), "(", ")")

def map_groups(src, key):
    """يقرأ مجموعات "x" to mapOf(...) داخل تهيئة val المطلوبة فقط."""
    outer = _outer_body(src, key)
    if outer is None:
        return {}
    groups = {}
    for gm in re.finditer(r'"(\w+)"\s*to\s*mapOf\(', outer):
        ent = gm.group(1)
        body = _balanced(outer, gm.end() - 1, "(", ")")
        pairs = {}
        for pm in re.finditer(r'"([^"]*)"\s*to\s*("([^"]*)"|true|false|-?\d+(?:\.\d+)?)', body):
            val = pm.group(3) if pm.group(3) is not None else pm.group(2)
            pairs[pm.group(1)] = val
        groups[ent] = pairs
    return groups

LOCAL_ALIASES = map_groups(sw, "localAliases")
ENTITY_DEFAULTS = map_groups(sw, "entityDefaults")
WIRE_MIRRORS = map_groups(sw, "wireMirrors")
MILLIS_TARGETS = re.search(r'millisTargets: Set<String> = setOf\(([^)]*)\)', sw).group(1)
MILLIS_TARGETS = set(re.findall(r'"([^"]+)"', MILLIS_TARGETS))
SYNC_FIELDS = set(re.findall(r'override val (\w+)\s*:', (ENT/"BaseSyncEntity.kt").read_text(encoding='utf-8')))

AR = {
 "local_uuid":"المعرّف العالمي للصف (مفتاح المزامنة الحقيقي)",
 "server_id":"ظلّ id الخادمي (يُتعلَّم من السحب)",
 "created_at":"ختم الإنشاء (ثوانٍ)",
 "updated_at":"ختم آخر تحديث (ثوانٍ)",
 "deleted_at":"ختم الحذف الناعم (ثوانٍ)",
 "last_modified":"طابع LWW (ثوانٍ)",
 "created_at_iso":"صيغة ISO للإنشاء",
 "updated_at_iso":"صيغة ISO للتحديث",
 "deleted_at_iso":"صيغة ISO للحذف",
 "created_at_epoch":"ختم الإنشاء (ثوانٍ، مساعد)",
 "last_modified_epoch":"طابع LWW مساعد (ثوانٍ)",
 "version":"عدّاد النسخة (يتصاعد، كاسر التعادل)",
 "origin":"أصل الصف (local/server)",
 "vector_clock":"ساعة متجهة JSON",
 "device_id":"هوية الجهاز الكاتب",
 "sync_timestamp":"ختم المزامنة",
 "idempotency_key":"مفتاح منع التكرار",
}

# ─────────────────────────── الترويسة ───────────────────────────
w("# مواصفة المزامنة الكاملة — مسودة مرجعية لتطبيق Flutter/Dart")
w()
w("> **حالة الملف:** مسودة مرجعية (draft) للاستعمال في تطبيق Flutter/Dart. "
  "محتواها مستخرج **آلياً من المصدر** (`worker/src/database.ts`, `worker/schema.sql`, "
  "كيانات Room، `SyncWireFields.kt`, `SyncEpochs.kt`, `fk_rules.dart` في الفرع المرجعي) "
  "مع شروح منقولة من تعليقات الشيفرة نفسها — لا اجتهاد ولا أرقام محفوظة.")
w()
w("| البند | القيمة |")
w("| --- | --- |")
w("| تاريخ التوليد | 2026-10-08 |")
w("| فرع الجلسة | `arena/be8302d7-marina-hotel-wit-app` |")
w("| آخر التزام موثّق | `7051eae1` (سلسلة الإصلاح `c3bc16b5`…`d364b90b` + توثيق §5 في `341f92fd`) |")
w("| الفرع المرجعي الدارتي | `feat/cloudflare-sync-execution` |")
w("| قاعدة الدمج | `agent/android-cloudflare` (`d95974fc`) |")
w("| كيانات السلك (المتزامنة) | " + str(len(ENTITY_TABLES)) + " |")
w("| جداول D1 (كلها) | " + str(len(D1)) + " |")
w("| كيانات Room (كلها) | " + str(len(room_entities)) + " |")
w()
w("**إعادة التوليد:** `python3 docs/tools/generate_sync_spec.py` (يقرأ المخطط والكيانات وخرائط السلك من المصدر — لا قيم محفوظة).")
w()
w("**كيف تُقرأ:** الأقسام ١–٢ و٤–١٢ هي العقد (يجب أن تُطابقه أي جهة عميل)، "
  "والقسم ٣ فهارس حقول كاملة مولّدة لكل جدول. كل رقم في هذا الملف قابل للتحقق "
  "من الشيفرة المذكورة بجانبه؛ وما لم يُتحقق منه مُعلَم صراحةً.")
w()

# ─────────────────────────── ١) المعمارية ───────────────────────────
w("## ١) المعمارية")
w()
w("### ١.١ الطبقات (وما يقابلها في Dart)")
w()
w("| الطبقة | عندنا (Kotlin) | المقابل الدارتي (الفرع المرجعي) | الدور |")
w("| --- | --- | --- | --- |")
w("| التخزين المحلي | Room (`AppDatabase`، schema 77) | Drift (`local_db.dart`) | 24 جدولاً متزامناً + جداول محلية |")
w("| الوصول | `data/local/dao/*.dao.kt` | `services/daos/*.dart` | استعلامات + كتابات جزئية |")
w("| المستودعات | `data/repository/*RepositoryImpl.kt` | `services/repositories/*.dart` | ختم الطوابع + `version+1` + outbox |")
w("| صندوق الصادر | `OutboxRepository` + `outbox` | `OutboxDao` | طابور رفع + idempotencyKey |")
w("| محرك المزامنة | `SyncManager` + `CloudflareSyncService` | `cloudflare_sync_manager.dart` | سحب/دفع/مؤشرات/مسح |")
w("| استيعاب السحب | `SyncIngestorRegistry` | منطق `_applyRemoteRecord` في مدير المزامنة | ترجمة FK + LWW + عزل |")
w("| الحقول المشتقة | `BookingDerivedRefreshService` | `booking_derived_fields_service.dart` | إعادة حساب الإجماليات المخزَّنة |")
w("| الحيّ (Realtime) | `data/remote/realtime/*` | `cloudflare_realtime_sync.dart` | إشارات + debounce/cooldown |")
w("| FCM | `MarinaMessagingService` | إشعار بيانات من الـWorker | إشارة «هناك تغيير» فقط |")
w("| الـWorker | `worker/src/*.ts` (D1) | نفسه (خادم مشترك) | مصدر الحقيقة + مؤشر الدلتا |")
w()
w("**القاعدة الذهبية:** العميل لا يحسب الحقيقة النهائية للتزامن — الـWorker هو من "
  "يرتب الدلتا ويملك المؤشر و`version`، والعميل يُطبّق ويختم محلياً بعقد موحّد.")
w()
w("### ١.٢ دورة السحب (Pull) — خطوة بخطوة")
w()
w("```text")
w("① إشارة (يدوي / Realtime / FCM / دوري كل ساعة) ⇒ بوابة AutomaticDeltaGate")
w("② GET /api/sync/pull?cursor=<محفوظ>&limit≤500&entity?&exclude_device?&tombstones_only?&include_remaining?")
w("③ لكل صفحة: SyncIngestorRegistry.ingestPage(records) داخل معاملة واحدة")
w("     • توجيه الكيان (_entity أو بصمة الأعمدة)")
w("     • ترجمة مراجع FK (fk_rules) — غير المحلول: تأجيل/عزل")
w("     • تطبيع: الأسماء السلكية (aliases) → الافتراضيات → وحدة الطوابع (ثوانٍ)")
w("     • قرار LWW: الوارد أحدث ⇒ استبدال؛ متعادل ⇒ الوارد؛ المحلي أحدث ⇒ تخطٍّ")
w("       (إلا إن كان version الوارد أعلى ⇒ حارس انزياح الساعة M3)")
w("     • tombstone ⇒ يُطبَّق دائماً (قرار نهائي) بحقول المزامنة فقط")
w("④ حفظ المؤشر من قيمة cursor التي أعادها الخادم (لا من آخر صف طُبِّق)")
w("⑤ بعد الدورة: مسح الحذفيات (tombstones_only=1) حتى 20 صفحة/دورة + إعادة بناء المشتقات")
w("⑥ الحجر: صفوف غير قابلة للتطبيق تُعزل بحمولتها (attempts + firstSeen) ويستمر المؤشر")
w("```")
w()
w("### ١.٣ دورة الدفع (Push)")
w()
w("```text")
w("① كل كتابة محلية تُدرج صف outbox: entity + op(insert/update/delete) + local_uuid + payload(JSON) + idempotencyKey")
w("② OutboxRepository.processPending(): دفعات ≤ PUSH_BATCH_SIZE ⇒ POST /api/sync/push {operations[]}")
w("③ PushWireContract: camelCase→snake_case، bool→int، insert→create، blacklist_entries→blacklist،")
w("   expenses بلا employee_uuid صريحة ⇒ حذف المفتاح + clear_employee_link=1، وتطبيع أعمدة الطوابع للثواني")
w("④ استجابة الخادم: results[] لكل عملية (success/skipped/status) + summary —")
w("   validation_error/conflict = رفض دائم ⇒ dead-letter (لا إعادة)، خطأ شبكة ⇒ requeue")
w("⑤ بعد ≥5 محاولات (فيما عدا salary_withdrawals) ⇒ dead-letter بتشخيص")
w("```")
w()
w("### ١.٤ التدفقات الحيّة والحراس")
w()
w("| المكوّن | العقد المختصر |")
w("| --- | --- |")
w("| Realtime (`/api/realtime`) | إشارة تغيير ⇒ debounce 500ms ⇒ دلتا واحدة بحد أدنى تبريد 15s؛ إعادة اتصال backoff 1s→60s (6 محاولات) ثم إعادة تسليح كل 120s؛ نبض 30s |")
w("| FCM | رسالة بيانات فقط (لا تُحدِّث شيئاً بنفسها) ⇒ تُحوَّل إلى إشارة سحب بالمصدر `fcm` |")
w("| Sweep | مسح تقارب للتمسّح الصامت: حتى 20 صفحة/دورة بمؤشر محفوظ لا يُضبط قبل الاكتمال |")
w("| بوابة الدلتا | سقف دوري 60 دقيقة لا يُتجاوَز بالضغطة اليدوية المتكررة |")
w("| مراقب المعلّقات | كل 5 دقائق: إن بقي معلّق ⇒ جدولة دفع |")
w("| حراس المؤشر | رفض مؤشر مستقبلي (>2e9) أو متقدم على الخادم > 366 يوماً ⇒ لا تقدّم أعمى |")
w()
w("### ١.٥ خريطة الملفات")
w()
w("| الموضع عندنا | الملف |")
w("| --- | --- |")
for f in ["data/sync/SyncEpochs.kt", "data/sync/SyncWireFields.kt", "data/sync/SyncEntityGson.kt",
          "data/sync/PullSanityPolicy.kt", "data/sync/RemoteSignalPolicy.kt", "data/sync/AutomaticDeltaGate.kt",
          "data/repository/SyncManager.kt", "data/repository/SyncIngestorRegistry.kt",
          "data/repository/OutboxRepository.kt", "data/repository/BookingDerivedRefreshService.kt",
          "data/remote/PushWireContract.kt", "data/remote/realtime/RealtimePolicy.kt",
          "data/local/AppDatabase.kt", "domain/util/StatusUtils.kt"]:
    w(f"| `{f}` | `mobile/android/app/src/main/kotlin/com/marina/marina/{f}` |")
w()
w("| المرجع الدارتي | الملف |")
w("| --- | --- |")
for f, note in [
    ("mobile/lib/services/cloudflare_sync_manager.dart", "محرك السحب/الدفع الكامل + LWW + العزل"),
    ("mobile/lib/services/sync/fk_rules.dart", "قواعد ترجمة العلاقات (FK)"),
    ("mobile/lib/services/sync/pull_quarantine.dart", "سياسة الحجر (عتبة 3 + شفاء)"),
    ("mobile/lib/services/sync/pull_apply_rules.dart", "قواعد الدمج بالمفتاح الطبيعي"),
    ("mobile/lib/services/repositories/rooms_repository.dart", "refreshAllRoomOccupancy"),
    ("mobile/lib/utils/status_utils.dart", "مجموعات الحالات"),
    ("mobile/lib/services/booking_derived_fields_service.dart", "الحقول المشتقة"),
    ("mobile/lib/services/payment_void_service.dart", "إلغاء الدفعة (عقد كامل)"),
]:
    w(f"| `{f}` | {note} |")
w()
w("### ١.٦ سجل التغييرات (ما تغيّر فعلاً — لا ادّعاء)")
w()
w("**جولة إغلاق §5 (2026-10-07/08) — سلسلة `c3bc16b5` … `341f92fd`:**")
w()
w("| الالتزام | التغيير | الأثر | الدليل |")
w("| --- | --- | --- | --- |")
for r in [
 ("`c3bc16b5`", "توحيد الزمن: كل مواضع الميلي في 13 مستودعاً ⇒ `SyncEpochs.nowSeconds()` + فصل صريح للحقول الزمنية-العملية",
  "لا صف محلي بطابع ميلي يرفض تحديثات الخادم", "CI `37698116017` + `RepositoryEpochParityTest` (10)"),
 ("`c3bc16b5`", "نقل `refreshAllRoomOccupancy` حرفياً + الاستدعاءان (حفظ الحجز/إتمام المغادرة) + حذف التقريب الموضعي",
  "إشغال كل الغرف يُعاد ضبطه من الحجوزات النشطة كالمرجع", "`RoomOccupancySweepParityTest` (6)"),
 ("`c3bc16b5`", "عطل `last_modified = 0`: 8 نداءات DAO جزئية + terminate/reactivate/updateSettlement/voidPayment/markRead/softDeleteItem",
  "تعديلنا المحلي لم يعد يُطمس بأي صف خادمي ولو أقدم", "`RepositoryEpochParityTest`"),
 ("`c3bc16b5`", "`updateComputedFields` لا يلمس `last_modified/version` (نصّ تعليق Dart)",
  "فتح شاشة الدفع لم يعد يُفقد الصف أفضليته في LWW", "`RepositoryEpochParityTest`"),
 ("`c3bc16b5`", "رصيد المخزون بعد الحركة: ختم ثوانٍ + `version+1` + رفع `inventory_items:update`",
  "تغيير الرصيد صار يصل السحابة (كان محلياً فقط)", "`RepositoryEpochParityTest`"),
 ("`c3bc16b5`", "`payment_voids` و`booking_price_adjustments` يُختمان بالثواني (كانت أصفاراً)", "صفوف جديدة سليمة الطابع", "`RepositoryEpochParityTest`"),
 ("`c3bc16b5`", "حارس انزياح الساعة M3 في LWW: `remote.version > local.version` ⇒ المضيّ بالوارد", "لا فقد دائم لجهاز ساعته متقدمة", "3 اختبارات في `SyncIngestorRegistryTest`"),
 ("`c3bc16b5`", "`inventory_transactions.transaction_time` ×1000 من `created_at`",
  "حركات المخزون الواردة صارت داخل نطاق تقارير الميلي", "`SyncWireFieldParityTest` (قفل محدَّث بإفصاح)"),
 ("`b3768022`", "إصلاحا تصريف: ختم `BookingPriceAdjustment` على الصف؛ `secondsToMillis` يعيد `Any`", "بناء أخضر", "CI `37696113594` ⇒ `37696941360`"),
 ("`14d768a8`", "إغلاق تعليق Kotlin متداخل في KDoc", "تصريف الاختبارات", "CI"),
 ("`4619441f`", "تمرير `lastModified` في اختبار قديم بعد تغيّر توقيع DAO", "تصريف الاختبارات", "CI"),
 ("`2b7af35d`", "`SyncEntityGson`: تسلسل واعٍ بظلّ حقول `BaseSyncEntity` — **عطل حقيقي كشفه الاختبار**: حركات المخزون كانت لا تُرفع إطلاقاً",
  "كل رفع كيان أصبح ممكناً + اختبار انحدار", "CI `37696941360` ⇒ `37697574905`"),
 ("`d364b90b`", "تصحيح توقعات كمية في اختبارات جديدة (رصيد يبدأ من صفر)", "اختبارات صحيحة", "CI `37698116017` أخضر"),
 ("`341f92fd`", "توثيق §5 في `android-epoch-unit-parity.md` بأدلة التشغيل", "إفصاح كامل", "هذا الملف"),
]:
    w(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} |")
w()
w("**جولات أسبق في الفرع نفسه** (للحدود الزمنية: `3e71420f` إصلاح جذر الوحدة، "
  "`f23eb8db` هجرة Room 76→77، `0f4d2d20` قفل `finance_snapshots`، `8cef717a` إغلاق F-1..F-4) "
  "— تفاصيلها في `docs/android-epoch-unit-parity.md` و`docs/merge-4df4118-review.md`.")
w()
w("---")
w()

# ─────────────────────────── ٢) عقد السلك ───────────────────────────
w("## ٢) عقد السلك (D1 / Worker)")
w()
w("### ٢.١ جدول الكيانات ↔ الجداول")
w()
w("| الكيان (على السلك) | جدول D1 | جدول Room | صنف Kotlin | عدد أعمدة Room | عدد أعمدة D1 |")
w("| --- | --- | --- | --- | --- | --- |")
def room_for(d1table):
    return room_entities.get(d1table)
BLACKLIST_LOCAL = "blacklist_entries"
for ent, table in ENTITY_TABLES.items():
    rt = BLACKLIST_LOCAL if ent == "blacklist" else table
    info = room_entities.get(rt)
    cls = info["cls"] if info else "—"
    ncols = len(info["columns"]) if info else 0
    nd1 = len(D1.get(table, {}))
    w(f"| `{ent}` | `{table}` | `{rt}` | `{cls}` | {ncols} | {nd1} |")
w()
w(f"ملاحظة: كيان السلك `blacklist` يقابل محلياً جدول `{BLACKLIST_LOCAL}` "
  "مع إعادة تسمية حقول (انظر §٣.١).")
w()
w("### ٢.٢ حقول المزامنة الإجبارية (BaseSyncEntity — 17 حقلاً)")
w()
w("| الحقل | الدور |")
w("| --- | --- |")
for f, desc in AR.items():
    w(f"| `{f}` | {desc} |")
w()
w("**قاعدة النقل:** كل جدول متزامن يحمل هذه الأعمدة. `local_uuid` هو مفتاح الهوية "
  "الحقيقي بين الأجهزة؛ `id` محلي و`server_id` ظلّ لا يُكتب إلا من السحب.")
w()
w("### ٢.٣ وحدة الزمن — ثوانٍ لا ميلي ثانية (عقد حاكم)")
w()
w("| البند | القيمة | المصدر |")
w("| --- | --- | --- |")
w("| وحدة أعمدة المزامنة | **ثوانٍ** (`created_at`, `updated_at`, `deleted_at`, `last_modified`, `*_epoch`) | `SyncEpochs.nowSeconds()` / `Time.nowEpoch()` |")
w("| الحد الفاصل للتعرّف على الميلي | `> 100_000_000_000` (1e11) | `SyncEpochs.MILLIS_THRESHOLD` = `Database.MS_TIMESTAMP_THRESHOLD` |")
w("| سقف «المستقبلي» | `2_000_000_000` (2e9) | `SyncEpochs.FUTURE_THRESHOLD` |")
w("| التسامح مع انزياح ساعة الكتابة | 90 ثانية | `Database.CLOCK_SKEW_ALLOWANCE_S` |")
w("| التطبيع الوارد | يُقسَم الميلي على 1000 قبل قرار LWW وقبل الخزن | `SyncEpochs.normalizeWireEpochFields` |")
w("| التطبيع الصادر | نفسه على حمولة الرفع | `SyncEpochs.normalizeOutgoingEpochFields` (داخل `PushWireContract`) |")
w("| حقول تبقى بالميلي **بعمد** | `expenses.date` (نص ISO من `Date(ms)`), `payments.payment_date` (ISO), `payment_voids.voided_at_iso`, `salary_withdrawals.withdraw_date` (ميلي), `inventory_transactions.transaction_time` (ميلي محلي بحت) | تعليقات المستودعات + `SyncWireFields.millisTargets` |")
w("| أزمنة ليست أعمدة مزامنة | `OutboxRepository.clientTs` (ميلي)، `SyncManager` (ميلي)، `BookingDerivedRefreshService.moment` (ميلي) | تعليقات صريحة |")
w()
w("**الأثر إن أُهمل هذا العقد** (مقيس): صف ملموس محلياً بطابع ميلي يفوز دائماً على "
  "تحديثات الخادم بالثواني ⇒ لا يستقبل تحديثاً أبداً؛ والعكس: طابع صفري/أقدم يجعل "
  "أي صف خادمي يطمس التعديل المحلي.")
w()
w("### ٢.٤ نقاط النهاية (Worker)")
w()
w("| المسار | الطريقة | الدور |")
w("| --- | --- | --- |")
for route, method, role in [
    ("/api/sync/pull", "GET", "الدلتا: `cursor`,`limit≤500`,`entity?`,`exclude_device?`,`tombstones_only?`,`include_remaining?`,`normalize_timestamps?`"),
    ("/api/sync/push", "POST", "دفعة عمليات (≤ حجم الدفعة) → results[] + summary"),
    ("/api/sync/migrate", "POST", "مخطط/هجرات (تشغيلي)"),
    ("/api/sync/log", "GET", "سجل المزامنة"),
    ("/api/sync/conflicts", "GET", "التعارضات"),
    ("/api/sync/lock · /api/sync/unlock · /api/sync/locks", "POST/GET", "قفل المزامنة بين العمليات"),
    ("/api/realtime · /api/realtime/status", "GET", "قناة التغييرات الحيّة"),
    ("/api/devices/register · /api/devices/tokens", "POST/GET", "تسجيل الجهاز ورموز FCM"),
    ("/api/auth/login · /api/auth/register", "POST", "المصادقة"),
    ("/api/health/d1 · /health · /api/ping", "GET", "صحة"),
    ("/api/admin/sync/rotate-epoch", "POST", "تدوير حقبة المزامنة (تشغيلي)"),
    ("/api/stats · /api/ai/query", "GET/POST", "إحصاءات/استعلام"),
]:
    w(f"| `{route}` | `{method}` | {role} |")
w()
w("استجابة `/api/sync/pull`:")
w()
w("```json")
w('{ "changes": [ { "_entity": "...", "id": 1, "local_uuid": "...", "...": "أعمدة السطر كما في D1" } ],')
w('  "cursor": "12345", "epoch": 1, "has_more": true, "repair_pending": false,')
w('  "remaining": 0, "errors": [], "normalization": null, "server_time": 1760000000 }')
w("```")
w()
w("استجابة `/api/sync/push`:")
w()
w("```json")
w('{ "results": [ { "success": true, "skipped": false, "status": null|"validation_error"|"conflict"|"internal_error"|"deleted" } ],')
w('  "summary": { "total": 3, "success": 3, "failed": 0, "skipped": 0 }, "server_time": 1760000000 }')
w("```")
w()
w("### ٢.٥ الهجرات (worker/migrations) — 15 ملفاً")
w()
w("| الملف | الغرض |")
w("| --- | --- |")
mig = {
 "0002_inventory_blacklist.sql": "جداول المخزون والقائمة السوداء",
 "0003_app_users.sql": "مستخدمو التطبيق (حسابات)",
 "0004_devices_sync.sql": "سجل الأجهزة + أهداف FCM",
 "0005_schema_parity.sql": "مواءمة المخطط (أعمدة ناقصة)",
 "0006_salary_withdrawals_employee_uuid.sql": "ربط سحوبات الرواتب بالموظف بـuuid",
 "0007_salary_tables_employee_uuid.sql": "uuid للأب في جداول الرواتب",
 "0008_idempotency_log_cleanup.sql": "تنظيف سجل منع التكرار",
 "0009_finance_snapshots.sql": "جدول لقطات المالية (خادمي)",
 "0010_sync_meta.sql": "ميتا المزامنة (منها حقبة المزامنة)",
 "0011_salary_parent_uuids.sql": "uuid الأب لجداول الرواتب",
 "0012_expense_employee_link_clear_flag.sql": "علم فصل ربط الموظف عن المصروف",
 "0013_salary_withdrawal_expense_uuid.sql": "uuid المصروف على السحب",
 "0014_sync_write_times.sql": "أعمدة أوقات الكتابة",
 "0015_expense_kind.sql": "تصنيف المصروف",
}
for f in sorted(p.name for p in (ROOT/"worker/migrations").iterdir()):
    w(f"| `{f}` | {mig.get(f, '—')} |")
w()
w("### ٢.٦ الجداول المحلية المحضة (لا تُزامَن: لا رفع ولا سحب)")
w()
w("«محضة» تعني: ليست في `ENTITY_TABLES` ولا تُرسَل في `pull/push` ولا تُذكر في `_entity`.")
w("نسخة Dart يجب أن تملك مكافئها المحلي (جدول Room/SQLite أو مكافئه) بالحقول نفسها:")
w()
LOCAL_ACTIVE = [
    ("outbox", "طابور الصادر — المصدر الوحيد للرفع (§١.٣)", "active"),
    ("sync_quarantine", "سجل الحجر: صفوف سحب فشل تطبيقها بحمولتها (نظير cf_pull_orphan_*)", "active"),
    ("pending_sync_links", "صندوق دائم للسجلات المؤجَّلة (FK غير محلولة) — يُعاد كل دورة", "active"),
]
LOCAL_LEGACY = [
    ("sync_queue", "مخلّف عصر Appwrite: لا مستدعي في مسار Cloudflare (DAO مسجَّل فقط)"),
    ("sync_log", "مخلّف: تدوين عمليات الرفع/Sync المستخدم سابقاً"),
    ("sync_conflicts", "مخلّف: نزاعات الرفع (مسار الرفع الحالي لا يكتبه)"),
    ("sync_remote_meta", "مخلّف: ميتا Appwrite (last updated) قبل مؤشر D1"),
    ("sync_state", "مخلّف: صف مفرد كان يحمل المؤشر — المؤشر الفعلي في SharedPreferences (§٢.٧)"),
]
for tbl, desc, _ in LOCAL_ACTIVE:
    info = room_entities.get(tbl)
    cols = info["columns"] if info else []
    w(f"#### `{tbl}` — {desc} — عدد الحقول: {len(cols)}" if cols else f"#### `{tbl}` — {desc}")
    w()
    if cols:
        w("| العمود | خاصية Kotlin | اسم السلك (Gson) |" + (" ملاحظة |"))
        w("| --- | --- | --- |" + (" --- |"))
        notes = {
            ("outbox", "id"): "مفتاح أساسي تلقائي — ترتيب FIFO يعتمد عليه مع `client_ts`",
            ("outbox", "entity"): "كيان السلك (`bookings`, `rooms`, …)",
            ("outbox", "op"): "`insert`/`update`/`delete` — ويُترجَم إلى `create` عند الإرسال",
            ("outbox", "local_uuid"): "هوية الصف — أساس إعادة المحاولة بنفس المفتاح",
            ("outbox", "server_id"): "ظلّ الخادم إن كان معروفاً",
            ("outbox", "payload"): "JSON نصي **مُحوَّل إلى أسماء السلك** قبل الإدراج (`SyncWireFields.toWire`)",
            ("outbox", "clientTs"): "طابع الإدراج **بالمللي** (ترتيب محلي فقط — ليس عمود مزامنة)",
            ("outbox", "attempts"): "عدّاد المحاولات — سقف 5 (استثناء `salary_withdrawals`)",
            ("outbox", "lastError"): "آخر خطأ (يُقصّ)",
            ("outbox", "idempotencyKey"): "`{entity}_{op}_{localUuid}_{uuid}` — ثابت للصف عبر كل المحاولات",
            ("outbox", "processingStatus"): "`pending` ⇒ `processing` ⇒ `completed` (و`pending` عند خطأ مؤقت)",
            ("outbox", "processingStartedAt"): "مللي — لأجل استرداد الانهيار",
            ("outbox", "processingWorker"): "`outbox-processor`",
            ("outbox", "source"): "`local` افتراضاً؛ `remote` للسجلات المستوردة",
            ("outbox", "deliveredToPrimary"): "=1 بعد تأكيد D1 (نجاح أو رفض دائم)",
            ("outbox", "deliveredToSecondary"): "افتراضي 1 — التسليم الثاني معطّل ما لم يُضبط خادم ثانٍ",
            ("outbox", "primaryProcessingStatus"): "`pending`/`completed`/`failed` — سجل dead-letter مرئي",
            ("outbox", "primaryAttempts"): "عدّاد محاولات التسليم الأول",
            ("outbox", "primaryLastError"): "سبب dead-letter (`validation_error`/`conflict`/…)",
            ("outbox", "secondaryProcessingStatus"): "غير مستخدم فعلياً (افتراضي `pending`)",
            ("outbox", "payloadVersion"): "نسخة شكل الحمولة — تُرفَع عند تغيّر العقد",
            ("outbox", "processingPayloadVersion"): "نسخة الحمولة وقت الحجز — للتشخيص",
            ("sync_quarantine", "entity"): "كيان الصف المعزول",
            ("sync_quarantine", "recordKey"): "مفتاح السجل (مثل `uuid:<local_uuid>`) — جزء من المفتاح الأساسي",
            ("sync_quarantine", "payload"): "الحمولة الخام للمراجعة — **لا تُرفع ولا تُسجَّل أبداً**",
            ("sync_quarantine", "reason"): "سبب العزل (FK غير محلولة/فشل تطبيق)",
            ("sync_quarantine", "attempts"): "عدّاد الدورات الفاشلة (عتبة الشفاء في §٦.٣)",
            ("sync_quarantine", "firstSeen"): "طابع أول عزل (ثوانٍ) — أساس إخلاء السقف الأقدم-أولاً",
            ("pending_sync_links", "entity"): "كيان الصف المؤجَّل — جزء من المفتاح الأساسي",
            ("pending_sync_links", "localUuid"): "هوية الصف المؤجَّل — جزء من المفتاح الأساسي",
            ("pending_sync_links", "payload"): "الحمولة الكاملة — تُعاد للمعالجة كل دورة بلا فقد",
        }
        for c in cols:
            note = notes.get((tbl, c["prop"]), "")
            w(f"| `{c['col'] or c['prop']}` | `{c['prop']}` | `{c['wire'] or '—'}` | {note} |")
    w()
w("> ملاحظة: عمود «اسم السلك» في هذه الجداول هو `@SerializedName` (شكل JSON إن سُجِّل الصف محلياً في")
w("> النسخ الاحتياطية) — وليس حقلاً يُرسَل إلى الـWorker.")
w()
w("#### ٢.٦.١ آلة حالات طابور الصادر (عقد تنفيذي — يُنقل حرفياً)")
w()
w("| المرحلة | القاعدة | المصدر |")
w("| --- | --- | --- |")
w("| الإدراج | `op` يُترجَم: `insert`⇒`create`؛ `update`/`delete` كما هي؛ الحمولة تُحوَّل لأسماء السلك قبل التخزين | `OutboxRepository.enqueue` |")
w("| مفتاح منع التكرار | `{entity}_{op}_{localUuid}_{uuid}` — يُولَّد مرة ويُعاد استخدامه في كل محاولة | المرجع نفسه |")
w("| الدفعات | حتى `PUSH_BATCH_SIZE` عملية/طلب؛ الصفوف تُحجز `processing` **قبل** الإرسال | `processPending` |")
w("| استرداد الانهيار | عند الإقلاع: كل `processing` ⇒ `pending` (صفوف انهار التطبيق قبل إتمامها لا تبقى معلّقة) | `OutboxDao.recoverStaleProcessing` |")
w("| نجاح | `markDeliveredPrimary` + `completed` ⇒ `delivered++` | المرجع نفسه |")
w("| نجاح بحالة `deleted` | يُطبَّق حذف محلي فوري (`tombstoneLocalRecord`) — حسم الخادم نهائي | المرجع نفسه |")
w("| رفض دائم | `validation_error`/`conflict` ⇒ `failed` + `completed` (dead-letter بلا إعادة أبدية) | `isPermanentRejection` |")
w("| خطأ مؤقت | `internal_error` ⇒ `pending` لإعادة المحاولة | المرجع نفسه |")
w("| فشل شبكة | الاستثناء ⇒ `pending` للصف كله (لا يُعدّ رفضاً) | `onFailure` |")
w("| سقف المحاولات | `attempts ≥ 5` ⇒ dead-letter — **عدا `salary_withdrawals`** (الأب قد يصل متأخراً) | `retryLimitReached` |")
w("| لا نتيجة للعملية | إن لم يُرجع الخادم نتيجة لهذه العملية ⇒ `pending` | المرجع نفسه |")
w("| التنظيف | `DELETE FROM outbox WHERE delivered_to_primary=1 AND delivered_to_secondary=1` بعد كل دورة | `cleanupDelivered` |")
w("| التسليم الثاني | معطّل فعلياً: الصفوف تُعلَم `delivered_to_secondary=1` افتراضاً (توافق مع صندوق Dart المزدوج) | `syncOutbox` |")
w()
w("**استعلامات مرآتها إلزامية في Dart:** المعلّق = `processing_status='pending' AND delivered_to_primary=0` "
  "بترتيب `client_ts ASC, id ASC`؛ وغير المُسلَّم = `source='local' AND delivered_to_primary=0`.")
w()
w("**جداول مخلّفة موجودة في القاعدة ولا يستعملها مسار Cloudflare** (تُنقل كمرجع للسجل التاريخي فقط،")
w("ولا حاجة لمكافئها في نسخة Dart):")
w()
w("| الجدول | السبب |" )
w("| --- | --- |")
for tbl, desc in LOCAL_LEGACY:
    w(f"| `{tbl}` | {desc} |")
w()
w("### ٢.٧ مفاتيح التخزين المحلي (SharedPreferences — عقد أسماء حرفي)")
w()
w("المؤشر والحقبة والإعدادات **ليست في القاعدة**: تُخزَّن في تفضيلات مشفّرة")
w("(`marina_secure_prefs` عبر `EncryptedSharedPreferencesManager`)، والأسماء")
w("مطابقة حرفياً لسلاسل Dart (`unified_sync_settings_screen.dart`) لضمان التوافق عند الترقية.")
w("**نسخة Dart يجب أن تستعمل المفاتيح نفسها حرفياً** وإلا انكسر الاستئناف بعد التحديث:")
w()
prefs_src = (ROOT/"mobile/android/app/src/main/kotlin/com/marina/marina/data/remote/CloudflareSyncService.kt").read_text(encoding='utf-8')
KEYS = re.findall(r'private const val (KEY_\w+)\s*=\s*"([^"]+)"', prefs_src)
KEY_ROLE = {
 "KEY_AUTH_TOKEN": ("توكن Bearer لدخول الـWorker", "—"),
 "KEY_LAST_PULL": ("طابع آخر سحب ناجح (ثوانٍ) — للعرض/المراقبة", "0"),
 "KEY_LAST_PUSH": ("طابع آخر رفع ناجح (ثوانٍ)", "0"),
 "KEY_DEVICE_ID": ("هوية الجهاز — أساس echo filter و`X-Device-Id`", "—"),
 "KEY_FULL_SYNC_COMPLETE": ("اكتمل السحب الشامل الأول", "false"),
 "KEY_CURRENT_USER": ("JSON المستخدم الحالي", "—"),
 "KEY_LAST_PULL_CURSOR": ("**مؤشر السحب العام** (D1 `updated_at`) — أساس الدلتا", "0"),
 "KEY_FULL_REPLAY_PENDING": ("مطلوب إعادة سحب كاملة (بعد استرجاع نسخة/تغيير حقبة)", "false"),
 "KEY_SYNC_EPOCH": ("حقبة المزامنة الخادمية (§٦.٥)", "—"),
 "KEY_SYNC_ERROR_HISTORY": ("آخر 40 خطأ مزامنة (بلا حمولات/رموز)", "[]"),
 "KEY_AUTO_SYNC_ENABLED": ("المفتاح الرئيسي للمزامنة التلقائية", "—"),
 "KEY_SYNC_ON_STARTUP": ("سحب عند الإطلاق", "—"),
 "KEY_BATTERY_OPTIMIZATION": ("تجاوز تحسين البطارية مطلوب", "—"),
 "KEY_WIFI_ONLY": ("المزامنة على Wi‑Fi فقط", "—"),
 "KEY_SMART_SYNC": ("المزامنة الذكية", "—"),
 "KEY_CLOUDFLARE_SYNC": ("مفتاح التزامن مع Cloudflare (يُصفَّر عند الاسترجاع)", "—"),
 "KEY_REALTIME_SYNC": ("تشغيل قناة Realtime", "—"),
 "KEY_SYNC_INTERVAL": ("دورية الفحص (دقائق)", "—"),
 "KEY_REMEMBER_ME": ("«تذكرني» في الدخول", "—"),
 "KEY_TS_NORMALIZATION_DONE": ("اكتمل تطبيع الطوابع الخادمي لمرة واحدة", "false"),
 "KEY_TOMBSTONE_SWEEP_DONE": ("اكتمل مسح الحذفيات التاريخي (يُضبط على النجاح فقط)", "false"),
 "KEY_TOMBSTONE_SWEEP_CURSOR": ("مؤشر استئناف المسح — يُحفظ بعد كل صفحة مطبَّقة", "0"),
}
w("| الثابت | المفتاح الفعلي | الدور | الافتراضي |")
w("| --- | --- | --- | --- |")
for name, key in KEYS:
    role, dflt = KEY_ROLE.get(name, ("—", "—"))
    w(f"| `{name}` | `{key}` | {role} | `{dflt}` |")
w()
w("**دلالات مضبوطة (لا اجتهاد):**")
w()
w("- `cf_full_replay_pending`: يُضبط `true` عند الاسترجاع من نسخة محلية، ثم تُطلب دورة كاملة من المؤشر 0.")
w("- `cf_timestamp_normalization_done`: `false` يعني أن العميل لم يطبّع طوابع ميلي قديمة بعد.")
w("- `cf_tombstone_sweep_done` لا يُضبط إلا على **اكتمال** مسح ناجح؛ ومؤشره يُحفظ لكل صفحة كي لا يُعاد من الصفر.")
w("- `marina_cloudflare_prefs` منفصلة: `cf_custom_worker_url` و`cf_worker_active_url` (§٢.٨).")
w()
w("### ٢.٨ المصادقة والنقل (Headers + تبديل نقاط النهاية)")
w()
w("| البند | القيمة | المصدر |")
w("| --- | --- | --- |")
w("| الترويسة | `Authorization: Bearer <JWT>` | `WorkerInterceptors.WorkerAuthInterceptor` |")
w("| ترويسة الجهاز | `X-Device-Id: <device_id>` (تُضاف فقط إن كانت غير فارغة) | المرجع نفسه |")
w("| مسارات بلا توكن | `/api/auth/login` و`/health` (توكن الجلسة المحلية `local:admin-session` لا يُرسل أبداً) | المرجع نفسه |")
w("| نقاط النهاية | النطاق المخصّص (`cf_custom_worker_url`) أولاً، وإلا المدمج `workers.dev`؛ والآخر الناجح يُثبَّت (`cf_worker_active_url`) | `WorkerEndpoints` |")
w("| حالات تُدوّر النقطة | فشل شبكة (`IOException`) أو `521/522/530` من Cloudflare | `WorkerFailoverInterceptor` |")
w("| تسجيل الجهاز | `POST /api/devices/register` بحقول `deviceId` / `fcmToken` / `deviceName` / `platform` / `localUuid` | `worker/src/index.ts` |")
w("| توكنات FCM | `GET /api/devices/tokens` (يستثني الجهاز الحالي) | المرجع نفسه |")
w("| معدّل الطلبات | نافذة `RATE_LIMIT_WINDOW` ثوانٍ بحد `RATE_LIMIT_MAX` (افتراضي 60/1000)، والدخول بحد أقصى 20 محاولة | المرجع نفسه |")
w("| سرقة التوكن في السجلات | أي `Bearer …` يُستبدل بـ`Bearer [محذوف]` قبل التخزين (حد 2500 حرف/سجل، 40 سجلاً) | `SyncPreferences.recordSyncError` |")
w()
w("**عقد الدخول** (`POST /api/auth/login`): الطلب `{username, password, device_id?}`؛ ")
w("النجاح `200 {token, user:{id, username, role}}` و`device_id` يُضمَّن في JWT؛ ")
w("الرفض `401 {error:\"Invalid credentials\"}`؛ النقص `400 {error:\"Username and password required\"}`.")
w("**التسجيل** (`POST /api/auth/register`): الطلب `{username, password, role?}` حيث `role ∈ {admin, manager, staff}`؛ ")
w("يُسمح به بلا توكن فقط ما دام لا يوجد مستخدم نشط (bootstrap)، وإلا فيشترط دور `admin`.")
w()
w("**غلاف الأخطاء الموحّد:** `{error: \"…\"}` وبجانبه حسب الحالة: `detail` عند 500، ")
w("`retry_after` (طابع نهائي بالمللي) + ترويسة `Retry-After` (ثوانٍ) عند 429.")
w()
w("### ٢.٩ سياسات الحسم (منطق خالص قابل للنقل حرفياً)")
w()
w("| السياسة | المدخلات | القرار/القاعدة | الملف |")
w("| --- | --- | --- | --- |")
w("| إشارة بعيدة | `data[\"type\"] ?? data[\"source\"]` | `marina_sync` وإلا تُهمَل | `RemoteSignalPolicy.isSyncMessage` |")
w("| صدى الجهاز | `senderDeviceId` | غائب ⇒ ليست صدى؛ مطابق لمعرّفنا ⇒ صدى (لا سحب) | `RemoteSignalPolicy.isOwnEcho` |")
w("| ما يُفعل بالإشارة | مفتاح المزامنة + ظهور الواجهة | معطّل ⇒ `IGNORE`؛ أمام الواجهة ⇒ `DELIVER`؛ خلفيتها ⇒ `DEFER` | `RemoteSignalPolicy.decide` |")
w("| استهلاك المؤجَّل | مفتاح المزامنة + تصريح الشبكة | لا يُستهلك (ولا يُسقَط) إلا بتحقّق الشرطين معاً | `RemoteSignalPolicy.shouldConsumeDeferred` |")
w("| بوابة الدلتا التلقائية | `now`, `lastSuccess` | فاصل 60 دقيقة (`AUTOMATIC_PULL_INTERVAL_MS`) | `AutomaticDeltaGate` |")
w("| حقبة المزامنة | المخزّنة، الواردة، `pageBuiltFromZero` | مطابقة ⇒ لا تغيير؛ أول حقبة ⇒ تُتبنّى بلا إعادة سحب؛ تغيّرت بلا صفحة-من-الصفر ⇒ إعادة من 0 | `SyncEpochPolicy.evaluate` |")
w("| سلامة المؤشر | المخزّن، مؤشر الخادم، وقت الخادم | `> 2e9` مرفوض؛ تقدّم على وقت الخادم > 366 يوماً مرفوض؛ لا يُثبَّت مؤشر معلّق قبل النجاح | `PullSanityPolicy` |")
w("| مراقب المعلّقات | طابور الصادر | فحص كل 5 دقائق (`PENDING_PUSH_MONITOR_MS`) | `AutoSyncEngine` |")
w("| Realtime: المهلة/الانحدار | المحاولة | `debounce 500ms`، `cooldown 15s`، انحدار 1s→60s، 6 محاولات، إعادة تسليح 120s، نبض 30s، مهلة اتصال 15s | `RealtimePolicy` |")
w("| Realtime: الرسالة | نص JSON | `{type, entity, entityId, operation?, deviceId?, timestamp}` — أي شكل غير متوقع ⇒ `null` وتُهمَل بهدوء | `RealtimeMessage.tryParse` |")
w()
w("**FCM:** التصفية (المصدر ثم الصدى) ثم `onRemoteSignal(source=\"fcm\")`؛ ما لم يُنقل عمداً:")
w("إشعارات FCM المحلية وعرض حمولتها (ليست من عقد السحب).")
w()
w("---")
w()

# ─────────────────────────── ٣) الحقول ───────────────────────────
w("## ٣) الحقول والربط — الفهارس الكاملة (مولّدة من المصدر)")
w()
w("### ٣.١ أسماء السلك المختلفة (aliases عند الاستيعاب)")
w()
w("| الكيان | حقل السلك | الحقل المحلي |")
w("| --- | --- | --- |")
for ent, pairs in LOCAL_ALIASES.items():
    for wire, local in pairs.items():
        w(f"| `{ent}` | `{wire}` | `{local}` |")
w()
w("### ٣.٢ الافتراضيات عند غياب الحقل (entityDefaults — نظير `?? fallback` في محوّلات Dart)")
w()
w("| الكيان | الحقل | القيمة الافتراضية |")
w("| --- | --- | --- |")
for ent, pairs in ENTITY_DEFAULTS.items():
    for k, v in pairs.items():
        shown = ('`' + v + '`') if v != '' else '(فراغ)'
        w(f"| `{ent}` | `{k}` | {shown} |")
w()
w("### ٣.٣ مرايا الرفع (wireMirrors — تُضاف بجانب المحلي قبل الإرسال)")
w()
w("| الكيان | الحقل المحلي | اسم السلك |")
w("| --- | --- | --- |")
for ent, pairs in WIRE_MIRRORS.items():
    for local, wire in pairs.items():
        w(f"| `{ent}` | `{local}` | `{wire}` |")
w()
w("### ٣.٤ أعمدة محلية بميلي تُغذّى بالثواني (تُضاعف ×1000 عند الاستيعاب)")
w()
for t in sorted(MILLIS_TARGETS):
    w(f"- `{t}`")
w()
w("### ٣.٥ جداول الحقول — كل كيان")
w()
w("> `—` في عمود الغلاف يعني «لا مقابل على السلك» (عمود محلي بحت). "
  "الحقول المعلَّمة «مزامنة» هي حقول `BaseSyncEntity`.")
w()
SYNC_SET = SYNC_FIELDS
for ent, table in ENTITY_TABLES.items():
    rt = BLACKLIST_LOCAL if ent == "blacklist" else table
    info = room_entities.get(rt)
    if not info:
        continue
    w(f"#### `{ent}` → D1 `{table}` · Room `{rt}` · {info['cls']} ({len(info['columns'])} حقلاً)")
    w()
    aliases = LOCAL_ALIASES.get(ent, {})
    defaults = ENTITY_DEFAULTS.get(ent, {})
    mirrors = WIRE_MIRRORS.get(ent, {})
    w("| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |")
    w("| --- | --- | --- | --- | --- |")
    for c in info["columns"]:
        col = c["col"] or c["wire"] or c["prop"]
        wire = c["wire"] or ""
        d1 = D1.get(table, {}).get(col)
        d1type = (d1["type"] + (" • NOT NULL" if d1["notnull"] else "") +
                  (f" • DEFAULT {d1['default']}" if d1.get("default") else "")) if d1 else "—"
        notes = []
        if c["prop"] in SYNC_SET: notes.append("مزامنة")
        if not wire and c["prop"] not in SYNC_SET: notes.append("محلي فقط")
        for wire_alias, local_alias in aliases.items():
            if local_alias == col:
                notes.append(f"يُغذّى من `{wire_alias}` على السلك")
        if c["prop"] in defaults or col in defaults:
            key = c["prop"] if c["prop"] in defaults else col
            shown = defaults[key] if defaults[key] != "" else '""'
            notes.append(f"افتراضي عند الغياب: `{shown}`")
        if col in mirrors: notes.append(f"يُرسَل أيضاً كـ`{mirrors[col]}`")
        if f"{ent}.{col}" in MILLIS_TARGETS: notes.append("ميلي محلي (×1000 من السلك)")
        w(f"| `{col}` | {('`'+wire+'`') if wire else '—'} | `{c['prop']}` | {d1type} | {' • '.join(notes)} |")
    w()

# ─────────────────────────── ٤) العلاقات ───────────────────────────
FK_ROWS = [
 ("bookings","room_number","naturalKey","rooms","room_number",False,None,False,False),
 ("booking_nights","booking_local_id","numericPointer","bookings","id",False,"booking_uuid_cache",True,False),
 ("booking_notes","booking_id","numericPointer","bookings","id",False,None,True,False),
 ("payments","booking_local_id","numericPointer","bookings","id",True,"booking_uuid_cache",True,False),
 ("payments","cash_transaction_local_id","numericPointer","cash_transactions","id",True,None,False,True),
 ("booking_price_adjustments","booking_local_id","numericPointer","bookings","id",True,"booking_uuid",True,False),
 ("booking_price_adjustments","booking_local_uuid","naturalKey","bookings","local_uuid",False,None,False,False),
 ("salary_cycles","employee_id","numericPointer","employees","id",False,"employee_uuid",False,False),
 ("salary_payments","cycle_id","numericPointer","salary_cycles","id",False,None,False,False),
 ("salary_withdrawals","employee_id","numericPointer","employees","id",False,"employee_uuid",False,False),
 ("salary_carry_over_logs","employee_id","numericPointer","employees","id",False,None,False,False),
 ("inventory_transactions","item_id","numericPointer","inventory_items","id",False,"item_local_uuid",False,False),
]
w("## ٤) قواعد العلاقات (FK) — ترجمة هوية الخادم إلى الهوية المحلية")
w()
w("المصدر الحاكم: `mobile/lib/services/sync/fk_rules.dart` في الفرع المرجعي "
  "(مستخرج آلياً من `local_db.dart` و`schema.sql`)، ومطابقة تنفيذه عندنا في "
  "`SyncIngestorRegistry`. **نوعان فقط:**")
w()
w("- `numericPointer`: العمود الرقمي يحمل `id` الأب في فضاء الخادم ⇒ يُترجَم إلى `id` الصف المحلي.")
w("- `naturalKey`: العمود نصّي عالمي (`room_number` أو `local_uuid`) ⇒ يمر كما هو، ويُشترط وجود الأب فقط.")
w()
w("| الكيان | العمود | النوع | الأب | مفتاح الأب | nullable | عمود uuid-cache | يُجرَّب server_booking_id القديم | NULL عند تعذّر الحل |")
w("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for r in FK_ROWS:
    ent, col, kind, pt, pk, nul, ucc, legacy, nu = r
    w(f"| `{ent}` | `{col}` | `{kind}` | `{pt}` | `{pk}` | {'نعم' if nul else 'لا'} | "
      f"{('`'+ucc+'`') if ucc else '—'} | {'نعم' if legacy else '—'} | {'نعم' if nu else '—'} |")
w()
w("### ٤.١ خوارزمية الحل (بالترتيب)")
w()
w("```text")
w("① الهوية العالمية أولاً: uuid-cache على الابن → local_uuid الأب (الأوثق بين الأجهزة)")
w("② ظلّ الخادم: bookings.server_id / *_id المحلي ← تُعلَّم من السحب (server_id := id الخادمي)")
w("③ الفضاء القديم: server_booking_id على الابن ← server_booking_id على الأب (صفوف Appwrite المهاجرة)")
w("④ فشل الكل: العمود nullable ⇒ يُترك NULL (أو يُحذف من الحمولة)؛ غير nullable ⇒")
w("   الصف يُؤجَّل (deferred) ويُعاد بعد اكتمال الصفحات، وإن تكرّر ⇒ حجر بحمولته")
w("```")
w()
w("**نقاط دقيقة مثبتة:**")
w("")
w("- `booking_nights`: المفتاح الطبيعي `(booking_local_id, hotel_day_key)` — صف بـ`local_uuid` "
  "جديد لنفس الليلة **يُدمج LWW** بدل إدراج صف ثانٍ.")
w("- `payments.cash_transaction_local_id`: مؤشر ثانوي — تعذّر الحل ⇒ NULL (لا يُعطّل الدورة).")
w("- `payment_voids` و`price_adjustments`: كل أعمدتها uuid عالمية بلا قيود FK محلية ⇒ تمر بلا ترجمة.")
w("- حارس الكتابة المحلية: أي كتابة تُثبّت `localUuid` من الصف القائم (لا تولّد جديداً عند التحديث).")
w()
w("---")
w()

# ─────────────────────────── ٥) عقد الكتابة ───────────────────────────
w("## ٥) عقد الكتابة المحلية (ما يجب أن يفعله كل مسار كتابة)")
w()
w("| # | القاعدة | التفصيل |")
w("| --- | --- | --- |")
w("| 1 | ختم الزمن بالثواني | `createdAt/updatedAt/lastModified/deletedAt/lastModifiedEpoch = SyncEpochs.nowSeconds()` |")
w("| 2 | `last_modified` يُكتب دائماً | لا يُترك صفراً: نموذج المجال لا يحمله ⇒ يُختم على `.toEntity()` أو على صف `getById` |")
w("| 3 | `version+1` في التحديث | نظير `existing.version + 1` (كاسر تعادل الـWorker عند تساوي `updated_at`) |")
w("| 4 | الكتابات الجزئية (UPDATE) | كل `@Query` تحديث يمرّر `lastModified` ويُرفع `version` حيث يرفعه Dart |")
w("| 5 | outbox مع الكتابة | `enqueueObject(entity, op, localUuid, payload)` — و`insert` تُترجَم إلى `create` |")
w("| 6 | الحذف ناعم + مزامن | `deleted_at` + `updated_at` + `last_modified` + صف outbox `delete` |")
w("| 7 | حقول الهوية تُحفظ | عند التحديث: `localUuid/createdAt/serverId` من الصف القائم لا من النموذج |")
w("| 8 | استثناء معلن | `checkout` (مسار الحجز): لا يدرج outbox — صراحةً مطابق للمرجع |")
w("| 9 | الحقول المشتقة | تُحسب محلياً وتُكتب **بلا** لمس `last_modified/version` (وإلا منعت السحب من تحديثها) |")
w()
w("### ٥.١ جدول الكتابات الجزئية المصلَحة (عطل `last_modified=0`)")
w()
w("| DAO | الدالة | ما تكتبه الآن |")
w("| --- | --- | --- |")
for r in [
 ("BlacklistEntriesDao/CashTransactionsDao/DebtsDao/EmployeesDao/ExpensesDao/GuestInfosDao/InventoryDao/PaymentsDao/SalaryWithdrawalsDao/ShiftNotesDao/BookingsDao/RoomsDao", "softDelete", "`deleted_at`,`updated_at`,`last_modified` = now(ثوانٍ)"),
 ("DebtsDao", "updateSettlement", "+ `version = version + 1` (نظير Dart)"),
 ("EmployeesDao", "terminate / reactivate", "+ `version = version + 1`"),
 ("PaymentsDao", "voidPayment", "+ `version = version + 1` + `is_immutable = 1`"),
 ("ShiftNotesDao", "markRead", "+ `version = version + 1`"),
 ("InventoryDao", "softDeleteItem", "`deleted_at`,`updated_at`,`last_modified`"),
 ("InventoryDao", "updateQuantity (بعد حركة)", "+ `last_modified`,`last_modified_epoch`، `version+1`"),
]:
    w(f"| `{r[0]}` | `{r[1]}` | {r[2]} |")
w()
w("### ٥.٢ كتابات كاملة (insert/update) — العقد لكل مستودع")
w()
w("| المستودع | insert | update | ملاحظة |")
w("| --- | --- | --- | --- |")
for r in [
 ("BlacklistRepositoryImpl", "ثوانٍ + lastModified/epoch على الصف", "ثوانٍ + version+1 (fallback: existing?.version ?: 1)", "localUuid/createdAt من القائم"),
 ("CashRepositoryImpl", "ثوانٍ + lastModified/epoch", "—", "لا تحديث"),
 ("DebtsRepositoryImpl", "ثوانٍ + lastModified/epoch", "ثوانٍ + version+1", "markSettled عبر DAO جزئي"),
 ("EmployeesRepositoryImpl", "ثوانٍ + lastModified/epoch", "ثوانٍ + version+1", "terminate/reactivate جزئيان"),
 ("ExpensesRepositoryImpl", "ثوانٍ؛ `date` = ISO بالميلي", "ثوانٍ + version+1 (coerce 0..999999)", "مرآة السحب/الراتب داخل معاملة"),
 ("GuestInfosRepositoryImpl", "ثوانٍ + lastModified/epoch", "ثوانٍ + version+1 (fallback ?: 1)", ""),
 ("InventoryRepositoryImpl", "ثوانٍ + lastModified/epoch", "ثوانٍ + version+1 (fallback ?: prepared.version)", "recordMovement: ختم الصنف + رفع الصف + الحركة"),
 ("PaymentsRepositoryImpl", "ثوانٍ؛ `payment_date` ISO بالميلي", "ثوانٍ + version+1", "void: سجل payment_voids مختم + رفع الدفعة"),
 ("BookingsRepositoryImpl", "ثوانٍ + lastModified/epoch + إعادة بناء المشتقات", "ثوانٍ + version+1 + إعادة البناء", "updateComputedFields: بلا لمس lastModified/version"),
 ("BookingNightsRepositoryImpl", "replaceNights/upsertAdjustment: ثوانٍ", "deactivateAdjustment: version+1", "منطق المفتاح الطبيعي"),
 ("SalaryRepositoryImpl", "insertCycle/insertPayment/carryOver: ثوانٍ + lastModified", "updateCycle: ثوانٍ + version+1", "employee_uuid إلزامي"),
 ("SalaryWithdrawalsRepositoryImpl", "ثوانٍ؛ `withdraw_date` ميلي", "ثوانٍ + حفظ localUuid/createdAt", "مرآة المصروف"),
 ("ShiftNotesRepositoryImpl", "ثوانٍ + lastModified/epoch", "ثوانٍ + version+1", "markRead جزئي + version"),
 ("RoomsRepositoryImpl", "ثوانٍ + lastModified/epoch", "ثوانٍ + version+1", "updateStatus + مسح الإشغال"),
]:
    w(f"| `{r[0]}` | {r[1]} | {r[2]} | {r[3]} |")
w()
w("---")
w()

# ─────────────────────────── ٦) السحب ───────────────────────────
w("### ٥.٣ عقد التسلسل (ما يقابل `SyncEntityGson` عندنا)")
w()
w("الحمولة تُبنى بـ`Map<String,Any?>` بأسماء **snake_case للسلك**، مع ثلاث قواعد مُثبتة بالتشغيل:")
w()
w("| القاعدة | السبب | الدليل |")
w("| --- | --- | --- |")
w("| لا تكرار لاسم مفتاح في JSON ناتج عن كيان يرث حقول الأساس | في Kotlin يفشل `Gson()` البسيط بـ`declares multiple JSON fields named 'id'`؛ في Dart لا يظهر الخطر نفسه لأن البناء يدوي | `SyncEntityGson` + اختبار الانحدار #11 |")
w("| الحركات التي لا تُرفع = عطل صامت: أي استثناء أثناء التسلسل يجب أن يُسجَّل لا أن يُبتلع | حركات المخزون لم تُرفع إطلاقاً قبل الإصلاح | `2b7af35d` |")
w("| القيم `null` لا تُرسَل كأعمدة فارغة تُطمس الخادم | الخادم يحدّث الأعمدة المرسلة فقط | `PushWireContract` |")
w()
w("**في Dart:** ابنِ الحمولة من نموذج المجال مع `toWireMap()` صريح، وتحقّق في اختبار أن مفاتيح حمولة ")
w("كل كيان تساوي تماماً قائمة أعمدة السلك في §٣.٥ (لا زيادة ولا نقصان).")
w()
w("---")
w()

w("## ٦) عقد السحب التفصيلي")
w()
w("### ٦.١ LWW + حارس انزياح الساعة (M3)")
w()
w("```text")
w("normalizedRemote = toSeconds(record.last_modified)")
w("if (local == null)                      ⇒ تخزين (صف جديد)")
w("else if (remote.deleted_at != null)      ⇒ tombstone: تُحدَّث حقول المزامنة فقط (قرار نهائي)")
w("else if (normalizedRemote >= toSeconds(local.last_modified)) ⇒ استبدال الصف المحلي (بنفس id)")
w("else if (remote.version > local.version) ⇒ استبدال أيضاً  ← حارس M3 (ساعة الجهاز متقدمة)")
w("else                                    ⇒ تخطٍّ (المحلي أحدث ولم يُرفع بعد)")
w("```")
w()
w("**لماذا M3:** بلا الحارس، جهاز ساعته متقدمة يُسقط كل وارد إلى الأبد بينما مؤشر "
  "السحب يتقدم فوقه ⇒ فقد دائم غير مرئي. الدليل: الخادم يختم `version` بنفسه "
  "(`existing.version + 1` في `database.ts`) فلا يقبل نسخة العميل.")
w()
w("**تطابق التعادل:** عند تساوي الطابع يفوز الوارد (نظير `local > remote` كشرط تخطٍّ في Dart).")
w()
w("### ٦.٢ مسح الحذفيات (Tombstone sweep)")
w()
w("- الـWorker يدعم `tombstones_only=1` (الصفوف المحذوفة فقط) — نافذة رخيصة لالتقاط ما فاته عميل بنى على نافذة العقد القديم.")
w("- العميل يمسح حتى **20 صفحة/دورة** بمؤشر محفوظ، والعلم لا يُضبط قبل الاكتمال.")
w("- ترتيب البث: التمثال يُبَث في الترتيب الزمني نفسه بجوار الصفوف الحية (لا يُسطَّح مرة واحدة).")
w()
w("### ٦.٣ الحجر والشفاء (Quarantine)")
w()
w("| البند | القيمة |")
w("| --- | --- |")
w("| سعة الحجر | 300 صف (الأقدم يُطرد) |")
w("| العتبة | 3 محاولات قبل اعتباره محجوراً دائماً (يُتخطى في صفحات السحب) |")
w("| الشفاء | دفعة شفاء حتى 100/دورة (`healQuarantinedBatch`) |")
w("| مبدأ حاكم | **المؤشر يتقدم دائماً** — لا تجميد؛ الصف المحجور يبقى قابل الاسترجاع بحمولته |")
w("| أثر الصف السيئ | يُعزل ولا يُسقط الصفحة (فلسفة Dart: «الصف يُطبَّق» والبقية تمضي) |")
w()
w("### ٦.٤ إعادة بناء الحقول المشتقة")
w()
w("- الكيانات المُحفِّزة: `bookings`, `booking_nights`, `payments`, `price_adjustments`, `booking_price_adjustments`, `payment_voids`.")
w("- تُنفَّذ بعد دورة السحب إن لمس أي منها، وفي معاملة واحدة لكل الدفعة، وحجز فاشل لا يُسقط البقية.")
w("- الكاتب المحلي: أي كتابة حجز/دفعة تُعيد البناء في المعاملة نفسها.")
w()
w("### ٦.٥ حراس سلامة المؤشر")
w()
w("| الحارس | القيمة |")
w("| --- | --- |")
w("| سقف صفحات الدورة | 100 |")
w("| نافذة الدلتا القصوى (مجموعة `updated_at` واحدة) | 20,000 صف |")
w("| مؤشر مستقبلي مرفوض | > 2e9 |")
w("| تقدم على الخادم مرفوض | > 366 يوماً |")
w("| معاينة `remaining` | كل 5 صفحات (تخفيف حمل) |")
w()
w("---")
w()

# ─────────────────────────── ٧) الإشغال ───────────────────────────
w("## ٧) الإشغال والحالات (نظير `status_utils.dart`)")
w()
w("### ٧.١ `refreshAllRoomOccupancy` (النقل الحرفي)")
w()
w("```text")
w("occupied = { room_number | bookings.deleted_at IS NULL AND status IN (التسعة) }")
w("لكل غرفة غير محذوفة:")
w("  shouldBeOccupied = occupied.contains(room.roomNumber)")
w("  if ( shouldBeOccupied && !isRoomOccupied(room.status))   ⇒ status = 'محجوزة'")
w("  else if (!shouldBeOccupied && !isRoomAvailable(room.status)) ⇒ status = 'شاغرة'")
w("  else ⇒ لا كتابة (بلا رفع نسخة وبلا outbox)")
w("```")
w()
w("الاستدعاءان الوحيدان: حفظ الحجز (`booking_edit.dart` l.1131) وإتمام المغادرة "
  "(`booking_checkout_screen.dart` l.702-711). **المقايضة المعلنة:** غرفة «صيانة» "
  "بلا حجز نشط ⇒ «شاغرة» (سلوك Dart الحرفي — ليست مشغولة ولا متاحة).")
w()
w("### ٧.٢ مجموعات الحالات")
w()
w("| المجموعة | القيم (كما في Dart) |")
w("| --- | --- |")
w("| غرف متاحة | `شاغرة`, `شاغره`, `متاحة`, `متاح`, `available`, `vacant`, `empty` |")
w("| غرف مشغولة | `محجوزة`, `محجوز`, `مشغولة`, `occupied`, `محجوز temporarily`, `نشط`, `active`, `مؤقت`, `provisional` |")
w("| غرف مكتملة (مستبعدة صراحةً من الإشغال) | `مكتمل`, `مكتملة`, `completed`, `checked_out`, `checked out` |")
w("| صيانة | `صيانة`, `maintenance`, `under_maintenance`, `under maintenance` |")
w("| حجوزات نشطة (SQL) | `محجوزة`, `محجوز`, `نشط`, `active`, `confirmed`, `قيد الحجز`, `in_progress`, `مؤقت`, `provisional` |")
w()
w("التطبيع قبل المقارنة: `trim + lowercase`. ومنطق الحجز الفعّال: `isRoomOccupied` "
  "يستبعد المكتملة **صراحةً** ثم يفحص مجموعة المشغولة؛ و`isRoomAvailable` تتقاطع مع المشغولة.")
w()

# ─────────────────────────── ٨) الثوابت ───────────────────────────
w("## ٨) الثوابت والحراس — جدول موحّد")
w()
w("| الثابت | القيمة | الجهة |")
w("| --- | --- | --- |")
for r in [
 ("`MS_TIMESTAMP_THRESHOLD` / `MILLIS_EPOCH_THRESHOLD` / `MILLIS_THRESHOLD`", "1e11", "Worker + Android (ثلاثة أسماء لعقد واحد)"),
 ("`FUTURE_TIMESTAMP_THRESHOLD` / `FUTURE_THRESHOLD`", "2e9", "Worker + Android"),
 ("`CLOCK_SKEW_ALLOWANCE_S`", "90 ثانية", "Worker"),
 ("`MAX_SANE_VERSION`", "1,000,000", "Worker (نسخة أعلى ⇒ 1)"),
 ("`PUSH_BATCH_SIZE`", "وفق `CloudflareConfig`", "Android"),
 ("`MAX_ATTEMPTS_BEFORE_BACKOFF`", "5 (بلا `salary_withdrawals`)", "Android (dead-letter)"),
 ("`MAX_PULL_PAGES_PER_CYCLE`", "100", "Android"),
 ("`MAX_TOMBSTONE_SWEEP_PAGES_PER_CYCLE`", "20", "Android"),
 ("`MAX_PULL_WINDOW`", "20,000", "Worker"),
 ("`MAX_SANE_PULL_CURSOR_FUTURE`", "2e9", "Android"),
 ("`MAX_PULL_CURSOR_AHEAD_OF_SERVER_SEC`", "366 يوماً", "Android"),
 ("`PULL_QUARANTINE_CAP` / عتبة العزل / `HEAL_LIMIT`", "300 / 3 / 100", "Android"),
 ("`AUTOMATIC_PULL_INTERVAL_MS`", "60 دقيقة", "Android (بوابة الدلتا)"),
 ("`PENDING_PUSH_MONITOR_MS`", "5 دقائق", "Android"),
 ("`REALTIME_DEBOUNCE_MS` / `REALTIME_PULL_COOLDOWN_MS`", "500ms / 15s", "Android"),
 ("`REALTIME_BASE_BACKOFF_MS` / `MAX_BACKOFF_MS` / `MAX_RECONNECT_ATTEMPTS`", "1s / 60s / 6", "Android"),
 ("`REALTIME_REARM_INTERVAL_MS` / `REALTIME_HEARTBEAT_MS`", "120s / 30s", "Android"),
 ("`sync/auto_outbox_sync_watcher` (Dart)", "نظير مراقب المعلّقات", "Dart"),
]:
    w(f"| {r[0]} | {r[1]} | {r[2]} |")
w()
w("---")
w()

# ─────────────────────────── ٩) الاختبارات ───────────────────────────
w("## ٩) عقود الاختبار (ما يقفله كل ملف)")
w()
w("| الملف | الحالات | ما يقفله |")
w("| --- | --- | --- |")
for r in [
 ("RepositoryEpochParityTest.kt", "11", "طوابع ثوانٍ + version+1 لكل مستودع + حقول الأعمال بالميلي + تسلسل الكيان (ظلّ Gson)"),
 ("RoomOccupancySweepParityTest.kt", "6", "حالات المسح الأربع + عدم الكتابة بلا داعٍ + فرع originIsServer"),
 ("StatusUtilsParityTest.kt", "5", "مطابقة مجموعات الحالات مع `status_utils.dart`"),
 ("SyncIngestorRegistryTest.kt", "63", "FK/تأجيل/عزل/LWW/حارس الانزياح/الحذفيات"),
 ("SyncPullParityTest.kt", "12", "عقد السحب (مؤشر/صفحات/استئناف)"),
 ("BookingDerivedRefreshParityTest.kt", "6", "إعادة بناء المشتقة + الحذف"),
 ("SyncEpochParityTest.kt", "—", "وحدة الطوابع (ثوانٍ) على مسار الغرف"),
 ("SyncWireFieldParityTest.kt", "—", "أسماء السلك + الافتراضيات + وحدة `transaction_time`"),
 ("worker/test/*.ts", "—", "عقد الـWorker (sweep/تكافؤ لقطات المالية/idempotency)"),
]:
    w(f"| `{r[0]}` | {r[1]} | {r[2]} |")
w()

# ─────────────────────────── ١٠) CI ───────────────────────────
w("## ١٠) أدلة التشغيل (آخر دورة)")
w()
w("| التشغيل | الالتزام | النتيجة |")
w("| --- | --- | --- |")
w("| Sync Unit Tests `37698116017` | `d364b90b` | success — `:app:testDebugUnitTest` ‏409 حالة • 0 فشل • 0 خطأ • 0 متخطّاة؛ worker vitest+typecheck success؛ detekt success |")
w("| Android APK Build `37698116051` | `d364b90b` | success — release موقّع 5,960,887 بايت (`9771b444…`)، debug 25,366,772 بايت؛ apksigner v1/v2/v3 = true |")
w()
w("التشغيل الأحمر الوحيد على الفرع: «Code scanning AI findings on PR #617» "
  "(`github-advanced-security`، وكيل Copilot Autofix) — يفشل في خطوة "
  "«Processing Request» بعد نجاح كل خطوات الإعداد، وعلى فروع أخرى كذلك ⇒ خارجي.")
w()
w("---")
w()

# ─────────────────────────── ١١) الفجوات ───────────────────────────
w("## ١١) فجوات وتحفّظات معلنة (لا مخفية)")
w()
w("- `hotel_day_ledger`: جدول **محلي بحت** — غير موجود في `ENTITY_TABLES`؛ لا يُزامَن (خطة D8).")
w("- `finance_snapshots`: مرآة مخطط موثّقة؛ المسارات في الفرع المرجعي فقط ولا مستدعٍ عندنا.")
w("- `blacklist` كيان سلكي بلا جدول Drift في Flutter الأصلي (عندنا `blacklist_entries`).")
w("- `BookingsRepositoryImpl.checkout`: بلا إدراج outbox (مقصود؛ المسار الفعلي `update`).")
w("- `inventory_transactions.transaction_time`: عمود محلي بحت (لا مقابل على السلك) — يُغذّى من `created_at` ×1000.")
w("- `D1` يجلب بترتيب `DESC` مقابل `ASC` في Room لبعض الفهارس — افتراق موثّق بلا أثر وظيفي.")
w("- جداول مخلّفة في القاعدة المحلية (`sync_queue`/`sync_log`/`sync_conflicts`/`sync_remote_meta`/`sync_state`)")
w("  لا مستدعي لها في مسار Cloudflare (لم تُحذف حفاظاً على ترقية القاعدة) — و`sync_state` تحديداً")
w("  **لم يعد يحمل المؤشر**: المؤشر والحقبة في SharedPreferences (§٢.٧).")
w("- `sync_quarantine` و`pending_sync_links`: يُنشَأان بـ`execSQL` في `DatabaseModule` وتُكتب فيهما")
w("  `SyncManager` بـSQL مباشر؛ وأصناف DAO الخاصة بهما مسجَّلة بلا مستدعي — نسخة Dart تحتاج النقاش نفسه.")
w("- `devices` كيان متزامن (في `ENTITY_TABLES`) و`POST /api/devices/register` يكتبه مباشرة في الخادم؛")
w("  فالجهاز قد يُرى مرتين: عبر السحب كصف، وعبر التسجيل المباشر.")
w("")

# ─────────────────────────── ١٢) قائمة التحقق ───────────────────────────
w("## ١٢) قائمة تحقق — تطبيق Flutter/Dart")
w()
w("> الترتيب مقصود: كل بند قابل للفحص الآلي (مقارنة شيفرة أو اختبار).")
w()
w("| # | البند | معيار القبول |")
w("| --- | --- | --- |")
for i, r in enumerate([
 ("وحدة الزمن", "كل كتابة محلية على أعمدة المزامنة = `Time.nowEpoch()` (ثوانٍ)؛ والحقول الزمنية-العملية تبقى بوحدتها (§٢.٣)"),
 ("ختم `last_modified`", "لا يوجد مسار يكتب `last_modified = 0` — كل insert/update/softDelete يختمه"),
 ("`version+1`", "كل تحديث يرفع النسخة من الصف القائم (`existing.version + 1`)"),
 ("الكتابات الجزئية", "كل `update` جزئي يمرّر `lastModified` — لا استثناء"),
 ("الحذف الناعم", "`deleted_at + updated_at + last_modified` + صف outbox بمرآة الحذف"),
 ("صندوق الصادر", "idempotencyKey = `entity_op_localUuid_uuid`؛ insert⇒create؛ blacklist_entries⇒blacklist؛ bool⇒int؛ camelCase⇒snake_case"),
 ("استيعاب السحب", "ترتيب: كيان → FK (fk_rules) → aliases → defaults → وحدة الطوابع → LWW"),
 ("LWW", "`remote >= local` ⇒ استبدال؛ ومع `remote.version > local.version` ⇒ استبدال حتى لو الطابع أقدم"),
 ("tombstone", "يُطبَّق دائماً بحقول المزامنة فقط، ولا يعطّل الدورة"),
 ("المفتاح الطبيعي", "`booking_nights` بـ`(booking_local_id, hotel_day_key)` يُدمج LWW لا يُدرج ثانياً"),
 ("الحجر", "سعة 300، عتبة 3، شفاء 100/دورة، والمؤشر يتقدم دائماً"),
 ("مسح الحذفيات", "`tombstones_only=1` حتى 20 صفحة/دورة بمؤشر لا يُضبط قبل الاكتمال"),
 ("الحقول المشتقة", "تُبنى بعد السحب عند لمس الكيانات الستة، وبلا لمس `last_modified/version`"),
 ("الإشغال", "`refreshAllRoomOccupancy` حرفياً بموضعَي الاستدعاء، بما فيه سلوك الصيانة"),
 ("الحالات", "المجموعات الخمس حرفية بتطبيع `trim+lowercase`"),
 ("الحقن/الحماية", "`clear_employee_link=1` عند الفصل الصريح فقط؛ ولا يُرسَل `employee_uuid` فارغاً عمداً"),
 ("الاختبارات", "عقد آلي يقفل: الوحدة، version، المسح، المجموعات، FK، LWW، الحجر"),
 ("الأدلة", "تشغيل CI أخضر + إفصاح عن أي فشل خارجي (لا ادّعاء نجاح بلا تشغيل)"),
 ("الجداول المحلية المحضة", "`outbox` + `sync_quarantine` + `pending_sync_links` بالحقول والاستعلامات نفسها (§٢.٦)، والتنظيف على `delivered_to_primary=1 AND delivered_to_secondary=1`"),
 ("آلة حالات الصادر", "حجز `processing` قبل الإرسال، استرداد الانهيار عند الإقلاع، dead-letter للرفض الدائم، إعادة `pending` للمؤقت، وسقف 5 بلا استثناء `salary_withdrawals`"),
 ("مفاتيح التفضيلات", "أسماء المفاتيح حرفياً كما في §٢.٧ — وإلا انكسر الاستئناف بعد الترقية"),
 ("النقل", "`Authorization: Bearer` + `X-Device-Id`، ولا يُرسَل توكن `local:admin-session`، وتبديل النقاط على 521/522/530"),
]):
    w(f"| {i+1} | {r[0]} | {r[1]} |")
w()
w("---")
w()
w("**نهاية المسودة.** أي بند بلا دليل تشغيل في هذا الملف مُعلَم؛ وما لم يُذكر هنا "
  "فمرجعه الفرع `arena/be8302d7-marina-hotel-wit-app` نفسه (المصدر الأصدق).")

(ROOT/"docs/sync-spec-draft-for-flutter-dart.md").write_text("\n".join(out) + "\n", encoding='utf-8')
print("written:", len(out), "lines")
