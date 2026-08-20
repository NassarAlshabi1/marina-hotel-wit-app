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


## Android 1GB Low-RAM memory cycle

يستخدم `android_low_ram_memory_test.sh` لقياس `TOTAL PSS` و`Private Other` و`Unknown` وJava/Native Heap وRSS وSwap PSS في emulator مقيّد بذاكرة 1GB. لا يسجل السكربت `cold_start_before` كقيمة ذاكرة؛ عندما تكون العملية متوقفة يسجل الحدث في `lifecycle.log` فقط، لأن `dumpsys meminfo` لا ينتج baseline صالحاً لعملية غير موجودة.

```bash
chmod +x scripts/android_low_ram_memory_test.sh
chmod +x scripts/android_low_ram_navigation_actions.sh
MAX_PSS_KB=393216 LOW_RAM_CYCLES=5 LOW_RAM_SWIPES=8 \
  scripts/android_low_ram_memory_test.sh \
  --package com.aden.marina \
  --apk mobile/build/app/outputs/flutter-apk/app-profile.apk \
  --cycles 5 \
  --swipes 8 \
  --action-script scripts/android_low_ram_navigation_actions.sh \
  --output mobile/build/low-ram-performance
```

ينتج الاختبار `memory_metrics.csv` و`summary.txt` و`lifecycle.log` ولقطات `dumpsys meminfo -d` الخام داخل مجلد `raw/`. يستخدم action script عناصر UI النصية عبر `uiautomator` لفتح مدفوعات اليوم والمصروفات ومحاولة فتح غرف Dashboard ثم العودة. إذا ظهرت شاشة تسجيل الدخول دون جلسة اختبار، يسجل السكربت `navigation_skipped:login_screen_no_credentials` ولا يخترع بيانات اعتماد أو يعتبر التنقل ناجحاً.

يُشغّل workflow `Android 1GB Low-RAM Performance` خمس دورات cold-start/action، ويرفع جميع اللقطات الخام كـ artifact حتى يمكن تحليل `Private Other` و`Unknown` بعد كل دورة بدلاً من الاكتفاء بملخص PSS.
