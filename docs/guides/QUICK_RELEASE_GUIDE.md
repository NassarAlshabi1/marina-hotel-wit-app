# 🚀 Quick Start: Build & Release APK

## تشغيل سريع (3 دقائق)

### الطريقة 1: Build تلقائي مع Release (موصى به)

```bash
# 1. تأكد من أن كل شيء محدث
git add .
git commit -m "feat: ready for release v1.2.3"
git push

# 2. أنشئ tag للإصدار
git tag v1.2.3

# 3. ادفع الـ tag
git push origin v1.2.3

# ✅ هذا سيقوم تلقائياً بـ:
# - بناء APK
# - إنشاء GitHub Release
# - رفع APK كـ asset
```

### الطريقة 2: Build يدوي من GitHub

1. اذهب إلى: [GitHub Actions](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions)
2. اختر: **"Build and Release APK"**
3. اضغط: **"Run workflow"**
4. املأ:
   - Version: `1.2.3` (أو اتركه فارغاً)
   - Create Release: ✅
5. اضغط: **"Run workflow"** (الأخضر)

---

## 📥 تحميل APK

### من Artifacts (جميع الـ builds)
```
GitHub > Actions > اختر workflow run > Artifacts > Download
```

### من Releases (فقط الـ tagged builds)
```
GitHub > Releases > اختر الإصدار > Assets > Download APK
```

---

## 🏷️ إدارة الإصدارات

### تحديث الإصدار في pubspec.yaml

```yaml
# mobile/pubspec.yaml
version: 1.2.3+4
#        |   | |
#        |   | Build number (يزيد بـ 1 كل build)
#        |   Patch (bug fixes)
#        Minor (features)
#        Major (breaking changes)
```

### القواعد:
- **Major**: تغييرات كبيرة (1.0.0 → 2.0.0)
- **Minor**: ميزات جديدة (1.0.0 → 1.1.0)
- **Patch**: إصلاحات (1.0.0 → 1.0.1)
- **Build**: رقم التجميع (+1, +2, +3...)

---

## 🔄 سيناريوهات شائعة

### إصدار جديد مع ميزات
```bash
# 1. حدّث الإصدار
# mobile/pubspec.yaml: 1.2.0 → 1.3.0

# 2. Commit وPush
git add mobile/pubspec.yaml
git commit -m "chore: bump version to 1.3.0"
git push

# 3. أنشئ tag
git tag v1.3.0
git push origin v1.3.0
```

### إصلاح سريع (hotfix)
```bash
# 1. حدّث patch version
# mobile/pubspec.yaml: 1.2.0 → 1.2.1

# 2. Commit وPush
git add mobile/pubspec.yaml
git commit -m "fix: critical bug fix"
git push

# 3. أنشئ tag
git tag v1.2.1
git push origin v1.2.1
```

### اختبار بدون release
```bash
# فقط push بدون tag
git push origin main

# سيبني APK لكن لن ينشئ release
# APK متاح في Artifacts فقط
```

---

## 📊 مراقبة الـ Build

### أثناء الـ Build
```
1. اذهب: Actions > Build and Release APK > اختر Run
2. شاهد: الخطوات تتنفذ في الوقت الفعلي
3. انتظر: حتى تظهر ✅ Build Complete
```

### بعد انتهاء الـ Build
```
✅ APK Size: 45.2 MB
✅ Version: 1.2.3+4
✅ SHA-1: 67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C
✅ Release: Created
```

---

## 🐛 حل المشاكل السريع

### Problem: Build فشل
```bash
# تحقق من الأخطاء في Logs
# الأسباب الشائعة:
1. خطأ في الكود (flutter analyze)
2. dependencies غير متوافقة
3. build_runner فشل

# الحل: اختبر محلياً أولاً
cd mobile
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

### Problem: Release لم يُنشأ
```bash
# السبب: لا يوجد tag
# الحل: أنشئ وادفع tag
git tag v1.2.3
git push origin v1.2.3
```

### Problem: APK حجمه كبير جداً
```bash
# الحل: استخدم Split APKs
# في GitHub Actions:
# 1. Run workflow يدوياً
# 2. سيبني APKs منفصلة لكل architecture
# 3. كل APK سيكون أصغر (~15-20 MB)
```

---

## 🎯 Best Practices

### ✅ قبل كل Release
```bash
# 1. اختبر محلياً
flutter test

# 2. تحقق من التحليل
flutter analyze

# 3. تأكد من الإصدار
cat mobile/pubspec.yaml | grep version

# 4. اكتب changelog واضح
git commit -m "release: version 1.2.3 with new features"
```

### ✅ رقم الإصدار
```
- استخدم semantic versioning (MAJOR.MINOR.PATCH)
- زد build number مع كل build
- لا تعيد استخدام نفس الرقم
```

### ✅ Git Tags
```bash
# استخدم format موحد
git tag v1.2.3  ✅
git tag 1.2.3   ❌
git tag V1.2.3  ❌
```

---

## 📝 Checklist قبل Release

- [ ] ✅ تم اختبار الكود محلياً
- [ ] ✅ تم تحديث الإصدار في pubspec.yaml
- [ ] ✅ تم كتابة commit message واضح
- [ ] ✅ تم push الكود
- [ ] ✅ تم إنشاء tag بالصيغة الصحيحة (v1.2.3)
- [ ] ✅ تم push الـ tag
- [ ] ✅ تم التحقق من بدء الـ workflow
- [ ] ✅ تم انتظار انتهاء الـ build بنجاح
- [ ] ✅ تم التحقق من إنشاء الـ release
- [ ] ✅ تم تحميل واختبار الـ APK

---

## 🚀 أوامر سريعة

### All-in-One Release Command
```bash
#!/bin/bash
# save as: release.sh

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh 1.2.3"
  exit 1
fi

# Update version in pubspec.yaml
sed -i "s/^version: .*/version: $VERSION+$(date +%s)/" mobile/pubspec.yaml

# Commit
git add mobile/pubspec.yaml
git commit -m "release: version $VERSION"
git push

# Tag
git tag v$VERSION
git push origin v$VERSION

echo "✅ Release v$VERSION initiated!"
echo "📊 Check: https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions"
```

### استخدام:
```bash
chmod +x release.sh
./release.sh 1.2.3
```

---

## 📞 المساعدة

### الوثائق الكاملة
- [GitHub Actions Release Guide](./GITHUB_ACTIONS_RELEASE_GUIDE.md)
- [Appwrite Integration](./mobile/APPWRITE_INTEGRATION_GUIDE.md)

### الروابط السريعة
- [Actions](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions)
- [Releases](https://github.com/NassarAlshabi1/marina-hotel-wit-app/releases)
- [Issues](https://github.com/NassarAlshabi1/marina-hotel-wit-app/issues)

---

**هل تحتاج مساعدة؟** افتح Issue على GitHub!

🎉 **Happy Building!**
