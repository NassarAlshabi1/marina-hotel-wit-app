#!/bin/bash
# verify_crash_fixes.sh
# التحقق من تطبيق كل إصلاحات الـ crashes على الكود الحالي
# الاستخدام: bash verify_crash_fixes.sh

set -e

LIB="/home/z/my-project/marina-hotel-wit-app/mobile/lib"

echo "🔍 ═══════════════════════════════════════════════"
echo "   التحقق من إصلاحات Fatal Crashes"
echo "═══════════════════════════════════════════════"
echo ""

PASS=0
FAIL=0

check() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "✅ $description"
    PASS=$((PASS + 1))
  else
    echo "❌ $description"
    echo "   الملف: $file"
    echo "   النمط المطلوب: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

# ═══════════════════════════════════════════════════════════════
# 1. createRow / createSyncLog protection
# ═══════════════════════════════════════════════════════════════

echo "🔹 1) حماية createRow و createSyncLog:"
echo ""

check "createRow يستخدم withRetryAndTimeout" \
  "$LIB/services/appwrite_service.dart" \
  "withRetryAndTimeout"

check "createSyncLog محاط بـ try-catch مستقل" \
  "$LIB/services/appwrite_sync_manager.dart" \
  "logCreateError"

check "fallback value لـ syncLogId عند الفشل" \
  "$LIB/services/appwrite_sync_manager.dart" \
  "localSyncLogId ?? 'local_"

echo ""

# ═══════════════════════════════════════════════════════════════
# 2. Timer callbacks protection (11 إصلاح)
# ═══════════════════════════════════════════════════════════════

echo "🔹 2) حماية Timer callbacks في مسار المزامنة:"
echo ""

# central_sync_coordinator.dart (2 Timers)
check "central_sync_coordinator Timer 27 محمي" \
  "$LIB/services/central_sync_coordinator.dart" \
  "خطأ في المزامنة المؤجلة"

check "central_sync_coordinator Timer 76 محمي" \
  "$LIB/services/central_sync_coordinator.dart" \
  "خطأ في cooldown delayed sync"

# appwrite_sync_manager.dart
check "appwrite_sync_manager startAutoSync Timer محمي" \
  "$LIB/services/appwrite_sync_manager.dart" \
  "Auto sync Timer: استثناء غير متوقع"

# unified_sync_orchestrator.dart
check "unified_sync_orchestrator debounce Timer محمي" \
  "$LIB/services/unified_sync_orchestrator.dart" \
  "خطأ في debounce auto sync"

# sync_guardian.dart
check "sync_guardian pending monitor Timer محمي" \
  "$LIB/services/sync_guardian.dart" \
  "SyncGuardian pending monitor خطأ"

# sync/sync_timers.dart
check "sync_timers startAutoSync Timer محمي" \
  "$LIB/services/sync/sync_timers.dart" \
  "Sync Timer: استثناء غير متوقع"

# secondary_sync_manager.dart
check "secondary_sync_manager Timer محمي" \
  "$LIB/services/secondary_sync_manager.dart" \
  "Auto-sync Timer error"

# smart_sync_manager.dart (2 fixes)
check "smart_sync_manager _performFullSync محمي" \
  "$LIB/services/smart_sync_manager.dart" \
  "فشل المزامنة الكاملة الدورية"

check "smart_sync_manager rethrow أُزيل" \
  "$LIB/services/smart_sync_manager.dart" \
  "لا rethrow — نمنع fatal crash"

# google_drive_unified_sync_coordinator.dart (3 fixes)
check "gd_unified _handlePeriodicPull محمي" \
  "$LIB/services/google_drive_unified_sync_coordinator.dart" \
  "Periodic pull error"

check "gd_unified _triggerSync محمي" \
  "$LIB/services/google_drive_unified_sync_coordinator.dart" \
  "Trigger sync error"

check "gd_unified _periodicSyncTimer محمي" \
  "$LIB/services/google_drive_unified_sync_coordinator.dart" \
  "Periodic full backup error"

echo ""

# ═══════════════════════════════════════════════════════════════
# 3. Dashboard animation crash fix
# ═══════════════════════════════════════════════════════════════

echo "🔹 3) إصلاح crash AnimationController:"
echo ""

check "dashboard_sync_button _safeStopAnimation موجود" \
  "$LIB/widgets/dashboard_sync_button.dart" \
  "_safeStopAnimation"

echo ""

# ═══════════════════════════════════════════════════════════════
# 4. التقرير النهائي
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════"
echo "   📊 التقرير النهائي"
echo "═══════════════════════════════════════════════"
echo ""
echo "  ✅ نجح: $PASS"
echo "  ❌ فشل: $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "🎉 ممتاز! كل الإصلاحات موجودة في الكود."
  echo ""
  echo "📝 الخطوات التالية:"
  echo "   1. flutter build apk --release"
  echo "   2. انشر الإصدار 1.2.0+1762 (أو أحدث)"
  echo "   3. راقب Crashlytics — يجب ألا يتكرر الـ crash"
  echo "   4. الـ crash الحالي من نسخة 1.2.0+1761 قبل الإصلاحات"
else
  echo "⚠️  يوجد إصلاحات مفقودة — راجع النقاط الحمراء أعلاه."
fi
echo ""
echo "═══════════════════════════════════════════════"
