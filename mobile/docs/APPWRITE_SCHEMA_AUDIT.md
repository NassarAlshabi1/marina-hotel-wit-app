# Appwrite Schema Audit Report
## Marina Hotel Billing System

**Audit Date:** February 8, 2026  
**Status:** PRODUCTION SYSTEM - NO DATA DELETION

---

## 🔴 Critical Issues Found

| Issue | Severity | Impact |
|-------|----------|--------|
| Missing `price_adjustments` collection | HIGH | No audit trail for rate changes |
| Missing `audit_logs` collection | HIGH | No financial operation tracking |
| Mutable financial totals in bookings | CRITICAL | Sync can overwrite calculated values |
| Missing indexes on Appwrite | MEDIUM | Slow queries, timeouts |
| Payments lack immutability flag | HIGH | Historical payments can be modified |
| No sync conflict resolution | HIGH | Last-write-wins can lose data |

---

## 📋 Current Collections Analysis

### ✅ Existing Collections
- `rooms` - Room inventory
- `bookings` - Guest reservations  
- `payments` - Payment records
- `expenses` - Expense tracking
- `employees` - Staff records
- `debts` - Outstanding balances
- `devices` - Sync devices
- `sync_logs` - Sync history
- `booking_notes` - Booking annotations
- `cash_transactions` - Cash flow
- `booking_nights` - Nightly breakdown
- `hotel_day_ledger` - Daily summaries
- `salary_cycles` - Payroll periods
- `salary_payments` - Salary disbursements
- `shift_notes` - Shift handover notes

### ❌ Missing Collections
- `price_adjustments` - Rate change history
- `audit_logs` - Financial operation audit trail
- `payment_voids` - Voided payment records (instead of mutation)

---

## 🛠️ Schema Fixes

### 1. New Collection: `price_adjustments`

```json
{
  "collectionId": "price_adjustments",
  "name": "Price Adjustments",
  "attributes": [
    {"key": "localUuid", "type": "string", "size": 36, "required": true},
    {"key": "targetType", "type": "string", "size": 20, "required": true},
    {"key": "targetUuid", "type": "string", "size": 36, "required": true},
    {"key": "adjustmentType", "type": "string", "size": 30, "required": true},
    {"key": "previousValue", "type": "double", "required": true},
    {"key": "newValue", "type": "double", "required": true},
    {"key": "reason", "type": "string", "size": 500, "required": false},
    {"key": "effectiveDate", "type": "string", "size": 30, "required": true},
    {"key": "appliedBy", "type": "string", "size": 100, "required": true},
    {"key": "hotelDayKey", "type": "string", "size": 10, "required": true},
    {"key": "isReversed", "type": "boolean", "required": true, "default": false},
    {"key": "reversedAt", "type": "string", "size": 30, "required": false},
    {"key": "reversedBy", "type": "string", "size": 100, "required": false},
    {"key": "createdAt", "type": "integer", "required": true},
    {"key": "updatedAt", "type": "integer", "required": true},
    {"key": "deletedAt", "type": "integer", "required": false},
    {"key": "version", "type": "integer", "required": true, "default": 1},
    {"key": "origin", "type": "string", "size": 20, "required": true, "default": "local"}
  ],
  "indexes": [
    {"key": "idx_target", "type": "key", "attributes": ["targetType", "targetUuid"]},
    {"key": "idx_hotel_day", "type": "key", "attributes": ["hotelDayKey"]},
    {"key": "idx_effective_date", "type": "key", "attributes": ["effectiveDate"]}
  ]
}
```

### 2. New Collection: `audit_logs`

