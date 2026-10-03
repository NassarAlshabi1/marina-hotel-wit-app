#!/usr/bin/env bash
# Only a fresh disposable emulator; never use this script on a personal phone.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$PWD/performance-evidence"
PKG=com.a.a
mkdir -p "$OUT"
# Refuse physical devices. Never expose production data or trigger cloud writes.
[[ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]] || { echo 'Disposable emulator required'; exit 1; }
adb root
adb wait-for-device
adb install -t mobile/build/app/outputs/apk/debug/app-debug.apk
UID_VALUE=$(adb shell pm list packages -U "$PKG" | tr -d '\r' | sed -n 's/.*uid:\([0-9]*\).*/\1/p')
[[ "$UID_VALUE" =~ ^[0-9]+$ ]] || { echo 'Cannot determine application UID'; exit 1; }
# Fail closed if either IPv4 or IPv6 network isolation cannot be established.
# This matters because the current app automatically initializes cloud sync.
adb shell iptables -I OUTPUT -m owner --uid-owner "$UID_VALUE" -j REJECT
adb shell ip6tables -I OUTPUT -m owner --uid-owner "$UID_VALUE" -j REJECT
adb shell getprop > "$OUT/device-properties.txt"
adb shell wm size > "$OUT/display.txt"
adb shell wm density >> "$OUT/display.txt"
printf '%s\n' 'Debug APK / hosted emulator / offline / fresh local database' \
  'Entry screen only: this does not claim authenticated Dashboard/payment coverage.' \
  'am start timing is diagnostic, not Macrobenchmark TTID/TTFD or a phone speed score.' > "$OUT/scope.txt"
trap 'adb logcat -d -b crash > "$OUT/crashes.txt" 2>&1 || true' EXIT
adb logcat -c
for attempt in 1 2 3 4 5; do
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PKG/com.marina.marina.MainActivity" > "$OUT/start-$attempt.txt"
  grep -q 'Status: ok' "$OUT/start-$attempt.txt"
  sleep 3
  adb shell pidof "$PKG" > "$OUT/pid-$attempt.txt"
  adb exec-out screencap -p > "$OUT/screen-$attempt.png"
  adb shell dumpsys gfxinfo "$PKG" framestats > "$OUT/frames-$attempt.txt"
  adb shell dumpsys meminfo "$PKG" > "$OUT/memory-$attempt.txt"
done
adb shell uiautomator dump /sdcard/marina-window.xml
adb pull /sdcard/marina-window.xml "$OUT/window.xml"
python3 - <<'PY'
import json, pathlib, re, statistics
out = pathlib.Path('performance-evidence')
values = []
for file in sorted(out.glob('start-*.txt')):
    match = re.search(r'TotalTime:\s*(\d+)', file.read_text())
    if match:
        values.append(int(match.group(1)))
report = {'scope': 'debug offline entry-screen emulator diagnostics, not device benchmark',
          'total_time_ms': values, 'median_ms': statistics.median(values) if values else None}
(out / 'startup-summary.json').write_text(json.dumps(report, indent=2))
if len(values) != 5:
    raise SystemExit('Incomplete startup measurements; inspect captured evidence')
print(json.dumps(report))
PY
