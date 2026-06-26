#!/usr/bin/env python3
"""
Script to add idempotencyKey attribute to all Appwrite collections
Run: python add_idempotency_key.php
     or: ./add_idempotency_key.php (if executable)
"""

import os
import sys
import time

# Install appwrite SDK if not present
try:
    from appwrite.client import Client
    from appwrite.services.databases import Databases
    from appwrite.exception import AppwriteException
except ImportError:
    os.system('pip3 install appwrite -q')
    from appwrite.client import Client
    from appwrite.services.databases import Databases
    from appwrite.exception import AppwriteException

# Configuration
ENDPOINT = os.environ.get('APPWRITE_ENDPOINT', 'https://fra.cloud.appwrite.io/v1')
PROJECT_ID = os.environ.get('APPWRITE_PROJECT_ID', '')
API_KEY = os.environ.get('APPWRITE_API_KEY', '')
DATABASE_ID = os.environ.get('APPWRITE_DATABASE_ID', 'hotel_db')

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


def init_client():
    """Initialize Appwrite client."""
    client = Client()
    client.set_endpoint(ENDPOINT)
    client.set_project(PROJECT_ID)
    client.set_key(API_KEY)
    return Databases(client)


def attribute_exists(databases, collection_id):
    """Check if idempotencyKey attribute already exists."""
    try:
        attrs = databases.list_attributes(database_id=DATABASE_ID, collection_id=collection_id)
        for attr in attrs['attributes']:
            if attr['key'] == 'idempotencyKey':
                return True
    except Exception as e:
        print(f"  ⚠️ Error checking: {e}")
    return False


def wait_for_attribute(databases, collection_id, max_wait=30):
    """Wait for attribute to be ready."""
    for i in range(max_wait):
        try:
            attr = databases.get_attribute(database_id=DATABASE_ID, collection_id=collection_id, attribute_key='idempotencyKey')
            if attr['status'] == 'available':
                print("  ✅ Attribute is ready!")
                return True
            print(f"  ⏳ Status: {attr['status']} (waiting... {i+1}/{max_wait})")
            time.sleep(2)
        except Exception as e:
            print(f"  ⏳ Waiting... ({i+1}/{max_wait})")
            time.sleep(2)
    print("  ⚠️ Timeout waiting for attribute")
    return False


def create_attribute(databases, collection_id):
    """Create idempotencyKey attribute in collection."""
    try:
        print("  📤 Creating attribute...")
        result = databases.create_string_attribute(
            database_id=DATABASE_ID,
            collection_id=collection_id,
            key='idempotencyKey',
            size=255,
            required=False
        )
        print(f"  ✅ Created! Status: {result['status']}")
        return True
    except AppwriteException as e:
        if '409' in str(e) or 'already exists' in str(e).lower():
            print("  ⚠️ Already exists")
            return True
        print(f"  ❌ Error: {e.message}")
        return False
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return False


def main():
    print("=" * 50)
    print("🔧 Adding idempotencyKey to Collections")
    print("=" * 50)
    
    # Check required environment variables
    if not PROJECT_ID or not API_KEY:
        print("\n❌ Error: APPWRITE_PROJECT_ID and APPWRITE_API_KEY must be set!")
        print("\n   Example:")
        print("   export APPWRITE_PROJECT_ID=your_project_id")
        print("   export APPWRITE_API_KEY=your_api_key")
        print("   python add_idempotency_key.php")
        sys.exit(1)
    
    print(f"\n📍 Endpoint: {ENDPOINT}")
    print(f"📁 Project: {PROJECT_ID}")
    print(f"📁 Database: {DATABASE_ID}")
    print(f"📋 Collections: {len(COLLECTIONS)}")
    
    # Initialize client
    databases = init_client()
    
    print("\n" + "=" * 50)
    print("🚀 Starting...")
    print("=" * 50 + "\n")
    
    results = {}
    
    for collection_id in COLLECTIONS:
        print(f"📋 Collection: {collection_id}")
        
        # Check if exists
        if attribute_exists(databases, collection_id):
            print("  ✅ idempotencyKey already exists")
            results[collection_id] = True
            print()
            continue
        
        # Create attribute
        success = create_attribute(databases, collection_id)
        
        if success:
            wait_for_attribute(databases, collection_id)
        
        results[collection_id] = success
        print()
    
    # Summary
    print("=" * 50)
    print("📊 Summary")
    print("=" * 50)
    
    success_count = sum(1 for v in results.values() if v)
    fail_count = len(results) - success_count
    
    for collection_id, success in results.items():
        status = "✅" if success else "❌"
        print(f"  {status} {collection_id}")
    
    print(f"\n📈 Total: {len(results)} collections")
    print(f"  ✅ Success: {success_count}")
    print(f"  ❌ Failed: {fail_count}")
    
    if fail_count > 0:
        print("\n⚠️ Some collections failed.")
        sys.exit(1)
    else:
        print("\n🎉 All collections updated successfully!")
        sys.exit(0)


if __name__ == '__main__':
    main()
