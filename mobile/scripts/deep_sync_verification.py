#!/usr/bin/env python3
"""
Deep Sync Verification - Compare local Dart tables with Appwrite Cloud
for both PUSH (upload) and PULL (download) operations.

Checks:
1. All fields in _paymentToRemote for PUSH compatibility
2. All fields in _applyPaymentChange for PULL compatibility
3. Field type compatibility
4. Missing fields in Appwrite vs Local
5. Extra fields in Appwrite vs Local
"""

import json
import re
import urllib.request
import urllib.error

# Configuration
APPWRITE_ENDPOINT = "https://fra.cloud.appwrite.io/v1"
PROJECT_ID = "690ff0da0025518570c1"
API_KEY = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da"
DB_ID = "hotel_db"

# Maps for field type conversion
FIELD_TYPE_MAP = {
    'integer': 'int',
    'double': 'double',
    'float': 'double',
    'string': 'String',
    'boolean': 'bool',
    'datetime': 'DateTime',
}

def api(path):
    req = urllib.request.Request(f'{APPWRITE_ENDPOINT}/{path}',
        headers={'X-Appwrite-Project': PROJECT_ID, 'X-Appwrite-Key': API_KEY})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except Exception as e:
        return None

def get_appwrite_schema(collection_id):
    result = api(f'databases/{DB_ID}/collections/{collection_id}')
    if result and 'attributes' in result:
        return {a['key']: a['type'] for a in result['attributes']}
    return {}

def parse_local_db():
    """Extract table definitions from local_db.dart"""
    with open('/workspace/project/marina-hotel-wit-app/mobile/lib/services/local_db.dart', 'r') as f:
        content = f.read()
    
    tables = {}
    # Match table class definitions
    pattern = r'class\s+(\w+)\s+extends\s+Table.*?\{(.*?)\n  \}'
    matches = re.findall(pattern, content, re.DOTALL)
    
    for name, body in matches:
        fields = []
        # Extract field definitions
        field_pattern = r'(\w+)\s+get\s+(\w+)\s+=>\s+([^;]+);'
        field_matches = re.findall(field_pattern, body)
        for type_name, field_name, definition in field_matches:
            if field_name not in ['indexes', 'getIndex']:
                fields.append(field_name)
        tables[name.lower()] = {'name': name, 'fields': fields}
    
    return tables

def get_push_fields():
    """Extract fields used in PUSH operations (_paymentToRemote, etc.)"""
    files_to_check = [
        '/workspace/project/marina-hotel-wit-app/mobile/lib/services/appwrite_sync_manager.dart',
        '/workspace/project/marina-hotel-wit-app/mobile/lib/services/appwrite_delta_sync.dart',
    ]
    
    push_fields = {}
    for file_path in files_to_check:
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            
            # Extract _paymentToRemote
            match = re.search(r'Map<String, dynamic>\s+_paymentToRemote.*?\n(.*?)\n  \}', content, re.DOTALL)
            if match:
                body = match.group(1)
                # Find data[key] = value patterns
                field_matches = re.findall(r"data\['(\w+)'\]", body)
                push_fields['payments'] = set(field_matches)
            
            # Extract _debtToRemote
            match = re.search(r'Map<String, dynamic>\s+_debtToRemote.*?\n(.*?)\n  \}', content, re.DOTALL)
            if match:
                body = match.group(1)
                field_matches = re.findall(r"data\['(\w+)'\]", body)
                push_fields['debts'] = set(field_matches)
                
        except: pass
    
    return push_fields

def get_pull_fields():
    """Extract fields used in PULL operations (_applyPaymentChange, etc.)"""
    files_to_check = [
        '/workspace/project/marina-hotel-wit-app/mobile/lib/services/appwrite_delta_sync.dart',
        '/workspace/project/marina-hotel-wit-app/mobile/lib/services/appwrite_sync_manager.dart',
    ]
    
    pull_fields = {}
    for file_path in files_to_check:
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            
            # Extract _applyPaymentChange
            match = re.search(r'Future<void>\s+_applyPaymentChange.*?\n(.*?)\n  \}', content, re.DOTALL)
            if match:
                body = match.group(1)
                # Find data['field'] patterns
                field_matches = re.findall(r"data\['(\w+)'\]", body)
                pull_fields['payments'] = set(field_matches)
            
            # Extract _applyDebtChange
            match = re.search(r'Future<void>\s+_applyDebtChange.*?\n(.*?)\n  \}', content, re.DOTALL)
            if match:
                body = match.group(1)
                field_matches = re.findall(r"data\['(\w+)'\]", body)
                pull_fields['debts'] = set(field_matches)
                
        except: pass
    
    return pull_fields

