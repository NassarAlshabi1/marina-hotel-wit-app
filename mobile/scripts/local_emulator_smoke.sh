#!/usr/bin/env bash
# ==========================================================================
#  Marina Hotel — LOCAL emulator smoke test (one command, any machine)
# ==========================================================================
#  يشغّل التطبيق على محاكي محلي ويعطي نتيجة سريعة: إقلاع، شاشة دخول،
#  فحص FATAL في logcat، ولقطة شاشة. اختيارياً يشغّل سيناريوهات Patrol.
#
#  الاستخدام:
#    bash mobile/scripts/local_emulator_smoke.sh [الخيارات]
#
#  الخيارات:
#    --apk <path>      APK جاهز للتثبيت (افتراضي: يبحث في download/
#                      ثم mobile/build/...، وإلا يبني debug x86_64)
#    --avd <name>      اسم الـ AVD (افتراضي: أول AVD متاح)
#    --scenarios       يشغّل سيناريوهات Patrol السبعة كاملة (بعد الدخان)
#    --memory <mb>     ذاكرة الضيف (افتراضي 2048، أو 1024 للأجهزة الضعيفة)
#
#  متطلبات: ANDROID_HOME مضبوط (أو SDK في المسار الافتراضي)، وجهاز
#  بـ KVM/HAXM/WHPX إن أردت إقلاعاً بالثواني — بدونه يعمل بالـ TCG
#  البرمجي (إقلاع 15-40 دقيقة، مقبول للدخان فقط).
# ==========================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
OUT="$ROOT/build/local-emulator"
mkdir -p "$OUT"

APK=""
AVD=""
SCENARIOS=0
GUEST_MEM=2048

while [ $# -gt 0 ]; do
  case "$1" in
    --apk) APK="$2"; shift 2 ;;
    --avd) AVD="$2"; shift 2 ;;
    --scenarios) SCENARIOS=1; shift ;;
    --memory) GUEST_MEM="$2"; shift 2 ;;
    *) echo "خيار غير معروف: $1"; exit 2 ;;
  esac
done

# ── تحديد SDK ────────────────────────────────────────────────────────────
if [ -z "${ANDROID_HOME:-}" ]; then
  for CAND in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" \
              "/usr/local/lib/android/sdk" "$HOME/android-sdk"; do
    [ -d "$CAND/platform-tools" ] && export ANDROID_HOME="$CAND" && break
  done
fi
[ -n "${ANDROID_HOME:-}" ] || { echo "ANDROID_HOME غير مضبوط ولا يوجد SDK معروف"; exit 1; }
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
echo "SDK: $ANDROID_HOME"

# ── اختيار AVD ───────────────────────────────────────────────────────────
if [ -z "$AVD" ]; then
  AVD="$(emulator -list-avds 2>/dev/null | head -1)"
  [ -n "$AVD" ] || { echo "لا يوجد AVD — أنشئ واحداً:"; \
    echo "  avdmanager create avd -n marina -k 'system-images;android-30;google_apis;x86_64' -d pixel_2"; exit 1; }
fi
echo "AVD: $AVD"

# ── تسريع عتادي أم TCG؟ ──────────────────────────────────────────────────
ACCEL_FLAGS="-no-snapshot -no-boot-anim"
if [ -w /dev/kvm ] && [ "$(uname -s)" = "Linux" ]; then
  echo "التسريع: KVM ✅"
elif [ "$(uname -s)" = "Darwin" ]; then
  echo "التسريع: Hypervisor.framework ✅"
else
  echo "⚠️ لا يوجد تسريع عتادي — الإقلاع سيكون بطيئاً (TCG برمجي)"
  ACCEL_FLAGS="-no-snapshot -no-boot-anim -no-accel"
fi

# ── توفير APK ────────────────────────────────────────────────────────────
if [ -z "$APK" ]; then
  for CAND in "$ROOT/download/marina-x64-debug.apk" \
              "$ROOT/build/app/outputs/flutter-apk/app-debug.apk" \
              "$ROOT/mobile/build/app/outputs/flutter-apk/app-debug.apk"; do
    [ -f "$CAND" ] && APK="$CAND" && break
  done
