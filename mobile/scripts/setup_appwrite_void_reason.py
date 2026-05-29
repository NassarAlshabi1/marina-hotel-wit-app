#!/usr/bin/env python3
"""
Script to add voidReason field to payments collection in Appwrite Cloud
and ensure all required fields are synced properly.

Database: hotel_db (690ff0da0025518570c1)
Endpoint: https://fra.cloud.appwrite.io/v1
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

# Collection IDs
PAYMENTS_COLLECTION_ID = "payments"
PAYMENT_VOIDS_COLLECTION_ID = "payment_voids"  # Correct name (plural)

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
            print(f"   ❌ HTTP Error {e.code}: {error_json.get('message', error_body[:200])}")
        except:
            print(f"   ❌ HTTP Error {e.code}: {error_body[:200]}")
        return None
    except Exception as e:
        print(f"   ❌ Request failed: {e}")
        return None

def print_step(step, emoji="📋"):
    """Print step header"""
    print(f"\n{'='*60}")
    print(f"{emoji} {step}")
    print(f"{'='*60}")

def print_success(msg):
    print(f"   ✅ {msg}")

def print_error(msg):
    print(f"   ❌ {msg}")

def print_info(msg):
    print(f"   ℹ️  {msg}")

def print_wait(msg):
    print(f"   ⏳ {msg}")

# ============================================================
# Step 1: List all collections in the database
# ============================================================
def list_collections():
    print_step("1. Listing all collections in database", "🔍")
    result = make_request(f"databases/{DATABASE_ID}/collections")
    
    if not result:
        print_error("Failed to list collections")
        return []
    
    collections = result.get('collections', [])
    print_info(f"Found {len(collections)} collections:")
    
    for col in collections:
        print(f"   - {col['$id']}: {col.get('name', 'N/A')}")
    
    return collections

# ============================================================
# Step 2: Get payments collection schema
# ============================================================
def get_payments_schema():
    print_step("2. Getting payments collection schema", "📄")
    result = make_request(f"databases/{DATABASE_ID}/collections/{PAYMENTS_COLLECTION_ID}")
    
    if not result:
        print_error("Failed to get payments collection")
        return None
    
    attributes = result.get('attributes', [])
    print_info(f"Payments collection has {len(attributes)} attributes:")
    
    for attr in attributes:
        required = "required" if attr.get('required') else "optional"
        print(f"   - {attr['key']} ({attr['type']}) {required}")
    
    return attributes

# ============================================================
# Step 3: Check if voidReason attribute exists
# ============================================================
def check_void_reason_attribute(attributes):
    print_step("3. Checking for voidReason attribute", "🔎")
    
    for attr in attributes:
        if attr['key'] == 'voidReason':
            print_success(f"voidReason attribute exists! (type: {attr['type']})")
            return True
    
    print_info("voidReason attribute NOT found")
    return False

# ============================================================
# Step 4: Create voidReason attribute with retry
# ============================================================
def create_void_reason_attribute():
    print_step("4. Creating voidReason attribute", "➕")
    
    # Create the attribute
    data = {
        "key": "voidReason",
        "type": "string",
        "required": False,
        "size": 255
    }
    
    print_wait("Creating attribute (may take a moment)...")
    
    result = make_request(
        f"databases/{DATABASE_ID}/collections/{PAYMENTS_COLLECTION_ID}/attributes",
        method="POST",
        data=data
    )
    
    if result:
        print_success("voidReason attribute created! Waiting for propagation...")
        # Wait for attribute to be created
        time.sleep(3)
        return True
    else:
        print_error("Failed to create voidReason attribute")
        print_info("The attribute may already exist or API key lacks permissions")
        return False

# ============================================================
# Step 5: Get payment_voids collection schema
# ============================================================
def get_payment_voids_schema():
    print_step("5. Getting payment_voids collection schema", "📄")
    result = make_request(f"databases/{DATABASE_ID}/collections/{PAYMENT_VOIDS_COLLECTION_ID}")
    
    if not result:
        print_error("Failed to get payment_voids collection")
        return None
    
    attributes = result.get('attributes', [])
    print_info(f"payment_voids collection has {len(attributes)} attributes:")
    
    for attr in attributes:
        print(f"   - {attr['key']} ({attr['type']})")
    
    return attributes

# ============================================================
# Step 6: Verify all required attributes for payments sync
# ============================================================
def verify_required_attributes(attributes):
    print_step("6. Verifying required attributes for payments sync", "✓")
    
    # Required attributes for payments collection
    required_payment_attrs = [
        'localUuid', 'amount', 'paymentDate', 'paymentMethod', 'revenueType',
        'hotelDayKey', 'isVoided', 'voidedAt', 'voidedBy', 'voidReason',
        'bookingLocalId', 'bookingUuidCache', 'roomNumber', 'notes',
        'cashTransactionLocalId', 'linkedDebtUuid', 'discountAmount',
        'discountStartDate', 'isPendingBalance', 'version', 'vectorClock',
        'lastModified', 'createdAt', 'updatedAt', 'deletedAt', 'serverId'
    ]
    
    existing_attrs = {attr['key'] for attr in attributes}
    missing_attrs = [a for a in required_payment_attrs if a not in existing_attrs]
    
    if missing_attrs:
        print_info(f"Missing attributes ({len(missing_attrs)}):")
        for attr in missing_attrs:
            print(f"   - {attr}")
        return False
    else:
        print_success("All required attributes are present!")
        return True

# ============================================================
# Step 7: List indexes
# ============================================================
def list_indexes():
    print_step("7. Checking indexes", "📊")
    result = make_request(f"databases/{DATABASE_ID}/collections/{PAYMENTS_COLLECTION_ID}/indexes")
    
    if not result:
        print_error("Failed to get indexes")
        return []
    
    indexes = result.get('indexes', [])
    print_info(f"Payments collection has {len(indexes)} indexes:")
    
    for idx in indexes:
        print(f"   - {idx['key']}: {idx['type']} on {idx['attributes']}")
    
    return indexes

# ============================================================
# Step 8: Create required indexes if missing
# ============================================================
def ensure_void_index(indexes):
    print_step("8. Ensuring void-related indexes exist", "🔧")
    
    existing_keys = {idx['key'] for idx in indexes}
    
    # Check for void index
    if 'idx_payments_void' in existing_keys:
        print_success("idx_payments_void index exists")
        return True
    
    # Create index for isVoided
    data = {
        "key": "idx_payments_void",
        "type": "key",
        "attributes": ["isVoided"],
        "orders": ["ASC"]
    }
    
    print_wait("Creating void index...")
    result = make_request(
        f"databases/{DATABASE_ID}/collections/{PAYMENTS_COLLECTION_ID}/indexes",
        method="POST",
        data=data
    )
    
    if result:
        print_success("idx_payments_void index created!")
        return True
    else:
        print_info("Could not create idx_payments_void (may already exist or not supported)")
        return True

# ============================================================
# Main function
# ============================================================
def main():
    print("""
