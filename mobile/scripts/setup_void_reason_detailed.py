#!/usr/bin/env python3
"""
Script to add voidReason field to payments collection in Appwrite Cloud
using Appwrite CLI for better compatibility.

Database: hotel_db (690ff0da0025518570c1)
Endpoint: https://fra.cloud.appwrite.io/v1

NOTE: If API fails, use Appwrite Console to manually add the attribute.
"""

import json
import sys
import urllib.request
import urllib.error
import time

# Configuration
APPWRITE_ENDPOINT = "https://fra.cloud.appwrite.io/v1"
APPWRITE_PROJECT_ID = "690ff0da0025518570c1"
APPWRITE_API_KEY = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da"
DATABASE_ID = "hotel_db"
PAYMENTS_COLLECTION_ID = "payments"

def make_request(endpoint, method="GET", data=None):
    """Make API request to Appwrite"""
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
        error_body = e.read().decode('utf-8') if e.fp else ""
        try:
            error_json = json.loads(error_body)
            print(f"   ❌ HTTP {e.code}: {error_json.get('message', 'Unknown error')}")
        except:
            print(f"   ❌ HTTP {e.code}: {error_body[:100]}")
        return None
    except Exception as e:
        print(f"   ❌ Request failed: {e}")
        return None

def print_success(msg):
    print(f"   ✅ {msg}")

def print_error(msg):
    print(f"   ❌ {msg}")

def print_info(msg):
    print(f"   ℹ️  {msg}")

def print_wait(msg):
    print(f"   ⏳ {msg}")

def create_attribute_with_retry(name, attribute_type, size=255, required=False, max_retries=3):
    """Create attribute with exponential backoff retry"""
    for attempt in range(max_retries):
        print_wait(f"Attempt {attempt + 1}/{max_retries}...")
        
        data = {
            "key": name,
            "type": attribute_type,
            "required": required,
        }
        
        if attribute_type == "string":
            data["size"] = size
        
        result = make_request(
            f"databases/{DATABASE_ID}/collections/{PAYMENTS_COLLECTION_ID}/attributes",
            method="POST",
            data=data
        )
        
        if result:
            return True
        
        if attempt < max_retries - 1:
            wait_time = (2 ** attempt) * 2
            print_wait(f"Retrying in {wait_time} seconds...")
            time.sleep(wait_time)
    
    return False

def main():
    print("""
╔══════════════════════════════════════════════════════════════╗
║  Appwrite Cloud Schema Setup - voidReason for payments       ║
║                                                              ║
║  Database: hotel_db                                          ║
║  Endpoint: https://fra.cloud.appwrite.io/v1                   ║
╚══════════════════════════════════════════════════════════════╝
    """)
    
    # Get current schema
    print_wait("Fetching payments collection schema...")
    result = make_request(f"databases/{DATABASE_ID}/collections/{PAYMENTS_COLLECTION_ID}")
    
    if not result:
        print_error("Failed to fetch payments collection")
        sys.exit(1)
    
    attributes = result.get('attributes', [])
    existing_attrs = {attr['key'] for attr in attributes}
    
    print(f"\n📊 Current attributes in payments collection ({len(attributes)}):")
    for attr in sorted(attributes, key=lambda x: x['key']):
        status = "✅" if attr['key'] in ['isVoided', 'voidedAt', 'voidedBy', 'voidReason', 'localUuid', 'lastModified'] else "  "
        print(f"   {status} {attr['key']} ({attr['type']})")
    
    # Check voidReason
    if 'voidReason' in existing_attrs:
        print_success("\nvoidReason attribute already exists!")
        print_info("No changes needed.")
    else:
        print_info("\n⚠️  voidReason attribute NOT found in payments collection")
        print_info("\nTo add it, you have two options:")
        print("\n   📋 Option 1: Appwrite Console (Recommended)")
        print("   ─────────────────────────────────────────")
        print("   1. Go to: https://cloud.appwrite.io")
        print("   2. Navigate to: Databases > hotel_db > payments")
        print("   3. Click 'Add attribute'")
        print("   4. Set:")
        print("      - Key: voidReason")
        print("      - Type: string")
        print("      - Size: 255")
        print("      - Required: No")
        print("   5. Save")
        
        print("\n   📋 Option 2: Appwrite CLI")
        print("   ─────────────────────────")
        print("   appwrite databases create-attribute \\")
        print("     --databaseId hotel_db \\")
        print("     --collectionId payments \\")
        print("     --key voidReason \\")
        print("     --type string \\")
        print("     --required false \\")
        print("     --size 255")
        
        print("\n   🔧 Option 3: Try API again")
        print("   ─────────────────────────")
        
        if create_attribute_with_retry("voidReason", "string", size=255, required=False):
            print_success("\nvoidReason attribute created successfully!")
        else:
            print_error("\nFailed to create voidReason via API")
            print_info("Please use Appwrite Console to add it manually")
    
    # Verify final state
    print("\n" + "="*60)
    print("📋 FINAL VERIFICATION")
    print("="*60)
    
    result = make_request(f"databases/{DATABASE_ID}/collections/{PAYMENTS_COLLECTION_ID}")
    if result:
        attributes = result.get('attributes', [])
        existing_attrs = {attr['key'] for attr in attributes}
        
        key_fields = ['isVoided', 'voidedAt', 'voidedBy', 'voidReason', 'localUuid', 'lastModified']
        for field in key_fields:
            status = "✅" if field in existing_attrs else "❌"
            print(f"   {status} {field}")
    
    print("\n" + "="*60)
    print_info("Database: hotel_db")
    print_info("Collection: payments")
    print_info("Endpoint: https://fra.cloud.appwrite.io/v1")
    print("="*60)

if __name__ == "__main__":
    main()