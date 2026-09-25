#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# ✅ v2 (2026-09-25): ترقية لبوابة الأداء الكاملة:
#   - cold_start.csv: توقيتات am start -W لكل إطلاق (بوابة ×5)
#   - gfxinfo + cpuinfo لكل نقطة قياس (تشخيص الرسم والمعالج)
#   - قراءة تقرير الأداء الداخلي من بناء Release عبر adb root
#   - اختبار دورة الحياة (خلفية/أمام + تغيير وضع ليلي + دوران)
#   - فحص الاستقرار: Crash/ANR/OOM من logcat → crash_scan_summary.txt
#   - emulator_profile.txt: إثبات مواصفات المحاكي (RAM/Heap/API)
# ═══════════════════════════════════════════════════════════════

PACKAGE="${ANDROID_PACKAGE:-com.aden.marina}"
APK_PATH=""
OUTPUT_DIR="${LOW_RAM_OUTPUT_DIR:-build/low-ram-performance}"
MAX_PSS_KB="${MAX_PSS_KB:-393216}"
ADB_BIN="${ADB:-adb}"
CYCLES="${LOW_RAM_CYCLES:-5}"
SWIPES="${LOW_RAM_SWIPES:-8}"
ACTION_SCRIPT="${LOW_RAM_ACTION_SCRIPT:-}"
PERF_REPORT_REMOTE_PATH="${LOW_RAM_PERF_REPORT_REMOTE_PATH:-files/marina_performance_report.json}"
START_TIMEOUT_SEC="${LOW_RAM_START_TIMEOUT_SEC:-45}"
RELAUNCH_RETRIES="${LOW_RAM_RELAUNCH_RETRIES:-1}"
# ✅ v2: نوع كل إطلاق (initial/cycle_N/lifecycle) لملف cold_start.csv
LAUNCH_KIND="initial"
RUNTIME_PERMISSIONS="${LOW_RAM_RUNTIME_PERMISSIONS:-android.permission.CAMERA android.permission.POST_NOTIFICATIONS android.permission.READ_MEDIA_IMAGES android.permission.READ_MEDIA_AUDIO android.permission.READ_MEDIA_VIDEO}"

usage() {
  cat <<'USAGE'
Usage: android_low_ram_memory_test.sh [options]

Options:
  --package <id>          Android application id (default: com.aden.marina)
  --apk <path>            APK to install before measuring
  --output <directory>    Output directory (default: build/low-ram-performance)
  --max-pss-kb <kb>       Fail when peak app PSS exceeds this value (default: 393216)
  --cycles <count>        Cold-start/action cycles after first launch (default: 5)
  --swipes <count>        Fallback swipes per cycle (default: 8)
  --action-script <path>  Optional executable: script adb package cycle
  --perf-report-path <p>  run-as path for profile PerformanceMonitor JSON

Environment:
  LOW_RAM_START_TIMEOUT_SEC  seconds to wait for the app process (default: 45)
  LOW_RAM_RELAUNCH_RETRIES   clean relaunch retries after a failed start (default: 1)
  LOW_RAM_RUNTIME_PERMISSIONS space-separated runtime permissions to grant before launch
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package) PACKAGE="$2"; shift 2 ;;
    --apk) APK_PATH="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --max-pss-kb) MAX_PSS_KB="$2"; shift 2 ;;
    --cycles) CYCLES="$2"; shift 2 ;;
    --swipes) SWIPES="$2"; shift 2 ;;
    --action-script) ACTION_SCRIPT="$2"; shift 2 ;;
    --perf-report-path) PERF_REPORT_REMOTE_PATH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$CYCLES" =~ ^[0-9]+$ ]] || { echo "--cycles must be a non-negative integer" >&2; exit 2; }
[[ "$SWIPES" =~ ^[0-9]+$ ]] || { echo "--swipes must be a non-negative integer" >&2; exit 2; }
[[ -z "$ACTION_SCRIPT" || -x "$ACTION_SCRIPT" ]] || {
  echo "Action script is not executable: $ACTION_SCRIPT" >&2
  exit 2
}

mkdir -p "$OUTPUT_DIR"

