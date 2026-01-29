# Zencoder AI Agent Workflow Setup

تم إضافة workflow جديد لاستخدام Zencoder AI Agents لمراجعة Pull Requests تلقائياً.

## المتطلبات الأساسية

### 1. إنشاء حساب Zencoder

1. انتقل إلى [Zencoder](https://zencoder.ai/)
2. أنشئ حساباً جديداً
3. انتقل إلى [Profile Settings](https://auth.zencoder.ai/profile)
4. اضغط على **Settings** -> **Personal Tokens**
5. احصل على:
   - `ZENCODER_CLIENT_ID`
   - `ZENCODER_CLIENT_SECRET`

### 2. إضافة Secrets إلى GitHub

1. انتقل إلى صفحة المشروع على GitHub
2. اذهب إلى **Settings** -> **Secrets and variables** -> **Actions**
3. أضف Secret جديد باسم `ZENCODER_CLIENT_ID` والصق القيمة
4. أضف Secret جديد باسم `ZENCODER_CLIENT_SECRET` والصق القيمة

**ملاحظة:** `GITHUB_TOKEN` متوفر بشكل تلقائي في GitHub Actions.

## استخدام الـ Workflow

### المراجعة التلقائية للـ Pull Requests

يتم تشغيل الـ workflow تلقائياً عند:
- فتح Pull Request جديد على فرع `main` أو فروع `capy/**`
- إضافة commits جديدة إلى Pull Request موجود

سيقوم الـ AI Agent بـ:
- مراجعة التغييرات في الـ PR
- كتابة تعليق بالمشاكل الجدية فقط
- كتابة "Looks good to me!" إذا لم يجد مشاكل جدية

### التشغيل اليدوي

يمكنك تشغيل الـ Agent يدوياً من خلال:

1. انتقل إلى **Actions** في صفحة المشروع
2. اختر **Zencoder AI Agent Review**
3. اضغط على **Run workflow**
4. أدخل:
   - **prompt**: التعليمات التي تريد من الـ Agent تنفيذها
   - **agent** (اختياري): alias الـ agent المحدد
   - **pr_number** (اختياري): رقم الـ PR للمراجعة

### أمثلة على Prompts

```
Please review the pull request with number 123 and add comment to it.
```

```
Please analyze the code quality in the mobile directory and provide suggestions for improvements.
```

```
Please check for security vulnerabilities in the authentication code.
```

## الملف المستخدم

`zen-agent-review.yml` - يحتوي على:
- **zen-agent-pr-review**: job تلقائي لمراجعة PRs
- **zen-agent-manual**: job يدوي للتشغيل بناءً على prompt مخصص

## تخصيص الـ Workflow

يمكنك تعديل الملف `zen-agent-review.yml` لتخصيص:
- الفروع المستهدفة
- نص الـ prompt
- نموذج الذكاء الاصطناعي (model)
- إعدادات إضافية

## المزيد من المعلومات

- [Zencoder Documentation](https://zencoder.ai/docs)
- [zen-agents-action Repository](https://github.com/zencoderai/zen-agents-action)
