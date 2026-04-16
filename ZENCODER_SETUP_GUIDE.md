# 🔧 دليل إعداد Zencoder بالتفصيل

## ⚠️ المشكلة الحالية
حصل خطأ `400 Bad Request` عند تشغيل Workflow، وهذا يعني:
- الـ Secrets غير موجودة أو غير صحيحة
- أو الـ credentials منتهية الصلاحية

---

## 📝 الخطوات المطلوبة (بالتفصيل)

### الخطوة 1: الحصول على Zencoder Credentials

#### 1.1 تسجيل الدخول إلى Zencoder
1. افتح المتصفح واذهب إلى: **https://auth.zencoder.ai/**
2. سجل دخول بحسابك (أو أنشئ حساب جديد)

#### 1.2 الوصول للـ Profile
1. بعد تسجيل الدخول، اضغط على أيقونة الملف الشخصي (أعلى اليمين)
2. أو اذهب مباشرة إلى: **https://auth.zencoder.ai/profile**

#### 1.3 إنشاء Personal Token
1. في صفحة Profile، اضغط على **Settings** (الإعدادات)
2. ثم اضغط على **Personal Tokens**
3. اضغط على **Create New Token** أو **Generate Token**
4. سيظهر لك:
   - `CLIENT_ID` - معرف العميل (مثل: `abc123...`)
   - `CLIENT_SECRET` - المفتاح السري (مثل: `xyz789...`)
5. **⚠️ هام جداً:** انسخ هذه القيم الآن - لن تستطيع رؤيتها مرة أخرى!

#### 1.4 حفظ القيم بشكل آمن
```
CLIENT_ID: abc123def456...
CLIENT_SECRET: xyz789uvw123...
```

---

### الخطوة 2: إضافة Secrets إلى GitHub Repository

#### الطريقة الأولى: عبر GitHub Website (موصى بها)

1. **افتح المستودع على GitHub:**
   ```
   https://github.com/NassarAlshabi1/marina-hotel-wit-app
   ```

2. **اذهب إلى Settings:**
   - اضغط على تبويب **Settings** (أعلى الصفحة)
   - إذا لم تظهر، تأكد أن لديك صلاحيات Admin على المستودع

3. **افتح Secrets and variables:**
   - في القائمة الجانبية اليسرى، اضغط على **Secrets and variables**
   - ثم اضغط على **Actions**

4. **أضف Secret جديد:**
   - اضغط على **New repository secret**
   - أضف أول Secret:
     ```
     Name: ZENCODER_CLIENT_ID
     Secret: [الصق CLIENT_ID من Zencoder هنا]
     ```
   - اضغط **Add secret**

5. **أضف Secret الثاني:**
   - اضغط مرة أخرى على **New repository secret**
   - أضف:
     ```
     Name: ZENCODER_CLIENT_SECRET
     Secret: [الصق CLIENT_SECRET من Zencoder هنا]
     ```
   - اضغط **Add secret**

6. **تحقق من الـ Secrets:**
   - يجب أن ترى الآن في القائمة:
     - ✅ `ZENCODER_CLIENT_ID`
     - ✅ `ZENCODER_CLIENT_SECRET`

#### الطريقة الثانية: عبر GitHub CLI (للمتقدمين)

```bash
# انتقل إلى مجلد المشروع
cd /path/to/marina-hotel-wit-app

# أضف ZENCODER_CLIENT_ID
gh secret set ZENCODER_CLIENT_ID
# (سيطلب منك إدخال القيمة، الصقها ثم اضغط Enter)

# أضف ZENCODER_CLIENT_SECRET
gh secret set ZENCODER_CLIENT_SECRET
# (سيطلب منك إدخال القيمة، الصقها ثم اضغط Enter)

# تحقق من الـ Secrets
gh secret list
```

---

### الخطوة 3: (اختياري) إضافة CICD_TOKEN للصلاحيات الموسعة

إذا كنت تريد أن يقوم Agent بـ:
- إنشاء Pull Requests
- إضافة تعليقات على PRs
- تعديل Workflows

#### 3.1 إنشاء GitHub Personal Access Token

1. **اذهب إلى GitHub Settings:**
   ```
   https://github.com/settings/tokens
   ```

2. **أنشئ Token جديد:**
   - اضغط على **Developer settings** (أسفل القائمة)
   - اضغط على **Personal access tokens**
   - اختر **Tokens (classic)**
   - اضغط **Generate new token** → **Generate new token (classic)**

3. **اختر الصلاحيات:**
   - **Note:** `Zencoder CI/CD Token`
   - **Expiration:** 90 days أو Custom
   - **Select scopes:**
     - ✅ `repo` - Full control of private repositories
     - ✅ `workflow` - Update GitHub Action workflows
     - ✅ `write:packages` (اختياري)

4. **احفظ الـ Token:**
   - اضغط **Generate token**
   - انسخ الـ Token (يبدأ بـ `ghp_...`)
   - **⚠️ لن تراه مرة أخرى!**

