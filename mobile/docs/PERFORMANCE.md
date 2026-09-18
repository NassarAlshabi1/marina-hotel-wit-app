# دليل أداء Flutter على الأجهزة الضعيفة (Android · 1GB RAM)

> **الهدف:** تطبيق لا يُقتل (No OOM)، بلا تقطيع (No Jank)، وحزمة صغيرة.
> **الفئة المستهدفة:** Android 5.0+ · رام 1GB · معالج ضعيف · GPU من فئة Mali-400 / Adreno 3xx (GLES2/GLES3 قديم).
> **الإصدار:** 2.0 · آخر تحديث: 2026-09-12

---

## كيف تستخدم هذا الملف

| الاستخدام | الطريقة |
|---|---------|
| مرجع للفريق | هذا الملف في جذر المشروع باسم `docs/PERFORMANCE.md` |
| مرجع للوكيل/المساعد البرمجي | أضف سطراً في `AGENTS.md` (الموجود في جذر `mobile/`): «اتبع `docs/PERFORMANCE.md` في كل تغيير» |
| بوابة مراجعة الكود (PR Gate) | استخدم **§10 قائمة التحقق** كبنود إلزامية في وصف كل Pull Request |

---

## 0) القواعد الذهبية — اقرأها أولاً

| # | القاعدة | لماذا |
|---|---------|-------|
| 1 | كل `Controller` و`Subscription` و`Timer` يُغلق في `dispose()` | سبب ~80% من إغلاقات OOM بعد دقائق من الاستخدام |
| 2 | لا تفكّ تشفير صورة أكبر مما ستُعرض به فعلياً | صورة 2MB قد تصبح 24MB في الرام بعد الـ Decode |
| 3 | `setState` نقطة لا دائرة — لا تستدعِها في جذر الشاشة | إعادة بناء الشجرة كاملة في كل إطار |
| 4 | أي عمل يتجاوز **8ms** ينتمي إلى Isolate | خيط الواجهة يشارك الـ GPU في إطار 16.6ms |
| 5 | `saveLayer` هو العدو الأول للـ GPU الضعيف | كل طبقة = نسخة إضافية في الرام + عملية رسم مزدوجة |
| 6 | قِس على **جهاز ضعيف حقيقي** في **Profile Mode** | نتائج المحاكي مضللة تماماً |
| 7 | ميزانيتك الفعلية: **100–150MB** رام، لا 200MB | `ActivityManager.getMemoryClass()` على جهاز 1GB يعيد عادة 128–192MB |

---

## 1) إدارة الذاكرة (الأولوية القصوى)

### 1.1 تحجيم الصور في الرام — `cacheWidth` / `cacheHeight`

القيمة المطلوبة **بالبكسل الفعلي (Physical Pixels)** لا المنطقي، لذا يجب ضربها في `devicePixelRatio`:

```dart
// ❌ كارثة على الأجهزة الضعيفة — فك تشفير بالحجم الكامل
Image.asset('assets/avatar.png')

// ❌ مقبول لكنه ضبابي على شاشات xxhdpi
Image.asset('assets/avatar.png', cacheWidth: 100)

// ✅ الصحيح
final dpr = MediaQuery.devicePixelRatioOf(context);
final side = (50 * dpr).round(); // دائرة 50dp بأعلى دقة ممكنة
Image.asset('assets/avatar.png', cacheWidth: side, cacheHeight: side)
```

للصور من الشبكة استخدم `cached_network_image` مع نفس المنطق:

```dart
CachedNetworkImage(
  imageUrl: url,
  memCacheWidth: (56 * MediaQuery.devicePixelRatioOf(context)).round(),
  memCacheHeight: (56 * MediaQuery.devicePixelRatioOf(context)).round(),
  fadeInDuration: const Duration(milliseconds: 120), // لا 500ms
  placeholder: (_, __) => const SizedBox.shrink(),
  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
)
```

> **قاعدة الصيغة:** استخدم **WebP** بدل PNG/JPEG. توفير نموذجي: 40–70% حجماً ونفس النسبة في زمن الفك.

### 1.2 تقليص `ImageCache` الافتراضي