```json
{
  "collectionId": "audit_logs",
  "name": "Audit Logs",
  "attributes": [
    {"key": "localUuid", "type": "string", "size": 36, "required": true},
    {"key": "operationType", "type": "string", "size": 30, "required": true},
    {"key": "entityType", "type": "string", "size": 30, "required": true},
    {"key": "entityUuid", "type": "string", "size": 36, "required": true},
    {"key": "entityId", "type": "integer", "required": false},
    {"key": "previousState", "type": "string", "size": 10000, "required": false},
    {"key": "newState", "type": "string", "size": 10000, "required": false},
    {"key": "changedFields", "type": "string", "size": 2000, "required": false},
    {"key": "performedBy", "type": "string", "size": 100, "required": true},
    {"key": "deviceId", "type": "string", "size": 100, "required": true},
    {"key": "ipAddress", "type": "string", "size": 45, "required": false},
    {"key": "hotelDayKey", "type": "string", "size": 10, "required": true},
    {"key": "timestamp", "type": "integer", "required": true},
    {"key": "timestampIso", "type": "string", "size": 30, "required": true},
    {"key": "isFinancial", "type": "boolean", "required": true, "default": false},
    {"key": "amountImpact", "type": "double", "required": false},
    {"key": "createdAt", "type": "integer", "required": true}
  ],
  "indexes": [
    {"key": "idx_entity", "type": "key", "attributes": ["entityType", "entityUuid"]},
    {"key": "idx_hotel_day", "type": "key", "attributes": ["hotelDayKey"]},
    {"key": "idx_timestamp", "type": "key", "attributes": ["timestamp"], "orders": ["DESC"]},
    {"key": "idx_financial", "type": "key", "attributes": ["isFinancial", "hotelDayKey"]},
    {"key": "idx_operation", "type": "key", "attributes": ["operationType", "entityType"]}
  ]
}
```

### 3. New Collection: `payment_voids`

```json
{
  "collectionId": "payment_voids",
  "name": "Payment Voids",
  "attributes": [
    {"key": "localUuid", "type": "string", "size": 36, "required": true},
    {"key": "originalPaymentUuid", "type": "string", "size": 36, "required": true},
    {"key": "originalPaymentId", "type": "integer", "required": true},
    {"key": "bookingUuid", "type": "string", "size": 36, "required": true},
    {"key": "voidedAmount", "type": "double", "required": true},
    {"key": "voidReason", "type": "string", "size": 500, "required": true},
    {"key": "voidedBy", "type": "string", "size": 100, "required": true},
    {"key": "voidedAt", "type": "integer", "required": true},
    {"key": "voidedAtIso", "type": "string", "size": 30, "required": true},
    {"key": "hotelDayKey", "type": "string", "size": 10, "required": true},
    {"key": "reversalPaymentUuid", "type": "string", "size": 36, "required": false},
    {"key": "approvedBy", "type": "string", "size": 100, "required": false},
    {"key": "createdAt", "type": "integer", "required": true},
    {"key": "version", "type": "integer", "required": true, "default": 1},
    {"key": "origin", "type": "string", "size": 20, "required": true, "default": "local"}
  ],
  "indexes": [
    {"key": "idx_original_payment", "type": "unique", "attributes": ["originalPaymentUuid"]},
    {"key": "idx_booking", "type": "key", "attributes": ["bookingUuid"]},
    {"key": "idx_hotel_day", "type": "key", "attributes": ["hotelDayKey"]}
  ]
}
```

---

## 🔧 Schema Modifications for Existing Collections

### Bookings Collection - Add Immutability Fields

```json
{
  "newAttributes": [
    {"key": "financialFrozenAt", "type": "integer", "required": false},
    {"key": "lastFinancialRecalc", "type": "integer", "required": false},
    {"key": "financialHash", "type": "string", "size": 64, "required": false},
    {"key": "syncConflictResolution", "type": "string", "size": 20, "required": false}
  ]
}
```

### Payments Collection - Add Immutability Fields

```json
{
  "newAttributes": [
    {"key": "isImmutable", "type": "boolean", "required": true, "default": false},
    {"key": "immutableAt", "type": "integer", "required": false},
    {"key": "isVoided", "type": "boolean", "required": true, "default": false},
    {"key": "voidedAt", "type": "integer", "required": false},
    {"key": "voidReason", "type": "string", "size": 500, "required": false},
    {"key": "originalAmount", "type": "double", "required": false},
    {"key": "financialHash", "type": "string", "size": 64, "required": false}
  ]
}
```

---

## 📊 Missing Indexes for Performance