"$ADB_BIN" wait-for-device
booted=""
for _ in $(seq 1 60); do
  booted=$("$ADB_BIN" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [[ "$booted" == "1" ]] && break
  sleep 2
done
if [[ "${booted:-}" != "1" ]]; then
  echo "Android device did not finish booting" >&2
  exit 1
fi

"$ADB_BIN" shell settings put global window_animation_scale 0 || true
"$ADB_BIN" shell settings put global transition_animation_scale 0 || true
"$ADB_BIN" shell settings put global animator_duration_scale 0 || true

# ✅ v2 (دعم Release): صور google_apis تسمح بـ adb root — دونه
# يستحيل قراءة files/marina_performance_report.json من بناء Release
# (غير debuggable، وrun-as يرفض العمل عليه).
"$ADB_BIN" root >/dev/null 2>&1 || true
"$ADB_BIN" wait-for-device >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
  booted=$("$ADB_BIN" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [[ "$booted" == "1" ]] && break
  sleep 2
done

# ✅ v2: توثيق مواصفات المحاكي (إثبات أن القياس على 1GB فعلاً).
{
  printf 'api_level=%s\n' "$("$ADB_BIN" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
  printf 'abis=%s\n' "$("$ADB_BIN" shell getprop ro.product.cpu.abilist 2>/dev/null | tr -d '\r')"
  printf 'dalvik_heapsize=%s\n' "$("$ADB_BIN" shell getprop dalvik.vm.heapsize 2>/dev/null | tr -d '\r')"
  printf 'dalvik_heapgrowthlimit=%s\n' "$("$ADB_BIN" shell getprop dalvik.vm.heapgrowthlimit 2>/dev/null | tr -d '\r')"
  printf 'screen=%s\n' "$("$ADB_BIN" shell wm size 2>/dev/null | tr -d '\r\n')"
  printf 'density=%s\n' "$("$ADB_BIN" shell wm density 2>/dev/null | tr -d '\r\n')"
  printf 'memtotal=%s\n' "$("$ADB_BIN" shell cat /proc/meminfo 2>/dev/null | head -1 | tr -d '\r')"
} > "$OUTPUT_DIR/emulator_profile.txt"

# Keep startup diagnostics scoped to this run; failure artifacts are uploaded by CI.
"$ADB_BIN" logcat -c >/dev/null 2>&1 || true

if [[ -n "$APK_PATH" ]]; then
  [[ -f "$APK_PATH" ]] || { echo "APK not found: $APK_PATH" >&2; exit 1; }
  "$ADB_BIN" install -r "$APK_PATH"
fi

# The production manifest requests runtime permissions. On a fresh emulator,
# PermissionController can remain on top after a force-stop and make `am start`
# report Status: ok while the app is not actually ready. The explicit grants
# below remain the first layer; grant_all_requested_runtime_permissions adds
# the full manifest set so no un-granted dangerous permission can surface a
# system dialog mid-cycle.
#
# Run 35543654200 post-mortem: a Settings-hosted permission page
# (com.android.settings/.spa.SpaActivity) stayed on top after force-stop and
# swallowed every subsequent `am start` via "delivered to currently running
# top-most instance" — cycles 2+ never launched. The fix is layered:
#   1. launch_app_once detects a foreign `Activity:` in `am start -W` output
#      and fails fast instead of waiting START_TIMEOUT_SEC on a dead launch.
#   2. dismiss_system_ui closes any surviving system UI (BACK + force-stop
#      of dialog-hosting packages) before every launch attempt, and the
#      launch uses FLAG_ACTIVITY_CLEAR_TASK so a stale task record can never
#      satisfy the launch intent without starting the process.
#   3. grant_all_requested_runtime_permissions covers every dangerous
#      permission the APK declares, plus appops for the special-access ones
#      that `pm grant` cannot handle.
if ! "$ADB_BIN" shell pm path "$PACKAGE" >/dev/null 2>&1; then
  echo "Package is not installed: $PACKAGE" >&2
  exit 1
fi

metrics_csv="$OUTPUT_DIR/memory_metrics.csv"
raw_dir="$OUTPUT_DIR/raw"
lifecycle_log="$OUTPUT_DIR/lifecycle.log"
cold_start_csv="$OUTPUT_DIR/cold_start.csv"
mkdir -p "$raw_dir"
# ✅ v2: توقيتات الإطلاق (am start -W) — بوابة cold-start ×5
printf 'label,total_time_ms,wait_time_ms\n' > "$cold_start_csv"
printf 'label,timestamp_ms,cycle,total_pss_kb,private_other_kb,unknown_kb,java_heap_kb,native_heap_kb,graphics_kb,total_rss_kb,swap_pss_kb,activities,views,webviews\n' > "$metrics_csv"
printf 'event,timestamp_ms,cycle,process_state\n' > "$lifecycle_log"

now_ms() {
  date +%s%3N
}

process_state() {
  if "$ADB_BIN" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' | grep -q '[0-9]'; then
    printf 'running'
  else
    printf 'absent'
  fi
}

wait_for_process() {
  local timeout="${1:-$START_TIMEOUT_SEC}"
  for _ in $(seq 1 "$timeout"); do
    [[ "$(process_state)" == "running" ]] && return 0
    sleep 1
  done
  echo "Application process did not start: $PACKAGE (timeout=${timeout}s)" >&2
  return 1
}

stop_app() {
  "$ADB_BIN" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  for _ in $(seq 1 15); do
    [[ "$(process_state)" == "absent" ]] && return 0
    sleep 1
  done
  # am force-stop is asynchronous on some emulator images. Ask ActivityManager
  # to kill the package before the next explicit launch instead of racing it.
  "$ADB_BIN" shell am kill "$PACKAGE" >/dev/null 2>&1 || true
  sleep 2
  [[ "$(process_state)" == "absent" ]]
}

grant_runtime_permissions() {
  local permission result
  for permission in $RUNTIME_PERMISSIONS; do
    result=$("$ADB_BIN" shell pm grant "$PACKAGE" "$permission" 2>&1 || true)
    printf 'permission_grant timestamp_ms=%s permission=%s result=%s\n' \
      "$(now_ms)" "$permission" "${result//$'\\n'/ | }" >> "$lifecycle_log"
  done
}

# Layer 3 (prevention): grant EVERY dangerous permission the installed APK
# actually requests, not a hand-picked list. The set is derived from
# `dumpsys package` intersected with `pm list permissions -g -d`, so any
# permission the manifest adds later is covered automatically. Special-access
# permissions (MANAGE_EXTERNAL_STORAGE, SCHEDULE_EXACT_ALARM,
# REQUEST_INSTALL_PACKAGES) cannot be `pm grant`-ed; they get their documented
# appop where the platform defines one, and the doze whitelist covers battery
# exemption. Every result is logged; nothing here is ever fatal.
grant_all_requested_runtime_permissions() {
  local requested dangerous perm result op
  requested=$("$ADB_BIN" shell dumpsys package "$PACKAGE" 2>/dev/null \
    | tr -d '\r' | grep -oE 'android\.permission\.[A-Z_]+' | sort -u)
  dangerous=$("$ADB_BIN" shell pm list permissions -g -d 2>/dev/null \
    | tr -d '\r' | grep -oE 'android\.permission\.[A-Z_]+' | sort -u)
  [[ -n "$requested" && -n "$dangerous" ]] || return 0
  for perm in $dangerous; do
    if printf '%s\n' "$requested" | grep -qx "$perm"; then
      result=$("$ADB_BIN" shell pm grant "$PACKAGE" "$perm" 2>&1 || true)
      printf 'permission_grant_all timestamp_ms=%s permission=%s result=%s\n' \
        "$(now_ms)" "$perm" "${result//$'\n'/ | }" >> "$lifecycle_log"
    fi
  done
  for op in MANAGE_EXTERNAL_STORAGE SCHEDULE_EXACT_ALARM REQUEST_INSTALL_PACKAGES; do
    result=$("$ADB_BIN" shell appops set "$PACKAGE" "$op" allow 2>&1 || true)
    printf 'appop_grant timestamp_ms=%s op=%s result=%s\n' \
      "$(now_ms)" "$op" "${result//$'\n'/ | }" >> "$lifecycle_log"
  done
  result=$("$ADB_BIN" shell dumpsys deviceidle whitelist "+$PACKAGE" 2>&1 || true)
  printf 'doze_whitelist timestamp_ms=%s result=%s\n' \
    "$(now_ms)" "${result//$'\n'/ | }" >> "$lifecycle_log"
}

# Layer 2 (recovery): close any foreign system UI that survived the app
# force-stop. Permission dialogs and special-access pages are hosted by
# Settings/PermissionController/PackageInstaller; they keep the foreground
# after our app is stopped and hijack the next `am start`. BACK dismisses
# dialog-hosted prompts; force-stop guarantees the rest. All best-effort.
dismiss_system_ui() {
  "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  local pkg
  for pkg in \
    com.android.settings \
    com.google.android.settings \
    com.android.permissioncontroller \
    com.google.android.permissioncontroller \
    com.android.packageinstaller \
    com.google.android.packageinstaller; do
    "$ADB_BIN" shell am force-stop "$pkg" >/dev/null 2>&1 || true
  done
  sleep 1
}

# Instrumentation: record which UI holds the foreground at cycle boundaries
# so a mid-cycle hijack is visible in lifecycle.log instead of requiring
# post-mortem artifact analysis.
log_foreground() {
  local cycle="$1" focus
  focus=$("$ADB_BIN" shell dumpsys window 2>/dev/null \
    | grep -m1 -E 'mCurrentFocus|mFocusedApp' | tr -d '\r' || true)
  printf 'foreground timestamp_ms=%s cycle=%s focus=%s\n' \
    "$(now_ms)" "$cycle" "${focus:-unknown}" >> "$lifecycle_log"
}

collect_startup_diagnostics() {
  local prefix="$raw_dir/startup_failure_$(now_ms)"
  "$ADB_BIN" shell dumpsys activity activities > "${prefix}_activity.txt" 2>&1 || true
  "$ADB_BIN" shell dumpsys package "$PACKAGE" > "${prefix}_package.txt" 2>&1 || true
  # Window focus pinpoints the UI on top at the failure moment — this is what
  # exposed the Settings permission-page hijack in the 35543654200 post-mortem.
  "$ADB_BIN" shell dumpsys window > "${prefix}_window.txt" 2>&1 || true
  # Broadened beyond the old Java-only filter: native crashes ("Fatal
  # signal"), process lifecycle (am_proc_*) and LMKD kills are captured too.
  "$ADB_BIN" logcat -d -b all -v threadtime -t 3000 \
    | grep -E "${PACKAGE//./\\.}|AndroidRuntime|ActivityTaskManager|FATAL EXCEPTION|Fatal signal|Process: |am_proc|am_kill|lowmemorykiller|lmkd|tombstoned" \
    > "${prefix}_logcat.txt" || true
}

# ✅ v2 (دعم Release): run-as يعمل على debug/profile فقط؛ على
# Release نقرأ مباشرة عبر جذر adbd (صور google_apis تسمح به).
read_perf_json() {
  local remote_path="$1" out_file="$2"
  if "$ADB_BIN" shell run-as "$PACKAGE" cat "$remote_path" > "$out_file" 2>/dev/null && [[ -s "$out_file" ]]; then
    return 0
  fi
  rm -f "$out_file"
  if "$ADB_BIN" shell cat "/data/data/$PACKAGE/$remote_path" > "$out_file" 2>/dev/null && [[ -s "$out_file" ]]; then
    return 0
  fi
  rm -f "$out_file"
  return 1
}

measure() {
  local label="$1"
  local cycle="$2"
  local timestamp raw perf_raw total_pss private_other unknown java_heap native_heap graphics total_rss swap_pss activities views webviews
  timestamp="$(now_ms)"
  raw="$raw_dir/${timestamp}_${label}.txt"
  perf_raw="$raw_dir/${timestamp}_${label}_performance.json"
  "$ADB_BIN" shell dumpsys meminfo -d "$PACKAGE" > "$raw"
  # ✅ best-effort عمداً: فشل قراءة تقرير الأداء (إعادة كتابة لحظية
  # للملف مثلاً) لا يجوز أن يقتل القياس — كان يفعلها return 1 تحت
  # set -e فقتل السكربت في منتصف الدورات.
  read_perf_json "$PERF_REPORT_REMOTE_PATH" "$perf_raw" || true
  # ✅ v2: تشخيص الرسم والمعالج لكل نقطة قياس
  "$ADB_BIN" shell dumpsys gfxinfo "$PACKAGE" > "${raw_dir}/${timestamp}_${label}_gfxinfo.txt" 2>&1 || true
  "$ADB_BIN" shell dumpsys cpuinfo > "${raw_dir}/${timestamp}_${label}_cpuinfo.txt" 2>&1 || true

  total_pss=$(awk '/TOTAL PSS:/ {gsub(",", "", $3); print $3; exit}' "$raw")
  private_other=$(awk '/^[[:space:]]*Private Other:/ {gsub(",", "", $3); print $3; exit}' "$raw")
  unknown=$(awk '/^[[:space:]]*Unknown:/ {gsub(",", "", $2); print $2; exit}' "$raw")
  java_heap=$(awk '/^[[:space:]]*Java Heap:/ {gsub(",", "", $3); print $3; exit}' "$raw")
  native_heap=$(awk '/^[[:space:]]*Native Heap:/ {gsub(",", "", $3); print $3; exit}' "$raw")
  graphics=$(awk '/^[[:space:]]*Graphics:/ {gsub(",", "", $2); print $2; exit}' "$raw")
  total_rss=$(awk '/TOTAL PSS:/ {for (i = 1; i <= NF; i++) if ($i == "RSS:") {gsub(",", "", $(i + 1)); print $(i + 1); exit}}' "$raw")
  swap_pss=$(awk '/TOTAL PSS:/ {gsub(",", "", $NF); print $NF; exit}' "$raw")
  activities=$(awk '/^[[:space:]]*Activities:/ {print $2; exit}' "$raw")
  views=$(awk '/^[[:space:]]*Views:/ {print $2; exit}' "$raw")
  webviews=$(awk '/^[[:space:]]*WebViews:/ {print $2; exit}' "$raw")

  total_pss="${total_pss:-0}"
  private_other="${private_other:-0}"
  unknown="${unknown:-0}"
  java_heap="${java_heap:-0}"
  native_heap="${native_heap:-0}"
  graphics="${graphics:-0}"
  total_rss="${total_rss:-0}"
  swap_pss="${swap_pss:-0}"
  activities="${activities:-0}"
  views="${views:-0}"
  webviews="${webviews:-0}"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$label" "$timestamp" "$cycle" "$total_pss" "$private_other" "$unknown" \
    "$java_heap" "$native_heap" "$graphics" "$total_rss" "$swap_pss" \
    "$activities" "$views" "$webviews" >> "$metrics_csv"
  printf 'LOW_RAM_METRIC label=%s cycle=%s total_pss_kb=%s private_other_kb=%s unknown_kb=%s java_heap_kb=%s native_heap_kb=%s total_rss_kb=%s swap_pss_kb=%s\n' \
    "$label" "$cycle" "$total_pss" "$private_other" "$unknown" "$java_heap" "$native_heap" "$total_rss" "$swap_pss"
}

launch_app_once() {
  local output started_activity
  # Layer 2 (recovery): never launch into a foreign foreground — the
  # hijacking dialog/page gets closed first.
  dismiss_system_ui
  # FLAG_ACTIVITY_CLEAR_TASK (0x10008000 = NEW_TASK | CLEAR_TASK): the target
  # task is wiped and rebuilt, so a stale activity record from the previous
  # cycle can never satisfy the launch intent without spawning the process
  # (the "delivered to currently running top-most instance" pathology).
  output=$("$ADB_BIN" shell am start -W \
    -n "$PACKAGE/.MainActivity" \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER \
    -f 0x10008000 \
    2>&1 || true)
  printf 'launch_attempt timestamp_ms=%s output=%s\n' "$(now_ms)" "${output//$'\\n'/ | }" >> "$lifecycle_log"
  # ✅ v2: تسجيل توقيت الإطلاق في cold_start.csv (بوابة cold-start)
  launch_total_ms=$(printf '%s' "$output" | grep -oE 'TotalTime: *[0-9]+' | grep -oE '[0-9]+' || true)
  launch_wait_ms=$(printf '%s' "$output" | grep -oE 'WaitTime: *[0-9]+' | grep -oE '[0-9]+' || true)
  if [[ -n "${launch_total_ms:-}" ]]; then
    printf '%s,%s,%s\n' "${LAUNCH_KIND:-launch}" "$launch_total_ms" "${launch_wait_ms:-0}" >> "$cold_start_csv"
  fi

  if printf '%s' "$output" | grep -Eq 'Error type|Error:|Exception|does not exist'; then
    return 1
  fi
  # Layer 1 (detection): `am start -W` reports the activity the launch
  # actually resolved to. When a foreign package steals the launch, Status
  # is still "ok" — the only tell is the Activity line. Fail fast instead of
  # waiting START_TIMEOUT_SEC on a process that will never spawn.
  started_activity=$(printf '%s' "$output" \
    | sed -n 's/^Activity:[[:space:]]*//p' | head -1 | tr -d '\r')
  if [[ -n "$started_activity" && "${started_activity%%/*}" != "$PACKAGE" ]]; then
    printf 'launch_foreign_activity timestamp_ms=%s reported=%s\n' \
      "$(now_ms)" "$started_activity" >> "$lifecycle_log"
    return 1
  fi
  wait_for_process "$START_TIMEOUT_SEC"
  sleep 8
  [[ "$(process_state)" == "running" ]] || return 1
}

launch_app() {
  local attempt
  for attempt in $(seq 0 "$RELAUNCH_RETRIES"); do
    if launch_app_once; then
      return 0
    fi
    printf 'launch_retry timestamp_ms=%s attempt=%s\n' "$(now_ms)" "$attempt" >> "$lifecycle_log"
    collect_startup_diagnostics
    stop_app || true
    sleep 2
  done
  collect_startup_diagnostics
  echo "Application process did not start: $PACKAGE after $((RELAUNCH_RETRIES + 1)) attempt(s)" >&2
  return 1
}

run_actions() {
  local cycle="$1"
  if [[ -n "$ACTION_SCRIPT" ]]; then
    # ✅ v2: فشل سكربت الإجراءات لا يقتل دورة القياس — تُستكمل
    # القياسات ويقرر الفشلَ البوابةُ النهائية من الأحداث المفقودة.
    if ! "$ACTION_SCRIPT" "$ADB_BIN" "$PACKAGE" "$cycle"; then
      printf 'action_script_failure cycle=%s\n' "$cycle" >> "$lifecycle_log"
    fi
    return 0
  fi

  # Fallback is intentionally limited to gestures. A real navigation action
  # script can be supplied when the emulator has an authenticated test state.
  for i in $(seq 1 "$SWIPES"); do
    "$ADB_BIN" shell input swipe 540 1750 540 350 500 >/dev/null || true
    sleep 1
  done
}

grant_runtime_permissions
grant_all_requested_runtime_permissions
stop_app || true
sleep 2

printf 'cold_start_before,%s,0,absent\n' "$(now_ms)" >> "$lifecycle_log"
# No meminfo row is written here: dumpsys on an absent process is not a valid
# cold-start baseline and must never be treated as zero memory.
LAUNCH_KIND="initial"
launch_app
printf 'cold_start_after,%s,0,%s\n' "$(now_ms)" "$(process_state)" >> "$lifecycle_log"
measure cold_start_after 0
log_foreground 0

for cycle in $(seq 1 "$CYCLES"); do
  if (( cycle > 1 )); then
    stop_app || true
    printf 'cycle_force_stop,%s,%s,%s\n' "$(now_ms)" "$cycle" "$(process_state)" >> "$lifecycle_log"
    sleep 2
    LAUNCH_KIND="cycle_${cycle}"
    launch_app
  fi
  printf 'cycle_start,%s,%s,%s\n' "$(now_ms)" "$cycle" "$(process_state)" >> "$lifecycle_log"
  measure "cycle_${cycle}_after_start" "$cycle"
  log_foreground "$cycle"
  run_actions "$cycle"
  sleep 2
  measure "cycle_${cycle}_after_actions" "$cycle"
  log_foreground "$cycle"
done

# ═══ ✅ v2 (17): دورة الحياة — خلفية/أمام + تغيير تكوين + حالة العملية ═══
# تغيير الوضع الليلي (cmd uimode) تغيير تكوين حقيقي يعيد بناء الواجهة
# (التطبيق يقفل الاتجاه عمودياً بتصميمه فمحاولة الدوران تُسجّل فقط).
lifecycle_note() {
  printf 'lifecycle_%s,%s,%s,%s\n' "$1" "$(now_ms)" "$2" "$(process_state)" >> "$lifecycle_log"
}

"$ADB_BIN" shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
sleep 3
lifecycle_note "backgrounded" 6
LAUNCH_KIND="lifecycle_home_return"
launch_app
measure "lifecycle_home_return" 6
lifecycle_note "warm_foreground_return" 6

"$ADB_BIN" shell cmd uimode night yes >/dev/null 2>&1 || true
sleep 4
lifecycle_note "dark_mode_config_change" 7
if [[ "$(process_state)" == "running" ]]; then
  measure "lifecycle_dark_mode" 7
else
  LAUNCH_KIND="lifecycle_dark_mode_relaunch"
  launch_app
  measure "lifecycle_dark_mode" 7
fi
"$ADB_BIN" shell cmd uimode night no >/dev/null 2>&1 || true
sleep 3
lifecycle_note "light_mode_restored" 7

"$ADB_BIN" shell settings put system accelerometer_rotation 0 >/dev/null 2>&1 || true
"$ADB_BIN" shell settings put system user_rotation 1 >/dev/null 2>&1 || true
sleep 3
lifecycle_note "rotate_attempt" 8
"$ADB_BIN" shell settings put system user_rotation 0 >/dev/null 2>&1 || true
sleep 2

# ═══ ✅ v2 (12/19): فحص الاستقرار — Crash / ANR / OOM من logcat ═══
# logcat مُسح في بداية التشغيل فكل ما هنا من هذه الجلسة تحديداً.
full_log="$raw_dir/logcat_final.txt"
"$ADB_BIN" logcat -d -v threadtime -t 20000 > "$full_log" 2>/dev/null || true
PACKAGE_RE="${PACKAGE//./\\.}"
fatal_count=$(awk '/FATAL EXCEPTION/{inblock=1} inblock && /Process: /{inblock=0; if ($0 ~ Pkg) ours++} END{print ours+0}' Pkg="$PACKAGE_RE" "$full_log" 2>/dev/null || true)
anr_count=$(grep -cE "ANR in $PACKAGE|am_anr.*$PACKAGE_RE" "$full_log" 2>/dev/null || true)
oom_count=$(grep -cE 'OutOfMemoryError' "$full_log" 2>/dev/null || true)
native_crash_count=$(grep -cE 'Fatal signal' "$full_log" 2>/dev/null || true)
{
  printf 'fatal_exception_count=%s\n' "${fatal_count:-0}"
  printf 'anr_count=%s\n' "${anr_count:-0}"
  printf 'oom_count=%s\n' "${oom_count:-0}"
  printf 'native_fatal_signal_count=%s\n' "${native_crash_count:-0}"
} > "$OUTPUT_DIR/crash_scan_summary.txt"
grep -E "FATAL EXCEPTION|ANR in |am_anr|OutOfMemoryError|Fatal signal|lowmemorykiller|Input dispatching|Process: " "$full_log" \
  > "$OUTPUT_DIR/crash_scan.txt" 2>/dev/null || true

peak_pss=$(awk -F, 'NR > 1 && $4 > max {max=$4} END {print max + 0}' "$metrics_csv")
peak_label=$(awk -F, -v max="$peak_pss" 'NR > 1 && $4 == max {print $1; exit}' "$metrics_csv")
last_pss=$(awk -F, 'NR > 1 {value=$4} END {print value + 0}' "$metrics_csv")
first_pss=$(awk -F, 'NR > 1 {print $4; exit}' "$metrics_csv")
cycle_peak_pss=$(awk -F, 'NR > 1 && $3 > 0 && $4 > max {max=$4} END {print max + 0}' "$metrics_csv")
cycle_last_pss=$(awk -F, 'NR > 1 && $3 > 0 {value=$4} END {print value + 0}' "$metrics_csv")

cat > "$OUTPUT_DIR/summary.txt" <<EOF
package=$PACKAGE
max_pss_kb=$MAX_PSS_KB
cycles=$CYCLES
swipes_per_cycle=$SWIPES
action_script=${ACTION_SCRIPT:-none}
perf_report_remote_path=$PERF_REPORT_REMOTE_PATH
cold_start_before=not_measurable_process_absent
first_measured_pss_kb=$first_pss
peak_pss_kb=$peak_pss
peak_label=$peak_label
last_pss_kb=$last_pss
cycle_peak_pss_kb=$cycle_peak_pss
cycle_last_pss_kb=$cycle_last_pss
cycle_delta_kb=$((cycle_last_pss - cycle_peak_pss))
cred_mode=${MARINA_TEST_CRED_MODE:-local-fallback}
cold_start_records=$(($(wc -l < "$cold_start_csv") - 1))
fatal_exception_count=${fatal_count:-0}
anr_count=${anr_count:-0}
oom_count=${oom_count:-0}
native_fatal_signal_count=${native_crash_count:-0}
EOF

if (( peak_pss <= 0 )); then
  echo "Unable to read TOTAL PSS from dumpsys meminfo" >&2
  exit 1
fi
if (( peak_pss > MAX_PSS_KB )); then
  echo "Peak app PSS ${peak_pss}KB exceeds limit ${MAX_PSS_KB}KB" >&2
  exit 1
fi

echo "LOW_RAM_RESULT status=PASS peak_pss_kb=$peak_pss limit_kb=$MAX_PSS_KB cycles=$CYCLES"