الافتراضي في Flutter هو **1000 صورة / 100MB** — رقم عبثي لجهاز 1GB:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = 20 * 1024 * 1024; // 20MB فقط
  cache.maximumSize = 40;                   // 40 صورة فقط

  runApp(const MyApp());
}
```

**في هذا المشروع:** مطبّق في `lib/utils/performance_config.dart` (`configurePerformance()`) بقيم تُضبط من `WeakDeviceOptimizer`.

### 1.3 الاستجابة لضغط الذاكرة (نقطة مفقودة في معظم الأدلة)

تصغير الكاش لا يكفي — يجب تفريغه عندما يطلب النظام ذلك:

```dart
class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MaterialApp(home: HomePage());
}
```

**في هذا المشروع:** مطبّق في `lib/main.dart` (`_AppState.didHaveMemoryPressure`).

### 1.4 تفريغ الموارد بدقة — لا استثناء

```dart
class _ScreenState extends State<Screen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final AnimationController _anim;
  StreamSubscription<Event>? _sub;
  Timer? _ticker;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _anim.dispose();
    _focusNode.dispose();
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
```

> 🔍 **كشف التسريبات:** أضف `leak_tracker`، ثم في DevTools → **Memory → Diff Snapshots** قارن قبل/بعد التنقل بين الشاشات 5 مرات. أي صعود مطّرد = تسريب. الرسم الصحي = **Sawtooth** (يصعد ويهبط).

### 1.5 الخطوط والنصوص

- خط واحد فقط، واقتصر على نطاق Unicode المطلوب (الخط العربي الكامل ثقيل جداً في الرام).
- تجنب `Text` بظلال متعددة أو `TextStyle` مع `shadows` — كل ظل نصي يكلّف طبقة.

### 1.6 تجنب القوائم الوسيطة (Allocations مؤقتة)

```dart
// ❌ ثلاث قوائم مؤقتة تُنشأ ثم تُهمَل
final items = parsed.map((j) => Item.fromJson(j)).toList()
    .where((i) => i.active).toList()
    .toList();

// ✅ مرور واحد فقط
final items = <Item>[];
for (final j in parsed) {
  final item = Item.fromJson(j);
  if (item.active) items.add(item);
}
```

---

## 2) تقليل إعادة البناء (CPU & Widget Rebuilds)

### 2.1 `const` في كل مكان ممكن

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
    prefer_const_declarations: true
    avoid_unnecessary_containers: true
    sized_box_for_whitespace: true
```

### 2.2 إدارة حالة دقيقة (Granular)

```dart
// ❌ يعيد بناء الشاشة كاملة عند كل نبضة
setState(() => _counter++);

// ✅ يعيد بناء النص فقط
ValueListenableBuilder<int>(
  valueListenable: _counter,
  builder: (_, value, __) => Text('$value'),
)

// Riverpod
final count = ref.watch(counterProvider.select((s) => s.count));

// Bloc
BlocSelector<CounterBloc, CounterState, int>(
  selector: (state) => state.count,
  builder: (context, count) => Text('$count'),
);
```

### 2.3 `MediaQuery` و `Theme` — قاتلان خفيان

`MediaQuery.of(context)` يعيد بناء الودجت عند تغيّر **أي** شيء (لوحة المفاتيح، الدوران، شريط الحالة). استخدم المحددات الدقيقة:

```dart
// ❌
final size = MediaQuery.of(context).size;
final padding = MediaQuery.of(context).padding;

// ✅
final size = MediaQuery.sizeOf(context);
final padding = MediaQuery.paddingOf(context);
final dpr = MediaQuery.devicePixelRatioOf(context);

// ✅ للثيم: خزّن ThemeData ثابتاً خارج build أو استخدم الامتدادات
final textTheme = Theme.of(context).textTheme;
```

### 2.4 القوائم الافتراضية (Virtualization) — التصحيح المهم

`ListView.builder` يبني ويهدم العناصر خارج الشاشة **افتراضياً**، وهذه هي الـ Virtualization الحقيقية. أما `addAutomaticKeepAlives` و`addRepaintBoundaries` فيخصّان **الاحتفاظ بالحالة والطبقات**، لا تقليل الذاكرة:

```dart
ListView.builder(
  itemCount: items.length,
  itemExtent: 72,              // ✅ إلزامي: يلغي عملية القياس الكاملة للقائمة
  addRepaintBoundaries: true,  // الافتراضي — اتركه
  // addAutomaticKeepAlives: اتركه true، إلا إذا كنت واعياً أنه
  // يكسر AutomaticKeepAliveClientMixin ويُفقد حالة TextField والتابات
  itemBuilder: (context, index) => ItemTile(items[index]),
)
```

> ⚠️ **ممنوع:** `SingleChildScrollView` + `Column` لعنصر قائمة كبيرة أو ديناميكية — يبني كل العناصر في الرام فوراً.

### 2.5 `RepaintBoundary` بذكاء

غلّف **الودجت المتحركة فقط** عندما تكون بجوار منطقة ثابتة ومعقدة (مؤقت، شريط تقدم، نقطة نابضة):

```dart
Column(
  children: [
    const HeavyStaticHeader(),        // تُرسم مرة واحدة
    RepaintBoundary(child: _Timer()), // تُرسم وحدها كل ثانية
  ],
)
```

> ⚠️ لا تُغلف كل شيء — كل `RepaintBoundary` = طبقة (Texture) إضافية في الرام.

---

## 3) الرسوميات ومعالج الجرافيكس (GPU)

خريطة الاستبدال الإلزامية:

| ❌ ممنوع / مكلف | ✅ البديل الخفيف | السبب |
|---|---|---|
| `BackdropFilter` (بلور/زجاج) | `Color(0x8A000000)` لون نصف شفاف | يفرض `saveLayer` لكل إطار |
| `Opacity` | `color: Colors.blue.withValues(alpha: 0.5)` | `Opacity` ينشئ Offscreen Buffer |
| `ShaderMask` / `ColorFiltered` | صورة/لون مُعدّ مسبقاً | `saveLayer` مزدوج |
| `ClipRRect` حول صورة | `BoxDecoration(borderRadius: ...)` على `Container` | الحواف عبر الـ Decoration أخف |
| `ClipPath` | `CustomPaint` أو شكل هندسي جاهز | clipping منحني = تحليل مسار كل إطار |
| `BoxShadow` بـ `blurRadius` عالٍ | `blurRadius: 2–4` أو `Border` خفيف | كل ظل = طبقة مرسومة منفصلة |
| `PhysicalModel` / `Material` مع elevation عالٍ | `elevation: 0–1` + حدود | نفس المشكلة |
| أنيميشن يحرّك `width/height` | `Transform.scale` / `SlideTransition` | تجنّب إعادة الـ Layout كل إطار |

### 3.1 Impeller — أهم بند على الإطلاق

من Flutter 3.29+ صار **Impeller افتراضياً** على أندرويد، ويحتاج GLES3/Vulkan. على أجهزة قديمة قد يكون **أبطأ من Skia** أو يُظهر أخطاء بصرية. قارن دائماً:

```bash
# اختبار سريع قبل أي حكم
flutter run --profile --no-enable-impeller
flutter run --profile                    # مع Impeller
```

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application ...>
  <meta-data
      android:name="io.flutter.embedding.android.EnableImpeller"
      android:value="false" />
</application>
```

**في هذا المشروع:** Impeller يبقى افتراضياً (لم يُعطَّل) — قرار التعطيل يتطلب قياساً على جهاز ضعيف حقيقي أولاً (لا تغيير بلا قياس).

### 3.2 اكتشاف الطبقات بصرياً

في Profile Mode:

```dart
debugRepaintRainbowEnabled = true;  // كل منطقة تُعاد رسمها تظهر بلون
debugPaintLayerBordersEnabled = true;
```

### 3.3 لتفريغ الجرافيكس نهائياً (تشخيصي فقط)

```bash
flutter run --profile --enable-software-rendering
```

إن اختفى التقطيع تماماً → العتاد هو السبب، لا كودك.

---

## 4) العمليات الثقيلة خارج خيط الواجهة

خيط الواجهة وحيد، ويشارك الـ Raster Thread في الإطار الواحد. أي عمل متزامن فوق ~8ms = إطار مسقوط.

```dart
// ❌ يجمّد الواجهة على المعالجات الضعيفة
final data = jsonDecode(responseBody);

