# Zencoder GitHub Workflows

هذا المجلد يحتوي على workflows لـ Zencoder AI Agent.

## 📁 الملفات الموجودة

### 1. `zen-agent-review.yml`
- **الوظيفة:** مراجعة Pull Requests تلقائياً على جميع الفروع
- **التشغيل:** عند فتح أو تحديث PR
- **Prompt:** "Fix dart flutter"

### 2. `zencoder-manual.yml` ⭐ جديد
- **الوظيفة:** تشغيل يدوي مع prompt مخصص
- **التشغيل:** من Actions tab يدوياً
- **المميزات:** 
  - اختيار Prompt مخصص
  - اختيار نموذج الذكاء الاصطناعي
  - اختيار Agent محدد

### 3. `zencoder-code-quality.yml` ⭐ جديد
- **الوظيفة:** فحص جودة الكود
- **التشغيل:** عند PR على main/develop
- **يفحص:** 
  - Code smells
  - مشاكل الأداء
  - ثغرات أمنية
  - Best practices

### 4. `zencoder-security-scan.yml` ⭐ جديد
- **الوظيفة:** فحص أمني شامل
- **التشغيل:** 
  - تلقائياً كل يوم اثنين
  - يدوياً
  - عند push على main
- **يفحص:**
  - SQL Injection
  - XSS vulnerabilities
  - Hardcoded secrets
  - Authentication issues

## 🚀 كيفية الاستخدام

### تشغيل Workflow يدوياً
1. اذهب إلى **Actions** tab
2. اختر الـ Workflow المطلوب
3. اضغط **Run workflow**
4. أدخل البيانات المطلوبة
5. اضغط **Run workflow**

### مثال على Prompts مفيدة
```
- Fix dart flutter
- Review security issues in authentication module
- Generate unit tests for new features
- Optimize database queries
- Refactor duplicate code
- Add documentation comments
```

## ⚙️ الإعدادات المطلوبة

يجب إضافة الـ Secrets التالية في Repository Settings:

| Secret Name | المصدر | الاستخدام |
|------------|--------|----------|
| `ZENCODER_CLIENT_ID` | https://auth.zencoder.ai/profile | مصادقة Zencoder |
| `ZENCODER_CLIENT_SECRET` | https://auth.zencoder.ai/profile | مصادقة Zencoder |
| `CICD_TOKEN` | GitHub Settings | صلاحيات موسعة |

## 📖 الوثائق الكاملة

راجع الملف: `ZENCODER_WORKFLOW_EXAMPLES.md` في جذر المشروع للحصول على:
- أمثلة workflows إضافية
- شرح تفصيلي للـ parameters
- نماذج prompts متنوعة
- دليل استكشاف الأخطاء

## 🔗 روابط مفيدة

- [Zencoder Docs](https://docs.zencoder.ai)
- [Zencoder Profile](https://auth.zencoder.ai/profile)
- [zen-agents-action GitHub](https://github.com/zencoderai/zen-agents-action)
