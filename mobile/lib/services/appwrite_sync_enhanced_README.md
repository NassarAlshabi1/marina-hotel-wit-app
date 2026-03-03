# AppwriteSyncManagerEnhanced - نظام المزامنة المحسن مع حل التعارضات

## ✅ المميزات الجديدة

### 1. نظام التعارضات المتقدم (EnhancedConflictResolver)
```dart
final resolver = EnhancedConflictResolver(
  defaultStrategy: ConflictStrategy.lastWriteWins,
  tableStrategies: {
    'bookings': ConflictStrategy.fieldLevel,     // دمج على مستوى الحقول
    'payments': ConflictStrategy.lastWriteWins,   // الأحدث يفوز
    'expenses': ConflictStrategy.fieldLevel,
    'debts': ConflictStrategy.fieldLevel,
  },
);
```

### 2. Vector Clock للتعارضات الحقيقية
- يكتشف التعديلات المتزامنة (Concurrent Edits)
- يتجنب False Positives
- يدعم تتبع الأجهزة المتعددة

### 3. الحقول الحرجة المحمية

| الجدول | الحقول الحرجة |
|--------|---------------|
| **bookings** | status, checkout_date, total_due_cached, total_paid_cached, remaining_balance_cached, guest_name, is_fully_paid, discount |
| **payments** | amount, payment_date, payment_method, booking_uuid, status, revenue_type |
| **rooms** | status, price, room_number, floor, type, cleaning_status, requires_maintenance |
| **expenses** | amount, date, category, description, expense_type, hotel_day_key |
| **debts** | amount, status, due_date, paid_amount, remaining_amount, is_settled |
| **employees** | name, phone, basic_salary, position, status |
| **cash_transactions** | amount, transaction_type, transaction_time |

### 4. استراتيجيات الحل المتعددة

| الاستراتيجية | الوصف | الاستخدام |
|--------------|-------|-----------|
| `lastWriteWins` | الأحدث يفوز (timestamp) | العمليات العادية |
| `fieldLevel` | دمج على مستوى الحقول | الحجوزات، الديون، المصروفات |
| `firstWriteWins` | الأقدم يفوز | نادر الاستخدام |
| `manualResolve` | يدوي | يتطلب تدخل المستخدم |
| `customPriority` | أولوية الجهاز | للأجهزة ذات الأولوية العالية |

### 5. استثناءات مخصصة

```dart
// عند اكتشاف تعارض
throw ConflictDetectedException(
  conflictRecord: ConflictRecord(...),
  context: conflictContext,
  localData: local,
  remoteData: remote,
);

// عند فشل FOREIGN KEY
throw ForeignKeyException('Booking not found for payment');
```

## 📊 مقارنة بالنسخة الأصلية

| الميزة | النسخة الأصلية | النسخة المحسنة |
|--------|---------------|----------------|
| حل التعارضات | ❌ Database-level upserts | ✅ EnhancedConflictResolver |
| Vector Clock | ❌ غير مستخدم | ✅ متكامل |
| الحقول الحرجة | ❌ غير محمية | ✅ محمية لكل جدول |
| تتبع التعارضات | ❌ غير متوفر | ✅ ConflictManager |
| FOREIGN KEY | ✅ Defer & Retry | ✅ + معالجة أفضل |
| الحل التلقائي | ❌ لا يوجد | ✅ يحاول الحل تلقائياً |

## 🚀 الاستخدام

```dart
// التهيئة
final syncManager = AppwriteSyncManagerEnhanced(
  appwriteService: appwriteService,
  database: database,
);
await syncManager.initialize();

// المزامنة مع حل التعارضات
final result = await syncManager.sync(push: true, pull: true);

if (result.hasConflicts) {
  print('تم اكتشاف ${result.conflicts} تعارض');
  print('تم حل ${result.conflictsResolved} تلقائياً');
  
  for (final conflict in result.conflictDetails) {
    if (conflict.resolution == null) {
      // يتطلب مراجعة يدوية
      print('تعارض يحتاج مراجعة: ${conflict.targetTable}/${conflict.uuid}');
    }
  }
}
```

## 📁 الملفات المُنشأة

| الملف | الوصف |
|-------|-------|
| `appwrite_sync_manager_enhanced.dart` | المدير المحسن مع نظام التعارضات |
| `appwrite_sync_enhanced_README.md` | هذا الملف |

## 🔧 التكامل المستقبلي

لاستبدال النسخة الأصلية:

```dart
// في main.dart أو providers
final enhancedSyncManager = AppwriteSyncManagerEnhanced(
  appwriteService: appwriteService,
  database: database,
);

// استبدال الـ Provider
final appwriteSyncManagerProvider = Provider<AppwriteSyncManagerEnhanced>((ref) {
  return enhancedSyncManager;
});
```
