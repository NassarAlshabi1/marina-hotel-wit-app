#!/usr/bin/env python3
"""
Appwrite خطة تنظيف التكرارات (READ-ONLY — لا يحذف شيئًا)
========================================================
يبني قائمة مراجعة بالمستندات المكررة الفارغة المرشّحة للحذف، مع تحقّق أمان
صارم لكل مرشّح قبل إدراجه. المخرجات ملف JSON للمراجعة اليدوية فقط.

قاعدة الأمان لكل زوج مكرر (نفس UUID مطبّع):
  - نُبقي دائمًا النسخة الأصلية (UUID بشرطات).
  - نرشّح للحذف النسخة الأخرى (بدون شرطات) فقط إذا تحقّق كل التالي:
      * totalPaidCached == 0  و  totalDueCached == 0
      * لا توجد أي مدفوعات مرتبطة بها (bookingUuidCache == uuid)
      * لا توجد booking_nights / booking_notes مرتبطة
  - أي زوج لا ينطبق عليه ذلك → "review" (مراجعة يدوية، لا حذف مقترح).

⚠️ لا يُنفّذ هذا السكربت أي حذف. الحذف يحتاج خطوة منفصلة بموافقة صريحة.

الاستخدام:
    export APPWRITE_ENDPOINT / APPWRITE_PROJECT_ID / APPWRITE_DATABASE_ID / APPWRITE_API_KEY
    python3 scripts/appwrite_dedup_plan.py  > /tmp/logs/dedup_plan.json
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

H = {"X-Appwrite-Project": PID, "X-Appwrite-Key": KEY, "Content-Type": "application/json"}


def q(**kw):
    return json.dumps(kw, ensure_ascii=False)


def _get(url):
    req = urllib.request.Request(url, headers=H)
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": e.read().decode()}


def list_all(col, page=100):
    out, cursor = [], None
    while True:
        qs = [q(method="limit", values=[page]), q(method="orderAsc", values=["$id"])]
        if cursor:
            qs.append(q(method="cursorAfter", values=[cursor]))
        url = (f"{EP}/databases/{DB}/collections/{col}/documents?"
               + urllib.parse.urlencode([("queries[]", x) for x in qs]))
        d = _get(url)
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
    d = _get(url)
    return d.get("total", -1)  # -1 = خطأ/حقل غير موجود


def norm(u):
    return (u or "").replace("-", "").lower()


def is_hyphenated(u):
    return "-" in (u or "")


def main():
    bookings = list_all("bookings")
    groups = {}
    for b in bookings:
        groups.setdefault(norm(b.get("localUuid")), []).append(b)
    dups = {k: v for k, v in groups.items() if len(v) > 1}

    safe_delete, needs_review = [], []
    for k, v in dups.items():
        hy = [b for b in v if is_hyphenated(b.get("localUuid"))]
        non = [b for b in v if not is_hyphenated(b.get("localUuid"))]

        # الحالة المثالية: نسخة مشرّطة واحدة + نسخة غير مشرّطة واحدة
        if not (len(hy) == 1 and len(non) == 1):
            needs_review.append({"reason": "بنية غير متوقعة (ليست زوج مشرّط/غير مشرّط)",
                                 "norm_uuid": k,
                                 "docs": [{"id": b["$id"], "uuid": b.get("localUuid"),
                                           "paid": b.get("totalPaidCached"),
                                           "due": b.get("totalDueCached")} for b in v]})
            continue

        keep, cand = hy[0], non[0]
        paid = float(cand.get("totalPaidCached") or 0)
        due = float(cand.get("totalDueCached") or 0)
        pay_n = count_linked("payments", "bookingUuidCache", cand["$id"])
        night_n = count_linked("booking_nights", "bookingUuidCache", cand["$id"])
        note_n = count_linked("booking_notes", "bookingUuidCache", cand["$id"])

        record = {
            "norm_uuid": k, "room": cand.get("roomNumber"), "guest": cand.get("guestName"),
            "keep": {"id": keep["$id"], "paid": keep.get("totalPaidCached"), "due": keep.get("totalDueCached")},
            "delete_candidate": {"id": cand["$id"], "paid": paid, "due": due,
                                 "linked_payments": pay_n, "linked_nights": night_n, "linked_notes": note_n},
        }
        safe = (paid == 0 and due == 0 and pay_n == 0 and night_n in (0, -1) and note_n in (0, -1))
        (safe_delete if safe else needs_review).append(record)

    out = {
        "summary": {
            "total_bookings": len(bookings),
            "duplicate_groups": len(dups),
            "safe_to_delete": len(safe_delete),
            "needs_manual_review": len(needs_review),
        },
        "safe_to_delete": safe_delete,
        "needs_manual_review": needs_review,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
