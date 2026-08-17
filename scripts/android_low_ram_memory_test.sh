#!/usr/bin/env bash
set -euo pipefail

PACKAGE="${ANDROID_PACKAGE:-com.aden.marina}"
APK_PATH=""
OUTPUT_DIR="${LOW_RAM_OUTPUT_DIR:-build/low-ram-performance}"
MAX_PSS_KB="${MAX_PSS_KB:-393216}"
ADB_BIN="${ADB:-adb}"

usage() {
  cat <<'USAGE'
Usage: android_low_ram_memory_test.sh [options]

Options:
  --package <id>       Android application id (default: com.aden.marina)
  --apk <path>         APK to install before measuring
  --output <directory> Output directory (default: build/low-ram-performance)
  --max-pss-kb <kb>    Fail when peak app PSS exceeds this value (default: 393216)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package) PACKAGE="$2"; shift 2 ;;
    --apk) APK_PATH="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --max-pss-kb) MAX_PSS_KB="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

"$ADB_BIN" wait-for-device
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

if [[ -n "$APK_PATH" ]]; then
  [[ -f "$APK_PATH" ]] || { echo "APK not found: $APK_PATH" >&2; exit 1; }
  "$ADB_BIN" install -r "$APK_PATH"
fi

if ! "$ADB_BIN" shell pm path "$PACKAGE" >/dev/null 2>&1; then
  echo "Package is not installed: $PACKAGE" >&2
  exit 1
fi

metrics_csv="$OUTPUT_DIR/memory_metrics.csv"
raw_dir="$OUTPUT_DIR/raw"
mkdir -p "$raw_dir"
printf 'label,timestamp_ms,total_pss_kb,java_heap_kb,native_heap_kb,graphics_kb\n' > "$metrics_csv"

now_ms() {
  date +%s%3N
}

measure() {
  local label="$1"
  local timestamp raw total_pss java_heap native_heap graphics
  timestamp="$(now_ms)"
  raw="$raw_dir/${timestamp}_${label}.txt"
  "$ADB_BIN" shell dumpsys meminfo "$PACKAGE" > "$raw"

  total_pss=$(awk '/TOTAL PSS:/ {gsub(",", "", $3); print $3; exit}' "$raw")
  java_heap=$(awk '/Java Heap:/ {gsub(",", "", $3); print $3; exit}' "$raw")
  native_heap=$(awk '/Native Heap:/ {gsub(",", "", $3); print $3; exit}' "$raw")
  graphics=$(awk '/Graphics:/ {gsub(",", "", $2); print $2; exit}' "$raw")

  total_pss="${total_pss:-0}"
  java_heap="${java_heap:-0}"
  native_heap="${native_heap:-0}"
  graphics="${graphics:-0}"
  printf '%s,%s,%s,%s,%s,%s\n' "$label" "$timestamp" "$total_pss" "$java_heap" "$native_heap" "$graphics" >> "$metrics_csv"
  printf 'LOW_RAM_METRIC label=%s total_pss_kb=%s java_heap_kb=%s native_heap_kb=%s graphics_kb=%s\n' \
    "$label" "$total_pss" "$java_heap" "$native_heap" "$graphics"
}

"$ADB_BIN" shell am force-stop "$PACKAGE"
sleep 2
measure cold_start_before
"$ADB_BIN" shell monkey -p "$PACKAGE" 1 >/dev/null
sleep 8
measure cold_start_after

# Exercise repeated list scrolling without depending on fragile widget coordinates.
for i in $(seq 1 8); do
  "$ADB_BIN" shell input swipe 540 1750 540 350 500 >/dev/null || true
  sleep 1
  measure "scroll_${i}"
done

peak_pss=$(awk -F, 'NR > 1 && $3 > max {max=$3} END {print max + 0}' "$metrics_csv")
peak_label=$(awk -F, -v max="$peak_pss" 'NR > 1 && $3 == max {print $1; exit}' "$metrics_csv")
last_pss=$(awk -F, 'NR > 1 {value=$3} END {print value + 0}' "$metrics_csv")

cat > "$OUTPUT_DIR/summary.txt" <<EOF
package=$PACKAGE
max_pss_kb=$MAX_PSS_KB
peak_pss_kb=$peak_pss
peak_label=$peak_label
last_pss_kb=$last_pss
EOF

if (( peak_pss <= 0 )); then
  echo "Unable to read TOTAL PSS from dumpsys meminfo" >&2
  exit 1
fi
if (( peak_pss > MAX_PSS_KB )); then
  echo "Peak app PSS ${peak_pss}KB exceeds limit ${MAX_PSS_KB}KB" >&2
  exit 1
fi

echo "LOW_RAM_RESULT status=PASS peak_pss_kb=$peak_pss limit_kb=$MAX_PSS_KB"