fi
if [ -z "$APK" ]; then
  echo "لا يوجد APK — بناء debug x86_64 (يتطلب Flutter)..."
  (cd "$ROOT/mobile" && flutter build apk --debug --target-platform android-x64) || exit 1
  APK="$ROOT/mobile/build/app/outputs/flutter-apk/app-debug.apk"
fi
echo "APK: $APK"

# ── الإقلاع ──────────────────────────────────────────────────────────────
echo "=== إقلاع المحاكي ==="
emulator -avd "$AVD" -no-window -gpu swiftshader_indirect -noaudio \
  $ACCEL_FLAGS -memory "$GUEST_MEM" -cores 2 > "$OUT/emulator.log" 2>&1 &
EMU_PID=$!
trap 'kill $EMU_PID 2>/dev/null || true' EXIT

# انتظر اتصال adb ثم اكتمال الإقلاع (سقف 45 دقيقة يغطي حتى TCG)
adb wait-for-device
BOOT_TIMEOUT=2700
ELAPSED=0
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  if ! kill -0 "$EMU_PID" 2>/dev/null; then
    echo "::error::مات المحاكي أثناء الإقلاع — راجع $OUT/emulator.log"; exit 1
  fi
  if [ "$ELAPSED" -ge "$BOOT_TIMEOUT" ]; then
    echo "::error::انتهت مهلة الإقلاع (45 د)"; exit 1
  fi
  sleep 10; ELAPSED=$((ELAPSED + 10))
done
echo "اكتمل الإقلاع بعد $((ELAPSED / 60)) دقيقة ✅"

# ── تثبيت التطبيق وتشغيله ────────────────────────────────────────────────
echo "=== تثبيت APK ==="
adb install -r "$APK" | tee "$OUT/install.log"

echo "=== Cold Start (am start -W) ==="
adb shell am start -W -S -n com.marina.marina/.MainActivity | tee "$OUT/cold_start.txt"
sleep 12

adb exec-out screencap -p > "$OUT/screen_home.png" 2>/dev/null
echo "لقطة شاشة: $OUT/screen_home.png"

# ── فحص FATAL/ANR في logcat ──────────────────────────────────────────────
echo "=== فحص logcat ==="
adb logcat -d > "$OUT/logcat.txt" 2>&1 || true
if rg -i "FATAL EXCEPTION|ANR in com.marina.marina" "$OUT/logcat.txt" > "$OUT/fatal.txt" 2>/dev/null; then
  echo "::error::وُجد FATAL/ANR — راجع $OUT/fatal.txt"; SMOKE=FAIL
else
  echo "لا يوجد FATAL/ANR ✅"; SMOKE=PASS
fi

# ── سيناريوهات Patrol اختيارية (بنفس منطق CI: محاولة ثانية وحيدة) ────────
if [ "$SCENARIOS" = "1" ]; then
  echo "=== سيناريوهات Patrol ==="
  cd "$ROOT/mobile" || exit 1
  dart pub global activate patrol_cli 4.6.1 >/dev/null 2>&1
  export PATH="$HOME/.pub-cache/bin:$PATH"
  : > "$OUT/results.txt"
  for S in "Login integration_test/app_test.dart" \
           "Dashboard integration_test/dashboard_test.dart" \
           "Bookings integration_test/bookings_test.dart" \
           "Payments integration_test/booking_payment_test.dart" \
           "Expenses integration_test/expenses_test.dart" \
           "Reports integration_test/reports_test.dart" \
           "Sync integration_test/sync_indicator_test.dart"; do
    NAME="${S%% *}"; FILE="${S#* }"
    echo "=== Scenario: $NAME ==="
    if patrol test --target "$FILE" > "$OUT/test_${NAME}.log" 2>&1; then
      echo "$NAME=PASS" >> "$OUT/results.txt"; continue
    fi
    # محاولة ثانية وحيدة — انهيار الـ instrumentation العابر ليس انحداراً
    if patrol test --target "$FILE" >> "$OUT/test_${NAME}.log" 2>&1; then
      echo "$NAME=PASS" >> "$OUT/results.txt"
      echo "  (نجحت في المحاولة الثانية)"
    else
      echo "$NAME=FAIL" >> "$OUT/results.txt"
    fi
  done
  echo "=== النتائج ==="; cat "$OUT/results.txt"
fi

echo "=== النتيجة: $SMOKE ==="
[ "$SMOKE" = "PASS" ]
