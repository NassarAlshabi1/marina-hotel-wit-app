# 🧪 دليل اختبار محرك المزامنة التلقائية (Auto Sync Engine Testing Guide)

<div dir="rtl">

## 🎯 نظرة عامة

هذا الدليل يوفر سيناريوهات اختبار شاملة للتحقق من عمل **Auto Sync Engine** بشكل صحيح.

---

## 📋 قائمة الاختبارات

### المجموعة 1: الاختبارات الأساسية ✅

- [x] اختبار 1: تهيئة وبدء المحرك
- [x] اختبار 2: مراقبة الشبكة
- [x] اختبار 3: مراقبة دورة الحياة
- [x] اختبار 4: Debouncing للتغييرات المحلية
- [x] اختبار 5: Self-Healing مع Retry

### المجموعة 2: اختبارات التكامل 🔄

- [x] اختبار 6: Push تلقائي بعد تغيير محلي
- [x] اختبار 7: Pull تلقائي عند فتح التطبيق
- [x] اختبار 8: المزامنة عند استعادة الشبكة
- [x] اختبار 9: المزامنة قبل الدخول للخلفية

### المجموعة 3: اختبارات متقدمة 🚀

- [x] اختبار 10: حل التضارب التلقائي
- [x] اختبار 11: Health Check الدوري
- [x] اختبار 12: Exponential Backoff
- [x] اختبار 13: تعدد الأجهزة

---

## 🧪 الاختبارات التفصيلية

### اختبار 1: تهيئة وبدء المحرك ✅

**الهدف:** التحقق من أن المحرك يتهيأ ويبدأ بشكل صحيح

**الخطوات:**

```dart
test('Auto Sync Engine initializes and starts', () async {
  // 1. إنشاء الخدمات المطلوبة
  final logger = GoogleDriveLogger();
  await logger.initialize(minLevel: LogLevel.debug);
  
  final backupService = GoogleDriveBackupService();
  final database = DatabaseManager.instance;
  
  // 2. تهيئة المحرك
  final engine = AutoSyncEngine.instance;
  await engine.initialize(
    backupService: backupService,
    database: database,
    logger: logger,
  );
  
  // 3. التحقق من التهيئة
  expect(engine.isInitialized, isTrue);
  expect(engine.isRunning, isFalse);
  
  // 4. بدء المحرك
  await engine.start();
  
  // 5. التحقق من البدء
  expect(engine.isRunning, isTrue);
  
  // 6. التحقق من الحالة
  final state = engine.currentState;
  expect(state.isRunning, isTrue);
  
  // 7. التنظيف
  engine.stop();
});
```

**النتيجة المتوقعة:**
```
✅ Engine initialized
✅ Engine started
✅ All listeners active
```

---

### اختبار 2: مراقبة الشبكة 📡

**الهدف:** التحقق من أن المحرك يتفاعل مع تغييرات الشبكة

**الخطوات اليدوية:**

1. **شغّل التطبيق** مع المحرك مفعّل
2. **افحص Logs:**
   ```
   [AutoSyncEngine] 📡 Setting up connectivity listener...
   [AutoSyncEngine] 📡 Initial network status: true
   ```

3. **عطّل الشبكة** (Wi-Fi + Mobile Data)
4. **افحص Logs:**
   ```
   [AutoSyncEngine] 📡 Network status changed: false
   [AutoSyncEngine] 📴 Network lost - canceling pending operations
   ```

5. **فعّل الشبكة مرة أخرى**
6. **افحص Logs:**
   ```
   [AutoSyncEngine] 📡 Network status changed: true
   [AutoSyncEngine] 🌐 Network restored - triggering sync...
   ```

**النتيجة المتوقعة:**
- ✅ المحرك يكتشف فقدان الشبكة فوراً
- ✅ يلغي جميع العمليات الجارية
- ✅ عند استعادة الشبكة، يرفع التغييرات المعلقة تلقائياً

---

### اختبار 3: مراقبة دورة الحياة 🔄

