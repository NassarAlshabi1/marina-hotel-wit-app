#!/usr/bin/env bash
set -euo pipefail

ADB_BIN="${1:?adb binary is required}"
PACKAGE="${2:?package name is required}"
CYCLE="${3:?cycle number is required}"
UI_XML="/sdcard/marina_low_ram_ui_${CYCLE}.xml"
LOG_FILE="${LOW_RAM_ACTION_LOG:-/tmp/marina_low_ram_navigation_actions.log}"

mkdir -p "$(dirname "$LOG_FILE")"
log() {
  printf 'cycle=%s event=%s\n' "$CYCLE" "$1" | tee -a "$LOG_FILE"
}

sleep_for_ui() {
  sleep "${LOW_RAM_ACTION_SETTLE_SEC:-2}"
}

dump_ui() {
  "$ADB_BIN" shell uiautomator dump "$UI_XML" >/dev/null 2>&1 || return 1
  "$ADB_BIN" shell cat "$UI_XML" 2>/dev/null | tr -d '\r\n'
}

tap_text() {
  local requested="$1"
  local xml bounds x1 y1 x2 y2 x y
  xml="$(dump_ui || true)"
  [[ -n "$xml" ]] || return 1
  bounds=$(printf '%s' "$xml" | grep -o "text=\"$requested\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | sed -n '1p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/\1 \2 \3 \4/p')
  if [[ -z "$bounds" ]]; then
    bounds=$(printf '%s' "$xml" | grep -o "content-desc=\"$requested\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | sed -n '1p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/\1 \2 \3 \4/p')
  fi
  [[ -n "$bounds" ]] || return 1
  read -r x1 y1 x2 y2 <<< "$bounds"
  x=$(( (x1 + x2) / 2 ))
  y=$(( (y1 + y2) / 2 ))
  "$ADB_BIN" shell input tap "$x" "$y"
  log "tap:$requested"
  sleep_for_ui
  return 0
}

back_to_dashboard() {
  "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  sleep_for_ui
}

# The script is intentionally best-effort. If the APK is at LoginScreen, no
# credentials are invented and the cycle is recorded as skipped.
ui="$(dump_ui || true)"
if printf '%s' "$ui" | grep -q 'اسم المستخدم\|كلمة المرور\|تسجيل الدخول'; then
  log 'navigation_skipped:login_screen_no_credentials'
  exit 0
fi

if tap_text 'مدفوعات اليوم'; then
  back_to_dashboard
else
  log 'not_found:مدفوعات اليوم'
fi

if tap_text 'المصروفات'; then
  back_to_dashboard
else
  log 'not_found:المصروفات'
fi

# Dashboard room cards expose their room number as text. Try a bounded set of
# common labels without assuming that any particular room exists.
for room in 101 102 103 104; do
  if tap_text "$room"; then
    back_to_dashboard
    break
  fi
done

log 'navigation_cycle_complete:best_effort'
