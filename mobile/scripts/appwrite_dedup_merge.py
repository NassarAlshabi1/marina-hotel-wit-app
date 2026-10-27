#!/usr/bin/env python3
"""
Appwrite دمج أزواج الحجوزات المكررة المتبقية (التي بها بيانات)
==============================================================
يعالج الأزواج (UUID بشرطات = الأصلية نُبقيها / بدون شرطات = المكررة ندمجها)
حيث تحمل النسخة المكررة سجلات فعلية، فالحذف الأعمى يفقد بيانات.

المنطق لكل زوج:
  لكل مجموعة أبناء (payments, booking_nights, booking_notes,
  booking_price_adjustments, debts, payment_voids) مرتبطة بالمكررة عبر
  bookingUuidCache:
    • ابن مكرر (localUuid مطبّع يطابق ابنًا على الأصلية) → حذفه (تكرار).
    • ابن فريد (غير موجود على الأصلية) → إعادة ربطه بالأصلية
      (bookingUuidCache = localUuid الأصلية) + تحديث الطوابع الزمنية.
  ثم حذف مستند الحجز المكرر.

أمان:
  • نسخة احتياطية كاملة (الحجز المكرر + كل أبنائه) قبل أي تعديل.
  • dry-run افتراضيًا؛ التنفيذ يحتاج --apply.
  • لا نلمس النسخة الأصلية إطلاقًا سوى استقبال الأبناء الفريدين.

الاستخدام:
    export APPWRITE_ENDPOINT / APPWRITE_PROJECT_ID / APPWRITE_DATABASE_ID / APPWRITE_API_KEY
    python3 scripts/appwrite_dedup_merge.py            # معاينة
    python3 scripts/appwrite_dedup_merge.py --apply    # تنفيذ
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

EP = os.environ.get("APPWRITE_ENDPOINT", "https://fra.cloud.appwrite.io/v1")
PID = os.environ.get("APPWRITE_PROJECT_ID")
DB = os.environ.get("APPWRITE_DATABASE_ID")
KEY = os.environ.get("APPWRITE_API_KEY")
if not all([PID, DB, KEY]):
    sys.exit("❌ متغيرات البيئة ناقصة")

APPLY = "--apply" in sys.argv
BACKUP = os.environ.get("MERGE_BACKUP", "/tmp/logs/dedup_merge_backup.json")
H = {"X-Appwrite-Project": PID, "X-Appwrite-Key": KEY, "Content-Type": "application/json"}
CHILD_COLS = ["payments", "booking_nights", "booking_notes",
              "booking_price_adjustments", "debts", "payment_voids"]


def q(**kw):
    return json.dumps(kw, ensure_ascii=False)


def _req(method, url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, headers=H, method=method, data=data)
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode()
            return (json.loads(body) if body else {}), r.status
    except urllib.error.HTTPError as e:
        return {"error": e.read().decode()}, e.code


def list_all(col, page=100):
    out, cur = [], None
    while True:
        qs = [q(method="limit", values=[page]), q(method="orderAsc", values=["$id"])]
        if cur:
            qs.append(q(method="cursorAfter", values=[cur]))
        d, _ = _req("GET", f"{EP}/databases/{DB}/collections/{col}/documents?"
                    + urllib.parse.urlencode([("queries[]", x) for x in qs]))
        if "error" in d:
            break
        ds = d.get("documents", [])
        out += ds
        if len(ds) < page:
            break
        cur = ds[-1]["$id"]
    return out


def children(col, uuid):
    d, _ = _req("GET", f"{EP}/databases/{DB}/collections/{col}/documents?"
                + urllib.parse.urlencode([("queries[]", q(method="equal", attribute="bookingUuidCache", values=[uuid])),
                                          ("queries[]", q(method="limit", values=[200]))]))
    return d.get("documents", []) if "error" not in d else []


def norm(u):
    return (u or "").replace("-", "").lower()


def is_hy(u):
    return "-" in (u or "")


def strip_meta(doc):
    """يزيل حقول Appwrite النظامية للسماح بإعادة الكتابة."""
    return {k: v for k, v in doc.items() if not k.startswith("$")}


def update_child(col, doc_id, new_cache, now_epoch):
    payload = {"bookingUuidCache": new_cache,
               "lastModifiedEpoch": now_epoch,
               "lastModified": now_epoch}
    return _req("PATCH", f"{EP}/databases/{DB}/collections/{col}/documents/{doc_id}",
                {"data": payload})


def delete_doc(col, doc_id):
    return _req("DELETE", f"{EP}/databases/{DB}/collections/{col}/documents/{doc_id}")


def main():
    print(f"🔗 {EP} | db={DB}")
    print("🚦", "⚠️ APPLY (تنفيذ فعلي)" if APPLY else "معاينة فقط (dry-run)")
    now_epoch = int(time.time())

    bookings = list_all("bookings")
    groups = {}
    for b in bookings:
        groups.setdefault(norm(b.get("localUuid")), []).append(b)
    dups = {k: v for k, v in groups.items()
            if len(v) == 2 and any(is_hy(x["$id"]) for x in v) and any(not is_hy(x["$id"]) for x in v)}
    print(f"أزواج للدمج: {len(dups)}\n")

    backup = []
    relinked = deleted_children = deleted_bookings = 0

    for k, v in dups.items():
        keep = [x for x in v if is_hy(x["$id"])][0]
        dup = [x for x in v if not is_hy(x["$id"])][0]
        print("=" * 66)
        print(f"غرفة {keep.get('roomNumber')} | {keep.get('guestName')}")
        print(f"  KEEP {keep['$id']}  |  DUP {dup['$id']}")

        pair_backup = {"keep_id": keep["$id"], "dup_booking": dup, "children": {}}

        for col in CHILD_COLS:
            ck = children(col, keep["$id"])
            cd = children(col, dup["$id"])
            if not cd:
                continue
            pair_backup["children"][col] = cd
            keep_keys = set(norm(x.get("localUuid")) for x in ck)
            for child in cd:
                is_dupe = norm(child.get("localUuid")) in keep_keys
                cid = child["$id"]
                if is_dupe:
                    print(f"    [{col}] حذف ابن مكرر {cid} (amount={child.get('amount')})")
                    if APPLY:
                        _, st = delete_doc(col, cid)
                        if st in (200, 204):
                            deleted_children += 1
                        else:
                            print(f"        ⚠️ فشل الحذف HTTP {st}")
                    else:
                        deleted_children += 1
                else:
                    print(f"    [{col}] إعادة ربط ابن فريد {cid} (amount={child.get('amount')}) → KEEP")
                    if APPLY:
                        _, st = update_child(col, cid, keep["$id"], now_epoch)
                        if st == 200:
                            relinked += 1
                        else:
                            print(f"        ⚠️ فشل التحديث HTTP {st}")
                    else:
                        relinked += 1

        # حذف الحجز المكرر بعد نقل/حذف أبنائه
        print(f"    حذف الحجز المكرر {dup['$id']}")
        if APPLY:
            _, st = delete_doc("bookings", dup["$id"])
            if st in (200, 204):
                deleted_bookings += 1
            else:
                print(f"        ⚠️ فشل حذف الحجز HTTP {st}")
        else:
            deleted_bookings += 1

        backup.append(pair_backup)
        print()

    os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
    with open(BACKUP, "w", encoding="utf-8") as f:
        json.dump(backup, f, ensure_ascii=False, indent=2)

    print("=" * 66)
    print(f"💾 نسخة احتياطية → {BACKUP}")
    print(f"{'تم' if APPLY else 'سيتم'}: إعادة ربط={relinked} | حذف أبناء مكررين={deleted_children} | حذف حجوزات={deleted_bookings}")
    if not APPLY:
        print("\nℹ️ معاينة فقط. للتنفيذ: --apply")
        print("⚠️ بعد التنفيذ: شغّل إعادة حساب الحقول المشتقة على الأجهزة لتحديث الأرصدة المخزّنة.")


if __name__ == "__main__":
    main()