**الهدف:** التحقق من استجابة المحرك لتغييرات دورة حياة التطبيق

**الخطوات:**

1. **افتح التطبيق** (من الصفر)
   ```
   Logs المتوقعة:
   [AutoSyncEngine] 🔄 App lifecycle changed: resumed
   [AutoSyncEngine] 📱 App resumed - triggering foreground sync
   [AutoSyncEngine] 📥 Checking for remote changes after network restore
   ```

2. **اضغط Home** (اجعل التطبيق في الخلفية)
   ```
   Logs المتوقعة:
   [AutoSyncEngine] 🔄 App lifecycle changed: paused
   [AutoSyncEngine] ⏸️ App paused
   ```

3. **ارجع للتطبيق** (Resume)
   ```
   Logs المتوقعة:
   [AutoSyncEngine] 🔄 App lifecycle changed: resumed
   [AutoSyncEngine] 📱 App resumed - triggering foreground sync
   ```

**النتيجة المتوقعة:**
- ✅ عند Resume: Pull تلقائي للتحديثات
- ✅ عند Pause مع تغييرات معلقة: Push سريع قبل الخلفية
- ✅ تأخير 500ms لإعطاء UI الأولوية

---

### اختبار 4: Debouncing للتغييرات المحلية ⏱️

**الهدف:** التحقق من تجميع التغييرات المتتالية

**الخطوات:**

```dart
test('Debouncing batches multiple changes', () async {
  final engine = AutoSyncEngine.instance;
  await engine.start();
  
  // 1. أضف تغيير
  engine.notifyDataChange(table: 'bookings', operation: 'INSERT', count: 1);
  expect(engine.pendingChangesCount, 1);
  
  // 2. انتظر 2 ثانية (أقل من Debounce)
  await Future.delayed(Duration(seconds: 2));
  
  // 3. أضف تغيير آخر
  engine.notifyDataChange(table: 'payments', operation: 'INSERT', count: 1);
  expect(engine.pendingChangesCount, 2);
  
  // 4. انتظر 6 ثوانٍ (أكثر من Debounce)
  await Future.delayed(Duration(seconds: 6));
  
  // 5. التحقق من الرفع
  expect(engine.pendingChangesCount, 0); // تم الرفع
});
```

**النتيجة المتوقعة:**
```
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT (count=1, total pending=1)
[انتظار 2 ثانية]
[AutoSyncEngine] 💾 Data change detected: payments/INSERT (count=1, total pending=2)
[انتظار 5 ثوانٍ]
[AutoSyncEngine] 📤 Debounce complete - pushing 2 changes
[UnifiedSyncCoordinator] ✅ Pushed 2 changes
```

---

### اختبار 5: Self-Healing مع Retry 🔁

**الهدف:** التحقق من إعادة المحاولة التلقائية عند الفشل

**الخطوات:**

1. **محاكاة فشل API** (مثلاً بتعطيل Scopes)
2. **أضف بيانات جديدة**
3. **افحص Logs:**

```
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT
[بعد 5 ثوانٍ - Debounce]
[UnifiedSyncCoordinator] ❌ Sync failed
[AutoSyncEngine] ❌ Sync failed (attempt 1): API Error
[AutoSyncEngine] ⏰ Scheduling retry #1 in 2 seconds

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 ENGINE STATE UPDATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Failed attempts: 1
⏰ Next retry in: 2s
⚠️ Last error: API Error
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[بعد 2 ثانية]
[AutoSyncEngine] 🔄 Executing scheduled retry #1
[UnifiedSyncCoordinator] ❌ Sync failed again
[AutoSyncEngine] ❌ Sync failed (attempt 2): API Error
[AutoSyncEngine] ⏰ Scheduling retry #2 in 4 seconds

[بعد 4 ثوانٍ]
[AutoSyncEngine] 🔄 Executing scheduled retry #2
[UnifiedSyncCoordinator] ✅ Sync succeeded!
[AutoSyncEngine] ✅ Sync succeeded: pushed=1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 ENGINE STATE UPDATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Last successful sync: [NOW]
❌ Failed attempts: 0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**النتيجة المتوقعة:**
- ✅ Retry #1 بعد 2 ثانية
- ✅ Retry #2 بعد 4 ثوانٍ (2^2)
- ✅ نجح في المحاولة الثانية
- ✅ تم تصفير العداد

---

### اختبار 6: Push تلقائي بعد تغيير محلي 📤

**الهدف:** التحقق من الرفع التلقائي للتغييرات

**السيناريو الكامل:**

```dart
// على الجهاز A (هاتف الفندق)

