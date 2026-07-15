#!/usr/bin/env python3
"""
Appwrite تشخيص التكرارات (READ-ONLY)
=====================================
يمسح مجموعات Appwrite ويكتشف المستندات المكررة الناتجة عن اختلاف
تطبيع الـ UUID (بشرطات / بدون شرطات) بالإضافة إلى تضارب bookingLocalId.

⚠️ هذا السكربت للقراءة فقط — لا يكتب ولا يحذف أي شيء.

الاستخدام:
    export APPWRITE_ENDPOINT="https://fra.cloud.appwrite.io/v1"
    export APPWRITE_PROJECT_ID="..."
    export APPWRITE_DATABASE_ID="..."
    export APPWRITE_API_KEY="..."        # لا تضع المفتاح داخل الملف
    python3 scripts/appwrite_dedup_diagnostic.py
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
    sys.exit(
        "❌ متغيرات مفقودة. لازم: APPWRITE_PROJECT_ID, APPWRITE_DATABASE_ID, APPWRITE_API_KEY"
    )

H = {
    "X-Appwrite-Project": PID,
    "X-Appwrite-Key": KEY,
    "Content-Type": "application/json",
}


def q(**kw):
    """يبني query بصيغة Appwrite 1.9 (JSON)."""
    return json.dumps(kw, ensure_ascii=False)


def _get(url):
    req = urllib.request.Request(url, headers=H)
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": e.read().decode()}


def list_all(collection, page=100):
    """يجلب كل المستندات عبر ترقيم offset (يتعامل مع >5000 عبر cursor)."""
    out = []
    cursor = None
    while True:
        qs = [q(method="limit", values=[page]),
              q(method="orderAsc", values=["$id"])]
        if cursor:
            qs.append(q(method="cursorAfter", values=[cursor]))
        url = (f"{EP}/databases/{DB}/collections/{collection}/documents?"
               + urllib.parse.urlencode([("queries[]", x) for x in qs]))
        d = _get(url)
        if "error" in d:
            print(f"  ⚠️ {collection}: {d['error'][:120]}")
            break
        docs = d.get("documents", [])
        out.extend(docs)
        if len(docs) < page:
            break
        cursor = docs[-1]["$id"]
    return out


def norm(u):
    """تطبيع UUID: إزالة الشرطات + حروف صغيرة."""
    return (u or "").replace("-", "").lower()


def is_empty_booking(b):
    paid = float(b.get("totalPaidCached") or 0)
    due = float(b.get("totalDueCached") or 0)
    return paid == 0 and due == 0


def scan_bookings():
    print("=" * 70)
    print("📋 فحص التكرارات في bookings (حسب UUID المطبّع)")
    print("=" * 70)
    docs = list_all("bookings")
    print(f"إجمالي الحجوزات: {len(docs)}")

    groups = {}
    for b in docs:
        groups.setdefault(norm(b.get("localUuid")), []).append(b)

    dups = {k: v for k, v in groups.items() if len(v) > 1}
    print(f"عدد مجموعات UUID المكررة: {len(dups)}  "
          f"(تشمل {sum(len(v) for v in dups.values())} مستند)")
    print()
    for k, v in sorted(dups.items(), key=lambda x: -len(x[1])):
        print(f"  ▸ UUID مطبّع: {k}  ({len(v)} نسخ)")
        for b in v:
            tag = "فارغ" if is_empty_booking(b) else "به بيانات"
            print(f"      - $id={b['$id']:36s} uuid={b.get('localUuid'):38s} "
                  f"room={b.get('roomNumber')} guest={b.get('guestName')} "
                  f"paid={b.get('totalPaidCached')} due={b.get('totalDueCached')} "
                  f"del={b.get('deletedAt')} [{tag}]")
        print()
    return docs, dups


def scan_payments():
    print("=" * 70)
    print("💳 فحص التكرارات في payments (حسب localUuid المطبّع)")
    print("=" * 70)
    docs = list_all("payments")
    print(f"إجمالي المدفوعات: {len(docs)}")

    # تكرار حسب localUuid
    groups = {}
    for p in docs:
        groups.setdefault(norm(p.get("localUuid")), []).append(p)
    dups = {k: v for k, v in groups.items() if len(v) > 1}
    print(f"مدفوعات مكررة (نفس localUuid): {len(dups)} مجموعة")
    for k, v in list(dups.items())[:20]:
        print(f"  ▸ {k}: {len(v)} نسخ | "
              f"amounts={[p.get('amount') for p in v]}")

    # تضارب bookingLocalId عبر أكثر من bookingUuidCache
    print()
    print("  تضارب bookingLocalId (نفس الرقم لأكثر من حجز/غرفة):")
    byid = {}
    for p in docs:
        lid = p.get("bookingLocalId")
        if lid is None:
            continue
        byid.setdefault(lid, {"uuids": set(), "rooms": set(), "n": 0})
        byid[lid]["uuids"].add(p.get("bookingUuidCache"))
        byid[lid]["rooms"].add(p.get("roomNumber"))
        byid[lid]["n"] += 1
    conflicts = {k: v for k, v in byid.items() if len(v["uuids"]) > 1}
    print(f"    عدد الأرقام المتضاربة: {len(conflicts)}")
    for lid, info in sorted(conflicts.items()):
        print(f"    - bookingLocalId={lid}: {info['n']} دفعة | "
              f"rooms={info['rooms']} | uuids={len(info['uuids'])}")
    return docs


def main():
    print(f"🔗 {EP} | project={PID} | db={DB}")
    print("⚠️  وضع القراءة فقط — لن يُكتب أو يُحذف أي شيء\n")
    scan_bookings()
    scan_payments()
    print("\n✅ انتهى التشخيص (لم تُجرَ أي كتابة).")


if __name__ == "__main__":
    main()