### Bookings Collection
```bash
# Index for active bookings by hotel day
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId bookings \
  --key idx_status_hotel_day \
  --type key \
  --attributes status,hotelDayCheckin

# Index for guest search
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId bookings \
  --key idx_guest_name \
  --type fulltext \
  --attributes guestName

# Index for room lookups
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId bookings \
  --key idx_room_status \
  --type key \
  --attributes roomNumber,status
```

### Payments Collection
```bash
# Index for booking payments
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId payments \
  --key idx_booking_date \
  --type key \
  --attributes bookingLocalId,paymentDate

# Index for hotel day reports
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId payments \
  --key idx_hotel_day_type \
  --type key \
  --attributes hotelDayKey,revenueType

# Index for immutable payments
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId payments \
  --key idx_immutable \
  --type key \
  --attributes isImmutable,isVoided
```

### Expenses Collection
```bash
# Index for hotel day expenses
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId expenses \
  --key idx_hotel_day_type \
  --type key \
  --attributes hotelDayKey,expenseType

# Index for date range queries
appwrite databases createIndex \
  --databaseId hotel_db \
  --collectionId expenses \
  --key idx_date \
  --type key \
  --attributes date
```

---

## 🔐 Security Rules

### Collection-Level Permissions

```json
{
  "bookings": {
    "read": ["role:all"],
    "create": ["role:all"],
    "update": ["role:all"],
    "delete": ["role:all"]
  },
  "payments": {
    "read": ["role:all"],
    "create": ["role:all"],
    "update": ["role:all"],
    "delete": []
  },
  "payment_voids": {
    "read": ["role:all"],
    "create": ["role:all"],
    "update": [],
    "delete": []
  },
  "audit_logs": {
    "read": ["role:all"],
    "create": ["role:all"],
    "update": [],
    "delete": []
  },
  "price_adjustments": {
    "read": ["role:all"],
    "create": ["role:all"],
    "update": ["role:all"],
    "delete": []
  }
}
```

### Recommended Function-Based Validation

```javascript
// Appwrite Function: validate_payment_mutation
module.exports = async function(req, res) {
  const { paymentId, action } = JSON.parse(req.payload);
  
  if (action === 'update' || action === 'delete') {
    const payment = await databases.getDocument(
      'hotel_db', 
      'payments', 
      paymentId
    );
    
    if (payment.isImmutable) {
      return res.json({
        success: false,
        error: 'Payment is immutable. Use void instead.'
      });
    }
  }
  
  return res.json({ success: true });
};
```

---

## 📜 Migration Steps

### Phase 1: Create New Collections (Non-Breaking)

```bash
#!/bin/bash
# migration_phase1.sh - Create new collections

DATABASE_ID="hotel_db"

# 1. Create price_adjustments collection
appwrite databases createCollection \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --name "Price Adjustments" \
  --permissions 'read("any")' 'create("any")' 'update("any")'

# 2. Create audit_logs collection
appwrite databases createCollection \
  --databaseId $DATABASE_ID \
  --collectionId audit_logs \
  --name "Audit Logs" \
  --permissions 'read("any")' 'create("any")'

# 3. Create payment_voids collection
appwrite databases createCollection \
  --databaseId $DATABASE_ID \
  --collectionId payment_voids \
  --name "Payment Voids" \
  --permissions 'read("any")' 'create("any")'

echo "Phase 1 complete: New collections created"
```

### Phase 2: Add Attributes to New Collections

```bash
#!/bin/bash
# migration_phase2.sh - Add attributes to new collections

DATABASE_ID="hotel_db"

# price_adjustments attributes
appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key localUuid \
  --size 36 \
  --required true

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key targetType \
  --size 20 \
  --required true

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key targetUuid \
  --size 36 \
  --required true

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key adjustmentType \
  --size 30 \
  --required true

appwrite databases createFloatAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key previousValue \
  --required true

appwrite databases createFloatAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key newValue \
  --required true

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key reason \
  --size 500 \
  --required false

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key effectiveDate \
  --size 30 \
  --required true

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key appliedBy \
  --size 100 \
  --required true

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key hotelDayKey \
  --size 10 \
  --required true

appwrite databases createBooleanAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key isReversed \
  --required true \
  --default false

appwrite databases createIntegerAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key createdAt \
  --required true

appwrite databases createIntegerAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key updatedAt \
  --required true

appwrite databases createIntegerAttribute \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key version \
  --required true \
  --default 1

echo "Phase 2 complete: Attributes added to price_adjustments"
```

