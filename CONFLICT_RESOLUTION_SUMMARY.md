# نظام حل التعارضات المتقدم - Appwrite Sync Manager Enhanced

## ✅ تم التنفيذ بنجاح

### الملفات الرئيسية المُنشأة:
1. **`mobile/lib/services/appwrite_sync_manager_enhanced.dart`** (1627 سطر)
   - مدير المزامنة المتقدم مع نظام حل التعارضات
   - يستخدم `EnhancedConflictResolver` و `VectorClock`

2. **تم تحديث:**
   - `mobile/lib/providers/appwrite_providers.dart` - إضافة `enhancedSyncManagerProvider`
   - `mobile/lib/services/unified_sync_orchestrator.dart` - تحديث للعمل مع المدير الجديد

### استراتيجيات حل التعارضات المُنشأة:

| الاستراتيجية | الوصف | الجداول المُطبقة عليها |
|--------------|-------|------------------------|
| `lastWriteWins` | الاحتفاظ بالتغيير الأحدث | rooms, guests, services, employees, pricing_periods |
| `fieldLevel` | دمج الحقول غير الحرجة، الاحتفاظ بالأحدث للحقول الحرجة | bookings, payments, cash_transactions, expenses, debts |
| `manualResolve` | يتطلب مراجعة يدوية | - (احتياطي) |

### الحقول الحرجة المحمية (لا يمكن الكتابة فوقها):

| الجدول | الحقول الحرجة |
|--------|---------------|
| **bookings** | status, checkout_date, total_due_cached, total_paid_cached, remaining_balance_cached, guest_name, is_fully_paid, discount |
| **payments** | amount, payment_date, payment_method, booking_uuid, status, revenue_type |
| **rooms** | status, price, room_number, cleaning_status, requires_maintenance |
| **expenses** | amount, date, category, expense_type, hotel_day_key |
| **debts** | amount, status, due_date, paid_amount, remaining_amount, is_settled |
| **employees** | name, phone, basic_salary, position, status |
| **cash_transactions** | amount, transaction_type, transaction_time |

### الميزات الجديدة:

1. **Vector Clock Manager** - لاكتشاف التعارضات المتزامنة الحقيقية
2. **ConflictManager** - لتتبع التعارضات غير المحلولة
3. **ConflictDetectedException** - استثناء مخصص عند اكتشاف تعارض
4. **ForeignKeyException** - استثناء لأخطاء المفاتيح الخارجية
5. **محاولة حل تلقائي** - قبل طلب المراجعة اليدوية

### كيفية الاستخدام:

```dart
// في المزودات - المدير الجديد يُستخدم تلقائياً
final enhancedSync = ref.watch(enhancedSyncManagerProvider);

// يمكن الوصول للتعارضات المعلقة
final conflicts = ref.watch(conflictManagerProvider);

// حل تعارض يدوياً
await conflictManager.resolveManually(
  conflictId: 'bookings_abc123',
  resolution: mergedData,
);
```

### طريقة العمل:

1. عند السحب من السيرفر، يُقارن كل سجل محلي مع نظيره عن بُعد
2. إذا كانت هناك اختلافات، يُستخدم Vector Clock لتحديد إذا كان التعارض حقيقياً
3. إذا كان التعارض حقيقياً:
   - للجداول العادية: يُستخدم `lastWriteWins`
   - للجداول الحساسة: يُستخدم `fieldLevel` merge (يحافظ على الحقول الحرجة)
4. إذا لم يُحل تلقائياً، يُحفظ في `ConflictManager` للمراجعة

### التكامل مع المزامنة الحالية:

- ✅ يحافظ على توافق كامل مع `OutboxDao`
- ✅ يستخدم نفس `AdapterRegistry`
- ✅ يدعم نفس التدفق: `initialize()` → `sync()` → `dispose()`
- ✅ يُستخدم تلقائياً في `UnifiedSyncOrchestrator`

### الاختبار:

لاختبار نظام التعارضات:

```dart
// محاكاة تعارض
final conflict = ConflictContext(
  table: 'bookings',
  uuid: 'test-uuid',
  localData: {'status': 'checked_in', 'guest_name': 'Local'},
  remoteData: {'status': 'cancelled', 'guest_name': 'Remote'},
  localTimestamp: DateTime.now(),
  remoteTimestamp: DateTime.now().add(Duration(minutes: 5)),
  localDeviceId: 'device1',
  remoteDeviceId: 'device2',
);

final result = conflictResolver.resolve(conflict);
// سيتم اختيار 'cancelled' لأنه أحدث للحقل الحرج 'status'
```
