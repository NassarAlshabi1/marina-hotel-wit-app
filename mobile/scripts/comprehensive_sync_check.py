#!/usr/bin/env python3
"""Comprehensive Sync Verification - PUSH & PULL fields analysis"""

import json
import re
import urllib.request

APPWRITE_ENDPOINT = "https://fra.cloud.appwrite.io/v1"
PROJECT_ID = "690ff0da0025518570c1"
API_KEY = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da"
DB_ID = "hotel_db"

def api(path):
    req = urllib.request.Request(f'{APPWRITE_ENDPOINT}/{path}',
        headers={'X-Appwrite-Project': PROJECT_ID, 'X-Appwrite-Key': API_KEY})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except:
        return None

def get_aw_schema(cid):
    result = api(f'databases/{DB_ID}/collections/{cid}')
    return {a['key']: a['type'] for a in result.get('attributes', [])} if result else {}

def extract_fields(content, func_name):
    """Extract data['field'] from a function"""
    pattern = rf'Future<void>\s+_{func_name}.*?\n(.*?)\n  \}}'
    m = re.search(pattern, content, re.DOTALL)
    if m:
        return re.findall(r"data\['(\w+)'\]", m.group(1))
    return []

def parse_table(name):
    """Parse a table's fields from local_db.dart"""
    try:
        with open('/workspace/project/marina-hotel-wit-app/mobile/lib/services/local_db.dart', 'r') as f:
            content = f.read()
        # Find table
        pattern = r'class\s+' + name + r'\s+extends\s+Table.*?List<Index>\s+get\s+indexes.*?\};'
        m = re.search(pattern, content, re.DOTALL)
        if m:
            return re.findall(r'(?:IntColumn|TextColumn|RealColumn|BoolColumn)\s+get\s+(\w+)', m.group(0))
    except:
        pass
    return []

# MAIN
print("="*80)
print("🔬 COMPREHENSIVE SYNC VERIFICATION")
print("="*80)

# Fetch Appwrite
cols = api(f'databases/{DB_ID}/collections')
if not cols:
    print("❌ Failed to fetch collections")
    exit()

aw_schemas = {}
for c in cols['collections']:
    aw_schemas[c['$id']] = get_aw_schema(c['$id'])
print(f"✅ Fetched {len(aw_schemas)} collections from Appwrite")

# Read sync files
with open('/workspace/project/marina-hotel-wit-app/mobile/lib/services/appwrite_sync_manager.dart', 'r') as f:
    sync_mgr = f.read()
with open('/workspace/project/marina-hotel-wit-app/mobile/lib/services/appwrite_delta_sync.dart', 'r') as f:
    delta_sync = f.read()

# Extract PUSH fields
push_payments = re.findall(r"data\['(\w+)'\]", re.search(r'Map<String, dynamic>\s+_paymentToRemote.*?\n(.*?)\n  \}', sync_mgr, re.DOTALL).group(1) if re.search(r'Map<String, dynamic>\s+_paymentToRemote', sync_mgr) else [])
push_debts = re.findall(r"data\['(\w+)'\]", re.search(r'Map<String, dynamic>\s+_debtToRemote.*?\n(.*?)\n  \}', sync_mgr, re.DOTALL).group(1) if re.search(r'Map<String, dynamic>\s+_debtToRemote', sync_mgr) else [])

# Extract PULL fields
pull_payments = extract_fields(delta_sync, 'applyPaymentChange')
pull_debts = extract_fields(delta_sync, 'applyDebtChange')

print("\n" + "="*80)
print("💳 PAYMENTS - PUSH & PULL Analysis")
print("="*80)

local_payments = set(parse_table('Payments'))
aw_payments = set(aw_schemas.get('payments', {}).keys())

print(f"\n📁 Local payments: {len(local_payments)} fields")
print(f"☁️  Appwrite payments: {len(aw_payments)} fields")

print("\n📤 PUSH (Local → Appwrite):")
push_set = set(push_payments)
print(f"   Fields used: {len(push_set)}")
missing_push = push_set - aw_payments
if missing_push:
    for f in sorted(missing_push):
        print(f"   ❌ {f} - NOT in Appwrite!")
else:
    print("   ✅ All PUSH fields exist in Appwrite!")

print("\n📥 PULL (Appwrite → Local):")
pull_set = set(pull_payments)
print(f"   Fields used: {len(pull_set)}")
missing_pull = pull_set - local_payments
if missing_pull:
    for f in sorted(missing_pull):
        print(f"   ❌ {f} - NOT in local DB!")
else:
    print("   ✅ All PULL fields exist in local DB!")

print("\n" + "="*80)
print("📊 DEBTS - PUSH & PULL Analysis")
print("="*80)

local_debts = set(parse_table('Debts'))
aw_debts = set(aw_schemas.get('debts', {}).keys())

print(f"\n📁 Local debts: {len(local_debts)} fields")
print(f"☁️  Appwrite debts: {len(aw_debts)} fields")

print("\n📤 PUSH (Local → Appwrite):")
push_debt_set = set(push_debts)
print(f"   Fields used: {len(push_debt_set)}")
missing_push_d = push_debt_set - aw_debts
if missing_push_d:
    for f in sorted(missing_push_d):
        print(f"   ❌ {f} - NOT in Appwrite!")
else:
    print("   ✅ All PUSH fields exist in Appwrite!")

print("\n📥 PULL (Appwrite → Local):")
pull_debt_set = set(pull_debts)
print(f"   Fields used: {len(pull_debt_set)}")
missing_pull_d = pull_debt_set - local_debts
if missing_pull_d:
    for f in sorted(missing_pull_d):
        print(f"   ❌ {f} - NOT in local DB!")
else:
    print("   ✅ All PULL fields exist in local DB!")

# Summary
print("\n" + "="*80)
print("📋 SUMMARY TABLE")
print("="*80)
print(f"""
┌─────────────┬──────────┬──────────┬─────────┬─────────┐
│ Collection  │ Local    │ Appwrite │ PUSH    │ PULL    │
├─────────────┼──────────┼──────────┼─────────┼─────────┤
│ Payments    │ {len(local_payments):3}      │ {len(aw_payments):3}      │ {len(push_set):3}      │ {len(pull_set):3}      │
│ Debts       │ {len(local_debts):3}      │ {len(aw_debts):3}      │ {len(push_debt_set):3}      │ {len(pull_debt_set):3}      │
└─────────────┴──────────┴──────────┴─────────┴─────────┘

PUSH missing in Appwrite: {len(missing_push)} 
PULL missing in local DB: {len(missing_pull)}
""")

if missing_push or missing_pull or missing_push_d or missing_pull_d:
    print("\n⚠️  ISSUES FOUND - Sync may fail for these fields!")
else:
    print("\n✅ ALL SYNC FIELDS COMPATIBLE!")
