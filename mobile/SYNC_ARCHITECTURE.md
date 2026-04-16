# بنية المزامنة المتقدمة - Marina Hotel Mobile

## نظرة عامة

تم إعادة هندسة نظام المزامنة بالكامل ليكون أكثر موثوقية وكفاءة. يعتمد النظام الجديد على بنية موحدة مع فصل واضح للمسؤوليات.

## البنية التحتية الجديدة

### 1. المكونات الرئيسية

```
┌─────────────────────────────────────────────────────────────┐
│                      SyncOrchestrator                        │
│                   (المدير الرئيسي للمزامنة)                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ PushEngine  │ │ PullEngine  │ │ConflictRes. │
│   (رفع)     │ │   (سحب)     │ │ (حل النزاع)│
└─────────────┘ └─────────────┘ └─────────────┘
       │               │               │
       └───────────────┴───────────────┘
                       │
               ┌───────▼───────┐
               │   OutboxDao   │
               │ (قاعدة البيانات)│
               └───────────────┘
```

### 2. المميزات الرئيسية

#### 🔄 آلية المزامنة الموحدة
- **SyncOrchestrator**: مدير مركزي يتعامل مع Push و Pull وحل النزاعات
- فصل واضح بين عمليات الرفع والسحب
- إدارة متقدمة للحالة باستخدام Freezed

#### 🛡️ نظام الحماية والمراقبة
- **Retry Strategy**: استراتيجية إعادة المحاولة المتقدمة
- **Batch Processing**: معالجة دفعات الكائنات الكبيرة
- **Analytics Service**: تتبع وتحليل أحداث المزامنة
- **Crashlytics Service**: تسجيل الأخطاء والتحطم

#### ⚡ تحسينات الأداء
- معالجة الدفعات لعدد كبير من الكائنات
- تحسين استهلاك البطارية
- مؤشرات تصاعدية للتحميل

#### 📊 نماذج البيانات المحدثة
```dart
@freezed
class SyncOperation with _$SyncOperation {
  factory SyncOperation({
    required String id,
    required String tableName,
    required SyncOperationType type,
    required Map<String, dynamic> data,
    required DateTime timestamp,
    @Default(SyncStatus.pending) SyncStatus status,
    @Default(0) int retryCount,
  }) = _SyncOperation;
}
```

### 3. الاستخدام

#### المزامنة اليدوية
```dart
final syncManager = SmartSyncManager();
await syncManager.initialize();

// بدء مزامنة كاملة
await syncManager.syncNow(context);
```

#### المزامنة التلقائية
```dart
// في main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // بدء مزامنة تلقائية
  final syncManager = SmartSyncManager();
  syncManager.startAutoSync();
  
  runApp(MyApp());
}
```

#### التعامل مع النزاعات
```dart
// عرض النزاعات
final conflicts = await SmartSyncManager().getConflicts();

// حل نزاع معين
await SmartSyncManager().resolveConflict(
  operationId: conflictId,
  resolution: ConflictResolution.serverWins,
);
```

### 4. الأحداث المدعومة

| الحدث | الوصف |
|-------|-------|
| `syncStarted` | بدء عملية المزامنة |
| `syncCompleted` | اكتمال المزامنة بنجاح |
| `syncFailed` | فشل المزامنة |
| `dataPushed` | رفع البيانات |
| `dataPulled` | سحب البيانات |
| `conflictResolved` | حل نزاع |
| `batchPushCompleted` | اكتمال دفعة |
| `retryAttempt` | محاولة إعادة |

### 5. الإعدادات

#### Firebase
```yaml
dependencies:
  firebase_core: ^3.10.0
  firebase_analytics: ^11.4.0
  firebase_crashlytics: ^4.3.0
```

#### إعداد Firebase
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // تهيئة الخدمات
  await AnalyticsService().initialize();
  await CrashlyticsService().initialize();
  
  runApp(MyApp());
}
```

## الهيكل الجديد

```
lib/
├── services/
│   ├── sync/
│   │   ├── sync_orchestrator.dart      # المدير الرئيسي
│   │   ├── push_engine.dart            # محرك الرفع
│   │   ├── pull_engine.dart            # محرك السحب
│   │   ├── conflict_resolver.dart      # حل النزاعات
│   │   ├── retry_strategy.dart         # استراتيجية إعادة المحاولة
│   │   ├── batch_processor.dart        # معالج الدفعات
│   │   └── sync_state.dart             # حالات المزامنة (Freezed)
│   ├── analytics_service.dart          # خدمة التحليلات
│   ├── crashlytics_service.dart        # خدمة الأخطاء
│   └── smart_sync_manager.dart         # المدير الذكي
├── widgets/
│   ├── sync_status_bar.dart            # شريط الحالة
│   └── enhanced_sync_button.dart       # زر المزامنة المتقدم
└── providers/
    └── enhanced_sync_provider.dart     # Provider محدث
```

## الترحيل من النظام القديم

### اختصارات API

| القديم | الجديد |
|--------|--------|
| `SyncService.syncNow()` | `SmartSyncManager().syncNow()` |
| `SyncService.checkConnectivity()` | `SmartSyncManager().isOnline()` |
| `OutboxDao.getPendingCount()` | `SmartSyncManager().getPendingCount()` |
| `SyncService.getLastSync()` | `SmartSyncManager().lastSyncTime` |

## أفضل الممارسات

### 1. دائمًا تحقق من الاتصال
```dart
if (await SmartSyncManager().isOnline()) {
  await SmartSyncManager().syncNow(context);
}
```

### 2. التعامل مع الأخطاء
```dart
try {
  await SmartSyncManager().syncNow(context);
} on SyncException catch (e) {
  // معالجة خطأ المزامنة
  showSyncErrorDialog(context, e.message);
}
```

### 3. المزامنة في الخلفية
```dart
// استخدم WorkManager للمزامنة الدورية
Workmanager().registerPeriodicTask(
  'sync-task',
  'backgroundSync',
  frequency: Duration(minutes: 15),
);
```

## المشاكل الشائعة وحلولها

### 1. فشل المزامنة باستمرار
```dart
// تفعيل وضع التصحيح
SmartSyncManager().setLogLevel(LogLevel.verbose);

// مراقبة الأخطاء
CrashlyticsService().getErrorHistory();
```

### 2. بطء المزامنة
```dart
// تقليل حجم الدفعة
BatchProcessor.setBatchSize(50);

// تعطيل المزامنة التلقائية مؤقتًا
SmartSyncManager().stopAutoSync();
```

### 3. استهلاك البطارية
```dart
// تفعيل وضع توفير البطارية
SmartSyncManager().setBatteryOptimized(true);
```

---

**ملاحظة**: هذا التوثيق للنسخة 2.0 من نظام المزامنة. للأسئلة والدعم، يرجى مراجعة فريق التطوير.
