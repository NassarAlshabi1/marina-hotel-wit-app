#!/bin/bash

# =============================================================================
# سكربت إضافة الحقول الجديدة إلى Appwrite Cloud
# - employees: terminationDate, terminationReason (حقول إنهاء الخدمة)
# - salary_withdrawals: withdrawDate, reason, hotelDayKey, withdrawalType,
#                       description, employeeUuid
#
# الاستخدام: ./add_new_fields.sh <API_KEY>
# =============================================================================

set -e

ENDPOINT="https://fra.cloud.appwrite.io/v1"
PROJECT_ID="690ff0da0025518570c1"
DATABASE_ID="hotel_db"

echo "🚀 إضافة الحقول الجديدة إلى Appwrite Cloud"
echo "═══════════════════════════════════════════════════"

# التحقق من وجود API Key
if [ -z "$1" ]; then
    echo "❌ خطأ: API Key مطلوب"
    echo ""
    echo "الاستخدام:"
    echo "  ./add_new_fields.sh <API_KEY>"
    echo ""
    echo "للحصول على API Key:"
    echo "1. افتح https://cloud.appwrite.io/console"
    echo "2. اختر المشروع → Overview → API Keys"
    echo "3. أنشئ API Key جديد مع صلاحيات: databases.*"
    exit 1
fi

API_KEY="$1"

# دالة مساعدة لإضافة حقل نصي
add_string_attribute() {
    local collection_id="$1"
    local key="$2"
    local size="$3"
    local required="$4"
    local default="$5"

    echo "   📝 إضافة حقل نصي: $key → $collection_id"

    local payload="{\"key\":\"$key\",\"size\":$size,\"required\":$required"
    if [ -n "$default" ]; then
        payload="$payload,\"default\":\"$default\""
    fi
    payload="$payload}"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "${ENDPOINT}/databases/${DATABASE_ID}/collections/${collection_id}/attributes/string" \
        -H "Content-Type: application/json" \
        -H "X-Appwrite-Project: ${PROJECT_ID}" \
        -H "X-Appwrite-Key: ${API_KEY}" \
        -d "$payload")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
        echo "   ✅ تم إضافة $key بنجاح"
    elif [ "$HTTP_CODE" = "409" ]; then
        echo "   ℹ️  الحقل $key موجود مسبقاً"
    else
        echo "   ❌ خطأ HTTP $HTTP_CODE: $BODY"
    fi

    # انتظار لتجنب تجاوز Rate Limit
    sleep 2
}

# دالة مساعدة لإضافة حقل رقمي (integer)
add_integer_attribute() {
    local collection_id="$1"
    local key="$2"
    local required="$3"
    local default="$4"

    echo "   🔢 إضافة حقل رقمي: $key → $collection_id"

    local payload="{\"key\":\"$key\",\"required\":$required"
    if [ -n "$default" ]; then
        payload="$payload,\"default\":$default"
    fi
    payload="$payload}"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "${ENDPOINT}/databases/${DATABASE_ID}/collections/${collection_id}/attributes/integer" \
        -H "Content-Type: application/json" \
        -H "X-Appwrite-Project: ${PROJECT_ID}" \
        -H "X-Appwrite-Key: ${API_KEY}" \
        -d "$payload")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
        echo "   ✅ تم إضافة $key بنجاح"
    elif [ "$HTTP_CODE" = "409" ]; then
        echo "   ℹ️  الحقل $key موجود مسبقاً"
    else
        echo "   ❌ خطأ HTTP $HTTP_CODE: $BODY"
    fi

    sleep 2
}

echo ""
echo "📊 المعلومات:"
echo "Endpoint: $ENDPOINT"
echo "Project ID: $PROJECT_ID"
echo "Database ID: $DATABASE_ID"
echo ""

# =============================================================================
# 1️⃣  إضافة حقول إنهاء الخدمة إلى collection: employees
# =============================================================================
echo "1️⃣  إضافة حقول إنهاء الخدمة إلى employees..."
echo "─────────────────────────────────────────────"

# terminationDate - تاريخ إنهاء الخدمة
add_string_attribute "employees" "terminationDate" 50 false ""

# terminationReason - سبب إنهاء الخدمة
add_string_attribute "employees" "terminationReason" 200 false ""

echo ""

# =============================================================================
# 2️⃣  إضافة حقول السحوبات إلى collection: salary_withdrawals
# =============================================================================
echo "2️⃣  إضافة حقول السحوبات الجديدة إلى salary_withdrawals..."
echo "─────────────────────────────────────────────"

# withdrawDate - تاريخ السحب
add_string_attribute "salary_withdrawals" "withdrawDate" 50 false ""

# reason - سبب السحب
add_string_attribute "salary_withdrawals" "reason" 500 false ""

# hotelDayKey - يوم الفندق
add_string_attribute "salary_withdrawals" "hotelDayKey" 50 false ""

# withdrawalType - نوع السحب
add_string_attribute "salary_withdrawals" "withdrawalType" 50 false ""

# description - وصف السحب
add_string_attribute "salary_withdrawals" "description" 500 false ""

# employeeUuid - معرف الموظف UUID لحل FK عبر الأجهزة
add_string_attribute "salary_withdrawals" "employeeUuid" 100 false ""

echo ""

# =============================================================================
# ✅ اكتمل
# =============================================================================
echo "═══════════════════════════════════════════════════"
echo "✅ اكتمل إضافة الحقول الجديدة!"
echo ""
echo "ملاحظات مهمة:"
echo "• الحقول قد تحتاج 30-60 ثانية لتكون جاهزة (Indexing)"
echo "• لا تُجرِ مزامنة حتى تكتمل عملية الـ Indexing"
echo "• تحقق من Appwrite Console: https://cloud.appwrite.io/console"
echo "• راجع Attributes في كل Collection للتأكد"
echo ""
echo "تم إضافة الحقول التالية:"
echo "  employees: terminationDate, terminationReason"
echo "  salary_withdrawals: withdrawDate, reason, hotelDayKey,"
echo "                      withdrawalType, description, employeeUuid"
echo "═══════════════════════════════════════════════════"