### Phase 3: Add New Attributes to Existing Collections

```bash
#!/bin/bash
# migration_phase3.sh - Add immutability fields to existing collections

DATABASE_ID="hotel_db"

# Add to payments collection
appwrite databases createBooleanAttribute \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key isImmutable \
  --required false \
  --default false

appwrite databases createIntegerAttribute \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key immutableAt \
  --required false

appwrite databases createBooleanAttribute \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key isVoided \
  --required false \
  --default false

appwrite databases createIntegerAttribute \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key voidedAt \
  --required false

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key voidReason \
  --size 500 \
  --required false

appwrite databases createFloatAttribute \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key originalAmount \
  --required false

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key financialHash \
  --size 64 \
  --required false

# Add to bookings collection
appwrite databases createIntegerAttribute \
  --databaseId $DATABASE_ID \
  --collectionId bookings \
  --key financialFrozenAt \
  --required false

appwrite databases createIntegerAttribute \
  --databaseId $DATABASE_ID \
  --collectionId bookings \
  --key lastFinancialRecalc \
  --required false

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId bookings \
  --key financialHash \
  --size 64 \
  --required false

appwrite databases createStringAttribute \
  --databaseId $DATABASE_ID \
  --collectionId bookings \
  --key syncConflictResolution \
  --size 20 \
  --required false

echo "Phase 3 complete: Immutability fields added"
```

### Phase 4: Create Indexes

```bash
#!/bin/bash
# migration_phase4.sh - Create indexes

DATABASE_ID="hotel_db"

# Indexes for new collections
appwrite databases createIndex \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key idx_target \
  --type key \
  --attributes targetType,targetUuid

appwrite databases createIndex \
  --databaseId $DATABASE_ID \
  --collectionId price_adjustments \
  --key idx_hotel_day \
  --type key \
  --attributes hotelDayKey

appwrite databases createIndex \
  --databaseId $DATABASE_ID \
  --collectionId audit_logs \
  --key idx_entity \
  --type key \
  --attributes entityType,entityUuid

appwrite databases createIndex \
  --databaseId $DATABASE_ID \
  --collectionId audit_logs \
  --key idx_timestamp \
  --type key \
  --attributes timestamp \
  --orders DESC

appwrite databases createIndex \
  --databaseId $DATABASE_ID \
  --collectionId audit_logs \
  --key idx_financial \
  --type key \
  --attributes isFinancial,hotelDayKey

# Indexes for existing collections
appwrite databases createIndex \
  --databaseId $DATABASE_ID \
  --collectionId payments \
  --key idx_immutable \
  --type key \
  --attributes isImmutable,isVoided

appwrite databases createIndex \
  --databaseId $DATABASE_ID \
  --collectionId bookings \
  --key idx_financial_frozen \
  --type key \
  --attributes financialFrozenAt

echo "Phase 4 complete: Indexes created"
```

### Phase 5: Backfill Data

```bash
#!/bin/bash
# migration_phase5.sh - Backfill existing data

# This should be run via Flutter/Dart code or Appwrite Functions
# to mark existing payments as immutable after a cutoff date

echo "Run the following in your Flutter app:"
echo "await PaymentImmutabilityMigration.execute();"
```

---

## 🔄 Sync Conflict Resolution Strategy

### Recommended Vector Clock Implementation

