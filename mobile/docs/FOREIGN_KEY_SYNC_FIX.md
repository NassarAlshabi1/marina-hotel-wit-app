# إصلاح أخطاء FOREIGN KEY في المزامنة

## المشكلة

كانت المزامنة تفشل في إدراج الدفعات (payments) والديون (debts) بسبب أخطاء FOREIGN KEY constraint:

```
SqliteException(787): FOREIGN KEY constraint failed
Causing statement: INSERT INTO "payments" (...) VALUES (..., booking_local_id = 12, ...)
```

### السبب

الدفعات تحتوي على `booking_local_id` الذي يشير إلى جدول `bookings` عبر FOREIGN KEY constraint. إذا كان الحجز المشار إليه غير موجود في قاعدة البيانات المحلية، يفشل الإدراج.

هذا يحدث عندما:
1. الحجوزات لم تُزامن من Appwrite بعد
2. الحجوزات محذوفة محلياً أو في Appwrite
3. الحجوزات موجودة محلياً فقط ولم تُرفع إلى Appwrite
4. هناك تأخر في المزامنة بين الأجهزة

## الحل المطبق

### 1. معالجة ذكية للدفعات (`_syncPayments`)

```dart
// المرحلة الأولى: محاولة مزامنة جميع الدفعات
for (final doc in documents) {
  try {
    await _adapterRegistry.payments.upsertFromJson(data, src: Source.appwrite);
    processed++;
  } catch (e) {
    // تأجيل الدفعة إذا كان الخطأ FOREIGN KEY constraint
    if (e.toString().contains('FOREIGN KEY constraint failed')) {
      deferred.add(doc);
    }
  }
}

// المرحلة الثانية: إعادة محاولة الدفعات المؤجلة
if (deferred.isNotEmpty) {
  // محاولة مرة أخرى بعد مزامنة جميع الحجوزات
  for (final doc in deferred) {
    await _adapterRegistry.payments.upsertFromJson(data, src: Source.appwrite);
  }
}
```

### 2. نفس المعالجة للديون (`_syncDebts`)

الديون أيضاً لها FOREIGN KEY على `bookings`، لذا تم تطبيق نفس الحل.

### 3. تحذيرات تشخيصية في `PaymentsAdapter`

```dart
// تحذير إذا فشل حل المرجع
if (resolvedId == null && localId != null) {
  print('[PaymentsAdapter] Warning: Could not resolve booking for localId: $localId');
}
```

## كيف يعمل

1. **ترتيب المزامنة الصحيح:**
   - Rooms → **Bookings** → Employees → Expenses → **Payments** → **Debts**
   - الحجوزات تُزامن قبل الدفعات والديون

2. **معالجة الأخطاء:**
   - عند فشل إدراج دفعة بسبب FOREIGN KEY، تُؤجل الدفعة
   - بعد مزامنة جميع الحجوزات، نعيد محاولة الدفعات المؤجلة
   - إذا فشلت مرة أخرى، تُسجل warning وستحاول في المزامنة التالية

3. **التعافي التلقائي:**
   - الدفعات/الديون المؤجلة ستُزامن في المرة التالية عندما تكون الحجوزات متاحة
   - لا تفقد أي بيانات

## الفوائد

✅ **لا مزيد من أخطاء FOREIGN KEY في logs**
- الأخطاء تُعالج بشكل استباقي وتُؤجل للإعادة

✅ **مزامنة موثوقة**
- البيانات تُزامن في الترتيب الصحيح
- إعادة محاولة تلقائية للبيانات المؤجلة

✅ **تشخيص أفضل**
- Logs واضحة تبين الدفعات المؤجلة
- تحذيرات عند فشل حل المراجع

✅ **تعافي تلقائي**
- البيانات تُزامن في النهاية عندما تكون المراجع متاحة

## اختبار الإصلاح

لاختبار الإصلاح:

1. **سيناريو 1: مزامنة طبيعية**
   - قم بإنشاء حجز ودفعة
   - ارفعهما إلى Appwrite
   - افتح جهاز آخر وقم بالمزامنة
   - يجب أن تُزامن كل البيانات بنجاح

2. **سيناريو 2: دفعة بحجز مفقود**
   - في Appwrite، احذف حجز له دفعات
   - قم بالمزامنة على جهاز جديد
   - يجب أن ترى في logs: `Deferring payment ... FOREIGN KEY constraint`
   - الدفعة ستُؤجل ولن تسبب crash

3. **سيناريو 3: استرجاع تلقائي**
   - أعد الحجز المحذوف إلى Appwrite
   - قم بالمزامنة مرة أخرى
   - يجب أن تُزامن الدفعة بنجاح هذه المرة

## الملفات المعدلة

- `mobile/lib/services/appwrite_sync_manager.dart`: معالجة FOREIGN KEY في `_syncPayments` و `_syncDebts`
- `mobile/lib/services/adapters/payments_adapter.dart`: تحذيرات تشخيصية في `resolveRefs`

## تحسينات مستقبلية محتملة

- 🔄 محاولة جلب الحجوزات المفقودة من Appwrite تلقائياً
- 📊 إحصائيات عن الدفعات المؤجلة في dashboard
- 🔔 إشعارات عندما تفشل دفعة بعد عدة محاولات
- 🗂️ قائمة انتظار دائمة للبيانات المؤجلة (outbox pattern)
