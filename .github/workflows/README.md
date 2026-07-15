# GitHub Actions Workflows — Marina Hotel

> **9 workflows منظّمة** لـ CI/CD pipeline احترافي.

## 📋 جدول المحتويات

- [نظرة عامة](#نظرة-عامة)
- [الـ Workflows](#الـ-workflows)
- [Pipeline Flow](#pipeline-flow)
- [التفعيل التلقائي](#التفعيل-التلقائي)
- [إعدادات Branch Protection](#إعدادات-branch-protection)

---

## نظرة عامة

تم تنظيم الـ workflows من **20 workflow مكرر** إلى **9 workflows منظّمة**:

| # | Workflow | الوظيفة | الحالة |
|---|---|---|---|
| 1 | `quality.yml` | Quality Gate (formatting + analysis + metrics + architecture) | 🔴 Blocking |
| 2 | `test.yml` | اختبارات + coverage | 🟡 Non-blocking |
| 3 | `security-scan.yml` | CodeQL + Trivy + Semgrep + Syft + Grype + npm audit | 🔴 Blocking |
| 4 | `security-extended.yml` | Gitleaks + License Check + Flutter Secret Patterns | 🟡 Non-blocking |
| 5 | `flutter-apk-release.yml` | بناء Release APK | 🟡 Manual/Tag |
| 6 | `flutter-apk-staging.yml` | بناء Staging APK | 🟡 Manual |
| 7 | `pwa-deploy.yml` | نشر PWA | 🟡 Manual |
| 8 | `sonarcloud.yml` | SonarCloud analysis | 🟡 Non-blocking |
| 9 | `maintenance.yml` | تنظيف artifacts + failed runs + cache | ⏰ Scheduled |

---

## الـ Workflows

### 1️⃣ Quality (`quality.yml`)

**الوظيفة**: Quality Gate الرئيسي — يمنع دمج الكود منخفض الجودة.

**المراحل**:
1. 🎨 **Formatting** (blocking) — `dart format --set-exit-if-changed`
2. 🔍 **Static Analysis** (blocking) — `flutter analyze --fatal-infos --fatal-warnings`
3. 📊 **Code Metrics** (non-blocking) — `dart_code_metrics`
4. ⚡ **Performance Rules** (blocking) — مُدمجة في analysis_options.yaml
5. 🏗️ **Architecture** (non-blocking) — `architecture-validator.py`
6. 📦 **Dependency Audit** (non-blocking) — `dependency-audit.sh`

**التفعيل**:
- PR → `main`, `marina`, `refactor/**`, `feature/**`
- Push → `main`
- Manual

---

### 2️⃣ Test (`test.yml`)

**الوظيفة**: تشغيل كل الاختبارات + حساب التغطية.

**المراحل**:
1. 🧪 Unit Tests + Widget Tests + Integration Tests
2. 📈 Coverage analysis (عتبة 60% — قابلة للرفع إلى 85%)
3. 📋 Test Report في PR UI

**التفعيل**: مثل `quality.yml`

---

### 3️⃣ Security Scan (`security-scan.yml`)

**الوظيفة**: فحص أمني شامل متعدد الطبقات (Defense-in-Depth).

**الـ Jobs (9)**:
| Job | الأداة | الوظيفة |
|---|---|---|
| CodeQL | GitHub CodeQL | تحليل دلالي (SAST) |
| Semgrep | Semgrep | SAST متعدد اللغات + supply-chain |
| Trivy | Trivy | filesystem + secrets + license |
| Syft + Grype | Syft + Grype | SBOM generation + CVE matching |
| npm audit | npm | Node.js dependencies |
| pub security | pub.dev | Flutter/Dart packages |
| PHP security | sensiolabs + Psalm | PHP vulnerabilities |
| Malware | socket-security-cli | npm malware detection |
| Summary | — | تجميع النتائج |

**التفعيل**:
- PR → `main`, `marina`, `refactor/clean-v2`
- Push → نفس الفروع
- Schedule: يومياً 02:30 Asia/Aden
- Manual

---

### 4️⃣ Security Extended (`security-extended.yml`)

**الوظيفة**: فحوصات أمنية إضافية مُكمّلة لـ `security-scan.yml`.

**الـ Jobs (3)**:
1. 🔐 **Gitleaks** — كشف الأسرار المُسربة في git history (non-blocking)
2. 📜 **License Check** — فحص تراخيص الحزم + project LICENSE
3. 🔍 **Flutter Secret Patterns** — patterns مخصصة (Appwrite, Firebase, Telegram)

**التفعيل**: مثل `quality.yml`

---

### 5️⃣ Flutter APK Release (`flutter-apk-release.yml`)

**الوظيفة**: بناء Release APK للنشر على Production.

**المراحل**:
1. Checkout + Flutter setup
2. build_runner
3. `flutter build apk --release`
4. Upload APK artifact

**التفعيل**:
- Push → `main`, `marina`
- PR → `main`
- Manual

---

### 6️⃣ Flutter APK Staging (`flutter-apk-staging.yml`)

**الوظيفة**: بناء Staging APK للاختبار.

**التفعيل**: Manual فقط

---

### 7️⃣ PWA Deploy (`pwa-deploy.yml`)

**الوظيفة**: بناء ونشر Progressive Web App.

**التفعيل**:
- Push → `marina`
- Manual

---

### 8️⃣ SonarCloud (`sonarcloud.yml`)

**الوظيفة**: تحليل جودة الكود عبر SonarCloud.

**التفعيل**:
- Push → `main`, `marina`
- PR → `main`, `marina`
- Manual

---

### 9️⃣ Maintenance (`maintenance.yml`)

**الوظيفة**: مهام صيانة دورية لتقليل استهلاك storage.

**الـ Jobs (3)**:
1. 🧹 **Clean Old Artifacts** — حذف artifacts أقدم من 30 يوم
2. 🧹 **Clean Failed Workflow Runs** — الاحتفاظ بآخر 100 run فاشل فقط
3. 🧹 **Clean Old Cache** — حذف caches لم تُستخدم منذ 7 أيام

**التفعيل**:
- Schedule: يومياً منتصف الليل UTC
- Manual

---

## Pipeline Flow

```
PR إلى main/marina/refactor/**
    ↓
┌─────────────────────────────────────────────────┐
│  1. Quality Workflow                            │
│     ├─ 🎨 Formatting (blocking)                │
│     ├─ 🔍 Static Analysis (blocking)           │
│     ├─ 📊 Code Metrics (non-blocking)          │
│     ├─ ⚡ Performance Rules (blocking)          │
│     ├─ 🏗️ Architecture (non-blocking)          │
│     └─ 📦 Dependency Audit (non-blocking)      │
├─────────────────────────────────────────────────┤
│  2. Test Workflow                               │
│     ├─ 🧪 Unit/Widget/Integration Tests        │
│     └─ 📈 Coverage (60% threshold)             │
├─────────────────────────────────────────────────┤
│  3. Security Scan (شامل)                        │
│     ├─ CodeQL + Semgrep + Trivy                │
│     ├─ Syft + Grype + npm audit                │
│     └─ pub security + PHP + Malware            │
├─────────────────────────────────────────────────┤
│  4. Security Extended                           │
│     ├─ 🔐 Gitleaks (non-blocking)              │
│     ├─ 📜 License Check                        │
│     └─ 🔍 Flutter Secret Patterns              │
├─────────────────────────────────────────────────┤
│  5. SonarCloud (optional)                       │
└─────────────────────────────────────────────────┘
    ↓
✅ جاهز للدمج  OR  ❌ مرفوض
```

---

## التفعيل التلقائي

### عند فتح PR إلى `main`:
- ✅ `quality.yml` — يعمل تلقائياً
- ✅ `test.yml` — يعمل تلقائياً
- ✅ `security-scan.yml` — يعمل تلقائياً
- ✅ `security-extended.yml` — يعمل تلقائياً
- ✅ `sonarcloud.yml` — يعمل تلقائياً

### عند Push إلى `main`:
- ✅ كل الـ workflows أعلاه
- ✅ `flutter-apk-release.yml` — يعمل تلقائياً

### عند Push tag `v*`:
- ✅ `flutter-apk-release.yml` — يعمل تلقائياً

### يومياً (Scheduled):
- ⏰ `security-scan.yml` — 02:30 Asia/Aden
- ⏰ `maintenance.yml` — منتصف الليل UTC

### Manual فقط:
- 🔄 `flutter-apk-staging.yml`
- 🔄 `pwa-deploy.yml`

---

## إعدادات Branch Protection

لتفعيل Quality Gate بشكل كامل على `main`:

```bash
# عبر GitHub API
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
        "Security & Malware Scan",
        "Secret Scanning (Gitleaks)",
        "License Check"
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

أو عبر GitHub UI:
1. Settings → Branches → Add rule
2. Branch name: `main`
3. ✅ Require status checks to pass before merging
4. ✅ Require branches to be up to date before merging
5. أضف الـ status checks أعلاه

---

## Workflows المُحذوفة (التاريخ)

تم حذف الـ workflows التالية لعدم التكرار أو عدم الصلاحية:

| Workflow | السبب |
|---|---|
| `analyze-dart.yml` | مكرر مع `quality.yml` |
| `build-and-test.yml` | مكرر مع `test.yml` |
| `build.yml` | مكرر مع `flutter-apk-release.yml` |
| `ci.yml` | مكرر مع `quality.yml` + `test.yml` |
| `code-quality.yml` | مكرر تماماً مع `quality.yml` |
| `cleanup-failed-runs.yml` | مُدمج في `maintenance.yml` |
| `clean-old-artifacts.yml` | مُدمج في `maintenance.yml` |
| `debug-apk-clean-v2.yml` | مكرر |
| `fix_and_lint.yml` | خطير — يُعدّل الكود تلقائياً |
| `flutter-windows-release.yml` | المشروع لا يدعم Windows |
| `main.yml` | مكرر مع `flutter-apk-release.yml` |
| `sync-fields-audit.yml` | مُحدد الهدف جداً |
| `ethicalcheck.yml` | action محذوف من GitHub |
| `fortify.yml` | يتطلب commercial license |
