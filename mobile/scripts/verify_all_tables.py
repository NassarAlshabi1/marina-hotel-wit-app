#!/usr/bin/env python3
"""
Comprehensive verification of all Appwrite Cloud tables and attributes
for marina-hotel-wit-app sync.

Database: hotel_db (690ff0da0025518570c1)
Endpoint: https://fra.cloud.appwrite.io/v1
"""

import json
import urllib.request
import urllib.error

# Configuration
APPWRITE_ENDPOINT = "https://fra.cloud.appwrite.io/v1"
APPWRITE_PROJECT_ID = "690ff0da0025518570c1"
APPWRITE_API_KEY = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da"
DATABASE_ID = "hotel_db"

def make_request(endpoint, method="GET", data=None):
    url = f"{APPWRITE_ENDPOINT}/{endpoint}"
    headers = {
        "Content-Type": "application/json",
        "X-Appwrite-Project": APPWRITE_PROJECT_ID,
        "X-Appwrite-Key": APPWRITE_API_KEY
    }
    req = urllib.request.Request(url, method=method, headers=headers)
    if data:
        req.data = json.dumps(data).encode('utf-8')
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}", "message": e.read().decode('utf-8')[:200]}
    except Exception as e:
        return {"error": str(e)}

def get_all_collections():
    result = make_request(f"databases/{DATABASE_ID}/collections")
    return result.get('collections', []) if 'collections' in result else []

def get_collection_schema(collection_id):
    result = make_request(f"databases/{DATABASE_ID}/collections/{collection_id}")
    if 'attributes' in result:
        return result['attributes']
    return None

def get_collection_indexes(collection_id):
    result = make_request(f"databases/{DATABASE_ID}/collections/{collection_id}/indexes")
    return result.get('indexes', []) if 'indexes' in result else []

def main():
    print("""
╔══════════════════════════════════════════════════════════════╗
║     📊 Appwrite Cloud - Complete Schema Verification          ║
║                                                              ║
║  Database: hotel_db                                          ║
║  Project:  690ff0da0025518570c1                              ║
╚══════════════════════════════════════════════════════════════╝
    """)
    
    collections = get_all_collections()
    print(f"📋 Found {len(collections)} collections\n")
    
    all_data = {}
    for col in sorted(collections, key=lambda x: x['$id']):
        col_id = col['$id']
        col_name = col.get('name', col_id)
        print(f"📦 {col_id}")
        
        attrs = get_collection_schema(col_id)
        if attrs:
            print(f"   └─ {len(attrs)} attributes")
            all_data[col_id] = {
                'name': col_name,
                'attributes': [a['key'] for a in attrs],
                'indexes': []
            }
        else:
            print(f"   └─ ❌ Failed to fetch")
            all_data[col_id] = {'name': col_name, 'attributes': [], 'indexes': [], 'error': True}
    
    # Print detailed summary
    print("\n" + "="*70)
    print("📊 DETAILED SCHEMA REPORT")
    print("="*70)
    
    for col_id in sorted(all_data.keys()):
        data = all_data[col_id]
        print(f"\n🔷 {col_id} ({data['name']})")
        if 'error' in data:
            print("   ❌ Error fetching schema")
            continue
        
        print(f"   Attributes ({len(data['attributes'])}):")
        for attr in sorted(data['attributes']):
            # Mark sync-critical fields
            critical = any(x in attr.lower() for x in ['uuid', 'id', 'modified', 'created', 'void', 'sync'])
            marker = "⭐" if critical else "  "
            print(f"      {marker} {attr}")
    
    # Check sync-critical fields
    print("\n" + "="*70)
    print("⭐ SYNC-CRITICAL FIELDS CHECK")
    print("="*70)
    
    critical_fields = {
        'payments': ['localUuid', 'lastModified', 'isVoided', 'voidedAt', 'voidedBy', 'bookingLocalId'],
        'bookings': ['localUuid', 'lastModified', 'roomNumber'],
        'rooms': ['localUuid', 'lastModified', 'roomNumber'],
        'employees': ['localUuid', 'lastModified'],
        'expenses': ['localUuid', 'lastModified'],
        'debts': ['localUuid', 'lastModified'],
    }
    
    for col_id, required in critical_fields.items():
        if col_id in all_data and 'attributes' in all_data[col_id]:
            existing = set(all_data[col_id]['attributes'])
            missing = [f for f in required if f not in existing]
            if missing:
                print(f"\n❌ {col_id}: Missing {missing}")
            else:
                print(f"\n✅ {col_id}: All critical fields present")
        else:
            print(f"\n⚠️ {col_id}: Cannot verify (schema fetch failed)")
    
    print("\n" + "="*70)
    print("🎉 Verification Complete")
    print("="*70)

if __name__ == "__main__":
    main()
