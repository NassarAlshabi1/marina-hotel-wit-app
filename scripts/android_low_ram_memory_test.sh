#!/usr/bin/env bash
set -euo pipefail

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
# Keep startup diagnostics scoped to this run; failure artifacts are uploaded by CI.
"$ADB_BIN" logcat -c >/dev/null 2>&1 || true

if [[ -n "$APK_PATH" ]]; then
  [[ -f "$APK_PATH" ]] || { echo "APK not found: $APK_PATH" >&2; exit 1; }
  "$ADB_BIN" install -r "$APK_PATH"
fi

# The production manifest requests runtime permissions. On a fresh emulator,
# PermissionController can remain on top after a force-stop and make `am start`
# report Status: ok while the app is not actually ready. Grant only the
# permissions explicitly configured for this test harness before the first
# launch; failed grants are logged and do not hide real startup failures.
if ! "$ADB_BIN" shell pm path "$PACKAGE" >/dev/null 2>&1; then
  echo "Package is not installed: $PACKAGE" >&2
  exit 1
fi

metrics_csv="$OUTPUT_DIR/memory_metrics.csv"
raw_dir="$OUTPUT_DIR/raw"
lifecycle_log="$OUTPUT_DIR/lifecycle.log"
mkdir -p "$raw_dir"
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

collect_startup_diagnostics() {
  local prefix="$raw_dir/startup_failure_$(now_ms)"
  "$ADB_BIN" shell dumpsys activity activities > "${prefix}_activity.txt" 2>&1 || true
  "$ADB_BIN" shell dumpsys package "$PACKAGE" > "${prefix}_package.txt" 2>&1 || true
  "$ADB_BIN" logcat -d -b all -v threadtime -t 3000 \
    | grep -E "${PACKAGE//./\\.}|AndroidRuntime|ActivityTaskManager|FATAL EXCEPTION|Process: " \
    > "${prefix}_logcat.txt" || true
}

measure() {
  local label="$1"
  local cycle="$2"
  local timestamp raw perf_raw total_pss private_other unknown java_heap native_heap graphics total_rss swap_pss activities views webviews
  timestamp="$(now_ms)"
  raw="$raw_dir/${timestamp}_${label}.txt"
  perf_raw="$raw_dir/${timestamp}_${label}_performance.json"
  "$ADB_BIN" shell dumpsys meminfo -d "$PACKAGE" > "$raw"
  if ! "$ADB_BIN" shell run-as "$PACKAGE" cat "$PERF_REPORT_REMOTE_PATH" > "$perf_raw" 2>/dev/null; then
    rm -f "$perf_raw"
  fi

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
  local output
  output=$("$ADB_BIN" shell am start -W \
    -n "$PACKAGE/.MainActivity" \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER 2>&1 || true)
  printf 'launch_attempt timestamp_ms=%s output=%s\n' "$(now_ms)" "${output//$'\\n'/ | }" >> "$lifecycle_log"
  if printf '%s' "$output" | grep -Eq 'Error type|Error:|Exception|does not exist'; then
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
    "$ACTION_SCRIPT" "$ADB_BIN" "$PACKAGE" "$cycle"
    return
  fi

  # Fallback is intentionally limited to gestures. A real navigation action
  # script can be supplied when the emulator has an authenticated test state.
  for i in $(seq 1 "$SWIPES"); do
    "$ADB_BIN" shell input swipe 540 1750 540 350 500 >/dev/null || true
    sleep 1
  done
}

grant_runtime_permissions
stop_app || true
sleep 2

printf 'cold_start_before,%s,0,absent\n' "$(now_ms)" >> "$lifecycle_log"
# No meminfo row is written here: dumpsys on an absent process is not a valid
# cold-start baseline and must never be treated as zero memory.
launch_app
printf 'cold_start_after,%s,0,%s\n' "$(now_ms)" "$(process_state)" >> "$lifecycle_log"
measure cold_start_after 0

for cycle in $(seq 1 "$CYCLES"); do
  if (( cycle > 1 )); then
    stop_app || true
    printf 'cycle_force_stop,%s,%s,%s\n' "$(now_ms)" "$cycle" "$(process_state)" >> "$lifecycle_log"
    sleep 2
    launch_app
  fi
  printf 'cycle_start,%s,%s,%s\n' "$(now_ms)" "$cycle" "$(process_state)" >> "$lifecycle_log"
  measure "cycle_${cycle}_after_start" "$cycle"
  run_actions "$cycle"
  sleep 2
  measure "cycle_${cycle}_after_actions" "$cycle"
done

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
