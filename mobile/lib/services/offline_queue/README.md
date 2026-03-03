# نظام قائمة الانتظار للعمليات دون اتصال (Offline Queue System)

## نظرة عامة

نظام متكامل لإدارة العمليات التي تُنفذ عند فقدان الاتصال بالإنترنت، مع معالجة تلقائية عند عودة الاتصال.

## المميزات الرئيسية

- ✅ **تلقائي**: يعمل في الخلفية ويعالج العمليات عند عودة الاتصال
- ✅ **أولويات**: دعم مستويات أولوية مختلفة (حرجة، عالية، عادية، منخفضة)
- ✅ **مجموعات**: تجميع العمليات ذات الصلة معاً
- ✅ **معالجات قابلة للتخصيص**: تسجيل معالجات مخصصة لأنواع مختلفة من العمليات
- ✅ **إعادة محاولة ذكية**: محاولة تلقائية للعمليات الفاشلة مع الكشف عن الأخطاء الدائمة
- ✅ **مراقبة الاتصال**: استجابة فورية لتغيرات حالة الاتصال
- ✅ **واجهة مستخدم**: ويدجتات جاهزة لعرض حالة القائمة

## البنية

```
lib/services/offline_queue/
├── offline_queue_manager.dart    # المدير الرئيسي
├── offline_queue_processor.dart  # معالج العمليات
└── README.md                     # هذا الملف

lib/providers/
└── offline_queue_provider.dart   # Providers لـ Riverpod

lib/widgets/
└── offline_queue_widget.dart     # ويدجتات واجهة المستخدم
```

## الاستخدام الأساسي

### 1. التهيئة

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  await container.read(offlineQueueInitProvider.future);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(),
    ),
  );
}
```

### 2. إضافة عملية إلى القائمة

```dart
final manager = OfflineQueueManager.instance;

await manager.enqueue(
  entity: 'bookings',
  operation: OfflineOperationType.create,
  payload: {
    'roomId': roomId,
    'guestName': name,
    'checkIn': checkInDate.toIso8601String(),
    'checkOut': checkOutDate.toIso8601String(),
  },
  priority: OfflinePriority.high,
);
```

### 3. التعامل مع العمليات دون اتصال

```dart
// التحقق من حالة الاتصال
if (!ConnectivityService.instance.isOnline) {
  // إضافة إلى القائمة وسيتم المعالجة لاحقاً
  await manager.enqueue(
    entity: 'payments',
    operation: OfflineOperationType.create,
    payload: paymentData,
  );

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('سيتم الحفظ عند عودة الاتصال')),
  );
}
```

### 4. استخدام الويدجتات

```dart
// عرض حالة القائمة
AppBar(
  actions: [
    OfflineQueueWidget(),
  ],
)

// أو: زر عائم
Scaffold(
  floatingActionButton: OfflineQueueFab(),
)

// أو: شريط إشعار
Column(
  children: [
    OfflineQueueBanner(),
    Expanded(child: MainContent()),
  ],
)
```

### 5. مراقبة الحالة باستخدام Riverpod

```dart
class MyScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // مراقبة الإحصائيات
    final statsAsync = ref.watch(offlineQueueStatsProvider);

    // مراقبة عدد العمليات المعلقة
    final pendingCount = ref.watch(offlineQueuePendingCountProvider);

    // مراقبة حالة المعالجة
    final isProcessing = ref.watch(offlineQueueProcessingProvider);

    return statsAsync.when(
      data: (stats) => Text('${stats.pendingCount} عملية معلقة'),
      loading: () => CircularProgressIndicator(),
      error: (err, _) => Text('خطأ: $err'),
    );
  }
}
```

### 6. تسجيل معالج مخصص

```dart
final processor = OfflineQueueProcessor.instance;

processor.registerHandler(
  OfflineOperationType.upload,
  (item) async {
    try {
      final filePath = item.payload['filePath'];
      final result = await uploadFileToServer(filePath);
      return OfflineQueueResult.success(result);
    } catch (e) {
      return OfflineQueueResult.failure(
        'فشل الرفع: $e',
        shouldRetry: true,
      );
    }
  },
);
```

### 7. إضافة دفعية من العمليات

```dart
final batchIds = await manager.enqueueBatch([
  OfflineQueueBatchItem(
    entity: 'bookings',
    operation: OfflineOperationType.create,
    payload: bookingData,
  ),
  OfflineQueueBatchItem(
    entity: 'payments',
    operation: OfflineOperationType.create,
    payload: paymentData,
  ),
  OfflineQueueBatchItem(
    entity: 'notifications',
    operation: OfflineOperationType.create,
    payload: notificationData,
    priority: OfflinePriority.low,
  ),
]);

// انتظار اكتمال المجموعة
await manager.waitForGroup(batchIds.first);
```

## أنواع العمليات

| النوع | الوصف |
|-------|--------|
| `create` | إنشاء سجل جديد |
| `update` | تحديث سجل موجود |
| `delete` | حذف سجل |
| `sync` | مزامنة كاملة |
| `upload` | رفع ملف |
| `download` | تحميل ملف |

## مستويات الأولوية

| الأولوية | القيمة | الاستخدام |
|----------|--------|-----------|
| `critical` | 0 | حجوزات، مدفوعات عاجلة |
| `high` | 1 | تحديثات مهمة |
| `normal` | 2 | العمليات العادية |
| `low` | 3 | إشعارات، تحديثات ثانوية |

## Integration مع Outbox

النظام يتكامل مع `OutboxDao` الموجود:

```dart
// يتم تخزين العمليات في جدول Outbox تلقائياً
await _outboxDao.merge(
  entity: item.entity,
  op: item.operation.name,
  localUuid: item.uuid,
  payload: item.payload,
  clientTs: timestamp,
);
```

## API Reference

### OfflineQueueManager

| الدالة | الوصف |
|--------|-------|
| `initialize()` | تهيئة المدير |
| `enqueue()` | إضافة عملية |
| `enqueueBatch()` | إضافة مجموعة |
| `processQueue()` | معالجة يدوية |
| `retryFailed()` | إعادة محاولة الفاشلة |
| `clearCompleted()` | مسح المكتملة |
| `clearAll()` | مسح الكل |
| `getStats()` | الحصول على إحصائيات |
| `waitForGroup()` | انتظار مجموعة |

### Providers

| Provider | النوع | الوصف |
|----------|-------|-------|
| `offlineQueueManagerProvider` | Provider | المدير |
| `offlineQueueStatsProvider` | StreamProvider | الإحصائيات |
| `offlineQueueItemsProvider` | StreamProvider | العناصر |
| `offlineQueueStatusProvider` | Provider | الحالة الموجزة |

### Widgets

| Widget | الوصف |
|--------|-------|
| `OfflineQueueWidget` | عرض الحالة مع Badge |
| `OfflineQueueFab` | زر عائم |
| `OfflineQueueBanner` | شريط إشعار سفلي |
| `OfflineQueueDetailsSheet` | شاشة التفاصيل |

## أفضل الممارسات

1. **استخدم الأولويات بذكاء**: لا تجعل كل شيء `critical`
2. **تجميع العمليات**: استخدم `groupId` للعمليات ذات الصلة
3. **معالجة الأخطاء**: سجل معالجات مناسبة لكل نوع عملية
4. **تنظيف دوري**: استدعِ `clearCompleted()` بشكل دوري
5. **مراقبة الاتصال**: تحقق من `ConnectivityService` قبل العمليات الحرجة
