#!/usr/bin/env bash
# ==========================================================================
#  Marina Hotel — Performance Pipeline: emulator-phase script
#  ==========================================================================
#  يُنفَّذ داخل reactivecircus/android-emulator-runner بسطر واحد:
#    bash mobile/scripts/performance_pipeline_emulator.sh
#
#  سبب وجوده كملف مستقل: الـ action ينفّذ input الـ script سطراً سطراً
#  (كل سطر عبر sh -c منفصل) — أي construct متعدد الأسطر (دوال، حلقات،
#  if-blocks، أسطر مُتمِّمة بـ \) لا يعمل هناك. مُتحقَّق من run 36081684404.
#
#  المراحل (مطابقة للمخطط):
#    1. Install APK            adb install -r + تحقق الحزمة
#    2. Cold Start             am start -W -S على الـ release APK
#    3. تصفير gfxinfo + logcat
#    4. عيّنات خلفية meminfo/CPU كل 10 ثوانٍ
#    5. integration_test       7 سيناريوهات + Cold Start = 8
#    6. Dumps نهائية           meminfo / gfxinfo / cpuinfo / logcat / GC
#
#  مخرجات في mobile/build/perf-integration/:
#    install.log cold_start.txt results.txt test_<Scenario>.log
#    meminfo_samples.txt meminfo_final.txt gfxinfo.txt cpuinfo.txt
#    cpu_samples.txt logcat.txt gc.txt
# ==========================================================================
set -u

cd "$GITHUB_WORKSPACE" || exit 1

PKG="${APP_PACKAGE:-com.marina.marina}"
# ⚠️ مسار مطلق إلزامي: السكربت يقوم بـ cd mobile لاحقاً (لتشغيل flutter test)
# والمسار النسبي سيتحول إلى mobile/mobile/... بعد الـ cd — هذا بالضبط ما
# كسر run 36082917485 (test_*.log: No such file or directory).
MET="$GITHUB_WORKSPACE/mobile/build/perf-integration"
APK="mobile/build/app/outputs/flutter-apk/app-release.apk"
mkdir -p "$MET" || exit 1

# ══ إصلاح/تشخيص IOException: No such file or directory ═══════════════
# AGP ينشئ ملفات UTP المؤقتة في ~/.android/utp (getUtpPreferenceRootDir
# في UtpTestUtils.kt) — إن لم تكن قابلة للإنشاء فشل connectedDebugAndroidTest
# بـ IOException قبل تشغيل أي اختبار (run 36096436664). ننشئها مسبقاً
# ونوثّق حالة الأذونات في الـ artifact.
mkdir -p "$HOME/.android/utp" || true
{
  echo "=== env diagnosis ==="
  id
  ls -lad "$HOME/.android" "$HOME/.android/utp" 2>&1
  touch "$HOME/.android/utp/.write_test" 2>&1 && echo "utp dir writable: YES" \
    && rm -f "$HOME/.android/utp/.write_test" || echo "utp dir writable: NO"
  env | grep -E "ANDROID|HOME=|TMPDIR" || true
} > "$MET/env_diagnosis.txt" 2>&1

echo "=== Install APK ==="
if ! adb install -r "$APK" | tee "$MET/install.log"; then
  echo "::error::adb install failed for $APK"
  exit 1
fi
if ! adb shell pm list packages | grep "$PKG" | tee -a "$MET/install.log"; then
  echo "::error::package $PKG not installed"
  exit 1
fi

echo "=== Cold Start measurement ==="
adb shell am start -W -S -n "$PKG/.MainActivity" \
  > "$MET/cold_start.txt" 2>&1 || true
cat "$MET/cold_start.txt"

# نترك التطبيق يعمل قليلاً ليرسم إطارات (أساس مقاييس gfxinfo)
sleep 8

# ⚠️ إزالة الـ release APK قبل سيناريوهات patrol:
# الـ release بُني بـ --build-number=${{ github.run_number }} (versionCode
# كبير) بينما debug/test APK من pubspec (1.2.0+3 → versionCode=3) —
# gradle connectedAndroidTest لا يقبل التثبيت النازل (INSTALL_FAILED_
# VERSION_DOWNGRADE) فيفشل بصمت بـ 0 tests (مُتحقَّق في run 36087698698).
# flutter test كان ينجو لأن flutter_tools يعيد المحاولة بعد uninstall
# أما gradle فلا يملك هذا السلوك. مقاييس cold start أعلاه مأخوذة أصلاً
# من الـ release APK الحقيقي.
adb uninstall "$PKG" || true

echo "=== Resetting gfxinfo + logcat ==="
adb shell dumpsys gfxinfo "$PKG" reset > /dev/null 2>&1 || true
adb logcat -c || true

