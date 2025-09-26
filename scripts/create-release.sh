#!/bin/bash

# Marina Hotel Mobile - Release Creator
# إنشاء إصدار جديد مع GitHub Actions

set -e

echo "🏨 Marina Hotel Mobile - Release Creator"
echo "========================================"

# ألوان للعرض
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# التحقق من git
if ! command -v git &> /dev/null; then
    echo -e "${RED}❌ Git غير مثبت${NC}"
    exit 1
fi

# التحقق من gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}⚠️ GitHub CLI غير مثبت - سيتم إنشاء Tag فقط${NC}"
    HAS_GH=false
else
    HAS_GH=true
fi

# الحصول على الإصدار الحالي
echo -e "${BLUE}📋 معلومات الإصدار الحالي:${NC}"
if [ -f "mobile/pubspec.yaml" ]; then
    CURRENT_VERSION=$(grep 'version:' mobile/pubspec.yaml | sed 's/version: //' | xargs)
    echo "   الإصدار في pubspec.yaml: $CURRENT_VERSION"
fi

# عرض آخر tags
echo -e "${BLUE}🏷️ آخر Tags:${NC}"
git tag --sort=-version:refname | head -5 | sed 's/^/   /'

echo ""

# طلب رقم الإصدار الجديد
read -p "📝 أدخل رقم الإصدار الجديد (مثل v1.0.1): " VERSION

# التحقق من صيغة الإصدار
if [[ ! $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}❌ صيغة الإصدار غير صحيحة. يجب أن تكون مثل v1.0.0${NC}"
    exit 1
fi

# التحقق من وجود Tag
if git tag -l | grep -q "^${VERSION}$"; then
    echo -e "${RED}❌ الإصدار ${VERSION} موجود مسبقاً${NC}"
    exit 1
fi

# طلب ملاحظات الإصدار
echo ""
echo "📝 أدخل ملاحظات الإصدار (اضغط Enter للانتهاء، أو Enter فارغ للتخطي):"
RELEASE_NOTES=""
while IFS= read -r line; do
    if [[ -z "$line" ]]; then
        break
    fi
    RELEASE_NOTES="${RELEASE_NOTES}${line}\n"
done

# التأكد من الحالة الحالية
echo ""
echo -e "${BLUE}🔍 فحص حالة Git...${NC}"
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${YELLOW}⚠️ توجد تغييرات غير محفوظة:${NC}"
    git status --porcelain | sed 's/^/   /'
    echo ""
    read -p "❓ هل تريد المتابعة؟ (y/n): " CONTINUE
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
        echo "❌ تم الإلغاء"
        exit 1
    fi
fi

# التأكد النهائي
echo ""
echo -e "${YELLOW}📋 ملخص الإصدار الجديد:${NC}"
echo "   🏷️ Tag: $VERSION"
echo "   📅 التاريخ: $(date '+%Y-%m-%d %H:%M:%S')"
if [[ -n "$RELEASE_NOTES" ]]; then
    echo "   📝 الملاحظات: متوفرة"
else
    echo "   📝 الملاحظات: سيتم إنشاؤها تلقائياً"
fi
echo ""

read -p "❓ هل أنت متأكد من إنشاء هذا الإصدار؟ (y/n): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "❌ تم الإلغاء"
    exit 1
fi

echo ""
echo -e "${GREEN}🚀 إنشاء الإصدار...${NC}"

# إنشاء Tag
echo "📌 إنشاء Tag..."
if [[ -n "$RELEASE_NOTES" ]]; then
    git tag -a "$VERSION" -m "Marina Hotel Mobile $VERSION

$(echo -e "$RELEASE_NOTES")"
else
    git tag -a "$VERSION" -m "Marina Hotel Mobile $VERSION

✨ تحسينات وإصلاحات متنوعة
🏨 نظام المدفوعات المتقدم نشط
📱 واجهة محسّنة وأداء أفضل"
fi

# رفع Tag
echo "📤 رفع Tag إلى GitHub..."
git push origin "$VERSION"

echo -e "${GREEN}✅ تم إنشاء Tag بنجاح!${NC}"

# تشغيل GitHub Action إذا كان متاحاً
if [[ "$HAS_GH" == "true" ]]; then
    echo ""
    echo "🤖 تشغيل GitHub Action للبناء..."
    
    if gh workflow run release-apk.yml -f tag_name="$VERSION" -f release_notes="$RELEASE_NOTES" 2>/dev/null; then
        echo -e "${GREEN}✅ تم تشغيل workflow بنجاح!${NC}"
        
        echo ""
        echo "📋 يمكنك متابعة التقدم:"
        echo "   🌐 GitHub Actions: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/actions"
        echo "   📦 Releases: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/releases"
        
        # انتظار قصير ثم فتح الصفحة
        read -p "❓ فتح صفحة Actions في المتصفح؟ (y/n): " OPEN_BROWSER
        if [[ $OPEN_BROWSER =~ ^[Yy]$ ]]; then
            gh repo view --web --branch actions
        fi
    else
        echo -e "${YELLOW}⚠️ لم يتمكن من تشغيل workflow - قد تحتاج لتشغيله يدوياً${NC}"
    fi
fi

echo ""
echo -e "${GREEN}🎉 تمت العملية بنجاح!${NC}"
echo ""
echo "📋 الخطوات التالية:"
echo "1. 📱 انتظار انتهاء بناء APK (5-10 دقائق)"
echo "2. 📥 تحميل APK من GitHub Releases"
echo "3. 🧪 اختبار التطبيق على جهاز"
echo "4. 🚀 نشر على Google Play (إذا رغبت)"
echo ""
echo -e "${BLUE}🏨 Marina Hotel Mobile $VERSION جاهز للإطلاق!${NC}"