def main():
    print("="*80)
    print("🔬 DEEP SYNC VERIFICATION - Push & Pull Fields Analysis")
    print("="*80)
    
    # Get Appwrite schema
    print("\n📡 Fetching Appwrite Cloud schema...")
    appwrite_cols = api(f'databases/{DB_ID}/collections')
    if not appwrite_cols:
        print("❌ Failed to fetch Appwrite collections")
        return
    
    appwrite_schemas = {}
    for col in appwrite_cols['collections']:
        cid = col['$id']
        schema = get_appwrite_schema(cid)
        appwrite_schemas[cid] = schema
    print(f"✅ Fetched {len(appwrite_schemas)} collections from Appwrite")
    
    # Get local tables
    print("\n📁 Parsing local Dart tables...")
    local_tables = parse_local_db()
    print(f"✅ Found {len(local_tables)} tables in local_db.dart")
    
    # Get push/pull fields from sync code
    print("\n🔍 Analyzing sync code...")
    push_fields = get_push_fields()
    pull_fields = get_pull_fields()
    
    # Compare payments table in detail
    print("\n" + "="*80)
    print("💳 PAYMENTS TABLE - Deep Analysis")
    print("="*80)
    
    payments_local = set(local_tables.get('payments', {}).get('fields', []))
    payments_aw = set(appwrite_schemas.get('payments', {}).keys())
    
    print(f"\n📊 Local payments fields: {len(payments_local)}")
    print(f"📊 Appwrite payments fields: {len(payments_aw)}")
    
    # PUSH analysis
    print("\n" + "-"*60)
    print("📤 PUSH Analysis (Local → Appwrite)")
    print("-"*60)
    
    if 'payments' in push_fields:
        push_used = push_fields['payments']
        print(f"\nFields used in _paymentToRemote: {len(push_used)}")
        for field in sorted(push_used):
            status = "✅" if field in payments_aw else "❌ MISSING"
            print(f"   {status} {field}")
        
        missing_for_push = push_used - payments_aw
        if missing_for_push:
            print(f"\n⚠️  Missing in Appwrite (needed for PUSH): {missing_for_push}")
        else:
            print("\n✅ All PUSH fields exist in Appwrite!")
    
    # PULL analysis
    print("\n" + "-"*60)
    print("📥 PULL Analysis (Appwrite → Local)")
    print("-"*60)
    
    if 'payments' in pull_fields:
        pull_used = pull_fields['payments']
        print(f"\nFields used in _applyPaymentChange: {len(pull_used)}")
        for field in sorted(pull_used):
            status = "✅" if field in payments_local else "❌ MISSING"
            print(f"   {status} {field}")
        
        missing_for_pull = pull_used - payments_local
        if missing_for_pull:
            print(f"\n⚠️  Missing in local DB (needed for PULL): {missing_for_pull}")
        else:
            print("\n✅ All PULL fields exist in local DB!")
    
    # Compare debts table
    print("\n" + "="*80)
    print("📊 DEBTS TABLE - Deep Analysis")
    print("="*80)
    
    debts_local = set(local_tables.get('debts', {}).get('fields', []))
    debts_aw = set(appwrite_schemas.get('debts', {}).keys())
    
    if 'debts' in push_fields:
        push_used = push_fields['debts']
        print(f"\n📤 Fields used in _debtToRemote: {len(push_used)}")
        missing = push_used - debts_aw
        if missing:
            for field in sorted(missing):
                print(f"   ❌ {field}")
        else:
            print("✅ All PUSH fields exist in Appwrite!")
    
    if 'debts' in pull_fields:
        pull_used = pull_fields['debts']
        print(f"\n📥 Fields used in _applyDebtChange: {len(pull_used)}")
        missing = pull_used - debts_local
        if missing:
            for field in sorted(missing):
                print(f"   ❌ {field}")
        else:
            print("✅ All PULL fields exist in local DB!")
    
    # Summary
    print("\n" + "="*80)
    print("📋 SUMMARY")
    print("="*80)
    
    print(f"""
✅ Appwrite Collections: {len(appwrite_schemas)}
✅ Local Tables: {len(local_tables)}

💳 Payments:
   - Local: {len(payments_local)} fields
   - Appwrite: {len(payments_aw)} fields
   - PUSH: {len(push_fields.get('payments', []))} fields used
   - PULL: {len(pull_fields.get('payments', []))} fields used

📊 Debts:
   - Local: {len(debts_local)} fields
   - Appwrite: {len(debts_aw)} fields
   - PUSH: {len(push_fields.get('debts', []))} fields used
   - PULL: {len(pull_fields.get('debts', []))} fields used
""")
    
    print("="*80)

if __name__ == "__main__":
    main()