#### 3.2 أضف الـ Token للـ Repository

1. ارجع لـ Repository Settings → Secrets and variables → Actions
2. اضغط **New repository secret**
3. أضف:
   ```
   Name: CICD_TOKEN
   Secret: [الصق GitHub Token هنا]
   ```
4. اضغط **Add secret**

---

## ✅ الخطوة 4: اختبار الـ Configuration

بعد إضافة الـ Secrets، جرب تشغيل الـ Workflow:

### الطريقة 1: من GitHub Website

1. اذهب إلى: **Actions** tab في GitHub
2. اختر **Run Zencoder Agent on PR review** من القائمة
3. اضغط **Run workflow**
4. اختر branch: `capy/test2`
5. اضغط **Run workflow**
6. راقب التنفيذ

### الطريقة 2: من Command Line

```bash
# تشغيل يدوي
gh workflow run zen-agent-review.yml --ref capy/test2

# الانتظار 10 ثواني ثم مشاهدة التنفيذ
sleep 10 && gh run list --workflow zen-agent-review.yml --limit 1

# مشاهدة الـ logs
gh run list --workflow zen-agent-review.yml --limit 1 --json databaseId --jq '.[0].databaseId' | xargs gh run watch
```

### الطريقة 3: عبر Push Commit

```bash
# push أي تغيير بسيط
git commit --allow-empty -m "test: Trigger Zencoder workflow"
git push origin capy/test2
```

---

## 🔍 استكشاف الأخطاء

### إذا استمر الخطأ 400 Bad Request

1. **تحقق من صحة الـ Credentials:**
   - ارجع لـ https://auth.zencoder.ai/profile
   - تأكد أن الـ Token ما زال نشطاً
   - إذا كان منتهي، أنشئ Token جديد

2. **تحقق من الـ Secrets على GitHub:**
   - Settings → Secrets and variables → Actions
   - تأكد من وجود:
     - `ZENCODER_CLIENT_ID`
     - `ZENCODER_CLIENT_SECRET`
   - لا يجب أن تحتوي على مسافات زائدة

3. **جرب حذف وإعادة إضافة الـ Secrets:**
   - احذف الـ Secrets القديمة
   - أنشئ Token جديد من Zencoder
   - أضف الـ Secrets الجديدة

### إذا ظهر خطأ Permission Denied

- تأكد أن لديك صلاحيات **Admin** على المستودع
- أو اطلب من مالك المستودع إضافة الـ Secrets

### إذا لم يشتغل الـ Workflow على الإطلاق

1. **تحقق من وجود الملف:**
   ```bash
   ls -la .github/workflows/zen-agent-review.yml
   ```

2. **تحقق من صحة YAML:**
   ```bash
   cat .github/workflows/zen-agent-review.yml
   ```

3. **تأكد أن الـ Workflow على الفرع الصحيح:**
   ```bash
   git branch --show-current
   ```

---

## 📖 موارد إضافية

### روابط مهمة:
- 🔐 **Zencoder Profile:** https://auth.zencoder.ai/profile
- 📚 **Zencoder Docs:** https://docs.zencoder.ai
- 🐙 **zen-agents-action GitHub:** https://github.com/zencoderai/zen-agents-action
- 🔑 **GitHub Personal Access Tokens:** https://github.com/settings/tokens

### أمثلة Prompts للتجربة:
```yaml
# إصلاح Dart/Flutter
prompt: "Fix dart flutter"

# مراجعة شاملة
prompt: "Review code quality and suggest improvements"

# إصلاح الأخطاء
prompt: "Fix all linting and compilation errors"

# إنشاء اختبارات
prompt: "Generate unit tests for modified files"

# تحليل أمني
prompt: "Analyze code for security vulnerabilities"
```

---

## 📞 الحصول على المساعدة

إذا واجهت مشاكل:

1. **راجع الـ Logs:**
   ```bash
   gh run view <run-id> --log
   ```

2. **تحقق من Status:**
   ```bash
   gh run list --workflow zen-agent-review.yml --limit 5
   ```

3. **اتصل بـ Zencoder Support:**
   - عبر Discord: https://discord.gg/zencoder
   - أو عبر Email من موقع Zencoder

---

## ✨ الخطوات التالية

بعد نجاح الـ Setup:

1. ✅ جرب Workflows الأخرى:
   - `zencoder-manual.yml` - للتشغيل اليدوي
   - `zencoder-code-quality.yml` - لفحص الجودة
   - `zencoder-security-scan.yml` - للفحص الأمني

2. ✅ راجع التوثيق الكامل:
   - `ZENCODER_WORKFLOW_EXAMPLES.md`
   - `.github/workflows/README.md`

3. ✅ خصص الـ Prompts حسب احتياجك

---

**آخر تحديث:** 29 يناير 2026
**الحالة:** ✅ جاهز للاستخدام بعد إضافة الـ Secrets
