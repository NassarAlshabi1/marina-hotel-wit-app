#!/bin/bash
# API Testing Script
# يقوم باختبار جميع endpoints تلقائياً

BASE_URL="http://localhost/marina-hotel-wit-app/api/v1"
TOKEN=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Marina Hotel API Testing Script"
echo "=================================="
echo ""

# Test Health Check
echo -n "Testing Health Check... "
response=$(curl -s "$BASE_URL/health.php")
if echo "$response" | grep -q '"status":"healthy"'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Login
echo -n "Testing Login... "
response=$(curl -s -X POST "$BASE_URL/auth/login.php" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}')

if echo "$response" | grep -q '"success":true'; then
    TOKEN=$(echo "$response" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    echo -e "${GREEN}✓ PASS${NC} (Token: ${TOKEN:0:20}...)"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
    exit 1
fi

# Test Ping
echo -n "Testing Ping (Auth)... "
response=$(curl -s "$BASE_URL/auth/ping.php" \
    -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"authenticated":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Pull Sync
echo -n "Testing Pull Sync... "
response=$(curl -s "$BASE_URL/sync/pull.php?since=0" \
    -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Rooms List
echo -n "Testing Rooms List... "
response=$(curl -s "$BASE_URL/entities/rooms.php" \
    -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Bookings List
echo -n "Testing Bookings List... "
response=$(curl -s "$BASE_URL/entities/bookings.php" \
    -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Employees List
echo -n "Testing Employees List... "
response=$(curl -s "$BASE_URL/entities/employees.php" \
    -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Payments List
echo -n "Testing Payments List... "
response=$(curl -s "$BASE_URL/entities/payments.php" \
    -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Expenses List
echo -n "Testing Expenses List... "
response=$(curl -s "$BASE_URL/entities/expenses.php" \
    -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$response"
fi

# Test Rate Limiting
echo -n "Testing Rate Limiting... "
for i in {1..5}; do
    curl -s "$BASE_URL/auth/ping.php" -H "Authorization: Bearer $TOKEN" > /dev/null
done
response=$(curl -s "$BASE_URL/auth/ping.php" -H "Authorization: Bearer $TOKEN")
if echo "$response" | grep -q '"success":true'; then
    echo -e "${YELLOW}⚠ WARNING${NC} (Rate limit not triggered - may need adjustment)"
else
    echo -e "${GREEN}✓ PASS${NC}"
fi

echo ""
echo "=================================="
echo "✅ All Tests Completed!"
echo "=================================="
