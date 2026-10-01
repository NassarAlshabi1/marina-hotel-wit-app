# 🛠️ Scripts - Marina Hotel Mobile

مجموعة أدوات مساعدة لتطوير ونشر تطبيق Marina Hotel Mobile.

## 📁 الملفات المتاحة

### 🚀 `create-release.sh`
**الوظيفة**: إنشاء إصدار جديد تلقائياً مع GitHub Actions

#### المميزات:
- ✅ إنشاء Git Tag مع ملاحظات الإصدار
- ✅ تشغيل GitHub Action للبناء التلقائي  
- ✅ فحص حالة Git قبل الإصدار
- ✅ واجهة تفاعلية سهلة الاستخدام
- ✅ فتح GitHub Actions في المتصفح

#### الاستخدام:
```bash
# تشغيل السكربت
./scripts/create-release.sh

# أو مع صلاحيات تلقائية
chmod +x scripts/create-release.sh
./scripts/create-release.sh
```

#### متطلبات:
- `git` مثبت ومُهيأ
- `gh` CLI (اختياري للمميزات المتقدمة)
- صلاحيات push للـ repository

#### خطوات العمل:
1. **فحص الحالة الحالية** - التأكد من Git status
2. **طلب رقم الإصدار** - يجب أن يكون بصيغة `v1.0.0`
3. **طلب ملاحظات الإصدار** - اختياري
4. **إنشاء Git Tag** مع الملاحظات
5. **رفع Tag** إلى GitHub
6. **تشغيل GitHub Action** للبناء التلقائي
7. **فتح صفحة متابعة** في المتصفح

### 🔗 `setup-graphite.sh`
**الوظيفة**: إعداد Graphite CLI تلقائيًا + تركيب hook يعمل عند كل `git pull`

#### ماذا يفعل:
- ✅ تثبيت `@withgraphite/graphite-cli@stable` عبر npm (إن لم يكن مثبتًا)
- ✅ التوثيق: `gt auth --token` (من متغير `GRAPHITE_TOKEN` أو ملف `.graphite-token` أو إدخال يدوي)
- ✅ تركيب `.git/hooks/post-merge` — بعد كل `git pull` يتحقق صامتًا من التثبيت والتوثيق
- ✅ حفظ التوكن محليًا في `.graphite-token` (مُستثنى من git — لا يُرفع أبدًا)

#### الاستخدام:
```bash
# مرة واحدة بعد clone المستودع
bash scripts/setup-graphite.sh

# أو مع توكن مباشر
GRAPHITE_TOKEN=xxxx bash scripts/setup-graphite.sh
```

#### مع الـ CI:
`.github/workflows/graphite-pr.yml` يكرر نفس الخطوات تلقائيًا عند كل Pull Request:
`npm install -g @withgraphite/graphite-cli@stable` ثم `gt auth --token $GRAPHITE_TOKEN`.
التوكن في CI يُقرأ من سرّ المستودع: **Settings → Secrets → Actions → `GRAPHITE_TOKEN`**.

#### متطلبات:
- `git` و `npm` (Node.js 18+)

## 🎯 سيناريوهات الاستخدام

### إصدار جديد كامل:
```bash
./scripts/create-release.sh
# اتبع الخطوات التفاعلية
# انتظر انتهاء البناء
# حمّل APK من Releases
```

### إصدار سريع (بدون ملاحظات):
```bash
./scripts/create-release.sh
# أدخل رقم الإصدار
# اضغط Enter لتخطي الملاحظات
# اضغط y للتأكيد
```

## 🔧 إعداد البيئة

### تثبيت GitHub CLI (اختياري):
```bash
# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# macOS
brew install gh

# Windows
winget install --id GitHub.cli
```

### تسجيل الدخول:
```bash
gh auth login
# اتبع الخطوات لربط حساب GitHub
```

### إعداد الصلاحيات:
```bash
# جعل السكربت قابل للتشغيل
chmod +x scripts/*.sh
```

## 📋 أمثلة على الإصدارات

### إصدار رئيسي (Major):
```bash
Input: v2.0.0
Notes: 
- إضافة نظام المدفوعات الجديد
- واجهة مستخدم محسّنة بالكامل
- دعم أجهزة جديدة
```

### إصدار فرعي (Minor):
```bash
Input: v1.1.0
Notes:
- إضافة تقارير جديدة
- تحسين أداء البحث
- إصلاح مشاكل الطباعة
```

### إصدار إصلاحات (Patch):
```bash
Input: v1.0.1
Notes:
- إصلاح مشكلة تسجيل الدخول
- تحسين استقرار التطبيق
```

## 🔍 استكشاف الأخطاء

### مشاكل شائعة:

#### 1. Git Tag موجود مسبقاً:
```bash
❌ الإصدار v1.0.0 موجود مسبقاً

# الحل: استخدم رقم إصدار جديد
```

#### 2. تغييرات غير محفوظة:
```bash
⚠️ توجد تغييرات غير محفوظة

# الحل: احفظ التغييرات أو اختر المتابعة
git add .
git commit -m "حفظ التغييرات"
```

#### 3. مشكلة في الصلاحيات:
```bash
❌ Permission denied

# الحل: تأكد من صلاحيات push
gh auth status
git remote -v
```

#### 4. GitHub CLI غير متاح:
```bash
⚠️ GitHub CLI غير مثبت - سيتم إنشاء Tag فقط

# لا مشكلة: سيعمل Git Tag وتحتاج تشغيل Action يدوياً
```

## 📊 مخرجات السكربت

### نجح التشغيل:
```bash
✅ تم إنشاء Tag بنجاح!
✅ تم تشغيل workflow بنجاح!
🎉 تمت العملية بنجاح!
```

### معلومات مفيدة:
- 🏷️ رقم Tag الجديد  
- 📅 تاريخ الإنشاء
- 🔗 روابط GitHub Actions و Releases
- 📋 الخطوات التالية

## 🚀 إضافة scripts جديدة

لإضافة أدوات جديدة:

1. **إنشاء ملف** في `scripts/`
2. **إضافة shebang**: `#!/bin/bash`
3. **جعله قابل للتشغيل**: `chmod +x`
4. **تحديث README** هذا

### مثال script جديد:
```bash
#!/bin/bash
# Marina Hotel Mobile - Build Local APK

echo "🏨 Building Marina Hotel APK locally..."
cd mobile
flutter clean
flutter pub get
flutter packages pub run build_runner build
flutter build apk --release
echo "✅ APK ready at: build/app/outputs/flutter-apk/app-release.apk"
```

---

🛠️ **هذه الأدوات تجعل إدارة إصدارات Marina Hotel Mobile أسهل وأكثر احترافية!**