```dart
// Add to existing sync logic
class SyncConflictResolver {
  static Map<String, dynamic> resolveBookingConflict(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    // Financial fields: NEVER overwrite with remote if local has changes
    final financialFields = [
      'totalDueCached',
      'totalPaidCached', 
      'remainingBalanceCached',
      'isFullyPaid',
    ];
    
    final result = Map<String, dynamic>.from(remote);
    
    // Keep local financial calculations if more recent
    if ((local['lastFinancialRecalc'] ?? 0) > 
        (remote['lastFinancialRecalc'] ?? 0)) {
      for (final field in financialFields) {
        result[field] = local[field];
      }
      result['lastFinancialRecalc'] = local['lastFinancialRecalc'];
      result['syncConflictResolution'] = 'local_financial_preserved';
    }
    
    return result;
  }
  
  static Map<String, dynamic> resolvePaymentConflict(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    // If either is immutable, prefer the immutable version
    if (local['isImmutable'] == true) {
      return local;
    }
    if (remote['isImmutable'] == true) {
      return remote;
    }
    
    // Otherwise, use standard last-write-wins
    return (local['updatedAt'] ?? 0) > (remote['updatedAt'] ?? 0) 
        ? local 
        : remote;
  }
}
```

---

## ✅ Verification Checklist

After migration, verify:

- [ ] All three new collections exist in Appwrite Console
- [ ] All new attributes are present on collections
- [ ] All indexes are created and active
- [ ] Permissions are correctly set (payments no delete)
- [ ] Existing data is intact (no deletions)
- [ ] App can sync with new schema
- [ ] Financial calculations remain accurate
- [ ] Audit logs capture financial operations

---

## 📝 Code Changes Status

### ✅ COMPLETED (Flutter App)

| File | Status | Description |
|------|--------|-------------|
| `appwrite_config.dart` | ✅ Done | Added `priceAdjustmentsCollectionId`, `auditLogsCollectionId`, `paymentVoidsCollectionId` |
| `local_db.dart` | ✅ Done | Added `PriceAdjustments`, `AuditLogs`, `PaymentVoids` tables with indexes |
| `appwrite_delta_sync.dart` | ✅ Done | Added sync support for new collections in `_getCollectionId`, `entitiesToPull`, `_applyRemoteChange` |
| `adapters/price_adjustments_adapter.dart` | ✅ Created | Full adapter for price adjustments |
| `adapters/audit_logs_adapter.dart` | ✅ Created | Full adapter for audit logs |
| `adapters/payment_voids_adapter.dart` | ✅ Created | Full adapter for payment voids |
| `adapters/adapter_registry.dart` | ✅ Updated | Registered all three new adapters |

### ⚠️ MANUAL STEPS REQUIRED

#### Step 1: Regenerate Drift Database (Local Machine)

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

This regenerates `local_db.g.dart` with the new tables.

#### Step 2: Create Collections in Appwrite Console

Go to **Appwrite Console > Database > hotel_db** and create:

**Collection 1: `price_adjustments`**
```json
{
  "collectionId": "price_adjustments",
  "name": "Price Adjustments",
  "permissions": ["read(\"any\")", "create(\"any\")", "update(\"any\")"]
}
```

**Collection 2: `audit_logs`**  
```json
{
  "collectionId": "audit_logs",
  "name": "Audit Logs",
  "permissions": ["read(\"any\")", "create(\"any\")"]
}
```
> ⚠️ NOTE: audit_logs has NO update/delete permissions - logs are immutable

**Collection 3: `payment_voids`**
```json
{
  "collectionId": "payment_voids", 
  "name": "Payment Voids",
  "permissions": ["read(\"any\")", "create(\"any\")", "update(\"any\")"]
}
```

#### Step 3: Add Attributes to New Collections

Use the Appwrite Console or CLI to add attributes as defined in Phase 2 of migration scripts above.

#### Step 4: Create Indexes

For each collection, create the indexes defined in Phase 3 of migration scripts above.

#### Step 5: Update Existing Collections (Optional but Recommended)

Add immutability tracking to `payments` collection:
- `isImmutable` (boolean, default: false)
- `isVoided` (boolean, default: false)
- `voidedAt` (integer, nullable)

Add financial freeze fields to `bookings` collection:
- `financialFrozenAt` (integer, nullable)  
- `financialHash` (string, nullable)

---

## 🔄 Database Migration Safety

The SQLite database (Drift) will auto-migrate when the app runs after regenerating. New tables are added without affecting existing data.

For Appwrite, follow the phased approach to ensure no data loss:
1. Create collections/attributes first
2. Deploy app update
3. Verify sync works
4. Enable strict permissions

---

*Generated by Appwrite Schema Audit Tool*
*Last Updated: February 8, 2026*
