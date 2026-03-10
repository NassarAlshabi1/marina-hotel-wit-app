#!/bin/bash

# 🔧 Zencoder Setup Helper Script
# يساعد في إعداد Secrets بسرعة

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Zencoder Setup Helper"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# التحقق من GitHub CLI
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI غير مثبت"
    echo "   قم بتثبيته من: https://cli.github.com"
    exit 1
fi

echo "✅ GitHub CLI موجود"
echo ""

# التحقق من Authentication
if ! gh auth status &> /dev/null; then
    echo "❌ لم تسجل دخول إلى GitHub CLI"
    echo "   قم بتسجيل الدخول: gh auth login"
    exit 1
fi

echo "✅ تم تسجيل الدخول إلى GitHub"
echo ""

# إضافة Secrets
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 إضافة Zencoder Secrets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "احصل على Credentials من:"
echo "👉 https://auth.zencoder.ai/profile"
echo ""

# ZENCODER_CLIENT_ID
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 ZENCODER_CLIENT_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "الصق CLIENT_ID (ثم اضغط Enter): " CLIENT_ID

if [ -z "$CLIENT_ID" ]; then
    echo "❌ CLIENT_ID فارغ!"
    exit 1
fi

echo "$CLIENT_ID" | gh secret set ZENCODER_CLIENT_ID
echo "✅ تم إضافة ZENCODER_CLIENT_ID"
echo ""

# ZENCODER_CLIENT_SECRET
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 ZENCODER_CLIENT_SECRET"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -sp "الصق CLIENT_SECRET (ثم اضغط Enter): " CLIENT_SECRET
echo ""

if [ -z "$CLIENT_SECRET" ]; then
    echo "❌ CLIENT_SECRET فارغ!"
    exit 1
fi

echo "$CLIENT_SECRET" | gh secret set ZENCODER_CLIENT_SECRET
echo "✅ تم إضافة ZENCODER_CLIENT_SECRET"
echo ""

# CICD_TOKEN (اختياري)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 CICD_TOKEN (اختياري)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "هل تريد إضافة GitHub Personal Access Token للصلاحيات الموسعة؟"
read -p "(y/n): " add_cicd

if [ "$add_cicd" = "y" ] || [ "$add_cicd" = "Y" ]; then
    echo ""
    echo "احصل على Token من:"
    echo "👉 https://github.com/settings/tokens"
    echo ""
    echo "اختر الصلاحيات: repo, workflow"
    echo ""
    read -sp "الصق GitHub Token (ثم اضغط Enter): " CICD_TOKEN
    echo ""
    
    if [ -n "$CICD_TOKEN" ]; then
        echo "$CICD_TOKEN" | gh secret set CICD_TOKEN
        echo "✅ تم إضافة CICD_TOKEN"
    else
        echo "⚠️  تم تخطي CICD_TOKEN"
    fi
else
    echo "⚠️  تم تخطي CICD_TOKEN"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ تم إضافة Secrets بنجاح!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# التحقق من Secrets
echo "📋 الـ Secrets المضافة:"
if gh secret list &> /dev/null; then
    gh secret list
else
    echo "   - ZENCODER_CLIENT_ID ✅"
    echo "   - ZENCODER_CLIENT_SECRET ✅"
    if [ "$add_cicd" = "y" ] || [ "$add_cicd" = "Y" ]; then
        echo "   - CICD_TOKEN ✅"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 الخطوات التالية:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. جرب تشغيل Workflow:"
echo "   gh workflow run zen-agent-review.yml --ref capy/test2"
echo ""
echo "2. راقب التنفيذ:"
echo "   gh run list --workflow zen-agent-review.yml --limit 3"
echo ""
echo "3. راجع التوثيق:"
echo "   cat ZENCODER_SETUP_GUIDE.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Setup مكتمل! يمكنك الآن استخدام Zencoder Workflows"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