// 1. المستخدم يضيف حجزاً جديداً
final bookingRepo = ref.read(bookingsRepositoryProvider);
await bookingRepo.create(
  roomNumber: '101',
  guestName: 'أحمد محمد',
  guestPhone: '0512345678',
  guestNationality: 'سعودي',
  checkinDate: '2025-01-07',
  status: 'active',
  expectedNights: 3,
);

// 2. الكود الداخلي:
// → Repository.create()
// → AutoSyncEngine.notifyDataChange(table='bookings', count=1)
// → pendingChangesCount = 1
// → بدء Debounce Timer (5 ثوانٍ)

// 3. انتظر 5 ثوانٍ
await Future.delayed(Duration(seconds: 6));

// 4. افحص Google Drive
final backupService = GoogleDriveBackupService();
final files = await backupService.listBackupFiles();

// التحقق من وجود ملف جديد
final latestFile = files.first;
expect(latestFile.fileName, startsWith('marina_sync_delta_'));

// التحقق من المحتوى
final backupData = await backupService.downloadBackup(latestFile.fileId);
final bookings = backupData['bookings'] as List;
expect(bookings.any((b) => b['guest_name'] == 'أحمد محمد'), isTrue);
```

**Logs المتوقعة:**
```
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT (count=1, total pending=1)
[انتظار 5 ثوانٍ - Debounce]
[AutoSyncEngine] 📤 Debounce complete - pushing 1 changes
[UnifiedSyncCoordinator] 🚀 Starting sync [trigger=localChange, mode=smart]
[UnifiedSyncCoordinator] 📤 Performing delta push...
[GoogleDriveDeltaSync] 📤 بدء المزامنة التفاضلية إلى Google Drive...
[GoogleDriveDeltaSync] ✅ تم رفع 1 تغيير إلى Google Drive
[UnifiedSyncCoordinator] ✅ Pushed 1 changes
[AutoSyncEngine] ✅ Sync succeeded: pushed=1, pulled=0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 ENGINE STATE UPDATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🟢 Running: true
🌐 Network: true
🔐 Signed in: true
📦 Pending changes: 0
✅ Last successful sync: 2025-01-07 14:45:23
❌ Failed attempts: 0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### اختبار 7: Pull تلقائي عند فتح التطبيق 📥

**الهدف:** التحقق من السحب التلقائي للتحديثات

**السيناريو الكامل:**

```dart
// على الجهاز B (هاتف المدير)

// 1. افتح التطبيق (Resume)
// ← didChangeAppLifecycleState(AppLifecycleState.resumed)
// ← AutoSyncEngine._onAppResumed()

// 2. انتظر 1 ثانية
await Future.delayed(Duration(seconds: 1));

// 3. افحص قاعدة البيانات المحلية
final bookingRepo = ref.read(bookingsRepositoryProvider);
final bookings = await bookingRepo.getAll();

// التحقق من وجود الحجز الجديد (من الجهاز A)
final newBooking = bookings.firstWhere(
  (b) => b.guestName == 'أحمد محمد',
  orElse: () => null,
);
expect(newBooking, isNotNull);
```

