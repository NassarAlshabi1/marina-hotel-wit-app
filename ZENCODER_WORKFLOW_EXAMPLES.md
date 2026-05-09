# نماذج Zencoder GitHub Actions Workflows

## 📋 جدول المحتويات
1. [المقدمة](#المقدمة)
2. [المتطلبات الأساسية](#المتطلبات-الأساسية)
3. [إعداد الـ Secrets](#إعداد-الـ-secrets)
4. [أمثلة Workflows](#أمثلة-workflows)
5. [Parameters المتاحة](#parameters-المتاحة)
6. [نماذج Prompts](#نماذج-prompts)

## المقدمة

Zencoder Agents Action هو GitHub Action يتيح لك تشغيل وكلاء ذكاء اصطناعي على الكود الخاص بك. يمكن استخدامه لـ:
- مراجعة Pull Requests تلقائياً
- إصلاح أخطاء Dart/Flutter
- تحليل الكود وكشف المشاكل
- تحسين الكود وإعادة الهيكلة
- كتابة الاختبارات تلقائياً

## المتطلبات الأساسية

### 1. الحصول على بيانات المصادقة
انتقل إلى: https://auth.zencoder.ai/profile
- اضغط على **Settings** → **Personal Tokens**
- احصل على `CLIENT_ID` و `CLIENT_SECRET`

### 2. إنشاء GitHub Personal Access Token
1. اذهب إلى GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. اضغط **Generate new token** → **Generate new token (classic)**
3. اختر الصلاحيات التالية:
   - `repo` - Full control of private repositories
   - `workflow` - Update GitHub Action workflows
4. احفظ الـ Token بشكل آمن

## إعداد الـ Secrets

### على مستوى المستودع (Repository-Level)
1. اذهب إلى **Repository Settings** → **Secrets and variables** → **Actions**
2. اضغط **New repository secret**
3. أضف الـ Secrets التالية:

| Secret Name | القيمة | الوصف |
|------------|--------|-------|
| `ZENCODER_CLIENT_ID` | Client ID من Zencoder | معرف المصادقة |
| `ZENCODER_CLIENT_SECRET` | Client Secret من Zencoder | مفتاح المصادقة |
| `CICD_TOKEN` | GitHub Personal Access Token | للصلاحيات الموسعة |

### على مستوى المنظمة (Organization-Level)
1. اذهب إلى **Organization Settings** → **Secrets and variables** → **Actions**
2. اضغط **New organization secret**
3. أضف نفس الـ Secrets أعلاه
4. اختر المستودعات التي يمكنها الوصول للـ Secrets

## أمثلة Workflows

### 1️⃣ مراجعة Pull Requests تلقائياً

**الملف:** `.github/workflows/zencoder-pr-review.yml`

```yaml
name: Zencoder PR Review

on:
  pull_request:
    types: [opened, synchronize]
    branches: 
      - '**'  # جميع الفروع
  pull_request_review:
    types: [submitted]

jobs:
  review:
    if: |
      github.event_name == 'pull_request' ||
      (github.event_name == 'pull_request_review' &&
       github.event.review.user.login == 'zencoderai')
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run PR Review
        uses: zencoderai/zen-agents-action@main
        with:
          prompt: "Review pull request #${{ github.event.pull_request.number }} and add comments. Focus on serious issues only."
          zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
          zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
          github_token: "${{ secrets.CICD_TOKEN }}"
```

### 2️⃣ إصلاح أخطاء Dart/Flutter

**الملف:** `.github/workflows/fix-dart-flutter.yml`

```yaml
name: Fix Dart Flutter Issues

on:
  pull_request:
    branches:
      - '**'
  workflow_dispatch:  # تشغيل يدوي

jobs:
  fix-dart:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Fix Dart/Flutter Issues
        uses: zencoderai/zen-agents-action@main
        with:
          prompt: "Fix dart flutter"
          zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
          zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
          github_token: "${{ secrets.GITHUB_TOKEN }}"
```

### 3️⃣ تنفيذ يدوي مع Prompt مخصص

**الملف:** `.github/workflows/zencoder-manual.yml`

```yaml
name: Run Zencoder Agent Manually

on:
  workflow_dispatch:
    inputs:
      prompt:
        type: string
        description: "The input prompt for the Agent"
        required: true
      agent:
        type: string
        description: "Alias of the agent to run"
        required: false
        default: ""
      model:
        type: choice
        description: "LLM model to use"
        required: false
        default: "default"
        options:
          - default
          - opus-4-5
          - sonnet-4
          - gemini-25-pro

jobs:
  agent-run:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Running Zencoder Agent
        uses: zencoderai/zen-agents-action@main
        with:
          prompt: "${{ inputs.prompt }}"
          agent: "${{ inputs.agent }}"
          model: "${{ inputs.model }}"
          zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
          zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
          github_token: "${{ secrets.GITHUB_TOKEN }}"
```

### 4️⃣ تحليل الأمان Security Analysis

**الملف:** `.github/workflows/security-scan.yml`

```yaml
name: Security Analysis

on:
  schedule:
    - cron: '0 2 * * 1'  # كل يوم اثنين الساعة 2 صباحاً
  workflow_dispatch:

jobs:
  security-scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run Security Analysis
        uses: zencoderai/zen-agents-action@main
        with:
          prompt: "Analyze the codebase for security vulnerabilities and create issues for critical findings"
          zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
          zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
          github_token: "${{ secrets.CICD_TOKEN }}"
```

### 5️⃣ إنشاء Unit Tests تلقائياً

**الملف:** `.github/workflows/auto-tests.yml`

```yaml
name: Generate Unit Tests

on:
  pull_request:
    types: [opened, synchronize]
    paths:
      - '**.dart'
      - '**.js'
      - '**.ts'

jobs:
  generate-tests:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Generate Tests
        uses: zencoderai/zen-agents-action@main
        with:
          prompt: "Generate unit tests for all modified files in this pull request. Follow best practices and ensure good coverage."
          zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
          zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
          github_token: "${{ secrets.CICD_TOKEN }}"
```

### 6️⃣ تحليل جودة الكود Code Quality

**الملف:** `.github/workflows/code-quality.yml`

```yaml
name: Code Quality Analysis

on:
  pull_request:
    branches:
      - main
      - develop

jobs:
  quality-check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Analyze Code Quality
        uses: zencoderai/zen-agents-action@main
        with:
          prompt: "Analyze code quality in this PR. Check for: code smells, performance issues, maintainability problems, and suggest improvements."
          model: "sonnet-4"
          zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
          zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
          github_token: "${{ secrets.GITHUB_TOKEN }}"
```

## Parameters المتاحة

| Parameter | النوع | مطلوب | القيمة الافتراضية | الوصف |
|-----------|------|-------|------------------|-------|
| `prompt` | String | ✅ نعم | - | التعليمات للـ Agent |
| `zencoder_client_id` | String | ✅ نعم | - | معرف المصادقة |
| `zencoder_client_secret` | String | ✅ نعم | - | مفتاح المصادقة |
| `github_token` | String | ✅ نعم | - | GitHub Token للوصول للـ APIs |
| `agent` | String | ❌ لا | `""` | اسم Agent محدد للتشغيل |
| `base_path` | String | ❌ لا | `"."` | المسار الأساسي للمشروع |
| `model` | String | ❌ لا | `"default"` | نموذج الذكاء الاصطناعي |
| `version` | String | ❌ لا | `"latest"` | إصدار Zencoder CLI |

### النماذج المتاحة (models)
- `default` - النموذج الافتراضي من السيرفر
- `opus-4-5` - Claude Opus 4.5 (الأقوى)
- `sonnet-4` - Claude Sonnet 4 (متوازن)
- `gemini-25-pro` - Google Gemini 2.5 Pro

## نماذج Prompts

### 🔧 إصلاح المشاكل
```yaml
prompt: "Fix dart flutter"
prompt: "Fix all TypeScript errors in this codebase"
prompt: "Resolve all linting issues"
prompt: "Fix failing tests and update test cases"
```

### 🔍 المراجعة والتحليل
```yaml
prompt: "Review this PR focusing on security vulnerabilities"
prompt: "Analyze code complexity and suggest simplifications"
prompt: "Check for performance bottlenecks in the modified files"
prompt: "Review API design and suggest improvements"
```

### ✅ الاختبارات
```yaml
prompt: "Generate unit tests for all new functions"
prompt: "Create integration tests for the API endpoints"
prompt: "Add E2E tests for the new features"
prompt: "Review existing tests and suggest improvements"
```

### 📝 التوثيق
```yaml
prompt: "Generate JSDoc comments for all public functions"
prompt: "Create README documentation for this feature"
prompt: "Add inline comments to explain complex logic"
prompt: "Generate API documentation from the code"
```

### ♻️ إعادة الهيكلة
```yaml
prompt: "Refactor repeated code into reusable functions"
prompt: "Apply SOLID principles to this module"
prompt: "Modernize legacy code to use latest patterns"
prompt: "Extract business logic from controllers"
```

## إعدادات الصلاحيات

لضمان عمل Workflows بشكل صحيح:

1. **Workflow Permissions:**
   - اذهب إلى: **Settings** → **Actions** → **General**
   - تحت "Workflow permissions":
     - اختر: ✅ **Read and write permissions**
     - فعّل: ✅ **Allow GitHub Actions to create and approve pull requests**

2. **Branch Protection:**
   - يمكنك إضافة Zencoder كـ required check
   - اذهب إلى: **Settings** → **Branches** → **Branch protection rules**

## استكشاف الأخطاء

### ❌ "GitHub tools not available"
- **الحل:** تأكد من إضافة `GITHUB_TOKEN` أو `CICD_TOKEN`
- تحقق من صلاحيات الـ Token

### ❌ "Authentication failed"
- **الحل:** تأكد من صحة `ZENCODER_CLIENT_ID` و `ZENCODER_CLIENT_SECRET`
- تحقق من أن الـ Token لم تنتهي صلاحيته

### ❌ "Workflow doesn't trigger"
- **الحل:** تأكد من صحة بناء ملف YAML
- تحقق من أن الـ workflow في الفرع الافتراضي
- راجع قواعد حماية الفروع

### 🔍 تفعيل Debug Logging
أضف إلى الـ workflow:
```yaml
env:
  ACTIONS_STEP_DEBUG: true
  ACTIONS_RUNNER_DEBUG: true
```

## أمثلة متقدمة

### تشغيل Agent على ملفات محددة
```yaml
- name: Check Mobile App
  uses: zencoderai/zen-agents-action@main
  with:
    base_path: "./mobile"
    prompt: "Review Flutter code in mobile directory"
    zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
    zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
    github_token: "${{ secrets.GITHUB_TOKEN }}"
```

### استخدام Agent مخصص
```yaml
- name: Run Custom Agent
  uses: zencoderai/zen-agents-action@main
  with:
    agent: "flutter-expert"  # agent مخصص تم إنشاؤه في Zencoder
    prompt: "Optimize Flutter performance"
    zencoder_client_id: "${{ secrets.ZENCODER_CLIENT_ID }}"
    zencoder_client_secret: "${{ secrets.ZENCODER_CLIENT_SECRET }}"
    github_token: "${{ secrets.GITHUB_TOKEN }}"
```

## الموارد والروابط

- 📖 **الوثائق الرسمية:** https://docs.zencoder.ai
- 🔐 **إعداد Tokens:** https://auth.zencoder.ai/profile
- 🐙 **GitHub Repository:** https://github.com/zencoderai/zen-agents-action
- 📚 **مكتبة Agents:** https://github.com/zencoderai/zenagents-library

## ملاحظات أمان 🔒

1. **لا تضع الـ Tokens في الكود مباشرة** - استخدم GitHub Secrets فقط
2. **قم بتجديد الـ Tokens دورياً** - كل 90 يوم على الأقل
3. **استخدم أقل الصلاحيات المطلوبة** - لا تعطي صلاحيات زائدة
4. **راقب استخدام الـ Actions** - تابع الـ billing والاستخدام

---

**تم التحديث:** يناير 2026
**الإصدار:** 1.0.0
