#!/bin/bash

echo "Running Security Scan..."
mkdir -p reports
FAILS=0

# أنماط البحث عن المفاتيح
PATTERNS=(
    "(AIza[0-9A-Za-z-_]{35})" # Firebase/Google API Key
    "(sk_live_[0-9a-zA-Z]{24})" # Stripe Secret Key
    "(password\s*[:=]\s*['\"][^'\"]+['\"])" # Hardcoded passwords
    "(api_?key\s*[:=]\s*['\"][^'\"]+['\"])" # Hardcoded API keys
)

for pattern in "${PATTERNS[@]}"; do
    # استثناء مجلدات build و .git و .dart_tool والملفات المولدة
    SEARCH_DIR=${1:-"lib"}
<<<<<<< HEAD
    EXCLUDES="--exclude-dir={build,.git,.dart_tool,ios,android} --exclude="*.g.dart" --exclude=".env""
    MATCHES=$(grep -rE $EXCLUDES "$pattern" "$SEARCH_DIR" 2>/dev/null)
=======
    MATCHES=$(grep -rE --exclude-dir={build,.git,.dart_tool,ios,android} --exclude="*.g.dart" "$pattern" "$SEARCH_DIR" 2>/dev/null)
>>>>>>> origin/refactor/clean-v2
    if [ ! -z "$MATCHES" ]; then
        echo "⚠️ WARNING: Potential secret found matching pattern: $pattern"
        echo "$MATCHES" >> reports/security_violations.txt
        FAILS=$((FAILS+1))
    fi
done

if [ $FAILS -eq 0 ]; then
    echo "✅ Security Scan Passed" > reports/security_report.txt
else
    echo "❌ Security Scan Failed: $FAILS potential secrets found" > reports/security_report.txt
fi
