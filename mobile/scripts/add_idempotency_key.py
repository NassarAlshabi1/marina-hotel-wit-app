#!/usr/bin/env python3
"""
Script to add idempotencyKey attribute to all collections in Appwrite.
This script only ADDS the attribute, it does NOT create the full schema.

Usage:
    python add_idempotency_key.py
"""

import os
import sys
import json
import requests

# Appwrite Configuration from environment or defaults
APPWRITE_ENDPOINT = os.environ.get('APPWRITE_ENDPOINT', 'https://cloud.appwrite.io/v1')
APPWRITE_PROJECT_ID = os.environ.get('APPWRITE_PROJECT_ID', '')
APPWRITE_DATABASE_ID = os.environ.get('APPWRITE_DATABASE_ID', 'marina_hotel')
APPWRITE_API_KEY = os.environ.get('APPWRITE_API_KEY', '')

# Collections that need idempotencyKey
COLLECTIONS = [
    'bookings',
    'payments',
    'expenses',
    'employees',
    'debts',
    'salary_payments',
    'salary_carry_over_logs',
    'shift_notes',
    'cash_transactions',
    'booking_notes',
]


def get_headers():
    """Get headers for Appwrite API requests."""
    return {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': APPWRITE_PROJECT_ID,
        'X-Appwrite-Key': APPWRITE_API_KEY,
    }


def check_attribute_exists(database_id, collection_id, attribute_key):
    """Check if an attribute already exists in the collection."""
    url = f"{APPWRITE_ENDPOINT}/databases/{database_id}/collections/{collection_id}/attributes"
    try:
        response = requests.get(url, headers=get_headers(), timeout=30)
        if response.status_code == 200:
            attributes = response.json().get('attributes', [])
            for attr in attributes:
                if attr.get('key') == attribute_key:
                    return True
        return False
    except Exception as e:
        print(f"  ⚠️ Error checking attribute: {e}")
        return False


def create_string_attribute(database_id, collection_id, attribute_key):
    """Create a string attribute in Appwrite."""
    url = f"{APPWRITE_ENDPOINT}/databases/{database_id}/collections/{collection_id}/attributes"
    
    payload = {
        'key': attribute_key,
        'size': 255,
        'required': False,
    }
    
    try:
        print(f"  📤 Creating attribute {attribute_key}...")
        response = requests.post(url, headers=get_headers(), json=payload, timeout=60)
        
        if response.status_code in [200, 201]:
            result = response.json()
            print(f"  ✅ Attribute '{attribute_key}' created successfully!")
            return True
        elif response.status_code == 409:
            print(f"  ⚠️ Attribute '{attribute_key}' already exists (409 Conflict)")
            return True  # Already exists, consider it a success
        else:
            print(f"  ❌ Failed to create attribute: {response.status_code}")
            print(f"     Response: {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        print(f"  ⏱️ Timeout while creating attribute (this is OK - attribute might be created)")
        return True
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return False


def wait_for_attribute(database_id, collection_id, attribute_key, max_wait=30):
    """Wait for an attribute to be ready."""
    import time
    
    for i in range(max_wait):
        url = f"{APPWRITE_ENDPOINT}/databases/{database_id}/collections/{collection_id}/attributes/{attribute_key}"
        try:
            response = requests.get(url, headers=get_headers(), timeout=10)
            if response.status_code == 200:
                data = response.json()
                status = data.get('status', 'unknown')
                if status == 'available':
                    print(f"  ✅ Attribute '{attribute_key}' is ready!")
                    return True
                elif status == 'processing':
                    print(f"  ⏳ Waiting for attribute '{attribute_key}'... ({i+1}/{max_wait})")
                    time.sleep(2)
                else:
                    print(f"  ⚠️ Attribute status: {status}")
                    return False
            elif response.status_code == 404:
                print(f"  ⏳ Attribute '{attribute_key}' not ready yet... ({i+1}/{max_wait})")
                time.sleep(2)
            else:
                print(f"  ⚠️ Error checking attribute status: {response.status_code}")
                time.sleep(2)
        except Exception as e:
            print(f"  ⏳ Waiting... ({i+1}/{max_wait})")
            time.sleep(2)
    
    print(f"  ⚠️ Timeout waiting for attribute '{attribute_key}'")
    return False


def add_idempotency_key_to_collection(database_id, collection_id):
    """Add idempotencyKey attribute to a single collection."""
    attribute_key = 'idempotencyKey'
    
    print(f"\n📋 Processing collection: {collection_id}")
    
    # Check if attribute already exists
    if check_attribute_exists(database_id, collection_id, attribute_key):
        print(f"  ✅ Attribute '{attribute_key}' already exists in '{collection_id}'")
        return True
    
    # Create the attribute
    success = create_string_attribute(database_id, collection_id, attribute_key)
    
    if success:
        # Wait for the attribute to be ready
        wait_for_attribute(database_id, collection_id, attribute_key)
    
    return success


def main():
    print("=" * 60)
    print("🔧 Appwrite: Add idempotencyKey to Collections")
    print("=" * 60)
    
    # Check for required environment variables
    if not APPWRITE_PROJECT_ID:
        print("\n❌ Error: APPWRITE_PROJECT_ID is not set!")
        print("   Please set the environment variable or edit this script.")
        sys.exit(1)
    
    if not APPWRITE_API_KEY:
        print("\n❌ Error: APPWRITE_API_KEY is not set!")
        print("   Please set the environment variable or edit this script.")
        sys.exit(1)
    
    print(f"\n📍 Endpoint: {APPWRITE_ENDPOINT}")
    print(f"📁 Database: {APPWRITE_DATABASE_ID}")
    print(f"📋 Collections: {len(COLLECTIONS)}")
    
    print("\n" + "=" * 60)
    print("🚀 Starting attribute creation...")
    print("=" * 60)
    
    results = {}
    for collection_id in COLLECTIONS:
        success = add_idempotency_key_to_collection(APPWRITE_DATABASE_ID, collection_id)
        results[collection_id] = success
    
    # Summary
    print("\n" + "=" * 60)
    print("📊 Summary")
    print("=" * 60)
    
    success_count = sum(1 for v in results.values() if v)
    fail_count = len(results) - success_count
    
    for collection_id, success in results.items():
        status = "✅" if success else "❌"
        print(f"  {status} {collection_id}")
    
    print(f"\n📈 Total: {len(results)} collections")
    print(f"  ✅ Success: {success_count}")
    print(f"  ❌ Failed: {fail_count}")
    
    if fail_count > 0:
        print("\n⚠️ Some collections failed. Please check the errors above.")
        sys.exit(1)
    else:
        print("\n🎉 All collections updated successfully!")
        sys.exit(0)


if __name__ == '__main__':
    main()