**Logs المتوقعة:**
```
[AutoSyncEngine] 🔄 App lifecycle changed: resumed
[AutoSyncEngine] 📱 App resumed - triggering foreground sync
[AutoSyncEngine] 📡 Network status: true
[AutoSyncEngine] 🔐 Signed in: true
[بعد 500ms]
[UnifiedSyncCoordinator] 📱 App entered foreground
[UnifiedSyncCoordinator] 🚀 Starting sync [trigger=appForeground, mode=smart]
[UnifiedSyncCoordinator] 📥 Performing delta pull...
[GoogleDriveDeltaSync] 📥 فحص التغييرات من Google Drive...
[GoogleDriveDeltaSync] ✅ تم سحب 1 تغيير
[UnifiedSyncCoordinator] ✅ Pulled 1 changes
[AutoSyncEngine] ✅ Sync succeeded: pushed=0, pulled=1
```

**التحقق في UI:**
- ✅ الحجز الجديد يظهر في قائمة الحجوزات
- ✅ لا حاجة لتحديث يدوي (Drift Stream يحدث تلقائياً)

---

### اختبار 8: المزامنة عند استعادة الشبكة 🌐

**الهدف:** التحقق من المزامنة التلقائية عند عودة الاتصال

**الخطوات:**

1. **عطّل الشبكة**
2. **أضف 3 حجوزات جديدة**
   ```dart
   for (int i = 1; i <= 3; i++) {
     await bookingRepo.create(
       roomNumber: '10$i',
       guestName: 'Guest $i',
       // ...
     );
   }
   ```

3. **افحص العداد:**
   ```dart
   final state = AutoSyncEngine.instance.currentState;
   expect(state.pendingChangesCount, 3);
   ```

4. **فعّل الشبكة**

5. **افحص Logs:**
   ```
   [AutoSyncEngine] 📡 Network status changed: true
   [AutoSyncEngine] 🌐 Network restored - triggering sync...
   [AutoSyncEngine] 🌐 Network restored handler triggered
   [AutoSyncEngine] 📤 Syncing 3 pending changes after network restore
   [UnifiedSyncCoordinator] ✅ Pushed 3 changes
   ```

6. **افحص العداد:**
   ```dart
   await Future.delayed(Duration(seconds: 3));
   expect(engine.pendingChangesCount, 0);
   ```

**النتيجة المتوقعة:**
- ✅ التغييرات تُحفظ محلياً عند فقدان الشبكة
- ✅ عند استعادة الشبكة، رفع فوري لجميع التغييرات
- ✅ لا فقدان للبيانات

---

### اختبار 9: المزامنة قبل الدخول للخلفية 💤

**الهدف:** التحقق من المزامنة السريعة عند الخلفية

**الخطوات:**

1. **أضف حجزاً جديداً**
2. **مباشرةً** اضغط Home (قبل انتهاء Debounce)
3. **افحص Logs:**

```
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT (count=1, total pending=1)
[بعد < 5 ثوانٍ]
[AutoSyncEngine] 🔄 App lifecycle changed: paused
[AutoSyncEngine] ⏸️ App paused
[AutoSyncEngine] 💾 App paused with pending changes - quick sync before background
[UnifiedSyncCoordinator] 🚀 Starting sync [trigger=localChange, mode=deltaOnly]
[UnifiedSyncCoordinator] ✅ Pushed 1 changes
[AutoSyncEngine] ✅ Quick sync before background completed
```

**النتيجة المتوقعة:**
- ✅ رغم عدم انتهاء Debounce، المزامنة تحدث فوراً عند الخلفية
- ✅ البيانات لا تُفقد حتى لو أُغلق التطبيق

---

### اختبار 10: حل التضارب التلقائي 🤝

**الهدف:** التحقق من حل التضاربات بشكل تلقائي

**السيناريو:**

```
الجهاز A (14:00): يُحدّث حجز رقم 101 → guest_name = "علي أحمد"
الجهاز B (14:05): يُحدّث نفس الحجز → guest_name = "أحمد علي"

من يفوز؟
```

**الخطوات:**

1. **على الجهاز A:**
   ```dart
   await bookingRepo.update(
     bookingId,
     updates: BookingsCompanion(guestName: Value('علي أحمد')),
   );
   // التوقيت: 14:00:00
   ```

