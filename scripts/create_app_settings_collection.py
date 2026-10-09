"""
سكربت إنشاء مجموعة app_settings في Appwrite Console
لمزامنة إعدادات الواتساب بين الأجهزة
"""

import json
import requests
import sys

# ─── إعدادات Appwrite ───
ENDPOINT = "https://fra.cloud.appwrite.io/v1"
PROJECT_ID = "690ff0da0025518570c1"
DATABASE_ID = "hotel_db"
COLLECTION_ID = "app_settings"
DOCUMENT_ID = "whatsapp_settings"

# الـ API Key - يمكن الحصول عليه من لوحة تحكم Appwrite
# إذا لم يعمل بدون مفتاح، أنشئ واحد من:
# https://fra.cloud.appwrite.io/project/690ff0da0025518570c1/api-keys
API_KEY = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da"

HEADERS = {
    "Content-Type": "application/json",
    "X-Appwrite-Project": PROJECT_ID,
}

if API_KEY:
    HEADERS["X-Appwrite-Key"] = API_KEY


def create_collection():
    """إنشاء مجموعة app_settings"""
    url = f"{ENDPOINT}/databases/{DATABASE_ID}/collections"
    payload = {
        "collectionId": COLLECTION_ID,
        "name": "App Settings",
        "description": "إعدادات التطبيق - واتساب وغيرها (مزامنة بين الأجهزة)",
        "enabled": True,
    }

    print(f"📦 إنشاء مجموعة: {COLLECTION_ID} ...")
    resp = requests.post(url, headers=HEADERS, json=payload)

    if resp.status_code == 200 or resp.status_code == 201:
        print(f"   ✅ تم إنشاء المجموعة بنجاح")
        return True
    elif resp.status_code == 409:
        print(f"   ⚠️ المجموعة موجودة مسبقاً — سيتم إنشاء الحقول فقط")
        return True
    else:
        print(f"   ❌ فشل إنشاء المجموعة: {resp.status_code}")
        print(f"   {resp.text}")
        return False


def create_attribute(attr_type, key, size=None, required=False, default_value=None):
    """إنشاء حقل في المجموعة"""
    url = f"{ENDPOINT}/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/attributes/{attr_type}"
    payload = {
        "key": key,
        "required": required,
        "size": size,
    }
    if default_value is not None:
        payload["default"] = default_value

    resp = requests.post(url, headers=HEADERS, json=payload)

    if resp.status_code == 200 or resp.status_code == 201:
        print(f"   ✅ {key} ({attr_type})")
        return True
    elif resp.status_code == 409:
        print(f"   ⏭️ {key} موجود مسبقاً")
        return True
    else:
        print(f"   ❌ {key}: {resp.status_code} — {resp.text[:100]}")
        return False


def create_document_if_empty():
    """إنشاء مستند فارغ أولي"""
    url = f"{ENDPOINT}/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/documents"
    payload = {
        "documentId": DOCUMENT_ID,
        "data": {
            "wa_api_type": "greenapi",
            "wa_api_base_url": "",
            "wa_api_instance_id": "",
            "wa_api_token": "",
            "wa_custom_url_template": "",
            "wa_sendzen_api_key": "",
            "wa_sendzen_from_number": "",
            "wa_template": "",
        },
    }

    resp = requests.post(url, headers=HEADERS, json=payload)
    if resp.status_code == 200 or resp.status_code == 201:
        print(f"   ✅ تم إنشاء المستند الأولي")
        return True
    elif resp.status_code == 409:
        print(f"   ⏭️ المستند موجود مسبقاً")
        return True
    else:
        print(f"   ⚠️ المستند: {resp.status_code} — {resp.text[:150]}")
        # ليس خطأ حرج، يمكن إنشاؤه من التطبيق
        return True


def main():
    print("=" * 55)
    print("  إنشاء مجموعة app_settings في Appwrite")
    print("=" * 55)
    print(f"  Endpoint: {ENDPOINT}")
    print(f"  Database: {DATABASE_ID}")
    print(f"  Collection: {COLLECTION_ID}")
    print("=" * 55)

    # 1. إنشاء المجموعة
    if not create_collection():
        print("\n❌ توقف: لم يتم إنشاء المجموعة")
        sys.exit(1)

    print(f"\n📝 إنشاء الحقول...")

    # 2. إنشاء الحقول (string attributes)
    fields = [
        ("wa_api_type", 50, False, "greenapi"),
        ("wa_api_base_url", 500, False, ""),
        ("wa_api_instance_id", 200, False, ""),
        ("wa_api_token", 500, False, ""),
        ("wa_custom_url_template", 1000, False, ""),
        ("wa_sendzen_api_key", 500, False, ""),
        ("wa_sendzen_from_number", 30, False, ""),
        ("wa_template", 5000, False, ""),
    ]

    success_count = 0
    for key, size, required, default in fields:
        if create_attribute("string", key, size=size, required=required, default_value=default):
            success_count += 1

    print(f"\n📊 تم إنشاء {success_count}/{len(fields)} حقل")

    # 3. إنشاء المستند الأولي
    print(f"\n📄 إنشاء المستند الأولي...")
    create_document_if_empty()

    print(f"\n{'=' * 55}")
    print(f"  ✅ تم الإعداد بنجاح!")
    print(f"{'=' * 55}")
    print(f"\n  يمكنك الآن:")
    print(f"  1. فتح Appwrite Console لرؤية المجموعة")
    print(f"  2. استخدام 'رفع إلى السحابة' من التطبيق")
    print(f"\n  رابط المجموعة:")
    print(f"  https://fra.cloud.appwrite.io/project/{PROJECT_ID}/database/{DATABASE_ID}/collection/{COLLECTION_ID}")


if __name__ == "__main__":
    main()
