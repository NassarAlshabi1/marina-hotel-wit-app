# Contributing to Marina Hotel

شكراً لاهتمامك بالمساهمة في مشروع Marina Hotel! هذا الدليل يُوضّح كيفية المساهمة بشكل احترافي.

## 📋 جدول المحتويات

- [البدء](#البدء)
- [Quality Gate](#quality-gate)
- [معايير الكود](#معايير-الكود)
- [عمل Pull Request](#عمل-pull-request)
- [Architecture Rules](#architecture-rules)

## البدء

```bash
# استنساخ المستودع
git clone https://github.com/NassarAlshabi1/marina-hotel-wit-app.git
cd marina-hotel-wit-app

# تثبيت Flutter 3.41.0
flutter --version  # يجب أن يكون 3.41.0

# تثبيت الاعتماديات
cd mobile
flutter pub get

# توليد الكود (drift, freezed, json_serializable)
dart run build_runner build --delete-conflicting-outputs
```

## Quality Gate

كل Pull Request يجب أن يجتاز **Quality Gate** المكوّن من 4 workflows:

### 1. Quality Workflow (`.github/workflows/quality.yml`)
```bash
# تشغيل محلي قبل الـ push
dart format --line-length 120 --set-exit-if-changed lib/ test/
flutter analyze --fatal-infos --fatal-warnings
```

### 2. Test Workflow (`.github/workflows/test.yml`)
```bash
# تشغيل محلي
flutter test --coverage
# العتبة: 60% (قابلة للرفع تدريجياً)
```

### 3. Security Workflow (`.github/workflows/security.yml`)
- CodeQL — تحليل دلالي للكود
- Gitleaks — كشف الأسرار المُسربة
- Trivy — فحص الثغرات في الاعتماديات
- License check

### 4. Build Workflow (`.github/workflows/build.yml`)
```bash
# تشغيل محلي
flutter build apk --debug
```

## معايير الكود

### ✅ مطلوب
- **Formatting**: `dart format --line-length 120`
- **Static Analysis**: `flutter analyze` بدون أخطاء أو تحذيرات
- **Type Safety**: `strict-casts`, `strict-inference`, `strict-raw-types` مُفعّلة
- **Lint Rules**: الالتزام بـ `very_good_analysis` + قواعد إضافية في `analysis_options.yaml`
- **Trailing Commas**: في كل collection/multi-line parameter
- **Documentation**: تعليقات `///` للـ public APIs
- **Tests**: للـ logic الجديد (هدف: 60%+ coverage)

### ❌ ممنوع
- `print()` — استخدم `debugPrint()` أو `AppLogger`
- `dynamic` — استخدم أنواع صريحة
- `BuildContext` بعد `await` بدون `if (!context.mounted) return;`
- Widgets بدون `const` constructor
- `StatelessWidget`/`StatefulWidget` في screens — استخدم `ConsumerWidget`/`ConsumerStatefulWidget`

## Architecture Rules

المشروع يتبع **Clean Architecture + Riverpod**:

```
lib/
├── screens/        # UI layer (ConsumerWidget فقط)
├── widgets/        # Reusable UI components
├── components/     # Layout components
├── providers/      # Riverpod providers (state management)
├── models/         # Domain models
├── repositories/   # Data access abstraction
├── services/       # Business logic + external services
├── data/           # Data sources (local/remote)
├── core/           # Core utilities + constants
├── utils/          # Helper functions
└── tasks/          # Background tasks (WorkManager)
```

### القواعد الإلزامية

| القاعدة | الوصف |
|---|---|
| **UI → State → Domain → Data** | كل طبقة تستورد من الأدنى فقط |
| **No DB from UI** | screens لا تستورد `local_db.dart` مباشرة |
| **No services from UI** | screens تستخدم providers فقط (استثناء: logging, crashlytics) |
| **No circular deps** | لا يوجد اعتماد دائري بين الوحدات |
| **Riverpod** | كل screens تستخدم `ConsumerWidget`/`ConsumerStatefulWidget` |

### التحقق المحلي

```bash
# تشغيل architecture validator
python3 scripts/architecture-validator.py --project-root mobile --strict
```

## عمل Pull Request

1. **أنشئ فرع** من `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **اكتب الكود** مع اتباع المعايير أعلاه

3. **شغّل الفحوصات محلياً**:
   ```bash
   dart format --line-length 120 lib/ test/
   flutter analyze --fatal-infos --fatal-warnings
   flutter test
   python3 scripts/architecture-validator.py --project-root mobile
   ```

4. **Commit برسائل واضحة**:
   ```bash
   git commit -m "feat: add booking export to PDF"
   git commit -m "fix: sync conflict on parallel bookings"
   git commit -m "docs: update API documentation"
   ```
   
   استخدم prefixes:
   - `feat:` ميزة جديدة
   - `fix:` إصلاح خطأ
   - `docs:` توثيق
   - `style:` تنسيق (لا تغيير كود)
   - `refactor:` إعادة هيكلة
   - `test:` اختبارات
   - `chore:` مهام صيانة
   - `ci:` GitHub Actions

5. **ادفع الفرع**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **افتح Pull Request** إلى `main`

7. **انتظر Quality Gate** — يجب أن تمر كل الـ 4 workflows:
   - ✅ Quality
   - ✅ Test
   - ✅ Security
   - ✅ Build

8. **عنوان المراجعة** — على الأقل موافقة واحدة من المراجعين

## معايير المراجعة

المراجعون يتحققون من:

- [ ] الكود يجتاز كل workflows
- [ ] لا أخطاء `flutter analyze`
- [ ] تنسيق صحيح `dart format`
- [ ] اختبارات للـ logic الجديد
- [ ] تعليقات للـ public APIs
- [ ] الالتزام بـ Architecture Rules
- [ ] لا `print()` أو `debugPrint()` زائد
- [ ] رسائل commit واضحة
- [ ] تحديث CHANGELOG.md للتغييرات الجوهرية

## الأسئلة الشائعة

### كيف أُضيف lint rule جديدة؟
أضفها في `mobile/analysis_options.yaml` تحت `linter.rules`.

### كيف أُضيف dependency جديدة؟
```bash
cd mobile
flutter pub add package_name
# أو للـ dev dependencies:
flutter pub add --dev package_name
```
تأكد أن الحزمة لا تتعارض مع الإصدارات الموجودة.

### كيف أُبلغ عن خطأ؟
افتح [Issue جديد](https://github.com/NassarAlshabi1/marina-hotel-wit-app/issues) مع:
- وصف واضح للمشكلة
- خطوات إعادة الإنتاج
- السلوك المتوقع vs الفعلي
- لقطات شاشة (إن أمكن)