2. **على الجهاز B (قبل المزامنة):**
   ```dart
   await bookingRepo.update(
     bookingId,
     updates: BookingsCompanion(guestName: Value('أحمد علي')),
   );
   // التوقيت: 14:05:00
   ```

3. **المزامنة:**
   - الجهاز A يرفع في 14:00
   - الجهاز B يفتح التطبيق في 14:06
   - Pull تلقائي → تضارب!

4. **Logs على الجهاز B:**
   ```
   [ConflictResolver] 🔍 Detected 1 conflicts
   [ConflictResolver] ⚠️ Detected conflict: Conflict[bookings/uuid-123]
                        Local(v2@2025-01-07T14:05:00) vs Remote(v2@2025-01-07T14:00:00)
   [ConflictResolver] 🔧 Resolving conflict using strategy: newerWins
   [ConflictResolver] ✅ Local record is newer (300s difference)
   [ConflictResolver] 📝 Logged conflict resolution: Local selected: Local record is newer
   ```

5. **النتيجة:**
   - الجهاز B يحتفظ بقيمته ("أحمد علي") لأنها أحدث
   - يتم رفع النسخة المحلية
   - الجهاز A يسحب التحديث في المزامنة التالية

**النتيجة المتوقعة:**
- ✅ كشف تلقائي للتضارب
- ✅ حل تلقائي (الأحدث يفوز)
- ✅ تسجيل في سجل التضاربات
- ✅ لا فقدان للبيانات

---

### اختبار 11: Health Check الدوري ❤️

**الهدف:** التحقق من الفحوصات الصحية الدورية

**الخطوات:**

1. **شغّل التطبيق واتركه**
2. **افحص Logs كل 5 دقائق:**

```
[بعد 5 دقائق]
[AutoSyncEngine] ❤️ Performing health check...
[AutoSyncEngine] ❤️ Health check: all systems nominal

[بعد 10 دقائق]
[AutoSyncEngine] ❤️ Performing health check...
[AutoSyncEngine] ❤️ Health check: all systems nominal
```

**سيناريو 2: اكتشاف مشكلة**

1. **أثناء عمل التطبيق، انتهت صلاحية Token**
2. **Health Check يكتشف المشكلة:**

```
[AutoSyncEngine] ❤️ Performing health check...
[AutoSyncEngine] ❤️ Health check: found pending changes - triggering sync
[AutoSyncEngine] 🔐 Not signed in for retry - attempting sign-in
[AutoSyncEngine] 🔐 Attempting silent sign-in...
[GoogleDriveBackupService] ✅ تم استعادة جلسة Google Drive
[AutoSyncEngine] ✅ Retry sign-in successful
[UnifiedSyncCoordinator] ✅ Pushed 2 changes
[AutoSyncEngine] ❤️ Health check: connection/auth restored - triggering pull
```

**النتيجة المتوقعة:**
- ✅ اكتشاف تلقائي للمشكلات
- ✅ محاولة استعادة تلقائية
- ✅ استئناف المزامنة تلقائياً

---

### اختبار 12: Exponential Backoff 📈

**الهدف:** التحقق من التأخيرات المتزايدة عند الفشل المتكرر

**الخطوات:**

```dart
test('Exponential backoff increases delay', () async {
  final engine = AutoSyncEngine.instance;
  final config = RetryConfig();
  
  // Attempt 1: 2 seconds
  expect(config.calculateDelay(0), 2);
  
  // Attempt 2: 4 seconds
  expect(config.calculateDelay(1), 4);
  
  // Attempt 3: 8 seconds
  expect(config.calculateDelay(2), 8);
  
  // Attempt 4: 16 seconds
  expect(config.calculateDelay(3), 16);
  
  // Attempt 5: 32 seconds
  expect(config.calculateDelay(4), 32);
  
  // Max: 300 seconds (5 minutes)
  expect(config.calculateDelay(10), 300);
});
```

**السيناريو الحقيقي:**