echo "=== Starting background samplers (meminfo + CPU / 10s) ==="
: > "$MET/meminfo_samples.txt"
: > "$MET/cpu_samples.txt"
(
  i=0
  while [ $i -lt 90 ]; do
    i=$((i + 1))
    echo "----- meminfo sample $i -----" >> "$MET/meminfo_samples.txt"
    # TOTAL PSS يقع في قسم App Summary (بعد السطر 50) —
    # نستخرج السطور المفيدة مباشرة بدل قصّ عدد أسطر ثابت
    adb shell dumpsys meminfo "$PKG" 2>/dev/null \
      | grep -E "TOTAL PSS|Native Heap|TOTAL RSS" \
      >> "$MET/meminfo_samples.txt" || true
    echo "----- cpu sample $i -----" >> "$MET/cpu_samples.txt"
    adb shell top -n 1 2>/dev/null | grep -E "$PKG|CPU%" \
      >> "$MET/cpu_samples.txt" || true
    sleep 10
  done
) &
SAMPLER_PID=$!

echo "=== Integration test scenarios ==="
: > "$MET/results.txt"

# Cold Start قيس أعلاه عبر am start -W — نُسجّل نتيجته الآن
if grep -qE "TotalTime: [0-9]+" "$MET/cold_start.txt"; then
  echo "Cold Start=PASS" >> "$MET/results.txt"
else
  echo "Cold Start=FAIL" >> "$MET/results.txt"
fi

run_scenario() {
  local NAME="$1"
  local FILE="$2"
  echo "=== Scenario: $NAME ($FILE) ==="
  # المُشغِّل الصحيح هو patrol test (وليس flutter test) — المشروع مُهيَّأ
  # للـ Patrol الأصلي وflutter test على الجهاز يُهيِّئ integration_test
  # binding أولاً فيتعارض مع PatrolBinding.ensureInitialized.
  # ملاحظة: أول استدعاء يبني androidTest APK (~4-5 د) ثم incrementals.
  if patrol test --verbose --target "$FILE" > "$MET/test_${NAME}.log" 2>&1; then
    echo "$NAME=PASS" >> "$MET/results.txt"
  else
    echo "$NAME=FAIL" >> "$MET/results.txt"
    echo "::warning::integration scenario $NAME failed — see artifact test_${NAME}.log"
    # ── تشخيص عميق ──
    # 1) إعادة تشغيل أمر gradle نفسه (المستخرج من اللوج) مع --stacktrace
    #    لكشف مصدر IOException: No such file or directory
    GRADLE_CMD=$(grep -m1 -o "\./gradlew :app:connectedDebugAndroidTest.*" \
      "$MET/test_${NAME}.log" | tail -1)
    if [ -n "$GRADLE_CMD" ]; then
      (cd android && eval "$GRADLE_CMD --stacktrace") \
        > "$MET/test_${NAME}_stacktrace.log" 2>&1 || true
    fi
    # 2) ذيل logcat كامل (بدون grep — الـ grep أفرغ الملف سابقاً)
    adb logcat -d -t 3000 > "$MET/test_${NAME}_device.logcat.txt" 2>&1 || true
    # 3) حالة الجهاز وملفات الـ APK
    adb devices -l > "$MET/test_${NAME}_adb_devices.txt" 2>&1 || true
    ls -la build/app/outputs/apk/debug/ build/app/outputs/apk/androidTest/debug/ \
      >> "$MET/test_${NAME}_adb_devices.txt" 2>&1 || true
  fi
}

cd mobile || exit 1
run_scenario Login     integration_test/app_test.dart
run_scenario Dashboard integration_test/dashboard_test.dart
run_scenario Bookings  integration_test/bookings_test.dart
run_scenario Payments  integration_test/booking_payment_test.dart
run_scenario Expenses  integration_test/expenses_test.dart
run_scenario Reports   integration_test/reports_test.dart
run_scenario Sync      integration_test/sync_indicator_test.dart
cd .. || exit 1

echo "=== Stopping background samplers ==="
kill "$SAMPLER_PID" 2>/dev/null || true

echo "=== Final metric dumps ==="
adb shell dumpsys meminfo -d "$PKG" > "$MET/meminfo_final.txt" 2>&1 || true
adb shell dumpsys gfxinfo "$PKG" > "$MET/gfxinfo.txt" 2>&1 || true
adb shell dumpsys cpuinfo > "$MET/cpuinfo.txt" 2>&1 || true
adb logcat -d > "$MET/logcat.txt" 2>&1 || true
grep -E "GC freed|concurrent copying GC|WaitForGcToBlock|CollectorTransition" \
  "$MET/logcat.txt" > "$MET/gc.txt" 2>/dev/null || true

echo "=== Scenario results ==="
cat "$MET/results.txt"

exit 0
