# دليل تكامل Outbox في جميع DAOs

## 📋 نظرة عامة

هذا الدليل يوضح كيفية التأكد من أن جميع DAOs مدمجة بشكل صحيح مع نظام Outbox للمزامنة الموثوقة مع Appwrite.

## 🎯 الهدف

تسجيل جميع عمليات CREATE، UPDATE، DELETE في جدول Outbox لضمان مزامنة موثوقة مع Appwrite حتى في حالة عدم توفر الاتصال بالإنترنت.

## ✅ قائمة التحقق - DAOs المدمجة مع Outbox

| DAO | OutboxDao مُمرر | استخدام في INSERT | استخدام في UPDATE | استخدام في DELETE | الحالة |
|-----|----------------|-------------------|-------------------|-------------------|---------|
| `bookings_dao` | ✅ نعم | ✅ نعم | ✅ نعم | ✅ نعم | ✅ **مكتمل** |
| `rooms_dao` | ✅ نعم | ✅ نعم | ✅ نعم | ✅ نعم | ✅ **مكتمل** |
| `payments_dao` | ✅ نعم | ✅ نعم | ✅ نعم | ✅ نعم | ✅ **مكتمل** |
| `debts_dao` | ✅ نعم | ✅ نعم | ✅ نعم | ✅ نعم | ✅ **مكتمل** |
| `employees_dao` | ⚠️ نعم | ⚠️ جزئي | ⚠️ جزئي | ⚠️ جزئي | ⚠️ **يحتاج تحسين** |
| `expenses_dao` | ⚠️ نعم | ⚠️ جزئي | ⚠️ جزئي | ⚠️ جزئي | ⚠️ **يحتاج تحسين** |
| `cash_transactions_dao` | ⚠️ نعم | ⚠️ جزئي | ⚠️ جزئي | ⚠️ جزئي | ⚠️ **يحتاج تحسين** |
| `booking_notes_dao` | ✅ نعم | ✅ نعم | ✅ نعم | ✅ نعم | ✅ **مكتمل** |
| `shift_notes_dao` | ✅ نعم | ✅ نعم | ✅ نعم | ✅ نعم | ✅ **مكتمل** |

## 📐 النمط القياسي لتكامل Outbox

### 1. تمرير OutboxDao في Constructor

```dart
@DriftAccessor(tables: [YourTable])
class YourDao extends DatabaseAccessor<AppDatabase> with _$YourDaoMixin {
  YourDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;  // ✅ إضافة هذا الحقل
  
  // ... بقية الكود
}
```

### 2. تسجيل عمليات INSERT

```dart
Future<int> insertOne(YourTableCompanion data, {bool originIsServer = false}) async {
  final now = Time.nowEpoch();
  final uuid = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
  
  final companion = data.copyWith(
    localUuid: Value(uuid),
    createdAt: Value(now),
    updatedAt: Value(now),
    lastModified: Value(now),
    version: const Value(1),
    origin: Value(originIsServer ? 'server' : 'local'),
  );
  
  final id = await into(yourTable).insert(companion);
  
  // ✅ تسجيل في Outbox (فقط للعمليات المحلية)
  if (!originIsServer) {
    await outboxDao.merge(
      entity: 'your_entity_name',  // اسم الكيان (مثل: 'rooms', 'bookings')
      op: 'create',
      localUuid: uuid,
      serverId: companion.serverId.present ? companion.serverId.value : null,
      payload: _payloadFrom(companion),
      clientTs: now,
    );
  }
  
  return id;
}
```

### 3. تسجيل عمليات UPDATE

