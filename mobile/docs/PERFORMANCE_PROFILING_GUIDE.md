# 🚀 Marina Hotel — Performance Profiling Toolkit

> دليل شامل لقياس وتحليل أداء تطبيق Marina Hotel باستخدام Flutter profile mode + DevTools + Performance Monitor مخصَّص.

## 📑 جدول المحتويات

- [نظرة عامة](#نظرة-عامة)
- [المكوِّنات](#المكوّنات)
- [الاستخدام السريع](#الاستخدام-السريع)
- [Performance Monitor المخصَّص](#performance-monitor-المخصّص)
- [Flutter Profile Mode + DevTools](#flutter-profile-mode--devtools)
- [Benchmark Tests](#benchmark-tests)
- [CI/CD Integration](#cicd-integration)
- [تفسير النتائج](#تفسير-النتائج)
- [Best Practices](#best-practices)

---

## نظرة عامة

يوفر هذا الـ toolkit ثلاث طبقات لقياس الأداء:

1. **Runtime Monitoring** (في app) — عبر `PerformanceMonitor` خفيف بدون dependency خارجي
2. **Manual Profiling** (محلي) — سكربت `perf_profile.sh` يُشغِّل Flutter profile + DevTools
3. **Automated Benchmarks** (CI) — اختبارات قياس في `test/performance/` تمنع regression

كل طبقة تكمل الأخرى — لا حاجة لـ `flutter_performance_optimizer` package الخارجي.

---

## المكوّنات

| الملف | الوصف |
|------|------|
| `mobile/lib/utils/performance_monitor.dart` | مراقب أداء خفيف (~600 سطر) — بديل `flutter_performance_optimizer` |
| `mobile/scripts/perf_profile.sh` | سكربت shell يُشغِّل Flutter profile + DevTools + يحفظ التقارير |
| `mobile/test/performance/benchmark_test.dart` | اختبارات قياس للأداء (FPS, memory, traces, rebuilds) |
| `.github/workflows/performance-benchmark.yml` | CI workflow يُشغِّل الـ benchmarks في كل PR |

---

## الاستخدام السريع

### 1. تشغيل المراقب في الـ app

```dart
// في main.dart، قبل runApp():
import 'utils/performance_monitor.dart';

void main() {
  PerformanceMonitor.instance.start();
  runApp(const ProviderScope(child: App()));
}
```

### 2. تتبُّع عملية معينة (custom trace)

```dart
// قياس زمن عملية
final result = await PerformanceMonitor.instance.measure('pdf_generation', () async {
  return await invoice.generatePdfBytes();
});

// أو manual start/end
PerformanceMonitor.instance.startTrace('heavy_query');
final data = await db.expensiveQuery();
PerformanceMonitor.instance.endTrace('heavy_query');
```

### 3. تتبُّع إعادة بناء widgets

```dart
PerformanceInspector(
  name: 'BookingPaymentScreen',
  child: BookingPaymentScreen(booking: booking),
)
```

### 4. تشغيل سكربت البروفايلينج

```bash
cd mobile

# android (default)
./scripts/perf_profile.sh

# web
./scripts/perf_profile.sh web

# بدون فتح DevTools + حفظ تقرير
./scripts/perf_profile.sh android --no-devtools --report
```

### 5. تشغيل benchmark tests

```bash
cd mobile
flutter test test/performance/ --reporter expanded
```

---

## Performance Monitor المخصَّص

### الميزات

| الميزة | الوصف |
|------|------|
| **FPS Tracker** | عبر `SchedulerBinding.addTimingsCallback` — متوسط آخر 120 إطار |
| **Frame Time** | build duration + raster duration لكل إطار |
| **Jank Detection** | إطارات > 16ms تُعدَّ jank، > 48ms critical |
| **Memory Tracking** | `ProcessInfo.currentRss` كل ثانية + كشف نمو مشبوه |
| **Rebuild Counter** | عبر `PerformanceInspector` widget wrapper |
| **Custom Traces** | `startTrace`/`endTrace`/`measure` لقياس العمليات |
| **Warning System** | بث تحذيرات عبر Stream + سجل كامل |
| **Performance Score** | 0-100 عبر 7 محاور (FPS, frame time, jank, memory, rebuilds, warnings, traces) |
| **Report Export** | JSON كامل قابل للحفظ في ملف للـ CI |
| **Memory Leak Tracker** | `MemoryTracker` لتتبُّع disposables |

### التكوين

```dart
PerformanceMonitor.instance.start(
  config: PerfConfig(
    enabled: true,                        // تشغيل/إيقاف
    fpsWarningThreshold: 45,              // FPS أقل من هذا = تحذير
    frameJankThresholdMs: 16,             // 60 FPS threshold
    rebuildWarningCount: 60,              // widget يُعاد بناؤه أكثر من هذا = تحذير
    memoryGrowthThresholdMB: 50,          // نمو ذاكرة أكثر من هذا = leak مشبوه
    maxWidgetDepth: 30,                   // عمق widget tree مشبوه
    collectFrameTimings: true,            // جمع frame timings
    collectMemory: true,                  // جمع عيّنات الذاكرة
    collectTraces: true,                  // تتبُّع العمليات
    dashboardEnabled: false,              // dashboard overlay (معطَّل افتراضياً)
  ),
);
```

### الوصول للمقاييس برمجياً

```dart
// مقاييس فورية
final fps = PerformanceMonitor.instance.currentFps;
final memoryMB = PerformanceMonitor.instance.currentMemoryMB;
final score = PerformanceMonitor.instance.performanceScore;

// تقرير كامل كـ JSON
final report = PerformanceMonitor.instance.exportReport();
await PerformanceMonitor.instance.saveReportToFile('/tmp/perf.json');

// الاستماع للتحذيرات
PerformanceMonitor.instance.warningStream.listen((warning) {
  debugPrint('⚠️ ${warning.message}');
  if (warning.suggestion != null) {
    debugPrint('💡 ${warning.suggestion}');
  }
});
```

---

## Flutter Profile Mode + DevTools

### ما هو profile mode؟

`flutter run --profile` يُنشئ build مماثل لـ release mode لكن مع:
- ✅ DevTools تعمل (Performance, Memory, CPU profiler)
- ✅ Debugging symbols محفوظة
- ✅ Performance قريب من production (AOT compilation)
- ❌ لا asserts/debug prints

### كيف يُستخدم في Marina Hotel

سكربت `perf_profile.sh` يقوم بـ:

1. فحص Flutter + جهاز متصل
2. تشغيل `flutter analyze` للتأكد من عدم وجود issues
3. توليد drift/freezed files
4. تشغيل `flutter run --profile --devtools -d <platform>`
5. فتح DevTools URL في المتصفح تلقائياً
6. عند الإغلاق: استخراج startup timeline + حفظ logs
7. تحليل الـ log باستخراج FPS/memory/frame times كـ JSON

### DevTools Tabs المهمة

| Tab | الاستخدام في Marina Hotel |
|------|------|
| **Performance** | فحص frame rendering — يكشف العمليات البطيئة في build/paint |
| **Memory** | مراقبة نمو الذاكرة — يكشف leaks في streams/controllers |
| **CPU Profiler** | تحليل دوال مستهلكة للـ CPU — مفيد لـ sync code |
| **Network** | فحص طلبات Appwrite/Google Drive — يكشف الطلبات المتكررة |
| **Widget Inspector** | فحص widget tree depth + RepaintBoundary |

### تفسير ما تراه في Performance tab

- **طول الإطار**: ideally < 16ms (60 FPS). > 32ms = jank واضح
- **UI Thread vs Raster Thread**: UI thread طويل = كود Dart بطيء. Raster طويل = paint heavy
- **Bars حمراء**: إطارات متأخرة — انقر عليها لرؤية stack trace
- **Timeline events**: ابحث عن `PerformanceMonitor.startTrace` — تظهر كـ events مخصصة

---

## Benchmark Tests

### ملف `test/performance/benchmark_test.dart`

يحتوي على اختبارات قياس في 7 محاور:

| المجموعة | الاختبارات |
|--------|------|
| **🚀 Startup Performance** | زمن بدء < 3s، image cache config < 10ms |
| **📊 Frame Performance** | FPS ≥ 55، frame time، jank ratio < 5% |
| **💾 Memory Performance** | memory < 100MB، نمو < 50MB خلال 30 ثانية |
| **⚡ Operation Latency** | dashboard query، payment aggregation، room search، PDF generation |
| **🔄 Rebuild Performance** | widget rebuild < 60/min، PerformanceInspector tracking |
| **🏆 Overall Score** | performance score ≥ 70/100 |
| **📋 Report Generation** | JSON export، file save، validity |
| **⚠️ Warning System** | jank detection، warningStream broadcast |

### تشغيلها

```bash
# تشغيل عادي
flutter test test/performance/ --reporter expanded

# تشغيل مع إخراج JSON (للـ CI)
flutter test test/performance/ --machine > perf_results.json

# تشغيل اختبار واحد
flutter test test/performance/benchmark_test.dart -N "Performance Score"
```

### إضافة اختبار جديد

```dart
test('اسم الاختبار', () async {
  await PerformanceMonitor.instance.measure('my_operation', () async {
    // ... الكود المراد قياسه
  });

  final report = PerformanceMonitor.instance.exportReport();
  final traces = report['traces'] as Map<String, dynamic>;
  final slowest = traces['slowest'] as List<dynamic>;
  final myTrace = slowest.firstWhere(
    (t) => (t as Map)['name'] == 'my_operation',
  );
  final elapsed = myTrace['elapsedMs'] as int;
  expect(elapsed, lessThan(1000)); // عتبة 1 ثانية
});
```

---

## CI/CD Integration

### Workflow: `performance-benchmark.yml`

يُشغَّل في 4 حالات:
- ✅ PR إلى main/marina/refactor/feature branches
- ✅ Push إلى main
- ✅ تشغيل يدوي (workflow_dispatch)
- ✅ أسبوعياً (الأحد 03:00 UTC) لتتبُّع regression عبر الزمن

### الـ Jobs الثلاثة

#### 1. `static-analysis` (10 دقائق)
فحص static للأداء بدون تشغيل التطبيق:
- `flutter analyze`
- عدّ RepaintBoundary، ValueNotifier، .select()، IndexedStack
- حساب نسبة const Text
- تدقيق BoxShadow (blurRadius > 4 = violation)
- كشف `print()` في screens (ممنوع)

#### 2. `benchmark-tests` (20 دقيقة)
تشغيل `flutter test test/performance/` مع:
- إخراج JSON (`--machine`)
- ملخّص في PR UI (جدول بكل اختبار + نتيجته)
- رفع النتائج كـ artifact (30 يوم retention)

#### 3. `regression-check` (15 دقيقة)
مقارنة النتائج الحالية مع baseline من main branch:
- تنزيل artifact سابق
- حفظ baseline جديد عند push لـ main
- (في الإصدار القادم: مقارنة تلقائية برقميّة)

### مراقبة النتائج

في كل PR، سترى:

1. **Checkboxes في PR UI** — نجاح/فشل كل job
2. **Step Summary** — جدول بالنتائج:
   ```
   ### 📊 Performance Benchmark Results
   - Passed: 18 ✅
   - Failed: 0 ❌
   - Skipped: 0 ⏭️
   ```
3. **Artifacts** — تنزيل النتائج الكاملة كـ JSON

---

## تفسير النتائج

### Performance Score (0-100)

| الدرجة | التفسير | الإجراء |
|------|------|------|
| **90-100** | ممتاز | لا إجراء مطلوب |
| **80-89** | جيد جداً | راجع التحذيرات فقط |
| **70-79** | مقبول | بعض المشاكل — خطط لتحسينات |
| **50-69** | ضعيف | مشاكل أداء واضحة — إصلاح عاجل |
| **0-49** | حرج | المشروع غير قابل للاستخدام على أجهزة ضعيفة |

### مكونات الدرجة

- **FPS** (25 نقطة) — على أساس currentFps
- **Frame Time** (15 نقطة) — على أساس averageFrameTimeMs
- **Jank Ratio** (15 نقطة) — على أساس jankFrames/totalFrames
- **Memory Stability** (15 نقطة) — على أساس نمو الذاكرة
- **Rebuild Density** (10 نقاط) — على أساس totalRebuilds
- **Warning Count** (10 نقاط) — على أساس critical/warning count
- **Trace Latency** (10 نقاط) — على أساس متوسط زمن التتبُّعات

### أسباب فشل الاختبارات الشائعة

| الخطأ | السبب | الحل |
|------|------|------|
| `FPS < 55` | build/paint بطيء | استخدم RepaintBoundary + CustomScrollView |
| `memory growth > 50MB` | leak في controllers/streams | أضف `dispose()` + `MemoryTracker.trackDisposable()` |
| `rebuild count > 60` | setState كثير | استبدل بـ ValueNotifier أو .select() |
| `frame time > 16ms` | عمليات sync في build | انقل لـ Isolate أو استخدم compute() |
| `PDF generation > 2000ms` | PDF ثقيل | استخدم MultiPage + تأجل isoloate |

---

## Best Practices

### 1. لا تُفعِّل PerformanceMonitor في production

```dart
void main() {
  if (kDebugMode) {
    PerformanceMonitor.instance.start();
  }
  runApp(const App());
}
```

`kDebugMode` يضمن عدم وصول المراقب لـ release APK.

### 2. استخدم PerformanceInspector بحكمة

لا تُغلف كل widget — فقط الشاشات عالية الحركة:

```dart
// ✅ جيد
PerformanceInspector(
  name: 'BookingPaymentScreen',
  child: BookingPaymentScreen(booking: booking),
)

// ❌ سيء (overhead بدون فائدة)
PerformanceInspector(
  name: 'Text',
  child: Text('hello'),
)
```

### 3. حدِّد عتبات منطقية

العتبات الافتراضية مبنية على أجهزة ضعيفة. في الاختبارات، استخدم عتبات أكثر تساهلاً:

```dart
test('memory in CI < 500MB', () {
  expect(memoryMB, lessThan(500));  // وليس 100MB
});
```

### 4. قارن عبر الـ runs

احفظ baseline من main branch:

```bash
# تنزيل آخر artifact من main
gh run download <run-id> -n performance-benchmark-<id>

# مقارنة مع current
diff baseline/results.json current/results.json
```

### 5. استخدم DevTools للتحليل العميق

الـ PerformanceMonitor يُعطي أرقام عامة. للحصول على stack trace دقيق:

```bash
./scripts/perf_profile.sh --report
# افتح DevTools URL الذي يظهر
# اذهب لـ Performance tab
# سجِّل scenario معين
# حلِّل الـ frames الحمراء
```

---

## مقارنة مع flutter_performance_optimizer package

| الميزة | `flutter_performance_optimizer` | Marina Hotel Toolkit |
|------|------|------|
| Dependencies | حزمة خارجية | 0 (كل الكود محلي) |
| pub.dev score | 0/160 | N/A |
| Backdrop blur | 10.0 (ثقيل) | معطَّل |
| Dashboard overlay | نعم (يُغلِّف UI) | optional + خفيف |
| CI integration | محدود | كامل (3 jobs) |
| Memory tracker | نعم | نعم + leak detection |
| Rebuild heatmap | نعم | عبر PerformanceInspector badge |
| Performance score | 0-100 | 0-100 (7 محاور) |
| Custom traces | لا | نعم (startTrace/endTrace/measure) |
| File export | محدود | JSON + file save |
| تعارض مع MaterialApp.builder | محتمل | لا (مستقل) |
| حجم الـ APK | +50KB | +5KB (debug only) |

**الخلاصة:** toolkit المخصَّص أخف، أعمق تكاملاً، بدون dependencies، وأكثر ملاءمة لتحسينات Marina Hotel الموجودة.

---

## الأسئلة الشائعة

### س: هل أؤثر على أداء production؟
**ج:** لا. `kDebugMode` يضمن عدم تفعيل المراقب في release. كل الكود يُستبعد من الـ APK في release mode.

### س: كيف أُضيف مقاييس لشاشة معينة؟
**ج:** اُغلِّفها بـ `PerformanceInspector`:
```dart
PerformanceInspector(
  name: 'MyScreen',
  showBadge: true,  // يُظهر عدّاد صغير في الـ corner
  child: MyScreen(),
)
```

### س: كيف أقارن نتائج benchmark بين فرعين؟
**ج:** شغِّل الـ workflow على كلا الفرعين، نزِّل artifacts، قارن `results.json`.

### س: الـ FPS في اختبارات منخفضة جداً (0 أو منخفضة)؟
**ج:** طبيعي — في `flutter test` لا يوجد rendering حقيقي. الـ benchmark يقيس العمليات الداخلية، ليس FPS المرئية. لقياس FPS حقيقي، استخدم `perf_profile.sh` على جهاز حقيقي.

### س: كيف أُضيف عتبة جديدة لـ CI؟
**ج:** أضف اختبار جديد في `test/performance/benchmark_test.dart`:
```dart
test('my operation < X ms', () async {
  await PerformanceMonitor.instance.measure('my_op', () async {
    // ...
  });
  // تحقق من elapsed < X
});
```

---

## Roadmap

الإصدارات القادمة ستضيف:

- [ ] **Dashboard overlay** (optional) — floating widget بـ FPS/memory/score
- [ ] **Baseline comparison** — مقارنة تلقائية مع main branch في PR UI
- [ ] **Performance alerts** — إشعار تلقائي في Slack/Telegram عند regression
- [ ] **GPU profiling** — عبر `flutter run --trace-gpu`
- [ ] **Custom timeline events** — تكامل مع `dart:developer` Timeline
- [ ] **Network profiling** — ربط مع Appwrite requests في DevTools

---

*آخر تحديث: 2026-07-17 — مرتبط بالـ commit `1867198c`*
