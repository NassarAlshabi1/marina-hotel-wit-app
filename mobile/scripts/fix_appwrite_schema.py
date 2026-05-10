#!/usr/bin/env python3
"""
سكربت إصلاح حقول المزامنة المفقودة في Appwrite Console
==========================================================
يُضيف الحقول المفقودة التي يحتاجها فحص التعارضات والمزامنة:
  - lastModified (integer) — الحقل الأساسي لفحص "الأحدث أولاً"
  - createdAt (integer)
  - updatedAt (integer)
  - deletedAt (integer)
  - version (integer)
  - origin (string)
  - deviceId (string)

الحقول تُضاف كـ required=False حتى لا تُكسر المستندات الموجودة.

الاستخدام:
  python3 fix_appwrite_schema.py
"""

import json
import sys
import time
import requests

# ─── الإعدادات ──────────────────────────────────────────────
ENDPOINT = "https://fra.cloud.appwrite.io/v1"
PROJECT_ID = "690ff0da0025518570c1"
DATABASE_ID = "hotel_db"
API_KEY = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da"

HEADERS = {
    "Content-Type": "application/json",
    "X-Appwrite-Project": PROJECT_ID,
    "X-Appwrite-Key": API_KEY,
}

# ─── الحقول المفقودة لكل مجموعة ────────────────────────────
# بناءً على الفحص الفعلي من Appwrite Console
MISSING_FIELDS = {
    # bookings: EVERYTHING missing except localUuid
    "bookings": [
        {"key": "lastModified", "type": "integer", "required": False, "default": 0},
        {"key": "createdAt", "type": "integer", "required": False, "default": 0},
        {"key": "updatedAt", "type": "integer", "required": False, "default": 0},
        {"key": "deletedAt", "type": "integer", "required": False},
        {"key": "version", "type": "integer", "required": False, "default": 1},
        {"key": "origin", "type": "string", "required": False, "size": 50, "default": "local"},
        {"key": "deviceId", "type": "string", "required": False, "size": 100},
    ],
    # rooms: only deviceId missing
    "rooms": [
        {"key": "deviceId", "type": "string", "required": False, "size": 100},
    ],
    # payments: deviceId + version missing
    "payments": [
        {"key": "deviceId", "type": "string", "required": False, "size": 100},
        {"key": "version", "type": "integer", "required": False, "default": 1},
    ],
    # debts: deviceId + version missing
    "debts": [
        {"key": "deviceId", "type": "string", "required": False, "size": 100},
        {"key": "version", "type": "integer", "required": False, "default": 1},
    ],
    # booking_price_adjustments: only deviceId missing
    "booking_price_adjustments": [
        {"key": "deviceId", "type": "string", "required": False, "size": 100},
    ],
    # guest_infos: only deviceId missing
    "guest_infos": [
        {"key": "deviceId", "type": "string", "required": False, "size": 100},
    ],
}


def create_integer_attribute(collection_id, field):
    """إنشاء حقل عدد صحيح"""
    url = f"{ENDPOINT}/databases/{DATABASE_ID}/collections/{collection_id}/attributes/integer"
    payload = {
        "key": field["key"],
        "required": field.get("required", False),
        "min": None,
        "max": None,
        "default": field.get("default"),
    }
    resp = requests.post(url, headers=HEADERS, json=payload, timeout=30)
    return resp


def create_string_attribute(collection_id, field):
    """إنشاء حقل نصي"""
    url = f"{ENDPOINT}/databases/{DATABASE_ID}/collections/{collection_id}/attributes/string"
    payload = {
        "key": field["key"],
        "required": field.get("required", False),
        "size": field.get("size", 100),
        "default": field.get("default"),
    }
    resp = requests.post(url, headers=HEADERS, json=payload, timeout=30)
    return resp


def wait_for_attribute_ready(collection_id, attribute_key, timeout=60):
    """انتظار حتى يصبح الحقل جاهزاً (status=available)"""
    url = f"{ENDPOINT}/databases/{DATABASE_ID}/collections/{collection_id}/attributes"
    start = time.time()
    while time.time() - start < timeout:
        try:
            resp = requests.get(url, headers=HEADERS, timeout=15)
            if resp.status_code == 200:
                attrs = resp.json().get("attributes", [])
                for attr in attrs:
                    if attr.get("key") == attribute_key:
                        status = attr.get("status", "")
                        if status == "available":
                            return True
                        elif status == "processing":
                            time.sleep(2)
                            continue
        except Exception:
            pass
        time.sleep(2)
    return False


