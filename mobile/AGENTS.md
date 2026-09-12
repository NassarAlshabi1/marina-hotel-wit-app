# AGENTS.md — تعليمات إلزامية للوكلاء البرمجية والمساهمين

## قاعدة أولى لا استثناء لها

> **اتبع `docs/PERFORMANCE.md` في كل تغيير.**
> دليل الأداء على الأجهزة الضعيفة (Android · 1GB RAM) هو المرجع التعاقدي لهذا المشروع.

## ما الذي يعنيه هذا عملياً

1. **قبل أي PR / Commit:** راجع قائمة التحقق في `docs/PERFORMANCE.md` §10 (PR Gate) وتأكد من كل بند ينطبق على تغييرك.
2. **قواعد ذهبية مختصرة** (التفصيل والأدلة في الدليل):
   - كل `Controller` / `StreamSubscription` / `Timer` يُغلق في `dispose()` — لا استثناء.
   - أي صورة جديدة: `cacheWidth`/`cacheHeight` (أو `memCache*` للشبكة) مضروبة في `devicePixelRatio`.
   - لا `BackdropFilter` / `Opacity` / `ShaderMask` / `ClipRRect`-حول-صورة بدون بديل أخف أو مبرر موثق.
   - `MediaQuery.sizeOf` / `paddingOf` / `devicePixelRatioOf` — لا `MediaQuery.of(context)` إلا لسبب موثق.
   - أي `jsonDecode` متوقع تجاوز 50KB → استخدم `JsonIsolate` من `lib/utils/json_isolate.dart`.
   - لا تهيئة ثقيلة جديدة في `main()` قبل `runApp()` — استخدم `addPostFrameCallback` (انظر النمط الحالي في `lib/main.dart`).
   - القوائم الديناميكية عبر `ListView.builder` / `PaginatedDataTable` — لا `SingleChildScrollView` + `Column` للقوائم.
   - لا قصّ SQL (`LIMIT`) في مسارات عرض البيانات — الحماية في طبقة العرض فقط (قرار موثق بسبب إصلاح guest infos).
   - `print()` ممنوع — استخدم `dlog`/`dwarn` أو `AppLogger`.
3. **قياس لا تخمين:** أي تحسين أداء أو قرار Impeller يجب أن يُثبت بأرقام من جهاز ضعيف حقيقي في Profile Mode (أوامر §8.2).
4. **حالة الامتثال الحالية** موثقة بالأدلة في `docs/PERFORMANCE.md` §13 — اقرأها قبل ادعاء "الإصلاح" لشيء مطبق أصلاً.
