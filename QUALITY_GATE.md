# 🏆 Marina Hotel — Quality Gate

> **Pipeline احترافي شامل لضمان جودة الكود** — مكوّن من 4 workflows تعمل تلقائياً على كل Pull Request.

## 📋 جدول المحتووات

- [نظرة عامة](#نظرة-عامة)
- [الـ Workflows الأربعة](#الـ-workflows-الأربعة)
- [مراحل الفحص التفصيلية](#مراحل-الفحص-التفصيلية)
- [حماية الفروع](#حماية-الفروع)
- [التشغيل المحلي](#التشغيل-المحلي)
- [حل المشاكل الشائعة](#حل-المشاكل-الشائعة)

---

## نظرة عامة

Quality Gate يمنع دمج أي Pull Request يحتوي على:

- ❌ كود غير منسّق
- ❌ أخطاء أو تحذيرات في `flutter analyze`
- ❌ تعقيد كود عالي
- ❌ انتهاكات Architecture
- ❌ أسرار مُسربة
- ❌ ثغرات أمنية
- ❌ فشل في البناء

### المبدأ

```
PR → Quality → Test → Security → Build → ✅ جاهز للدمج
                                      ↓
                                  ❌ مرفوض (إن فشل أي مرحلة)
```

---

## الـ Workflows الأربعة

### 1️⃣ Quality (`quality.yml`)
**المراحل:**
1. **Formatting** — `dart format --set-exit-if-changed` (blocking)
2. **Static Analysis** — `flutter analyze --fatal-infos --fatal-warnings` (blocking)
3. **Code Metrics** — `dart_code_metrics` (non-blocking)
4. **Performance Rules** — مُدمجة في Static Analysis (blocking)
5. **Architecture** — `architecture-validator.py` (non-blocking)
6. **Dependency Audit** — `dependency-audit.sh` (non-blocking)

### 2️⃣ Test (`test.yml`)
**المراحل:**
1. **Unit Tests** — `flutter test`
2. **Widget Tests** — مُدمجة
3. **Integration Tests** — مُدمجة
4. **Coverage** — عتبة 60% (قابلة للرفع إلى 85%)
5. **Test Report** — ملخّص في PR UI

### 3️⃣ Security (`security-extended.yml` + `security-scan.yml`)
**المراحل:**
1. **CodeQL** — تحليل دلالي (في security-scan.yml)
2. **Gitleaks** — كشف الأسرار المُسربة
3. **Trivy** — فحص الثغرات في الاعتماديات (في security-scan.yml)
4. **Semgrep** — SAST متعدد اللغات (في security-scan.yml)
5. **License Check** — فحص تراخيص الحزم
6. **Flutter Secret Patterns** — patterns إضافية

### 4️⃣ Build (`build.yml`)
**المراحل:**
1. **Android Debug APK** — `flutter build apk --debug`
2. **Artifact Upload** — رفع APK كـ artifact

---

## مراحل الفحص التفصيلية

### Formatting (`dart format`)

```bash
dart format --line-length 120 --set-exit-if-changed --output=none lib/ test/
```

- **يستثني**: `*.g.dart`, `*.freezed.dart` (ملفات مُولّدة)
- **Blocking**: نعم — أي ملف غير منسّق يفشل الـ PR

### Static Analysis (`flutter analyze`)

```bash
flutter analyze --fatal-infos --fatal-warnings
```

- **القواعد**: `very_good_analysis` + قواعد مخصصة في `analysis_options.yaml`
- **Strict mode**: `strict-casts`, `strict-inference`, `strict-raw-types`
- **Blocking**: نعم — أي info أو warning يفشل الـ PR

### Code Metrics (`dart_code_metrics`)

```bash
metrics analyze lib --config=dart_code_metrics.yaml
```

**الفحوصات:**
- Cyclomatic Complexity (≤20)
- Cognitive Complexity
- Method Length (≤80 lines)
- Class Length (≤1500 lines)
- Number of Parameters (≤6)
- Nesting Level (≤5)
- Long Files
- Technical Debt

### Architecture Validation (`architecture-validator.py`)

```bash
python3 scripts/architecture-validator.py --project-root mobile --strict
```

**القواعد:**
1. لا استيراد UI من Data layer
2. لا استيراد services مباشرة من screens (استخدم providers)
3. لا اعتماد دائري بين الوحدات
4. كل screens تستخدم `ConsumerWidget`/`ConsumerStatefulWidget`
5. لا وصول مباشر لـ `local_db.dart` من UI

### Security (Gitleaks + CodeQL + Trivy)

- **Gitleaks**: يفحص كل git history لكشف الأسرار
- **CodeQL**: تحليل دلالي للكود (PHP, JS, Dart)
- **Trivy**: فحص CVEs في الاعتماديات
- **Custom patterns**: GitHub tokens, Firebase keys, Appwrite keys, Telegram tokens

### Build Verification

- **Android**: `flutter build apk --debug`
- **Windows**: غير مدعوم حالياً
- **Linux**: غير مدعوم حالياً

---

## حماية الفروع

لتفعيل Quality Gate بشكل كامل، يجب إعداد Branch Protection Rules على `main`:

### عبر GitHub UI

1. اذهب إلى Settings → Branches → Add rule
2. Branch name pattern: `main`
3. ✅ Require status checks to pass before merging
4. ✅ Require branches to be up to date before merging
5. أضف الـ status checks التالية:
   - `Code Quality Check`
   - `Test Suite`
   - `Secret Scanning (Gitleaks)`
   - `License Check`
   - `Flutter Secret Patterns`
   - `Android Build`
6. ✅ Require conversation resolution before merging
7. ✅ Require signed commits (اختياري)
8. ✅ Do not allow bypassing the above settings

### عبر GitHub API

```bash
curl -X PUT \
  -H "Authorization: token YOUR_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/NassarAlshabi1/marina-hotel-wit-app/branches/main/protection \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": [
        "Code Quality Check",
        "Test Suite",
        "Secret Scanning (Gitleaks)",
        "License Check",
        "Android Build"
      ]
    },
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "required_approving_review_count": 1,
      "dismiss_stale_reviews": true
    },
    "restrictions": null
  }'
```

---

## التشغيل المحلي

قبل فتح PR، شغّل كل الفحوصات محلياً:

```bash
#!/bin/bash
# scripts/local-quality-check.sh

set -e

cd mobile

echo "🎨 Formatting..."
find lib test -name "*.dart" \
  ! -name "*.g.dart" \
  ! -name "*.freezed.dart" \
  -print0 | xargs -0 dart format --line-length 120 --set-exit-if-changed --output=none

echo "🔍 Static analysis..."
flutter analyze --fatal-infos --fatal-warnings

echo "🏗️ Architecture validation..."
cd ..
python3 scripts/architecture-validator.py --project-root mobile --strict

echo "📦 Dependency audit..."
bash scripts/dependency-audit.sh mobile true

echo "🧪 Tests..."
cd mobile
flutter test --coverage

echo "🔨 Build..."
flutter build apk --debug --no-pub

echo "✅ All quality checks passed!"
```

---

## حل المشاكل الشائعة

### `dart format` يفشل

```bash
# إصلاح التنسيق تلقائياً
dart format --line-length 120 lib/ test/
```

### `flutter analyze` يفشل

```bash
# عرض كل المشاكل
flutter analyze

# إصلاح تلقائي لما يمكن إصلاحه
dart fix --apply
```

### Architecture validator يفشل

#### مشكلة: screens تستورد services مباشرة
```dart
// ❌ خطأ
import 'package:marina_hotel_mobile/services/local_db.dart';

// ✅ صحيح
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
```

#### مشكلة: screen لا يستخدم ConsumerWidget
```dart
// ❌ خطأ
class MyScreen extends StatelessWidget { ... }
class MyScreen extends StatefulWidget { ... }

// ✅ صحيح
class MyScreen extends ConsumerWidget { ... }
class MyScreen extends ConsumerStatefulWidget { ... }
```

### Gitleaks يكتشف secret

1. **لا ت_commit الـ secret** — استخدم `git reset HEAD~1`
2. **أبطِل الـ secret فوراً** من المصدر (Firebase Console, GitHub Settings, etc.)
3. **استخدم متغيرات بيئة** بدلاً من hardcoded values:
   ```dart
   // ❌ خطأ
   const apiKey = 'ghp_xxxxxxxxxxxx';
   
   // ✅ صحيح
   const apiKey = String.fromEnvironment('API_KEY');
   // flutter run --dart-define=API_KEY=your_key
   ```

### Build يفشل

```bash
# تنظيف وإعادة البناء
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --debug
```

---

## إحصائيات Quality Gate

| المؤشر | القيمة الحالية | الهدف |
|---|---|---|
| `flutter analyze` issues | 0 | 0 |
| `dart format` warnings | 0 | 0 |
| Test coverage | ~40% | 85% |
| Architecture violations | 110 (transitional) | 0 |
| Security vulnerabilities | 0 | 0 |
| Build status | ✅ | ✅ |

---

## التحديثات المستقبلية

- [ ] رفع coverage threshold من 60% إلى 85%
- [ ] تفعيل Architecture validator كـ blocking
- [ ] تفعيل Code Metrics كـ blocking
- [ ] إضافة Windows build (عند دعمه)
- [ ] إضافة Linux build (عند دعمه)
- [ ] إضافة LCOV detailed report
- [ ] إضافة SonarCloud integration