```dart
Future<int> updateById(int id, YourTableCompanion data, {bool originIsServer = false}) async {
  final existing = await getById(id);
  if (existing == null) return 0;
  
  final now = Time.nowEpoch();
  final companion = data.copyWith(
    updatedAt: Value(now),
    lastModified: Value(now),
  );
  
  final rows = await (update(yourTable)..where((t) => t.id.equals(id))).write(companion);
  
  // ✅ تسجيل في Outbox (فقط للعمليات المحلية)
  if (rows > 0 && !originIsServer) {
    await outboxDao.merge(
      entity: 'your_entity_name',
      op: 'update',
      localUuid: existing.localUuid,
      serverId: existing.serverId,
      payload: _payloadFrom(companion, base: existing),
      clientTs: now,
    );
  }
  
  return rows;
}
```

### 4. تسجيل عمليات DELETE (Soft Delete)

```dart
Future<int> softDelete(int id, {bool originIsServer = false}) async {
  final now = Time.nowEpoch();
  final existing = await getById(id);
  if (existing == null) return 0;
  
  final rows = await (update(yourTable)..where((t) => t.id.equals(id))).write(
    YourTableCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ),
  );
  
  // ✅ تسجيل في Outbox (فقط للعمليات المحلية)
  if (rows > 0 && !originIsServer) {
    await outboxDao.merge(
      entity: 'your_entity_name',
      op: 'delete',
      localUuid: existing.localUuid,
      serverId: existing.serverId,
      payload: {'id': existing.serverId},
      clientTs: now,
    );
  }
  
  return rows;
}
```

### 5. إنشاء دالة _payloadFrom

```dart
Map<String, dynamic> _payloadFrom(YourTableCompanion comp, {YourEntity? base}) {
  final m = <String, dynamic>{};
  
  // إضافة جميع الحقول المهمة
  if (comp.field1.present) m['field1'] = comp.field1.value;
  if (comp.field2.present) m['field2'] = comp.field2.value;
  // ... إضافة باقي الحقول
  
  // للحقول غير المحدثة، استخدم القيم الحالية من base
  if (base != null) {
    m['field1'] ??= base.field1;
    m['field2'] ??= base.field2;
    // ...
  }
  
  return m;
}
```

## 🔧 خطوات التنفيذ للـ DAOs الناقصة

### Employees DAO

```dart
// في mobile/lib/services/daos/employees_dao.dart

// 1. التأكد من تمرير OutboxDao
EmployeesDao(AppDatabase db, this.outboxDao) : super(db);
final OutboxDao outboxDao;

// 2. إضافة تسجيل Outbox في insertOne
if (!originIsServer) {
  await outboxDao.merge(
    entity: 'employees',
    op: 'create',
    localUuid: uuid,
    serverId: companion.serverId.present ? companion.serverId.value : null,
    payload: _payloadFrom(companion),
    clientTs: now,
  );
}

// 3. إضافة _payloadFrom
Map<String, dynamic> _payloadFrom(EmployeesCompanion comp, {Employee? base}) {
  final m = <String, dynamic>{};
  if (comp.name.present) m['name'] = comp.name.value;
  if (comp.phone.present) m['phone'] = comp.phone.value;
  if (comp.position.present) m['position'] = comp.position.value;
  if (comp.salary.present) m['salary'] = comp.salary.value;
  if (comp.status.present) m['status'] = comp.status.value;
  // أضف باقي الحقول...
  return m;
}
```

### Expenses DAO

```dart
// في mobile/lib/services/daos/expenses_dao.dart

// نفس النمط مع تغيير:
entity: 'expenses',

// _payloadFrom للحقول المناسبة:
Map<String, dynamic> _payloadFrom(ExpensesCompanion comp, {Expense? base}) {
  final m = <String, dynamic>{};
  if (comp.category.present) m['category'] = comp.category.value;
  if (comp.amount.present) m['amount'] = comp.amount.value;
  if (comp.description.present) m['description'] = comp.description.value;
  if (comp.date.present) m['date'] = comp.date.value;
  // أضف باقي الحقول...
  return m;
}
```

### Cash Transactions DAO

