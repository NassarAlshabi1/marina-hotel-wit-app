#!/usr/bin/env bash
# ==============================================================================
# scripts/setup-graphite.sh
# إعداد Graphite CLI تلقائيًا: تثبيت + توثيق + تركيب hook يعمل تلقائيًا عند كل
# `git pull` (عبر post-merge hook).
#
# الاستخدام:
#   bash scripts/setup-graphite.sh
#
# مصادر التوكن (بالترتيب):
#   1) متغير البيئة GRAPHITE_TOKEN
#   2) ملف .graphite-token في جذر المستودع (غير مُتتبَّع في git)
#   3) إدخال يدوي (prompt)
#
# ⚠️  لا تكتب التوكن داخل هذا السكربت — سيُرفع إلى GitHub.
#     التوكن يُحفظ محليًا فقط في .graphite-token (مُستثنى من git).
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || { cd "$(dirname "$0")/.." && pwd; })"
TOKEN_FILE="$REPO_ROOT/.graphite-token"
GT_PACKAGE="@withgraphite/graphite-cli@stable"
AUTH_FILE="${HOME}/.config/graphite/auth"

echo "═══════ إعداد Graphite CLI ═══════"

# ---------- 1) تثبيت CLI ----------
if command -v gt >/dev/null 2>&1; then
  echo "✔ Graphite CLI مثبّت: $(gt --version 2>/dev/null | head -1)"
else
  echo "==> تثبيت Graphite CLI (npm install -g $GT_PACKAGE)..."
  if ! command -v npm >/dev/null 2>&1; then
    echo "✖ npm غير موجود — ثبّت Node.js أولاً: https://nodejs.org" >&2
    exit 1
  fi
  npm install -g "$GT_PACKAGE"
  echo "✔ تم تثبيت Graphite CLI"
fi

# ---------- 2) التوثيق ----------
TOKEN="${GRAPHITE_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
  TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
fi
if [ -z "$TOKEN" ]; then
  printf 'أدخل Graphite token: '
  read -r TOKEN || TOKEN=""
fi

if [ -n "$TOKEN" ]; then
  echo "==> التوثيق (gt auth --token ...)..."
  if gt auth --token "$TOKEN"; then
    echo "✔ تم التوثيق بنجاح"
    # حفظ محلي غير مُتتبَّع — يستخدمه hook الـ pull لاحقًا
    printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
    echo "✔ حُفظ التوكن محليًا في .graphite-token (خارج git)"
  else
    echo "⚠ فشل التوثيق — تحقق من صلاحية التوكن" >&2
  fi
else
  echo "⚠ لا يوجد توكن — تخطي التوثيق (مرّر GRAPHITE_TOKEN=... أو أنشئ .graphite-token)" >&2
fi

# ---------- 3) تركيب post-merge hook (يعمل تلقائيًا عند git pull) ----------
HOOK="$REPO_ROOT/.git/hooks/post-merge"
cat > "$HOOK" << 'HOOK_EOF'
#!/usr/bin/env bash
# post-merge hook — أُنشئ بواسطة scripts/setup-graphite.sh
# يعمل تلقائيًا بعد كل git pull: يضمن تثبيت Graphite CLI وتوثيقه.
# صامت عند اكتمال الإعداد، ولا يُفشل عملية pull إطلاقًا.

export PATH="$PATH:${HOME}/.npm-global/bin:/usr/local/bin"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TOKEN_FILE="$REPO_ROOT/.graphite-token"
AUTH_FILE="${HOME}/.config/graphite/auth"
GT_PACKAGE="@withgraphite/graphite-cli@stable"

TOKEN="${GRAPHITE_TOKEN:-}"
[ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ] && TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

# 1) تثبيت CLI عند الحاجة فقط
if ! command -v gt >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    echo "==> [graphite] تثبيت $GT_PACKAGE ..."
    if npm install -g "$GT_PACKAGE" >/dev/null 2>&1; then
      echo "✔ [graphite] تم التثبيت"
    else
      echo "⚠ [graphite] فشل التثبيت — شغّل يدويًا: npm install -g $GT_PACKAGE" >&2
    fi
  else
    echo "⚠ [graphite] npm غير موجود — تخطي التثبيت" >&2
  fi
fi

# 2) توثيق عند الحاجة فقط (توكن جديد/مختلف عن الموثّق سابقًا)
if [ -n "$TOKEN" ] && ! grep -qF -- "$TOKEN" "$AUTH_FILE" 2>/dev/null; then
  if gt auth --token "$TOKEN" >/dev/null 2>&1; then
    echo "✔ [graphite] تم التوثيق (gt auth)"
  else
    echo "⚠ [graphite] فشل التوثيق — شغّل يدويًا: gt auth --token <TOKEN>" >&2
  fi
fi

exit 0
HOOK_EOF
chmod +x "$HOOK"
echo "✔ رُكِّب hook الـ pull: .git/hooks/post-merge"

echo "═══════ اكتمل الإعداد ═══════"
echo "من الآن: كل git pull يتحقق تلقائيًا من تثبيت Graphite CLI والتوثيق."
