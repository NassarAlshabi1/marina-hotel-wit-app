#!/usr/bin/env python3
"""
Appwrite تنفيذ حذف التكرارات الفارغة (بنسخة احتياطية + تحقق لحظة الحذف)
======================================================================
يحذف فقط النسخ المكررة (UUID بدون شرطات) التي أثبت التحقق أنها فارغة تمامًا.

آلية الأمان:
  1) يحسب المرشحين من جديد (لا يعتمد على ملف قديم).
  2) لكل مرشح: نسخة احتياطية كاملة للمستند إلى ملف JSON.
  3) إعادة تحقق لحظة الحذف: totalPaidCached==0 و totalDueCached==0
     و صفر مدفوعات/ليالٍ/ملاحظات مرتبطة. أي فشل → تخطّي (لا حذف).
  4) الحذف يتم فقط مع --apply. بدونه: عرض فقط (dry-run).

الاستخدام:
    export APPWRITE_ENDPOINT / APPWRITE_PROJECT_ID / APPWRITE_DATABASE_ID / APPWRITE_API_KEY
    python3 scripts/appwrite_dedup_apply.py            # dry-run (لا حذف)
    python3 scripts/appwrite_dedup_apply.py --apply    # تنفيذ الحذف الفعلي
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

EP = os.environ.get("APPWRITE_ENDPOINT", "https://fra.cloud.appwrite.io/v1")
PID = os.environ.get("APPWRITE_PROJECT_ID")
DB = os.environ.get("APPWRITE_DATABASE_ID")
KEY = os.environ.get("APPWRITE_API_KEY")
if not all([PID, DB, KEY]):
    sys.exit("❌ متغيرات البيئة ناقصة (PROJECT_ID / DATABASE_ID / API_KEY)")

APPLY = "--apply" in sys.argv
BACKUP_PATH = os.environ.get("DEDUP_BACKUP", "/tmp/logs/dedup_deleted_backup.json")
H = {"X-Appwrite-Project": PID, "X-Appwrite-Key": KEY, "Content-Type": "application/json"}


def q(**kw):
    return json.dumps(kw, ensure_ascii=False)


def _req(method, url):
    req = urllib.request.Request(url, headers=H, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode()
            return json.loads(body) if body else {}, r.status
    except urllib.error.HTTPError as e:
        return {"error": e.read().decode()}, e.code


def list_all(col, page=100):
    out, cursor = [], None
    while True:
        qs = [q(method="limit", values=[page]), q(method="orderAsc", values=["$id"])]
        if cursor:
            qs.append(q(method="cursorAfter", values=[cursor]))
        url = (f"{EP}/databases/{DB}/collections/{col}/documents?"
               + urllib.parse.urlencode([("queries[]", x) for x in qs]))
        d, _ = _req("GET", url)
        if "error" in d:
            break
        docs = d.get("documents", [])
        out.extend(docs)
        if len(docs) < page:
            break
        cursor = docs[-1]["$id"]
    return out


def count_linked(col, attr, value):
    url = (f"{EP}/databases/{DB}/collections/{col}/documents?"
           + urllib.parse.urlencode([("queries[]", q(method="equal", attribute=attr, values=[value])),
                                     ("queries[]", q(method="limit", values=[1]))]))
    d, _ = _req("GET", url)
    return d.get("total", -1)


def get_doc(col, doc_id):
    d, st = _req("GET", f"{EP}/databases/{DB}/collections/{col}/documents/{doc_id}")
    return (d if st == 200 else None), st


def delete_doc(col, doc_id):
    return _req("DELETE", f"{EP}/databases/{DB}/collections/{col}/documents/{doc_id}")


def norm(u):
    return (u or "").replace("-", "").lower()


def is_hy(u):
    return "-" in (u or "")


def is_safe_empty(doc):
    """تحقق صارم أن المستند فارغ تمامًا وبلا ارتباطات."""
    paid = float(doc.get("totalPaidCached") or 0)
    due = float(doc.get("totalDueCached") or 0)
    if not (paid == 0 and due == 0):
        return False, f"غير فارغ (paid={paid}, due={due})"
    did = doc["$id"]
    pn = count_linked("payments", "bookingUuidCache", did)
    nn = count_linked("booking_nights", "bookingUuidCache", did)
    mn = count_linked("booking_notes", "bookingUuidCache", did)
    # ✅ معالجة -1 كخطأ (شبكة/API) بدلاً من "لا توجد ارتباطات".
    # المنطق القديم: `pn not in (0, -1)` → عند الفشل (=-1) يعود False
    # للشرط، أي يُعتبر "آمن" للحذف → قد يُفقد البيانات.
    if pn == -1 or nn == -1 or mn == -1:
        return False, f"خطأ في فحص الارتباطات (payments={pn}, nights={nn}, notes={mn})"
    if pn > 0 or nn > 0 or mn > 0:
        return False, f"مرتبط (payments={pn}, nights={nn}, notes={mn})"
    return True, "آمن"


def main():
    print(f"🔗 {EP} | db={DB}")
    print("🚦 وضع:", "⚠️ APPLY (سيحذف فعلاً)" if APPLY else "معاينة فقط (dry-run)")
    print()

    bookings = list_all("bookings")
    groups = {}
    for b in bookings:
        groups.setdefault(norm(b.get("localUuid")), []).append(b)

    candidates = []
    for k, v in groups.items():
        if len(v) != 2:
            continue
        hy = [b for b in v if is_hy(b.get("localUuid"))]
        non = [b for b in v if not is_hy(b.get("localUuid"))]
        if len(hy) == 1 and len(non) == 1:
            candidates.append(non[0])  # المرشح للحذف = النسخة بدون شرطات

    print(f"عدد المرشحين المبدئيين (بدون شرطات): {len(candidates)}")

    backup, deleted, skipped = [], [], []
    for cand in candidates:
        did = cand["$id"]
        fresh, st = get_doc("bookings", did)
        if fresh is None:
            skipped.append((did, f"تعذّر الجلب (HTTP {st})"))
            continue
        safe, reason = is_safe_empty(fresh)
        if not safe:
            skipped.append((did, reason))
            continue
        backup.append(fresh)  # نسخة احتياطية كاملة قبل الحذف
        if APPLY:
            _, dst = delete_doc("bookings", did)
            if dst in (200, 204):
                deleted.append(did)
            else:
                skipped.append((did, f"فشل الحذف (HTTP {dst})"))
        else:
            deleted.append(did)  # سيُحذف عند --apply

    os.makedirs(os.path.dirname(BACKUP_PATH), exist_ok=True)
    with open(BACKUP_PATH, "w", encoding="utf-8") as f:
        json.dump({"collection": "bookings", "documents": backup}, f,
                  ensure_ascii=False, indent=2)

    print(f"\n💾 نسخة احتياطية لـ {len(backup)} مستند → {BACKUP_PATH}")
    print(f"{'🗑️ حُذف' if APPLY else '✅ سيُحذف عند --apply'}: {len(deleted)}")
    print(f"⏭️ متخطّى (فشل التحقق): {len(skipped)}")
    for did, why in skipped:
        print(f"    - {did}: {why}")
    if not APPLY:
        print("\nℹ️ هذه معاينة فقط. للتنفيذ الفعلي: أضف --apply")


if __name__ == "__main__":
    main()