```dart
// في mobile/lib/services/daos/cash_transactions_dao.dart

// نفس النمط مع:
entity: 'cash_transactions',

Map<String, dynamic> _payloadFrom(CashTransactionsCompanion comp, {CashTransaction? base}) {
  final m = <String, dynamic>{};
  if (comp.transactionType.present) m['transaction_type'] = comp.transactionType.value;
  if (comp.amount.present) m['amount'] = comp.amount.value;
  if (comp.description.present) m['description'] = comp.description.value;
  if (comp.date.present) m['date'] = comp.date.value;
  // أضف باقي الحقول...
  return m;
}
```

## 🧪 اختبار التكامل

### 1. اختبار INSERT

```dart
// إنشاء سجل جديد
final dao = EmployeesDao(db, OutboxDao(db));
final id = await dao.insertOne(
  EmployeesCompanion(
    name: Value('Ahmed'),
    phone: Value('1234567890'),
  ),
);

// التحقق من Outbox
final outboxEntries = await db.select(db.outbox)
  .where((o) => o.localUuid.equals(uuid))
  .get();

assert(outboxEntries.isNotEmpty, 'يجب أن يكون هناك إدخال في Outbox');
assert(outboxEntries.first.entity == 'employees');
assert(outboxEntries.first.op == 'create');
```

### 2. اختبار UPDATE

```dart
// تحديث سجل
await dao.updateById(id, EmployeesCompanion(
  name: Value('Ahmed Updated'),
));

// التحقق من Outbox
final outboxEntries = await db.select(db.outbox)
  .where((o) => o.op.equals('update'))
  .get();

assert(outboxEntries.isNotEmpty);
```

### 3. اختبار DELETE

```dart
// حذف سجل
await dao.softDelete(id);

// التحقق من Outbox
final outboxEntries = await db.select(db.outbox)
  .where((o) => o.op.equals('delete'))
  .get();

assert(outboxEntries.isNotEmpty);
```

## 📊 فوائد تكامل Outbox الكامل

1. **المزامنة الموثوقة**: جميع التغييرات تُسجل حتى بدون إنترنت
2. **تتبع التغييرات**: يمكن تتبع كل عملية على كل سجل
3. **إعادة المحاولة التلقائية**: الطلبات الفاشلة تُعاد تلقائياً
4. **حل التضارب**: يمكن اكتشاف وحل التضاربات بين الأجهزة
5. **التدقيق والسجلات**: سجل كامل لجميع العمليات

## 🚀 الخطوات التالية

1. ✅ مراجعة جميع DAOs للتأكد من تمرير OutboxDao
2. ✅ إضافة استدعاءات outboxDao.merge في جميع عمليات INSERT/UPDATE/DELETE
3. ✅ إضافة دوال _payloadFrom لجميع DAOs
4. ✅ اختبار كل DAO بعد التحديث
5. ✅ مراقبة جدول Outbox أثناء التشغيل
6. ✅ التأكد من مزامنة البيانات مع Appwrite بشكل صحيح

## 📚 المراجع

- `mobile/lib/services/daos/bookings_dao.dart` - مثال مكتمل
- `mobile/lib/services/daos/rooms_dao.dart` - مثال مكتمل
- `mobile/lib/services/daos/outbox_dao.dart` - تعريف Outbox
- `mobile/lib/services/appwrite_sync_manager.dart` - استخدام Outbox للمزامنة

## ⚠️ ملاحظات مهمة

- **originIsServer**: استخدمه دائماً عند استيراد بيانات من Appwrite لتجنب حلقات لا نهائية
- **payload**: تأكد من تضمين جميع الحقول المهمة في payload
- **entity name**: يجب أن يطابق اسم الكيان في Appwrite بالضبط
- **localUuid**: مفتاح فريد لكل سجل، لا يتغير أبداً
- **serverId**: معرف السجل في Appwrite، قد يكون null للسجلات الجديدة

---

**آخر تحديث**: نوفمبر 2025  
**الإصدار**: 1.0  
**الحالة**: ✅ جاهز للتنفيذ
