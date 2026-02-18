#!/bin/bash

# 🔍 Zencoder Configuration Checker
# يتحقق من إعداد Zencoder بشكل صحيح

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Zencoder Configuration Checker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ERRORS=0
WARNINGS=0

# 1. التحقق من GitHub CLI
echo "1️⃣  التحقق من GitHub CLI..."
if command -v gh &> /dev/null; then
    GH_VERSION=$(gh --version | head -n 1)
    echo "   ✅ GitHub CLI موجود: $GH_VERSION"
else
    echo "   ❌ GitHub CLI غير مثبت"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 2. التحقق من Authentication
echo "2️⃣  التحقق من GitHub Authentication..."
if gh auth status &> /dev/null 2>&1; then
    echo "   ✅ تم تسجيل الدخول"
else
    echo "   ❌ لم يتم تسجيل الدخول"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 3. التحقق من Workflow Files
echo "3️⃣  التحقق من Workflow Files..."
WORKFLOWS=(
    ".github/workflows/zen-agent-review.yml"
    ".github/workflows/zencoder-manual.yml"
    ".github/workflows/zencoder-code-quality.yml"
    ".github/workflows/zencoder-security-scan.yml"
    ".github/workflows/zencoder-auto-tests.yml"
)

for workflow in "${WORKFLOWS[@]}"; do
    if [ -f "$workflow" ]; then
        echo "   ✅ $(basename $workflow)"
    else
        echo "   ⚠️  $(basename $workflow) - غير موجود"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

# 4. التحقق من صحة YAML
echo "4️⃣  التحقق من صحة YAML..."
if command -v yamllint &> /dev/null; then
    for workflow in "${WORKFLOWS[@]}"; do
        if [ -f "$workflow" ]; then
            if yamllint "$workflow" &> /dev/null; then
                echo "   ✅ $(basename $workflow) - YAML صحيح"
            else
                echo "   ❌ $(basename $workflow) - YAML به أخطاء"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done
else
    echo "   ⚠️  yamllint غير مثبت - تخطي الفحص"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 5. التحقق من الفرع الحالي
echo "5️⃣  التحقق من الفرع الحالي..."
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$CURRENT_BRANCH" ]; then
    echo "   ℹ️  الفرع الحالي: $CURRENT_BRANCH"
else
    echo "   ⚠️  لا يمكن تحديد الفرع"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 6. التحقق من آخر تشغيل
echo "6️⃣  التحقق من آخر تشغيل Workflow..."
if gh run list --workflow zen-agent-review.yml --limit 1 --json status,conclusion,createdAt &> /dev/null; then
    LAST_RUN=$(gh run list --workflow zen-agent-review.yml --limit 1 --json status,conclusion,createdAt,displayTitle --jq '.[0]')
    if [ -n "$LAST_RUN" ]; then
        STATUS=$(echo "$LAST_RUN" | jq -r '.status')
        CONCLUSION=$(echo "$LAST_RUN" | jq -r '.conclusion')
        TITLE=$(echo "$LAST_RUN" | jq -r '.displayTitle')
        
        echo "   ℹ️  آخر تشغيل:"
        echo "      العنوان: $TITLE"
        echo "      الحالة: $STATUS"
        if [ "$CONCLUSION" != "null" ]; then
            echo "      النتيجة: $CONCLUSION"
        fi
        
        if [ "$CONCLUSION" = "success" ]; then
            echo "   ✅ آخر تشغيل نجح"
        elif [ "$CONCLUSION" = "failure" ]; then
            echo "   ❌ آخر تشغيل فشل"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo "   ℹ️  لم يتم تشغيل Workflow بعد"
    fi
else
    echo "   ⚠️  لا يمكن الوصول لتاريخ التشغيل"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 7. التحقق من التوثيق
echo "7️⃣  التحقق من ملفات التوثيق..."
DOCS=(
    "ZENCODER_WORKFLOW_EXAMPLES.md"
    "ZENCODER_SETUP_GUIDE.md"
    ".github/workflows/README.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo "   ✅ $doc"
    else
        echo "   ⚠️  $doc - غير موجود"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

# 8. معلومات Repository
echo "8️⃣  معلومات Repository..."
REPO_INFO=$(gh repo view --json nameWithOwner,defaultBranchRef 2>/dev/null)
if [ -n "$REPO_INFO" ]; then
    REPO_NAME=$(echo "$REPO_INFO" | jq -r '.nameWithOwner')
    DEFAULT_BRANCH=$(echo "$REPO_INFO" | jq -r '.defaultBranchRef.name')
    echo "   ℹ️  المستودع: $REPO_NAME"
    echo "   ℹ️  الفرع الافتراضي: $DEFAULT_BRANCH"
else
    echo "   ⚠️  لا يمكن الحصول على معلومات المستودع"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# الخلاصة
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 الخلاصة:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ كل شيء جاهز!"
    echo ""
    echo "🚀 جرب تشغيل Workflow:"
    echo "   ./setup-zencoder-secrets.sh  # إذا لم تضف الـ Secrets بعد"
    echo "   gh workflow run zen-agent-review.yml --ref $CURRENT_BRANCH"
elif [ $ERRORS -eq 0 ]; then
    echo "⚠️  التكوين جيد مع $WARNINGS تحذير(ات)"
    echo ""
    echo "يمكنك المتابعة لكن راجع التحذيرات أعلاه"
else
    echo "❌ هناك $ERRORS خطأ و $WARNINGS تحذير"
    echo ""
    echo "يرجى إصلاح الأخطاء قبل المتابعة"
    echo ""
    echo "📖 راجع الدليل:"
    echo "   cat ZENCODER_SETUP_GUIDE.md"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $ERRORS