╔══════════════════════════════════════════════════════════════╗
║     Appwrite Cloud Schema Verification & Setup Script        ║
║                                                              ║
║  Database: hotel_db                                          ║
║  Endpoint: https://fra.cloud.appwrite.io/v1                   ║
║  Project:  690ff0da0025518570c1                              ║
╚══════════════════════════════════════════════════════════════╝
    """)
    
    print_step("Starting Appwrite Cloud schema verification", "🚀")
    
    # Step 1: List collections
    collections = list_collections()
    if not collections:
        print_error("No collections found or API error")
        sys.exit(1)
    
    # Step 2: Get payments schema
    attributes = get_payments_schema()
    if not attributes:
        print_error("Cannot proceed without payments schema")
        sys.exit(1)
    
    # Step 3: Check voidReason
    has_void_reason = check_void_reason_attribute(attributes)
    
    # Step 4: Create voidReason if missing
    if not has_void_reason:
        if create_void_reason_attribute():
            # Re-fetch schema after creation
            print_wait("Re-fetching payments schema...")
            time.sleep(2)
            attributes = get_payments_schema() or attributes
            has_void_reason = check_void_reason_attribute(attributes)
    else:
        print_info("voidReason already exists, skipping creation")
    
    # Step 5: Check payment_voids
    payment_voids_schema = get_payment_voids_schema()
    
    # Step 6: Verify all required attributes
    all_attrs_present = verify_required_attributes(attributes)
    
    # Step 7: List indexes
    indexes = list_indexes()
    
    # Step 8: Ensure indexes
    ensure_void_index(indexes)
    
    # Final summary
    print("\n" + "="*60)
    print("📊 FINAL SUMMARY")
    print("="*60)
    
    print_info(f"Database: {DATABASE_ID}")
    print_info(f"Endpoint: {APPWRITE_ENDPOINT}")
    print_info(f"Collections found: {len(collections)}")
    
    # Summary of key attributes
    key_attrs = ['isVoided', 'voidedAt', 'voidedBy', 'voidReason', 'localUuid', 'lastModified']
    for attr_name in key_attrs:
        found = any(a['key'] == attr_name for a in attributes)
        status = "✅" if found else "❌"
        print(f"   {status} {attr_name}")
    
    if all_attrs_present:
        print_success("✅ All required attributes are present!")
        print_success("✅ Schema verification completed!")
    else:
        print_error("⚠️ Some attributes may be missing")
        print_info("Check the list above for missing attributes")
    
    print(f"\n{'='*60}")
    print("🎉 Script completed!")
    print("="*60)

if __name__ == "__main__":
    main()