#!/bin/bash

# Script لإضافة حقول التخفيض إلى Appwrite Cloud
# الاستخدام: ./add_discount_fields.sh <API_KEY>

set -e

ENDPOINT="https://fra.cloud.appwrite.io/v1"
PROJECT_ID="690ff0da0025518570c1"
DATABASE_ID="hotel_db"
COLLECTION_ID="bookings"

echo "🚀 إضافة حقول التخفيض إلى Appwrite Cloud"
echo "═══════════════════════════════════════════════"

# التحقق من وجود API Key
if [ -z "$1" ]; then
    echo "❌ خطأ: API Key مطلوب"
    echo ""
    echo "الاستخدام:"
    echo "  ./add_discount_fields.sh <API_KEY>"
    echo ""
    echo "للحصول على API Key:"
    echo "1. افتح https://cloud.appwrite.io/console"
    echo "2. اختر المشروع → Settings → API Keys"
    echo "3. أنشئ API Key جديد مع صلاحيات: databases.write"
    exit 1
fi

API_KEY="$1"

echo ""
echo "📊 المعلومات:"
echo "Endpoint: $ENDPOINT"
echo "Project ID: $PROJECT_ID"
echo "Database ID: $DATABASE_ID"
echo "Collection ID: $COLLECTION_ID"
echo ""

# 1. إضافة حقل discountType
echo "1️⃣ إضافة حقل discountType..."
RESPONSE1=$(curl -s -w "\n%{http_code}" -X POST \
    "${ENDPOINT}/databases/${DATABASE_ID}/collections/${COLLECTION_ID}/attributes/string" \
    -H "Content-Type: application/json" \
    -H "X-Appwrite-Project: ${PROJECT_ID}" \
    -H "X-Appwrite-Key: ${API_KEY}" \
    -d '{
        "key": "discountType",
        "size": 20,
        "required": false,
        "default": "per_night"
    }')

HTTP_CODE1=$(echo "$RESPONSE1" | tail -n1)
BODY1=$(echo "$RESPONSE1" | sed '$d')

if [ "$HTTP_CODE1" = "201" ] || [ "$HTTP_CODE1" = "202" ]; then
    echo "   ✅ تم إضافة discountType بنجاح"
elif [ "$HTTP_CODE1" = "409" ]; then
    echo "   ℹ️ الحقل discountType موجود مسبقاً"
else
    echo "   ❌ خطأ HTTP $HTTP_CODE1: $BODY1"
fi

# انتظار قليلاً
sleep 2

# 2. إضافة حقل discountStartDate
echo ""
echo "2️⃣ إضافة حقل discountStartDate..."
RESPONSE2=$(curl -s -w "\n%{http_code}" -X POST \
    "${ENDPOINT}/databases/${DATABASE_ID}/collections/${COLLECTION_ID}/attributes/string" \
    -H "Content-Type: application/json" \
    -H "X-Appwrite-Project: ${PROJECT_ID}" \
    -H "X-Appwrite-Key: ${API_KEY}" \
    -d '{
        "key": "discountStartDate",
        "size": 50,
        "required": false
    }')

HTTP_CODE2=$(echo "$RESPONSE2" | tail -n1)
BODY2=$(echo "$RESPONSE2" | sed '$d')

if [ "$HTTP_CODE2" = "201" ] || [ "$HTTP_CODE2" = "202" ]; then
    echo "   ✅ تم إضافة discountStartDate بنجاح"
elif [ "$HTTP_CODE2" = "409" ]; then
    echo "   ℹ️ الحقل discountStartDate موجود مسبقاً"
else
    echo "   ❌ خطأ HTTP $HTTP_CODE2: $BODY2"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ اكتمل التحديث!"
echo ""
echo "ملاحظات:"
echo "• الحقول قد تحتاج بضع ثوانٍ لتكون جاهزة (Indexing)"
echo "• تحقق من Appwrite Console للتأكد"
echo "• يمكنك الآن استخدام التطبيق بشكل طبيعي"