def main():
    print("=" * 60)
    print("  سكربت إصلاح حقول المزامنة المفقودة - Appwrite")
    print("=" * 60)
    print()

    # التحقق من الاتصال
    print("📡 فحص الاتصال بـ Appwrite...")
    try:
        resp = requests.get(f"{ENDPOINT}/databases/{DATABASE_ID}", headers=HEADERS, timeout=10)
        if resp.status_code == 200:
            db_info = resp.json()
            print(f"  ✅ متصل: {db_info.get('name', DATABASE_ID)}")
        else:
            print(f"  ❌ فشل الاتصال: HTTP {resp.status_code}")
            print(f"     {resp.text}")
            sys.exit(1)
    except Exception as e:
        print(f"  ❌ خطأ في الاتصال: {e}")
        sys.exit(1)

    print()

    total_created = 0
    total_skipped = 0
    total_failed = 0

    for collection_id, fields in MISSING_FIELDS.items():
        print(f"📦 مجموعة: {collection_id}")
        print(f"   حقول مفقودة: {len(fields)}")

        for field in fields:
            field_key = field["key"]
            field_type = field["type"]

            if field_type == "integer":
                resp = create_integer_attribute(collection_id, field)
            elif field_type == "string":
                resp = create_string_attribute(collection_id, field)
            else:
                print(f"   ⚠️  نوع غير مدعوم: {field_type} → تخطي")
                total_skipped += 1
                continue

            if resp.status_code in (200, 201):
                print(f"   ✅ {field_key:20s} ({field_type}) → تم الطلب")
                total_created += 1
            elif resp.status_code == 409:
                # الحقل موجود مسبقاً
                print(f"   ⏭️  {field_key:20s} ({field_type}) → موجود مسبقاً")
                total_skipped += 1
            else:
                error_msg = ""
                try:
                    err_data = resp.json()
                    error_msg = err_data.get("message", resp.text[:100])
                except Exception:
                    error_msg = resp.text[:100]
                print(f"   ❌ {field_key:20s} ({field_type}) → {error_msg}")
                total_failed += 1

        print()

    # ─── انتظار تجهيز الحقول ──────────────────────────────
    if total_created > 0:
        print("⏳ انتظار تجهيز الحقول في Appwrite (قد يستغرق بضع ثوانٍ)...")
        all_fields = []
        for fields in MISSING_FIELDS.values():
            all_fields.extend([f["key"] for f in fields])
        unique_fields = list(dict.fromkeys(all_fields))

        ready_count = 0
        for collection_id in MISSING_FIELDS:
            for field_key in MISSING_FIELDS[collection_id]:
                key_str = f"{collection_id}.{field_key}"
                if wait_for_attribute_ready(collection_id, field_key["key"] if isinstance(field_key, dict) else field_key, timeout=30):
                    ready_count += 1
        print(f"   ✅ {ready_count}/{total_created} حقل أصبح جاهزاً")
        print()

    # ─── التحقق النهائي ────────────────────────────────────
    print("=" * 60)
    print("  التحقق النهائي")
    print("=" * 60)
    print()

    for collection_id, expected_fields in MISSING_FIELDS.items():
        try:
            resp = requests.get(
                f"{ENDPOINT}/databases/{DATABASE_ID}/collections/{collection_id}/attributes",
                headers=HEADERS,
                timeout=15,
            )
            if resp.status_code == 200:
                attrs = resp.json().get("attributes", [])
                existing_keys = {a["key"] for a in attrs}
                print(f"📦 {collection_id}:")
                for field in expected_fields:
                    key = field["key"]
                    if key in existing_keys:
                        attr = next((a for a in attrs if a["key"] == key), None)
                        status = attr.get("status", "?") if attr else "?"
                        print(f"   ✅ {key:20s} → {status}")
                    else:
                        print(f"   ❌ {key:20s} → غير موجود")
                print()
        except Exception as e:
            print(f"   ⚠️ فشل التحقق: {e}")
            print()

    # ─── الملخص ─────────────────────────────────────────────
    print("=" * 60)
    print(f"  الملخص:")
    print(f"    ✅ تم إنشاء: {total_created}")
    print(f"    ⏭️  موجود مسبقاً: {total_skipped}")
    print(f"    ❌ فشل: {total_failed}")
    print("=" * 60)

    if total_failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