// ✅ الأفضل (Dart 2.19+) — لا تحتاج دالة عليا
final items = await Isolate.run(() => _decodeAndMap(responseBody));

// ✅ البديل التقليدي
Future<List<Item>> parseData(String responseBody) =>
    compute(_decodeAndMap, responseBody);

List<Item> _decodeAndMap(String response) {
  final parsed = jsonDecode(response) as List;
  final out = <Item>[];
  for (final j in parsed) {
    out.add(Item.fromJson(j as Map<String, dynamic>));
  }
  return out;
}
```

> ⚠️ **تحذير مهم:** إنشاء Isolate يكلّف 1–10ms + نسخ البيانات. لأي JSON أصغر من ~50KB استخدم `jsonDecode` مباشرة — نقل العمل أسوأ من تركه.
> **للأحجام الضخمة (>1MB):** استخدم `TransferableTypedData` لتجنّب نسخة البيانات الكاملة.

**في هذا المشروع:** الأداة الجاهزة `lib/utils/json_isolate.dart` (`JsonIsolate.decode/encode/decodeBatch` — عتبة 4KB) — استخدمها لأي JSON قد يتجاوز 50KB بدل `jsonDecode` المباشر.

**عمليات أخرى تنتمي للـ Isolate:**

- فك تشفير/تشفير (تجزئة الملفات، ضغط، AES)
- قراءة/كتابة ملفات كبيرة
- معالجة صور (`image` package)
- حسابات، فلترة، وترتيب مجموعات كبيرة

---

## 5) الشبكة والتخزين

### 5.1 الشبكة

- **gzip** على الخادم (عادة توفير 60–80% من حجم الاستجابة النصية).
- **Pagination إلزامي** — لا تُحمّل 500 عنصر مرة واحدة.
- `CancelToken` وأَلغِ الطلبات عند الخروج من الشاشة.
- لا تُرسل صوراً بالحجم الكامل — استخدم CDN مع `?w=200` أو ما يعادلها.
- مهلة زمنية قصيرة (10s) مع إعادة محاولة واحدة — المستخدم على شبكة ضعيفة ينتظر.

```dart
final dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
  headers: {'Accept-Encoding': 'gzip'},
));
```

### 5.2 التخزين المحلي

- استعلامات مقسّمة: `LIMIT` / `OFFSET` بدل تحميل الجدول كاملاً.
- `sqflite` / `drift` — فعّل الاستعلامات المؤجّلة (Lazy).
- لا تفتح كل صناديق `Hive` عند الإقلاع — افتح فقط ما يخصّ الشاشة الحالية.
- تجنّب تحميل قوائم كبيرة في `shared_preferences` (ملف XML واحد يُقرأ كاملاً).

> **في هذا المشروع:** قاعدة §5.2 عن `LIMIT` تخصّ *الاستعلامات الموجّهة للتقارير والحسابات*. في شاشات العرض الرئيسية اعتمدنا سياسة معاكسة مقصودة: السحب بلا حدّ من السحابة + الحماية في طبقة العرض فقط (`PaginatedDataTable` / `ListView`) — لأن قصّ SQL كان سبب فقدان بيانات في شاشة guest infos (انظر تاريخ الإصلاح `a6574e88`). لا تُعد أدوات قصّ SQL إلى مسارات العرض دون موافقة.

---

## 6) زمن الإقلاع (Startup)

كل ما يُنفَّذ قبل `runApp()` يحجب أول إطار مباشرة على الشاشة.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ الحد الأدنى الإلزامي فقط قبل runApp
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;

  runApp(const MyApp());

  // ✅ كل شيء آخر بعد أول إطار
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _loadPrefs();
    await _initAnalytics();
    await _warmUpDatabase();
  });
}
```

**القياس:**

```bash
flutter run --profile --trace-startup
```

**تجنّب في `main()`:** `await` لشبكة، فتح قاعدة بيانات كاملة، تهيئة Firebase Plus/Ads، تحميل ملفات كبيرة.