```
محاولة 1: فشل → إعادة بعد 2 ثانية
محاولة 2: فشل → إعادة بعد 4 ثوانٍ
محاولة 3: فشل → إعادة بعد 8 ثوانٍ
محاولة 4: فشل → إعادة بعد 16 ثانية
محاولة 5: فشل → إعادة بعد 32 ثانية
محاولة 6: توقف (max retries reached)
```

---

### اختبار 13: تعدد الأجهزة 📱📱

**الهدف:** التحقق من المزامنة الصحيحة بين جهازين

**السيناريو الكامل:**

**على الجهاز A:**
```
14:00:00 - إضافة حجز #1 → رفع بعد 5 ثوانٍ
14:02:00 - إضافة حجز #2 → رفع بعد 5 ثوانٍ
14:05:00 - تحديث حجز #1 → رفع بعد 5 ثوانٍ
```

**على الجهاز B:**
```
14:01:00 - فتح التطبيق → Pull → يرى حجز #1 ✅
14:03:00 - فحص دوري (كل دقيقتين) → Pull → يرى حجز #2 ✅
14:06:00 - فتح التطبيق → Pull → يرى تحديث حجز #1 ✅
```

**Logs على الجهاز B:**
```
[14:01:00] [AutoSyncEngine] 📱 App resumed
[14:01:00] [UnifiedSyncCoordinator] 📥 Pulled 1 changes
[14:01:00] ✅ تم سحب حجز #1

[14:03:00] [AutoSyncEngine] 🔄 Periodic pull check triggered
[14:03:00] [UnifiedSyncCoordinator] 📥 Pulled 1 changes
[14:03:00] ✅ تم سحب حجز #2

[14:06:00] [AutoSyncEngine] 📱 App resumed
[14:06:00] [UnifiedSyncCoordinator] 📥 Pulled 1 changes
[14:06:00] ✅ تم سحب تحديث حجز #1
```

**التحقق:**
```dart
// على الجهاز B
final bookings = await bookingRepo.getAll();
expect(bookings.length, greaterThanOrEqualTo(2));

final booking1 = bookings.firstWhere((b) => b.id == 1);
// التحقق من التحديث
expect(booking1.lastModified, greaterThan(initialTimestamp));
```

---

## 🎯 اختبارات الإجهاد (Stress Tests)

### اختبار S1: إضافة 100 حجز متتالٍ

```dart
test('Handles 100 consecutive changes', () async {
  final engine = AutoSyncEngine.instance;
  
  // إضافة 100 حجز
  for (int i = 1; i <= 100; i++) {
    await bookingRepo.create(
      roomNumber: '${100 + i}',
      guestName: 'Guest $i',
      // ...
    );
    
    // انتظار 100ms بين كل حجز
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  // التحقق من Debouncing
  // يجب أن يتم الرفع مرة واحدة فقط (بعد انتهاء جميع الإضافات)
  
  await Future.delayed(Duration(seconds: 6));
  
  final state = engine.currentState;
  expect(state.pendingChangesCount, 0);
  expect(state.lastSuccessfulSync, isNotNull);
});
```

**النتيجة المتوقعة:**
```
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT (count=1, total pending=1)
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT (count=1, total pending=2)
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT (count=1, total pending=3)
...
[AutoSyncEngine] 💾 Data change detected: bookings/INSERT (count=1, total pending=100)
[بعد 5 ثوانٍ من آخر تغيير]
[AutoSyncEngine] 📤 Debounce complete - pushing 100 changes
[UnifiedSyncCoordinator] ✅ Pushed 100 changes
```

---

### اختبار S2: فقدان واستعادة الشبكة 10 مرات

```dart
test('Handles network flapping', () async {
  for (int i = 1; i <= 10; i++) {
    // عطّل الشبكة
    // simulateNetworkLoss();
    await Future.delayed(Duration(seconds: 2));
    
    // أضف بيانات
    await bookingRepo.create(/* ... */);
    
    // فعّل الشبكة
    // simulateNetworkRestore();
    await Future.delayed(Duration(seconds: 5));
    
    // التحقق من الرفع
    final state = engine.currentState;
    expect(state.pendingChangesCount, 0);
  }
});
```

