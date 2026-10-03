#!/usr/bin/env bash
# ينشئ فرعاً جديداً مشتقاً من feat/cloudflare-sync-execution ويطبّق عليه
# إصلاحات حماية ربط الموظفين/المصروفات/الرواتب (5 commits).
# الاستخدام (من جذر المستودع، وشجرة العمل نظيفة):
#   bash scripts/apply_cloudflare_salary_link_fixes.sh [اسم-الفرع]
# الافتراضي: fix/cloudflare-salary-link-protection
set -euo pipefail

NEW_BRANCH="${1:-fix/cloudflare-salary-link-protection}"
BASE="feat/cloudflare-sync-execution"
BASE_COMMIT="78c17381"   # النسخة التي بُنيت عليها الـ patches
SRC_DIR="patches/cloudflare-salary-link-fixes"

if [ -n "$(git status --porcelain)" ]; then
  echo "⛔ شجرة العمل غير نظيفة — احفظ أو تجاهل تغييراتك أولاً." >&2
  exit 1
fi
if ! ls "$SRC_DIR"/*.patch >/dev/null 2>&1; then
  echo "⛔ لم أجد $SRC_DIR/*.patch — شغّل السكربت من الفرع الذي يحتويها." >&2
  exit 1
fi

# نسخ الـ patches خارج المستودع قبل التبديل (قد لا توجد في الفرع الأساس)
TMP="$(mktemp -d)"
cp "$SRC_DIR"/*.patch "$TMP"/

git fetch origin "$BASE"
if ! git merge-base --is-ancestor "$BASE_COMMIT" "origin/$BASE"; then
  echo "⚠️ origin/$BASE لم يعد يحتوي $BASE_COMMIT — قد تحتاج حل تعارضات." >&2
fi
git switch -c "$NEW_BRANCH" "origin/$BASE"

if ! git am --3way "$TMP"/*.patch; then
  echo "⛔ تعارض أثناء التطبيق. حُلّه ثم: git am --continue  (أو git am --abort)" >&2
  exit 1
fi

echo "✅ الفرع $NEW_BRANCH جاهز ($(git rev-list --count "origin/$BASE"..HEAD) commits)."
echo "   للرفع: git push -u origin $NEW_BRANCH"