**في هذا المشروع:** مطبّق — على الأجهزة الضعيفة تُؤجَّل RemoteConfig/PostHog/ApiConfig/LatePayment إلى ما بعد أول frame (`addPostFrameCallback`)، وتبقى قبل `runApp` الخدمات الالتقاطية فقط (Crashlytics + Diagnostics + DB guard).

---

## 7) البناء والنشر (Release Optimization)

### 7.1 للنشر على Google Play (الإلزامي)

```bash
flutter build appbundle --release \
  --split-debug-info=build/symbols \
  --obfuscate
```

> ⚠️ **خطأ شائع:** `--split-per-abi` **لا يعمل مع Play** — المتجر يرفض APK مقسّماً ويشترط AAB (ويقسّم هو تلقائياً). كذلك **لا تُصدر** `--target-platform android-arm` للنشر، لأن Play يشترط دعم 64-bit.

### 7.2 للتوزيع المباشر (خارج المتجر)

```bash
flutter build apk --release --split-per-abi \
  --split-debug-info=build/symbols --obfuscate
```

### 7.3 قياس الحجم فعلياً (لا تخمين)

```bash
flutter build appbundle --analyze-size --target-platform android-arm64
```

يفتح تقريراً تفاعلياً يوضّح أي حزمة/ملف يستهلك الحجم.

### 7.4 R8 / ProGuard

```groovy
// android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                          'proguard-rules.pro'
            signingConfig signingConfigs.release
        }
    }

    packagingOptions {
        jniLibs { useLegacyPackaging = false } // تقليل حجم التثبيت
    }
}
```

> ⚠️ **تنبيه:** R8 لا يقلّص كود Dart (مُقلَّص ومُترجَم AOT أصلاً) — فائدته على جانب Java/Kotlin فقط. وقد يكسر مكتبات تعتمد على Reflection (بعض إضافات Firebase/الإعلانات). **اختبر نسخة `--release` كاملة قبل النشر.**

**في هذا المشروع:** `minifyEnabled true` + `shrinkResources true` + proguard-rules.pro — مفعّلة أصلاً في `android/app/build.gradle`.

### 7.5 الأصول (Assets)

- لا تُضمّن خطوطاً أو ملفات أيقونات أو Lottie animations ضخمة غير مستخدمة.
- `--tree-shake-icons` مُفعّل افتراضياً، **لكنه يتعطّل** إن استخدمت `IconData` ديناميكياً (من API أو قاعدة بيانات) — استخدم خريطة `Map<String, IconData>` صريحة.
- راجع `assets/` واحذف كل ملف غير مُشار إليه.

---

## 8) القياس والاختبار

### 8.1 البيئة الصحيحة

| ✅ صحيح | ❌ خاطئ |
|---|---|
| جهاز ضعيف **حقيقي** (أو Firebase Test Lab فئة ضعيفة) | محاكي على جهاز قوي |
| `flutter run --profile` | `--debug` (بطيء 5–10×) |
| مقارنة بعدّاد إطارات وأرقام | «يبدو سريعاً» |

### 8.2 الأوامر

```bash
flutter run --profile                 # الأداء الحقيقي
flutter run --profile --trace-startup # قياس زمن الإقلاع
flutter run --profile --no-enable-impeller
flutter build appbundle --analyze-size
dart devtools                         # ثم Attention: Performance / Memory
```

### 8.3 ما تراقبه في DevTools

| التبويب | ما تبحث عنه | الحد المقبول |
|---|---|---|
| **Performance** | UI time + Raster time لكل إطار | أقل من **16.6ms** (60fps) — والمفضل أقل من 8ms |
| **Performance** | Janky frames | أقل من 1% |
| **Memory** | الرام الثابتة أثناء التنقل | مستقرة تحت **100–150MB** |
| **Memory** | شكل الرسم | Sawtooth 🪚 — أي صعود مطّرد = تسريب |
| **App Size** | أكبر 10 أصول | لا أصل فردي فوق 500KB |

> 📱 على جهاز ضعيف: توقّع **30–45fps** واقعية، لا 60. القاعدة الحقيقية = **عدم وجود تقطيع محسوس**، لا الوصول إلى رقم معيّن.

