# Appwrite Scripts Sync Updates

## 📋 التحديثات المطبقة

تم تحديث جميع سكريبتات Appwrite لمطابقة Schema الكامل للتطبيق وضمان 0% فقدان بيانات.

---

## 🔄 الملفات المُحدّثة

### 1. **create_all_collections_complete.js**
✅ **إضافة**: `shift_notes` Collection بالحقول الكاملة:
- `localUuid` (string, 100, required, unique)
- `serverId` (integer, nullable)
- `title` (string, 500, required)
- `content` (string, 5000, required)
- `priority` (string, 50, default: 'medium')
- `shiftType` (string, 50, default: 'all')
- `isRead` (integer, default: 0)
- `expiresAt` (string, 50, nullable)
- `createdBy` (string, 100, default: 'user')
- + جميع حقول SyncFields القياسية

**Indexes**:
- `idx_localUuid` (unique)
- `idx_serverId`
- `idx_isRead`
- `idx_priority`
- `idx_shiftType`
- `idx_createdAt` (DESC)

---

### 2. **process_outbox_stdin.js**
✅ **تحديث**: `COLLECTIONS` لتشمل جميع الجداول:
```javascript
const COLLECTIONS = {
  rooms: 'rooms',
  bookings: 'bookings',
  booking_notes: 'booking_notes',
  booking_nights: 'booking_nights',
  employees: 'employees',
  expenses: 'expenses',
  payments: 'payments',
  debts: 'debts',
  cash_transactions: 'cash_transactions',
  salary_cycles: 'salary_cycles',
  salary_payments: 'salary_payments',
  shift_notes: 'shift_notes',
  hotel_day_ledger: 'hotel_day_ledger',
};
```

✅ **تصحيح**: `mapPayload` لـ `shift_notes`
- **قبل**: كان يستخدم `note`, `shiftDate`, `employeeId` (خطأ!)
- **بعد**: يستخدم `title`, `content`, `priority`, `shiftType`, `isRead`, `expiresAt`, `createdBy` (صحيح ✓)

✅ **إضافة**: `mapPayload` functions لـ:
- `booking_notes`: bookingId, noteText, noteType, createdBy
- `booking_nights`: bookingLocalId, hotelDayKey, nightDate, nightPrice, roomNumber
- `employees`: name, role, phone, nationalId, hireDate, salary, status
- `salary_cycles`: employeeId, cycleStartDate, cycleEndDate, baseSalary, deductions, bonuses, netSalary, status
- `salary_payments`: cycleId, employeeId, amount, paymentDate, paymentMethod, notes
- `hotel_day_ledger`: dayKey, totalRevenue, totalExpenses, netIncome, occupancyRate

---

### 3. **verify_collections.js**
✅ **إضافة**: `shift_notes` إلى `requiredCollections`

الآن يتحقق من **14 جدول كامل**:
1. rooms
2. bookings
3. booking_notes
4. booking_nights
5. employees
6. expenses
7. cash_transactions
8. payments
9. debts
10. salary_cycles
11. salary_payments
12. **shift_notes** ⭐ (جديد)
13. hotel_day_ledger
14. devices
15. sync_logs

---

### 4. **clear_all_data.js**
✅ **إضافة**: `shift_notes` إلى قائمة الجداول المراد حذفها

---

## ✅ التطابق الكامل مع Flutter Schema

### Schema Source: `mobile/lib/services/local_db.dart`

```dart
class ShiftNotes extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  TextColumn get shiftType => text().withDefault(const Constant('all'))();
  IntColumn get isRead => integer().withDefault(const Constant(0))();
  TextColumn get expiresAt => text().nullable()();
  TextColumn get createdBy => text().withDefault(const Constant('user'))();
}
```

✅ **جميع الحقول موجودة في Appwrite Collection**
✅ **جميع الـ defaults متطابقة**
✅ **جميع الـ nullable fields صحيحة**

---

## 🔐 حقول المزامنة القياسية (SyncFields)

جميع الجداول تحتوي على:
- `localUuid` (unique identifier)
- `serverId` (server reference)
- `createdAt` (epoch timestamp)
- `updatedAt` (epoch timestamp)
- `deletedAt` (soft delete, nullable)
- `lastModified` (conflict resolution)
- `createdAtIso` (ISO 8601 string)
- `updatedAtIso` (ISO 8601 string)
- `version` (optimistic locking)
- `origin` (source tracking: local/appwrite/drive)

---

## 🚀 كيفية الاستخدام

### 1. إنشاء Collections في Appwrite
```bash
cd scripts/appwrite
export APPWRITE_API_KEY="your-api-key"
node create_all_collections_complete.js
```

### 2. التحقق من Collections
```bash
node verify_collections.js
```

### 3. معالجة Outbox للمزامنة
```bash
# من Flutter app، يتم إرسال outbox entries كـ JSON
echo '[{"entity":"shift_notes","op":"create","localUuid":"uuid-123","payload":{"title":"Important Note","content":"Test content"}}]' | node process_outbox_stdin.js
```

### 4. مسح جميع البيانات (للتطوير فقط)
```bash
node clear_all_data.js
```

---

## 📊 النتيجة النهائية

✅ **15 Collection** جاهز في Appwrite  
✅ **100% Schema Match** مع Flutter Local DB  
✅ **0% Data Loss Architecture** مع Outbox Pattern  
✅ **Dual Sync** (Appwrite + Google Drive)  
✅ **Conflict Resolution** مع version & lastModified  
✅ **Soft Delete** مع deletedAt  

---

## 🔄 دورة المزامنة الكاملة

```
Local DB (Drift)
    ↓ (DAO.merge → OutboxDao)
Outbox Table (local changes queue)
    ↓ (UnifiedSyncOrchestrator)
┌───────────────────────────────┐
│  Appwrite Sync (Delta)        │ ← AppwriteSyncManager
│  Google Drive Sync (Delta)    │ ← GoogleDriveDeltaSync
└───────────────────────────────┘
    ↓
Remote Storage (Appwrite + Drive)
    ↓ (Pull)
Local DB (merge incoming changes)
```

---

## 📝 ملاحظات مهمة

1. **Appwrite Collection IDs** يجب أن تطابق `appwrite_config.dart`:
   ```dart
   static const String shiftNotesCollectionId = 'shift_notes';
   ```

2. **process_outbox_stdin.js** يدعم الآن:
   - ✅ JSON Array `[{...}, {...}]`
   - ✅ NDJSON (newline-delimited JSON)

3. **Field Name Conversion**:
   - Flutter: `shiftType`, `isRead`, `createdBy` (camelCase)
   - Appwrite: `shiftType`, `isRead`, `createdBy` (same)
   - Script auto-converts: `shift_type` → `shiftType`

4. **Timestamps**:
   - `createdAt`, `updatedAt`, `lastModified`: **epoch integers** (milliseconds)
   - `createdAtIso`, `updatedAtIso`: **ISO 8601 strings** (for readability)

---

## 🎯 الخطوات التالية

1. ✅ تشغيل `create_all_collections_complete.js` لإنشاء shift_notes
2. ✅ التحقق من Collections في Appwrite Console
3. ✅ اختبار المزامنة من Flutter App
4. ✅ مراقبة sync_logs للتأكد من نجاح العمليات

---

**Created**: 2026-01-31  
**Updated**: 2026-01-31  
**Version**: 1.0.0
