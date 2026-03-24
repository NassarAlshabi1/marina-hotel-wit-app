# 🤖 Zencoder AI Agent - دليل سريع

## 📚 الملفات الموجودة

### 📖 التوثيق
| الملف | الوصف |
|------|-------|
| `ZENCODER_SETUP_GUIDE.md` | 📝 **دليل الإعداد الشامل** - خطوة بخطوة لإعداد Zencoder |
| `ZENCODER_WORKFLOW_EXAMPLES.md` | 💡 **أمثلة Workflows** - نماذج جاهزة وPrompts مفيدة |
| `.github/workflows/README.md` | 📋 **دليل الـ Workflows** - شرح سريع للملفات |

### 🛠️ Scripts المساعدة
| Script | الاستخدام |
|--------|----------|
| `setup-zencoder-secrets.sh` | ⚙️ **إعداد Secrets** - إضافة credentials بسهولة |
| `check-zencoder-config.sh` | 🔍 **فحص الإعداد** - التأكد من صحة Configuration |

### ⚙️ Workflows
| Workflow | الوصف | التشغيل |
|----------|-------|---------|
| `zen-agent-review.yml` | مراجعة PRs تلقائياً | على كل PR |
| `zencoder-manual.yml` | تشغيل يدوي مع prompt مخصص | يدوي |
| `zencoder-code-quality.yml` | فحص جودة الكود | على PRs |
| `zencoder-security-scan.yml` | فحص أمني شامل | أسبوعياً + يدوي |
| `zencoder-auto-tests.yml` | إنشاء اختبارات تلقائياً | عند تعديل الكود |

---

## 🚀 البدء السريع (3 خطوات)

### 1️⃣ احصل على Credentials من Zencoder
```bash
# افتح في المتصفح
https://auth.zencoder.ai/profile
# Settings → Personal Tokens
# انسخ CLIENT_ID و CLIENT_SECRET
```

### 2️⃣ أضف Secrets إلى GitHub
```bash
# الطريقة السهلة - استخدم الـ Script
./setup-zencoder-secrets.sh

# أو يدوياً عبر GitHub Website
# Settings → Secrets and variables → Actions → New repository secret
```

### 3️⃣ شغّل Workflow
```bash
# تشغيل يدوي
gh workflow run zen-agent-review.yml --ref capy/test2

# أو push commit
git commit --allow-empty -m "test: Trigger Zencoder"
git push
```

---

## 🔍 التحقق من الإعداد

```bash
# تشغيل الفحص التلقائي
./check-zencoder-config.sh

# إذا كل شيء ✅ جاهز!
# إذا ظهرت ❌ أخطاء، راجع ZENCODER_SETUP_GUIDE.md
```

---

## 📖 أين تجد المعلومات؟

### للمبتدئين:
1. ابدأ بـ: `ZENCODER_SETUP_GUIDE.md` - دليل مفصل خطوة بخطوة
2. ثم راجع: `.github/workflows/README.md` - نظرة سريعة على الـ Workflows

### للمستخدمين المتقدمين:
1. راجع: `ZENCODER_WORKFLOW_EXAMPLES.md` - أمثلة شاملة وPrompts متقدمة
2. عدّل الـ Workflows في: `.github/workflows/`

---

## 💡 أمثلة سريعة

### تشغيل Agent على كود معين
```bash
# استخدام Manual Workflow
gh workflow run zencoder-manual.yml \
  --ref capy/test2 \
  -f prompt="Fix dart flutter" \
  -f model="sonnet-4"
```

### مراقبة التنفيذ
```bash
# عرض آخر التشغيلات
gh run list --workflow zen-agent-review.yml --limit 5

# مشاهدة Log مباشرة
gh run watch $(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
```

### أمثلة Prompts مفيدة
```yaml
# إصلاح Dart/Flutter
"Fix dart flutter"

# مراجعة شاملة
"Review code quality, check for bugs, and suggest improvements"

# فحص أمني
"Analyze code for security vulnerabilities and hardcoded secrets"

# إنشاء اختبارات
"Generate comprehensive unit tests with 80%+ coverage"
```

---

## 🆘 المساعدة وحل المشاكل

### المشكلة: خطأ 400 Bad Request
**الحل:**
```bash
# تأكد من صحة Secrets
# Settings → Secrets → تحقق من:
# - ZENCODER_CLIENT_ID ✓
# - ZENCODER_CLIENT_SECRET ✓
```

### المشكلة: Workflow لا يعمل
**الحل:**
```bash
# تحقق من Workflow Files
ls -la .github/workflows/zen*.yml

# تأكد أنك على الفرع الصحيح
git branch --show-current

# راجع Logs
gh run view <run-id> --log
```

### المشكلة: Permission Denied
**الحل:**
- تأكد أن لديك صلاحيات Admin على المستودع
- أو استخدم `CICD_TOKEN` بدلاً من `GITHUB_TOKEN`

---

## 🔗 روابط مفيدة

| الرابط | الوصف |
|--------|-------|
| [Zencoder Profile](https://auth.zencoder.ai/profile) | للحصول على Credentials |
| [Zencoder Docs](https://docs.zencoder.ai) | التوثيق الرسمي |
| [zen-agents-action](https://github.com/zencoderai/zen-agents-action) | GitHub Action |
| [GitHub Tokens](https://github.com/settings/tokens) | إنشاء Personal Access Token |

---

## ✅ Checklist

قبل الاستخدام، تأكد من:

- [ ] حصلت على `ZENCODER_CLIENT_ID` و `ZENCODER_CLIENT_SECRET`
- [ ] أضفت الـ Secrets إلى GitHub Repository
- [ ] الـ Workflow Files موجودة في `.github/workflows/`
- [ ] لديك صلاحيات مناسبة على المستودع
- [ ] قمت بتشغيل `./check-zencoder-config.sh`

---

## 🎯 الخطوات التالية

بعد إتمام الإعداد:

1. ✅ جرب Workflows المختلفة
2. ✅ خصص Prompts حسب احتياجاتك
3. ✅ اقرأ التوثيق الكامل في `ZENCODER_WORKFLOW_EXAMPLES.md`
4. ✅ شارك النماذج الناجحة مع فريقك

---

**آخر تحديث:** 29 يناير 2026  
**الحالة:** ✅ جاهز للاستخدام  
**النسخة:** 1.0.0

---

## 📞 الدعم

واجهت مشكلة؟
1. راجع `ZENCODER_SETUP_GUIDE.md` للحلول التفصيلية
2. شغّل `./check-zencoder-config.sh` للتشخيص
3. تحقق من Logs: `gh run view <run-id> --log`
4. اتصل بـ Zencoder Support عبر Discord أو Email