---

## 9) ميزانية الأداء (التزام تعاقدي)

| المقياس | الحد الأقصى |
|---|---|
| زمن الإقلاع (Cold Start) | < 1.5 ثانية |
| رام ثابتة في الاستخدام العادي | < 120MB |
| رام عند فتح شاشة الصور | < 160MB |
| Raster time لكل إطار | < 16ms |
| حجم AAB | < 15MB |
| ارتفاع الرام بعد 10 دقائق تنقل | صفر (لا نمو) |

---

## 10) قائمة التحقق (PR Gate)

انسخ هذا كبنود إلزامية في كل Pull Request:

```
### أداء الأجهزة الضعيفة
- [ ] كل Controller/Subscription/Timer جديد له dispose() مقابل
- [ ] كل صورة جديدة محدّدة بـ cacheWidth/cacheHeight أو memCacheWidth/memCacheHeight
- [ ] لا يوجد SingleChildScrollView + Column لقائمة كبيرة
- [ ] لا setState في جذر الشاشة — استخدم ValueListenableBuilder/Selector
- [ ] الودجت الثابتة موسومة بـ const
- [ ] لا BackdropFilter / Opacity / ShaderMask جديد بدون مبرر موثّق
- [ ] لا jsonDecode متزامن لأكثر من 50KB على خيط الواجهة
- [ ] MediaQuery.sizeOf / paddingOf بدل MediaQuery.of حيث أمكن
- [ ] لا تهيئة ثقيلة جديدة داخل main() قبل runApp()
- [ ] تم التشغيل على جهاز ضعيف حقيقي في Profile Mode
```

---

## 11) الأنماط الممنوعة (Anti-Patterns)

| # | النمط | الأثر |
|---|---|---|
| 1 | `ListView` بدون `itemExtent` لعناصر ثابتة الارتفاع | قياس كل العناصر = Layout مكلف |
| 2 | `Image.network` بدون Cache | إعادة تحميل وفك تشفير عند كل تمرير |
| 3 | `setState` في `build` أو داخل مستمع | حلقة إعادة بناء لا نهائية |
| 4 | `Theme.of(context)` داخل حلقة `itemBuilder` | يُستدعى مرة لكل عنصر |
| 5 | `Opacity(opacity: 0/1)` | طبقة كاملة بلا فائدة |
| 6 | `PrecacheImage` لكل صور الشاشة دفعة واحدة | يملأ الكاش فوراً = OOM |
| 7 | `Timer.periodic` بدون `cancel` | تسريب + استهلاك معالج مستمر |
| 8 | `StreamBuilder` بدون `initialData` | إعادة بناء مزدوجة عند كل حدث |
| 9 | أنيميشن يعمل خارج الشاشة | أدرج داخل `TickerMode(enabled: isVisible)` |
| 10 | `print()` في release | يستهلك معالجاً ويُبطئ الإطارات |

**في هذا المشروع:** استخدم `dlog`/`dwarn` من `lib/utils/debug_logs.dart` أو `AppLogger` بدل `print` (قاعدة `avoid_print` مفعّلة في `analysis_options.yaml`).

---

## 12) خيارات الخط الأخير (استخدمها بحذر)

| الخيار | الفائدة | التكلفة |
|---|---|---|
| `android:largeHeap="true"` | يرفع السقف إلى ~512MB | **يزيد** احتمال القتل عند ضغط النظام — لا تستخدمه كحل أساسي، بل كمُسكِّن مؤقت مع إصلاح التسريب |
| `--no-enable-impeller` | إصلاح تقطيع/أخطاء بصرية على GPU قديم | يعيد Skia ويؤجّل مشكلة الأداء المستقبلي |
| `--enable-software-rendering` | تشخيص فقط | أداء منخفض جداً — لا تنشره |

---

## ترتيب الأولويات الواقعي

```
1. Impeller on/off            → أكبر أثر على GPU ضعيف
2. تسريبات dispose            → سبب 80% من OOM
3. تقطيع إعادة البناء         → const + selectors + MediaQuery.sizeOf
4. تحجيم الصور + ضغط الذاكرة  → أكبر استهلاك للرام
5. Isolates للـ JSON الكبير   → منع Frame Freeze
6. حجم الحزمة (AAB)           → زمن تثبيت وإقلاع أقل
```

