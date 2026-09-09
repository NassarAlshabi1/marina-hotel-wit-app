# مؤشر المزامنة الحضي (Real-time Sync Indicator)

## 📊 نظرة عامة

مؤشر مزامنة حضي متقدم يعرض حالة نظام المزامنة في الوقت الفعلي مع تحديثات دقيقة كل 100ms.

## ✨ الميزات

### 1. **التحديث الحي (Real-time Updates)**
- تحديثات كل 100ms من `SyncHealthReport`
- رسوم متحركة سلسة مع `AnimationController`
- نبضات بصرية تشير إلى الحالة الحالية

### 2. **ثلاث أوضاع عرض**
```dart
// 1️⃣ مضغوط جداً (للـ AppBar)
RealtimeSyncIndicator(compact: true, showDetailedStats: false)
// → عرض: 24×24px مع icon أساسي

// 2️⃣ مضغوط متوسط (للـ Cards)
RealtimeSyncIndicator(compact: false, showDetailedStats: false)
// → عرض: card بسيط مع شريط تقدم

// 3️⃣ مكامل مفصّل (للشاشات)
RealtimeSyncIndicator(compact: false, showDetailedStats: true)
// → عرض: بطاقة رئيسية + 4 كروت إحصائية
```

### 3. **الإحصائيات المعروضة**
```
┌─────────────────────────────────────────┐
│ 🔵 جاري المزامنة...     [128 معلق]     │  ← رأس البطاقة
├─────────────────────────────────────────┤
│ التقدم: ████████░░ 75%                  │  ← شريط تقدم حي
└─────────────────────────────────────────┘

┌──────────┬──────────┬──────────┬────────┐
│  ⬆️ 256  │  ⏳ 128  │  ❌ 12   │  🕐 3  │  ← الإحصائيات
│ مرفوع   │ معلق    │ فاشل    │ عالق  │
└──────────┴──────────┴──────────┴────────┘
```

### 4. **المؤشرات اللونية**
| الحالة | اللون | الأيقونة |
|-------|------|--------|
| صحي | 🟢 أخضر | ✓ |
| معلق | 🔵 أزرق | ⏳ |
| تحذير | 🟠 برتقالي | ⚠️ |
| خطأ | 🔴 أحمر | ✗ |

### 5. **الرسوم المتحركة**
- **Rotation**: دوران الأيقونة عند المزامنة
- **Scale Pulse**: نبض التوسع للألوان الحية
- **Gradient Fade**: تلاشي متدرج في الخلفيات

## 🔧 طرق الاستخدام

### في AppBar
```dart
AppBar(
  title: const Text('الرئيسية'),
  actions: [
    const AppBarSyncIndicator(),  // مؤشر صغير
    const SizedBox(width: 8),
  ],
)
```

### في Dashboard
```dart
ListView(
  children: [
    const SyncStatusWidget(),  // عرض كامل مع إحصائيات
    const SizedBox(height: 16),
    // باقي محتوى الصفحة
  ],
)
```

### في الأسفل (Bottom Status Bar)
```dart
Scaffold(
  appBar: AppBar(title: const Text('الحجوزات')),
  body: BookingsList(),
  bottomNavigationBar: const SyncStatusBottomBar(),
)
```

### FloatingActionButton
```dart
FloatingActionButton.extended(
  onPressed: () => manualSync(),
  icon: const CompactSyncDot(),
  label: const Text('مزامنة'),
)
```

## 🎨 تخصيص الألوان

لتعديل الألوان، عدّل في `_buildStatCard()`:

```dart
_buildStatCard(
  context,
  icon: Icons.upload,
  label: 'مرفوع',
  value: '256',
  color: Colors.green,  // ← غيّر اللون هنا
)
```

## 📱 أمثلة التكامل

### 1. دمج مع شاشة الإعدادات
```dart
class SettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        actions: const [AppBarSyncIndicator()],
      ),
      body: ListView(
        children: [
          const SyncStatusWidget(),
          const Divider(),
          // إعدادات أخرى
        ],
      ),
    );
  }
}
```

### 2. دمج مع Dashboard
```dart
class Dashboard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const SyncStatusWidget(),
        Expanded(child: BookingsList()),
      ],
    );
  }
}
```

### 3. مؤشر مخصص في Card
```dart
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        const RealtimeSyncIndicator(
          compact: false,
          showDetailedStats: true,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => manualSync(),
          child: const Text('مزامنة الآن'),
        ),
      ],
    ),
  ),
)
```

## ⚙️ الخصائص المتاحة

```dart
RealtimeSyncIndicator(
  compact: bool,              // أم الحجم المضغوط
  showDetailedStats: bool,    // إظهار الإحصائيات المفصلة
)

CompactSyncDot(
  // بدون معاملات — استخدم مباشرة
)

AppBarSyncIndicator(
  // بدون معاملات — مُحسّن للـ AppBar
)

SyncStatusWidget(
  // بدون معاملات — للـ Dashboard
)
```

## 🔄 تحديث التردد

حالياً، التحديثات تحدث كل **100ms**:
```dart
_statsTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
  if (mounted) {
    ref.invalidate(syncHealthReportProvider);
  }
});
```

لتغيير التردد:
```dart
// للتحديث كل 500ms (أقل استهلاكاً للموارد)
const Duration(milliseconds: 500)

// للتحديث كل 1 ثانية (للشاشات غير الحساسة)
const Duration(seconds: 1)
```

## 📊 البيانات المستخدمة

المؤشر يعتمد على `SyncHealthReport`:

```dart
class SyncHealthReport {
  final String overallStatus;      // صحي / تحذير / خطأ / حرج
  final int outboxPending;         // عدد المعاملات المعلقة
  final int outboxFailed;          // عدد المعاملات الفاشلة
  final int outboxStuck;           // عدد المعاملات العالقة
  final int outboxProcessed;       // عدد المعاملات المنجزة
  final DateTime timestamp;        // وقت آخر تحديث
}
```

## 🐛 استكشاف الأخطاء

### المؤشر لا يتحدث
✅ تحقق من أن `SyncHealthMonitor` قيد التشغيل في `main.dart`

### الرسوم المتحركة بطيئة
✅ قلل تردد التحديثات من 100ms إلى 500ms

### الألوان لا تظهر بشكل صحيح
✅ تأكد من أن `Theme.of(context)` يعمل بشكل صحيح

## 🚀 الخطوات التالية

1. ✅ دمج `RealtimeSyncIndicator` في `main.dart` AppBar
2. ✅ استبدال `SyncIndicator` القديم في الإعدادات
3. ✅ إضافة مؤشر في Dashboard
4. ✅ اختبار الأداء على أجهزة ضعيفة (يقلل التردد إذا لزم)

## 📝 الملفات المرتبطة

- `lib/widgets/sync/realtime_sync_indicator.dart` — المكون الرئيسي
- `lib/screens/dashboard/sync_status_widget.dart` — أمثلة الاستخدام
- `lib/services/sync_health_monitor.dart` — مصدر البيانات
- `lib/providers/service_providers.dart` — Riverpod providers
