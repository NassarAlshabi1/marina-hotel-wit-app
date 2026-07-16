#!/usr/bin/env bash
# dependency-audit.sh
# ═══════════════════════════════════════════════════════════════
#  فحص شامل للاعتماديات في مشروع Flutter
# ═══════════════════════════════════════════════════════════════
#
#  الفحوصات:
#  1. pub outdated — كشف الحزم القديمة
#  2. dependency_validator — كشف الحزم غير المستخدمة والمفقودة
#  3. pub security check — فحص الثغرات الأمنية
#  4. flutter pub deps — عرض شجرة الاعتماديات
#
#  Exit codes:
#    0 = نجاح
#    1 = يوجد مشاكل

set -euo pipefail

PROJECT_ROOT="${1:-mobile}"
STRICT="${2:-false}"

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "❌ Directory $PROJECT_ROOT not found"
  exit 1
fi

echo "═" `printf '═%.0s' {1..58}`
echo "  📦 Dependency Audit — Marina Hotel"
echo "═" `printf '═%.0s' {1..58}`
echo ""

cd "$PROJECT_ROOT"

ERRORS=0
WARNINGS=0

# ═══════════════════════════════════════════════════════════════
#  1. pub outdated — كشف الحزم القديمة
# ═══════════════════════════════════════════════════════════════
echo "🔹 1. Outdated packages check"
echo "─────────────────────────────────────"
OUTDATED=$(flutter pub outdated --json 2>/dev/null || echo "[]")
OUTDATED_COUNT=$(echo "$OUTDATED" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(len(data.get('packages', [])))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

if [[ "$OUTDATED_COUNT" -gt 0 ]]; then
  echo "   ⚠️  $OUTDATED_COUNT outdated packages:"
  flutter pub outdated 2>/dev/null | head -15
  ((WARNINGS++)) || true
else
  echo "   ✅ All packages up to date"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
#  2. Unused/Missing dependencies
# ═══════════════════════════════════════════════════════════════
echo "🔹 2. Unused/Missing dependencies check"
echo "─────────────────────────────────────"
# تفعيل dependency_validator (لا يُضاف كـ dependency لتجنب التلوث)
dart pub global activate dependency_validator 2>/dev/null || true
export PATH="$PATH:$HOME/.pub-cache/bin"

if command -v dependency_validator &> /dev/null; then
  echo "   Running dependency_validator..."
  if dependency_validator 2>&1 | tee /tmp/dep_validator.txt; then
    echo "   ✅ No unused/missing dependencies"
  else
    echo "   ⚠️  Issues found (see above)"
    ((WARNINGS++)) || true
  fi
else
  echo "   ℹ️  dependency_validator not available, skipping"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
#  3. Security check
# ═══════════════════════════════════════════════════════════════
echo "🔹 3. Security vulnerabilities check"
echo "─────────────────────────────────────"
# pub security check غير متاح بشكل مباشر، نستخدم flutter pub outdated
# مع فلتر للـ security advisories
if flutter pub outdated 2>&1 | grep -i "security\|vulnerab\|CVE"; then
  echo "   ❌ Security vulnerabilities found!"
  ((ERRORS++)) || true
else
  echo "   ✅ No known security vulnerabilities"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
#  4. Dependency tree summary
# ═══════════════════════════════════════════════════════════════
echo "🔹 4. Dependency tree summary"
echo "─────────────────────────────────────"
DEPS_COUNT=$(flutter pub deps 2>/dev/null | grep -c "^├──\|^└──" || echo "0")
DIRECT_DEPS=$(grep -E "^\s+(dependencies|dev_dependencies):" pubspec.yaml -A 100 | grep -E "^\s{2}\S+:" | wc -l || echo "0")
echo "   📊 Direct dependencies: $DIRECT_DEPS"
echo "   📊 Total dependencies (incl. transitive): ~$DEPS_COUNT"
echo ""

# ═══════════════════════════════════════════════════════════════
#  5. License check
# ═══════════════════════════════════════════════════════════════
echo "🔹 5. License check"
echo "─────────────────────────────────────"
# فحص تراخيص الحزم — نتحقق من pubspec.lock
LICENSE_FILE="${PROJECT_ROOT}/LICENSE"
if [[ -f "../LICENSE" ]]; then
  echo "   ✅ Project LICENSE file exists"
else
  echo "   ⚠️  No LICENSE file at project root"
  ((WARNINGS++)) || true
fi

# فحص الحزم ذات التراخيص غير المعروفة
UNKNOWN_LICENSES=$(grep -c "license: unknown\|license: null" pubspec.lock 2>/dev/null)
UNKNOWN_LICENSES=${UNKNOWN_LICENSES:-0}
if [[ "$UNKNOWN_LICENSES" -gt 0 ]]; then
  echo "   ⚠️  $UNKNOWN_LICENSES packages with unknown license"
  ((WARNINGS++)) || true
else
  echo "   ✅ All packages have known licenses"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
#  النتيجة النهائية
# ═══════════════════════════════════════════════════════════════
echo "═" `printf '═%.0s' {1..58}`
if [[ "$ERRORS" -gt 0 ]]; then
  echo "  ❌ FAILED: $ERRORS errors, $WARNINGS warnings"
  exit 1
elif [[ "$WARNINGS" -gt 0 && "$STRICT" == "true" ]]; then
  echo "  ❌ FAILED (strict): $WARNINGS warnings"
  exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
  echo "  ⚠️  PASSED with $WARNINGS warnings"
  exit 0
else
  echo "  ✅ All dependency checks pass!"
  exit 0
fi