---

## 13) حالة الامتثال الحالية للمشروع (تدقيق بالأدلة — 2026-09-13)

تدقيق قائم على grep وتتبّع كود للالتزام `HEAD` وقت التدقيق — ليس تخميناً. المرجعية: §10 أعلاه.

| البند | الحالة | الدليل |
|---|---|---|
| ImageCache مصغّر + استجابة لضغط الذاكرة | ✅ مطبّق | `performance_config.dart:15-16` (من WeakDeviceOptimizer)؛ `main.dart` `_AppState.didHaveMemoryPressure` → clear + clearLiveImages |
| الإقلاع: تأجيل الخدمات على الأجهزة الضعيفة | ✅ مطبّق | `main.dart`: RemoteConfig/PostHog/ApiConfig/LatePayment داخل `addPostFrameCallback` عندما `isWeakDevice` |
| لا `Opacity` / `BackdropFilter` / `ShaderMask` | ✅ صفر استخدامات | grep على `lib/` — الاستخدام الوحيد لـ `ColorFiltered` في `shimmer_loading.dart` هو **بديل ثابت مقصود** لـ Shimmer المتحرك على الأجهزة الضعيفة (يمنع إعادة الرسم الدائمة) — مبرر وموثق |
| لا صور Flutter بلا تحجيم | ✅ لا صور إطلاقاً | صفر `Image.asset`/`Image.network`/`CachedNetworkImage` في `lib/`؛ `hotel_logo.jpg` يُقرأ `rootBundle.load` كبايتات للـ PDF فقط (لا يدخل image cache) |
| dispose/cancel لكل Timer/Controller | ✅ مطابق | فحص عيّنات: `sync_health_screen`، `appwrite_logs_screen`، `dashboard_sync_button`، `performance_monitor` (`_memoryTimer?.cancel()`)، `main.dart` — كلها تُلغى في `dispose()`؛ لints `cancel_subscriptions` + `close_sinks` مفعّلة |
| `SingleChildScrollView` + Column | ✅ لا قوائم كبيرة | كل الاستخدامات نماذج إدخال/حوارات محتوى محدود؛ القوائم عبر `ListView`/`PaginatedDataTable` |
| jsonDecode > 50KB | ✅ أداة جاهزة | `lib/utils/json_isolate.dart` (عتبة 4KB) مستخدمة في خدمات النسخ الاحتياطي؛ مسارات المزامنة تفكّك payloads صغيرة لكل سجل — أي decode جديد كبير يجب أن يمر عبر `JsonIsolate` |
| R8 + shrinkResources | ✅ مفعّل | `android/app/build.gradle` buildTypes.release |
| لا `largeHeap` | ✅ | غير موجود في AndroidManifest |
| `MediaQuery.of(context)` | ✅ مُصلَح في هذا الالتزام | 10 مواضع في 6 ملفات → `sizeOf`/`paddingOf` (كانت تُعيد البناء عند أي تغيير MediaQuery) |
| Impeller | ⚠️ قرار قياس | يبقى افتراضياً؛ التعطيل يتطلب مقارنة على جهاز حقيقي (§3.1) — لا تغيير بلا قياس |
| قياس على جهاز ضعيف حقيقي | ⚠️ مطلب تشغيلي | لا يمكن تنفيذه في بيئة التطوير هنا — استخدم أوامر §8.2 على الجهاز المستهدف |
| ClipRRect حول LinearProgressIndicator (×5) | ℹ️ لا تغيير مطلوب | `LinearProgressIndicator` في Flutter 3.44 يطبّق `borderRadius` عبر ClipRRect داخلياً (`progress_indicator.dart:641`) — الاستخدام الحالي مكافئ للإطار، لا مكسب من التغيير |

**قواعد إضافية مطبّقة في `analysis_options.yaml`:** `avoid_print`, `unawaited_futures`, `use_build_context_synchronously`, `cancel_subscriptions`, `close_sinks`, `prefer_const_constructors` + قواعد const/whitespace المضافة في هذا الالتزام.