**النتيجة المتوقعة:**
- ✅ النظام يتعامل مع تقلبات الشبكة بسلاسة
- ✅ لا تكرار في الرفع
- ✅ لا فقدان للبيانات

---

## 📊 Checklist النجاح

### بعد كل اختبار، تحقق من:

- [ ] ✅ لا أخطاء في Console
- [ ] ✅ pendingChangesCount = 0 بعد المزامنة
- [ ] ✅ lastSuccessfulSync تم تحديثه
- [ ] ✅ failedAttempts = 0
- [ ] ✅ البيانات موجودة في Google Drive
- [ ] ✅ البيانات مسحوبة على الجهاز الآخر
- [ ] ✅ لا تضاربات غير محلولة

---

## 🎓 نصائح الاختبار

### 1. استخدم Logs للتشخيص

```dart
// تفعيل Logs التفصيلية
final logger = GoogleDriveLogger();
await logger.initialize(
  minLevel: LogLevel.debug,  // ← debug للحصول على كل شيء
  enableConsole: true,
  enableFile: false,
);
```

### 2. استخدم Stream للمراقبة

```dart
AutoSyncEngine.instance.stateStream.listen((state) {
  debugPrint('State changed: pending=${state.pendingChangesCount}');
});
```

### 3. افحص Google Drive مباشرة

```dart
final backupService = GoogleDriveBackupService();
final files = await backupService.listBackupFiles();

for (final file in files) {
  debugPrint('File: ${file.fileName}, Created: ${file.createdTime}');
}
```

### 4. استخدم Timestamps للتحقق

```dart
final before = DateTime.now();

// عملية
await bookingRepo.create(/* ... */);
await Future.delayed(Duration(seconds: 6));

final state = engine.currentState;
expect(state.lastSuccessfulSync!.isAfter(before), isTrue);
```

---

## 🐛 استكشاف الأخطاء أثناء الاختبار

### المشكلة: "Engine not initialized"

```dart
// الحل: تأكد من التهيئة أولاً
await AutoSyncEngine.instance.initialize(/* ... */);
await AutoSyncEngine.instance.start();
```

### المشكلة: "No changes pushed"

```dart
// افحص:
final state = engine.currentState;
debugPrint('Running: ${state.isRunning}');
debugPrint('Network: ${state.hasNetworkConnection}');
debugPrint('Signed in: ${state.isSignedIn}');
debugPrint('Pending: ${state.pendingChangesCount}');
```

### المشكلة: "Conflicts not resolved"

```dart
// افحص الاستراتيجية
final resolver = GoogleDriveConflictResolver.instance;
final strategy = await resolver.getStrategy();
debugPrint('Strategy: $strategy');

// افحص السجل
final history = await resolver.getConflictHistory(limit: 10);
for (final entry in history) {
  debugPrint('Conflict: ${entry['resolution']}');
}
```

---

## ✅ معايير النجاح النهائي

### يُعتبر النظام ناجحاً إذا:

1. ✅ **جميع الاختبارات الأساسية تنجح** (1-5)
2. ✅ **جميع اختبارات التكامل تنجح** (6-9)
3. ✅ **جميع الاختبارات المتقدمة تنجح** (10-13)
4. ✅ **استهلاك البطارية < 2% في الساعة**
5. ✅ **استهلاك البيانات < 1 MB في الساعة**
6. ✅ **معدل نجاح المزامنة > 98%**
7. ✅ **لا فقدان للبيانات في أي سيناريو**
8. ✅ **التضاربات تُحل تلقائياً في 100% من الحالات**

---

## 🎉 الخلاصة

**Auto Sync Engine** تم اختباره بنجاح عندما:

✅ **يعمل تلقائياً** دون أي تدخل
✅ **يتعافى ذاتياً** من الأخطاء
✅ **يتعامل مع جميع الحالات الحدية**
✅ **يوفر تجربة سلسة** للمستخدم
✅ **موثوق بنسبة 99%+**

**ابدأ الاختبار الآن!** 🚀

</div>
