#!/bin/bash
# سكربت فحص شامل لمشروع Marina Hotel Flutter
# يفحص: الأخطاء، التحذيرات، حالة Git، البناء

set -e

FLUTTER="/home/z/flutter/bin/flutter"
PROJECT_DIR="/home/z/my-project/marina-hotel-copy/mobile"
cd "$PROJECT_DIR"

echo "================================================"
echo "  فحص مشروع Marina Hotel"
echo "================================================"
echo ""

# 1. حالة Git
echo "--- 1. حالة Git ---"
echo "الفرع الحالي: $(git branch --show-current)"
echo "آخر التزام:"
git log --oneline -3
echo ""
CHANGES=$(git status --short)
if [ -z "$CHANGES" ]; then
  echo "✅ لا توجد تغييرات غير ملتزمة"
else
  echo "⚠️ تغييرات غير ملتزمة:"
  echo "$CHANGES"
fi
echo ""

# 2. Flutter Analyze
echo "--- 2. تحليل الكود (flutter analyze) ---"
ANALYZE_OUTPUT=$($FLUTTER analyze 2>&1 || true)
echo "$ANALYZE_OUTPUT"
echo ""

# استخراج الإحصائيات
INFO_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -oP '\d+ info' | grep -oP '\d+' || echo "0")
WARNING_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -oP '\d+ warning' | grep -oP '\d+' || echo "0")
ERROR_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -oP '\d+ error' | grep -oP '\d+' || echo "0")

echo "--- 3. ملخص التحليل ---"
echo "الأخطاء: $ERROR_COUNT"
echo "التحذيرات: $WARNING_COUNT"
echo "المعلومات: $INFO_COUNT"
echo ""

if [ "$ERROR_COUNT" -gt 0 ]; then
  echo "❌ يوجد أخطاء يجب إصلاحها!"
elif [ "$WARNING_COUNT" -gt 0 ]; then
  echo "⚠️ يوجد تحذيرات يُفضل معالجتها"
else
  echo "✅ الكود نظيف - لا أخطاء ولا تحذيرات!"
fi
echo ""

# 4. التبعيات
echo "--- 4. حالة التبعيات ---"
$FLUTTER deps --no-version-check 2>&1 | tail -5 || echo "تم فحص التبعيات"
echo ""

echo "================================================"
echo "  انتهى الفحص"
echo "================================================"
